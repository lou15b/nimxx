import std / [ unicode, logging ]

import ./ [ types, timer, opengl_etc ]
import ./private/font/font_data

import ./private/font/stb_ttf_glyph_provider

import std/os
import pkg/malebolgia/lockers

import pkg/ttf/edtaa3func
import ./private/simple_table

when defined(android):
  import ./assets/url_stream

# No destructor needed for GlyphProvider, because it is an alias
type GlyphProvider = StbTtfGlyphProvider  

type Baseline* = enum
  bTop
  bAlphabetic
  bBottom

type CharInfo = ref object
  data: GlyphData
  texture: TextureGLRef

proc `=destroy`(x: typeof CharInfo()[]) =
  `=destroy`(x.data)
  if x.texture != invalidGLTexture:
    try:
      deleteGLTexture(x.texture)
    except Exception as e:
      echo "Exception encountered destroying CharInfo texture:", e.msg

template bakedChars(ci: CharInfo): GlyphMetrics = ci.data.glyphMetrics

# No destructor needed for FastString, because it is an alias
type FastString = string


template charHeightForSize(s: float): float =
  #if s > 128: 128
  #else: 64

  # TODO: Think some more about df generation because it's still slow for
  # 128 glyph size
  64

template scaleForSize(s: float): float = s / charHeightForSize(s)

type FontImpl = ref object
  chars: SimpleTable[int32, CharInfo]
  glyphProvider: GlyphProvider
  ascent: float32
  descent: float32

proc `=destroy`(x: typeof FontImpl()[]) =
  `=destroy`(x.chars.addr[])
  `=destroy`(x.glyphProvider)

var fontCache =
  initLocker(newSimpleTable(FastString, FontImpl))

proc cachedImplForFont(face: string, sz: float): FontImpl =
  lock fontCache as fc:
    var key : FastString = face & "_" & $charHeightForSize(sz).int
    if fc.hasKey(key):
      result = fc[key]
    else:
      result.new()
      result.chars = newSimpleTable(int32, CharInfo)
      result.glyphProvider.new()
      result.glyphProvider.setPath(face)
      result.glyphProvider.setSize(charHeightForSize(sz))
      result.glyphProvider.glyphMargin = 8
      fc[key] = result

type Font* = ref object
  impl: FontImpl
  mSize: float
  isHorizontal*: bool
  scale*: float
  filePath: string
  face*: string
  horizontalSpacing*: Coord
  shadowX*, shadowY*, shadowBlur*: float32
  glyphMargin: int32
  baseline*: Baseline # Beware! Experinmetal!

proc `=destroy`*(x: typeof Font()[]) =
  try:
    `=destroy`(x.impl)
  except Exception as e:
    echo "Exception encountered destroying Font impl:", e.msg
  `=destroy`(x.filePath)
  `=destroy`(x.face)

proc `size=`*(f: Font, s: float) =
  f.mSize = s
  f.scale = scaleForSize(s)
  f.impl = cachedImplForFont(f.filePath, s)

template size*(f: Font): float = f.mSize

const dumpDebugBitmaps = false

when dumpDebugBitmaps:
  template dumpBitmaps(name: string, bitmap: seq[byte], width, height, start: int,
      fSize: float) =
    var bmp = newSeq[byte](width * height * 3)
    for i in 0 .. < width * height:
      bmp[3*i] = bitmap[i]

    discard stbi_write_bmp(
      "atlas_nimx_" & name & "_" & $fSize & "_" & $start & "_" & $width & "x" & $height & ".bmp",
      width.cint, height.cint, 3.cint, addr bmp[0])

proc updateFontMetrics(f: Font) =
  f.impl.glyphProvider.getFontMetrics(f.impl.ascent, f.impl.descent)

template updateFontMetricsIfNeeded(f: Font) =
  if f.impl.ascent == 0: f.updateFontMetrics()

proc ascent*(f: Font): float32 =
  f.updateFontMetricsIfNeeded()
  result = f.impl.ascent * f.scale

proc descent*(f: Font): float32 =
  f.updateFontMetricsIfNeeded()
  result = f.impl.descent * f.scale

proc bakeChars(f: Font, start: int32, res: CharInfo) =
  f.impl.glyphProvider.bakeChars(start, res.data)
  when dumpDebugBitmaps:
    dumpBitmaps("df", res.data.bitmap, res.data.bitmapWidth, res.data.bitmapHeight,
      start, fSize)

proc newFontWithFile*(pathToTTFile: string, size: float): Font =
  result.new()
  result.isHorizontal = true # TODO: Support vertical fonts
  result.filePath = pathToTTFile
  result.face = splitFile(pathToTTFile).name
  result.size = size
  result.glyphMargin = 8

