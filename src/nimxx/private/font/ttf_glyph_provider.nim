import std / [ strutils, os, streams, logging ]
import ./font_data
import ../../assets/url_stream
import pkg/rect_packer
import ./ttf
import pkg/destructor

type TtfGlyphProvider* = ref object
  path: string
  size: float32 # "Real" glyph size. Usually bigger than font size.
  fontInfo: FontInfo
  glyphMargin*: int32

TtfGlyphProvider.traceDestructor():
  TtfGlyphProvider.destroyFields(x.path, x.fontInfo)

proc newTtfGlyphProvider*(path: string, size: float32, glyphMargin: int32): TtfGlyphProvider =
  result = TtfGlyphProvider.new()
  result.path = path
  result.size = size
  result.glyphMargin = glyphMargin
  result.fontInfo = FontInfo.new()

proc setPath*(p: TtfGlyphProvider, path: string) =
  p.path = path

template setSize*(p: TtfGlyphProvider, sz: float32) =
  p.size = sz

proc readFileBytes(filename: string): seq[byte] =
  let numBytes = filename.getFileSize().int
  result = newSeq[byte](numBytes)
  var file: File
  try:
    file = filename.open()
    let actual = file.readBytes(result, 0, numBytes)
    if actual != numBytes:
      echo "*** Warning - Tried to read ", numBytes, " bytes, actually read ",
        actual, " bytes"
      result.setLen(actual)
  except Exception as e:
    result = newSeq[byte](0)
    raise e
  finally:
    file.close()

proc readAllBytes(s: Stream): seq[byte] =
  ## Patterned after the non-JS portion of the runtime "streams.readAll"
  const bufferSize = 10240    # Font files are 10s to 100s of K, so larger buffer
  result = newSeqOfCap[byte](bufferSize)
  var buffer {.noinit.}: array[bufferSize, byte]
  while true:
    let numBytes = s.readData(addr(buffer[0]), bufferSize)
    if numBytes == 0:
      break
    result.add(buffer[0 ..< numBytes])
    if numBytes < bufferSize:
      break

proc loadFontData(p: TtfGlyphProvider) =
  var fontData: seq[byte]
  if p.path.startsWith("res://"):
    var s: Stream
    openStreamForUrl(p.path) do(st: Stream, err: string):
      s = st
    if s.isNil:
      error "Could not load font from path: ", p.path
    fontData = s.readAllBytes()
    s.close()
  else:
    fontData = readFileBytes(p.path)

  if not p.fontInfo.initFont(fontData, 0):
    warn "Could not init font"
    raise newException(Exception, "Could not init font")
  fontData.wasMoved()

proc getFontMetrics*(p: TtfGlyphProvider, oAscent, oDescent: var float32) =
  p.loadFontData()
  let scale = p.fontInfo.scaleForMappingEmToPixels(p.size)
  let (ascent, descent, lineGap) = p.fontInfo.getFontVMetrics()
  oAscent = float32(ascent) * scale
  oDescent = float32(descent) * scale

proc bakeChars*(p: TtfGlyphProvider, start: int32, data: var GlyphData) =
  let startChar = start * charChunkLength
  let endChar = startChar + charChunkLength

  var rectPacker = newPacker(32, 32)

  p.loadFontData()

  let scale = p.fontInfo.scaleForMappingEmToPixels(p.size)
  let (ascent, descent, lineGap) = p.fontInfo.getFontVMetrics()

  var glyphIndexes: array[charChunkLength, int]

  for i in startChar ..< endChar:
    if isPrintableCodePoint(i):
      let g = p.fontInfo.findGlyphIndex(i)    # g > 0 when found
      glyphIndexes[i - startChar] = g
      let (advance, lsb) = p.fontInfo.getGlyphHMetrics(g)
      let (x0, y0, x1, y1) = p.fontInfo.getGlyphBitmapBox(g, scale, scale)
      let gw = x1 - x0
      let gh = y1 - y0
      let (x, y) = rectPacker.packAndGrow((gw + p.glyphMargin * 2).int32,
        (gh + p.glyphMargin * 2).int32)

      let c = charOff(i - startChar)
      data.glyphMetrics.charOffComp(c, compX) = (x0.cfloat).int16
      data.glyphMetrics.charOffComp(c, compY) = (y0.cfloat + ascent.cfloat * scale).int16
      data.glyphMetrics.charOffComp(c, compAdvance) = (scale * advance.cfloat).int16
      data.glyphMetrics.charOffComp(c, compTexX) = (x + p.glyphMargin).int16
      data.glyphMetrics.charOffComp(c, compTexY) = (y + p.glyphMargin).int16
      data.glyphMetrics.charOffComp(c, compWidth) = (gw).int16
      data.glyphMetrics.charOffComp(c, compHeight) = (gh).int16

  let width = rectPacker.width
  let height = rectPacker.height
  data.bitmapWidth = width.uint16
  data.bitmapHeight = height.uint16
  var temp_bitmap = newSeq[byte](width * height)

  for i in startChar ..< endChar:
    let indexOfGlyphInRange = i - startChar
    data.dfDoneForGlyph[indexOfGlyphInRange] = true
    if isPrintableCodePoint(i):
      let c = charOff(indexOfGlyphInRange)
      if data.glyphMetrics.charOffComp(c, compAdvance) > 0:
        let x = data.glyphMetrics.charOffComp(c, compTexX).int
        let y = data.glyphMetrics.charOffComp(c, compTexY).int
        let w = data.glyphMetrics.charOffComp(c, compWidth).int
        let h = data.glyphMetrics.charOffComp(c, compHeight).int
        if w > 0 and h > 0:
          let outputPtr = cast[ptr UncheckedArray[byte]](addr temp_bitmap[x + y * width.int])
          p.fontInfo.makeGlyphBitmap(outputPtr, w, h, width, scale, scale,
            glyphIndexes[indexOfGlyphInRange])
          data.dfDoneForGlyph[indexOfGlyphInRange] = false

  data.bitmap = move(temp_bitmap)