const preferredFonts = when defined(windows):
    [
      "Arial",
      "OpenSans-Regular"
    ]
  elif defined(ios):
    [
      "OpenSans-Regular"
    ]
  elif defined(macosx):
    [
      "Arial",
      "Arial Unicode"
    ]
  elif defined(android):
    [
      "DroidSans"
    ]
  else:
    [
      "Ubuntu-R",
      "DejaVuSans"
    ]

import ./private/font/fontconfig

proc getAvailableFonts*(isSystem: bool = false): seq[string] =
  result = newSeq[string]()
  when not defined(android) and not defined(ios):
    for f in walkFiles(getAppDir() /../ "Resources/*.ttf"):
      result.add(splitFile(f).name)
    for f in walkFiles(getAppDir() / "res/*.ttf"):
      result.add(splitFile(f).name)
    for f in walkFiles(getAppDir() / "*.ttf"):
      result.add(splitFile(f).name)

proc newFontWithFace*(face: string, size: float): Font =
  let path = findFontFileForFace(face)
  if path.len != 0:
    result = newFontWithFile(path, size)
  else:
    when defined(android):
      let path = face & ".ttf"
      let url = "res://" & path
      var s: Stream
      openStreamForUrl(url) do(st: Stream, err: string):
        s = st
      if not s.isNil:
        s.close()
        result = newFontWithFile(url, size)

proc systemFontSize*(): float = 16

proc systemFontOfSize*(size: float): Font =
  for f in preferredFonts:
    result = newFontWithFace(f, size)
    if result != nil: return

  error "Could not find system font:"
  for face in preferredFonts:
    for f in potentialFontFilesForFace(face):
      error "Tried path '", f, "'"

var sysFont {.threadvar.}: Font

proc systemFont*(): Font =
  if sysFont == nil:
    sysFont = systemFontOfSize(systemFontSize())
  result = sysFont
  if result == nil:
    warn "Could not create system font"

var dfCtx {.threadvar.}: DistanceFieldContext[float32]

proc generateDistanceFieldForGlyph(ch: CharInfo, index: int, uploadToTexture: bool) =
  if dfCtx.isNil:
    dfCtx = newDistanceFieldContext()
  let c = charOff(index)

  let glyphMargin = 8

  let x = ch.bakedChars.charOffComp(c, compTexX).int - glyphMargin
  let y = ch.bakedChars.charOffComp(c, compTexY).int - glyphMargin
  let w = ch.bakedChars.charOffComp(c, compWidth).cint + glyphMargin * 2
  let h = ch.bakedChars.charOffComp(c, compHeight).cint + glyphMargin * 2

  dfCtx.make_distance_map(ch.data.bitmap, x, y, w, h, ch.data.bitmapWidth.int,
    not uploadToTexture)
  if uploadToTexture:
    glBindTexture(GL_TEXTURE_2D, ch.texture)
    if w mod 4 == 0:
      texGLSubImage2D(GL_TEXTURE_2D, 0, GLint(x), GLint(y), GLsizei(w), GLsizei(h),
        GL_ALPHA, GL_UNSIGNED_BYTE, dfCtx.output)
    else:
      glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
      texGLSubImage2D(GL_TEXTURE_2D, 0, GLint(x), GLint(y), GLsizei(w), GLsizei(h),
        GL_ALPHA, GL_UNSIGNED_BYTE, dfCtx.output)
      glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
  ch.data.dfDoneForGlyph[index] = true

  when dumpDebugBitmaps:
    if not dfCtx.output.isNil:
      dumpBitmaps("df" & $index, dfCtx.output, w, h, 0, 555.0)

var glyphGenerationTimer {.threadvar.}: Timer
var chunksToGen {.threadvar.}: seq[CharInfo]

proc generateDistanceFields() =
  let ch = chunksToGen[^1]
  if ch.data.dfDoneForGlyph.len != 0:
    for i in 0 ..< charChunkLength:
      if not ch.data.dfDoneForGlyph[i]:
        generateDistanceFieldForGlyph(ch, i, true)
        return
  chunksToGen.setLen(chunksToGen.len - 1)
  ch.data.bitmap.setLen(0)
  ch.data.dfDoneForGlyph.setLen(0)
  if chunksToGen.len == 0:
    glyphGenerationTimer.clear()
    glyphGenerationTimer = nil
    dfCtx = nil

proc chunkAndCharIndexForRune(f: Font, r: Rune): tuple[ch: CharInfo, index: int] =
  let chunkStart = r.int32 div charChunkLength
  result.index = r.int mod charChunkLength
  var ch: CharInfo
  if f.impl.chars.hasKey(chunkStart):
    ch = f.impl.chars[chunkStart]
  else:
    ch.new()
    ch.data.dfDoneForGlyph = newSeq[bool](charChunkLength)
    f.bakeChars(chunkStart, ch)
    f.impl.chars[chunkStart] = ch

  result.ch = ch

  # As a side effect, an opengl texture for the rune is created.
  # But this caode is also on the execution path of at least one unit test,
  # so the texture is only created if an opengl context has been established.
  if isOpenglInitialized():
    if ch.texture.isEmptyGLRef:
      if not ch.data.dfDoneForGlyph[result.index]:
        generateDistanceFieldForGlyph(ch, result.index, false)

      chunksToGen.add(ch)
      if glyphGenerationTimer.isNil:
        glyphGenerationTimer = setInterval(0.1, generateDistanceFields)

      ch.texture = createGLTexture()
      glBindTexture(GL_TEXTURE_2D, ch.texture)

      let texWidth = ch.data.bitmapWidth.GLsizei
      let texHeight = ch.data.bitmapHeight.GLsizei
      texGLImage2D(GL_TEXTURE_2D, 0, GLint(GL_ALPHA), texWidth, texHeight, 0,
        GL_ALPHA, GL_UNSIGNED_BYTE, ch.data.bitmap)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
      #glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_NEAREST)
      #glGenerateMipmap(GL_TEXTURE_2D)
    elif ch.data.dfDoneForGlyph.len != 0 and not ch.data.dfDoneForGlyph[result.index]:
      generateDistanceFieldForGlyph(ch, result.index, true)

proc getQuadDataForRune*(f: Font, r: Rune, quad: var openarray[Coord], offset: int,
    texture: var TextureGLRef, pt: var Point) =
  let (chunk, charIndexInChunk) = f.chunkAndCharIndexForRune(r)
  let c = charOff(charIndexInChunk)

  template charComp(e: GlyphMetricsComponent): auto =
    chunk.data.glyphMetrics.charOffComp(c, e).Coord

  let w = charComp(compWidth)
  let h = charComp(compHeight)

  f.updateFontMetricsIfNeeded()

  let baselineOffset = case f.baseline
    of bTop: 0.0
    of bBottom: -f.impl.ascent + f.impl.descent
    of bAlphabetic: -f.impl.ascent

  let m = f.glyphMargin.float * f.scale
  let x0 = pt.x + charComp(compX) * f.scale - m
  let x1 = x0 + w * f.scale + m * 2.0
  let y0 = pt.y + charComp(compY) * f.scale - m + baselineOffset * f.scale
  let y1 = y0 + h * f.scale + m * 2.0

  var s0 = charComp(compTexX) - f.glyphMargin.float
  var t0 = charComp(compTexY) - f.glyphMargin.float
  let s1 = (s0 + w + f.glyphMargin.float * 2.0) / chunk.data.bitmapWidth.Coord
  let t1 = (t0 + h + f.glyphMargin.float * 2.0) / chunk.data.bitmapHeight.Coord
  s0 /= chunk.data.bitmapWidth.Coord
  t0 /= chunk.data.bitmapHeight.Coord

  quad[offset + 0] = x0; quad[offset + 1] = y0; quad[offset + 2] = s0; quad[offset + 3] = t0
  quad[offset + 4] = x0; quad[offset + 5] = y1; quad[offset + 6] = s0; quad[offset + 7] = t1
  quad[offset + 8] = x1; quad[offset + 9] = y1; quad[offset + 10] = s1; quad[offset + 11] = t1
  quad[offset + 12] = x1; quad[offset + 13] = y0; quad[offset + 14] = s1; quad[offset + 15] = t0
  pt.x += charComp(compAdvance) * f.scale
  texture = chunk.texture

proc getCharComponent*(f: Font, text: string, comp: GlyphMetricsComponent): Coord =
  let (chunk, charIndexInChunk) =
    f.chunkAndCharIndexForRune(text.runeAtPos(0))
  let c = charOff(charIndexInChunk)

  f.updateFontMetricsIfNeeded()
  result = chunk.data.glyphMetrics.charOffComp(c, comp).Coord

template getQuadDataForRune*(f: Font, r: Rune, quad: var array[16, Coord],
    texture: var TextureGLRef, pt: var Point) =
  f.getQuadDataForRune(r, quad, 0, texture, pt)

proc getAdvanceForRune*(f: Font, r: Rune): Coord =
  let (chunk, charIndexInChunk) = f.chunkAndCharIndexForRune(r)
  let c = charOff(charIndexInChunk)
  result = chunk.bakedChars.charOffComp(c, compAdvance).Coord * f.scale

proc height*(f: Font): float32 =
  f.updateFontMetricsIfNeeded()
  result = (f.impl.ascent - f.impl.descent) * f.scale

proc sizeOfString*(f: Font, s: string): Size =
  var pt : Point
  var first = true
  for ch in s.runes:
    if first:
      first = false
    else:
      pt.x += f.horizontalSpacing
    pt.x += f.getAdvanceForRune(ch)
  result = newSize(pt.x, f.height)
