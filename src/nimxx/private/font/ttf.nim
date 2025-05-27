## Extracted, updated and converted to idiomatic Nim from
## ttf.nim in https://github.com/yglukhov/ttf and from
## stb_truetype.h (version 1.26) in https://github.com/nothings/stb
## Note that only the portions used by nimx/nimxx were converted
import std/strutils
import std/math
import std/deques
import std/syncio

# Conversions from (network order / big-endian) byte array to integer values
#--- ttCHAR
proc ttInt8(p: openArray[byte], offset: Natural): int8 =
  assert(p.len >= offset + 1)
  result = cast[int8](p[offset])

#--- ttUSHORT
proc ttUshort(p: openArray[byte], offset: Natural): uint16 =
  assert(p.len >= offset + 2)
  result = p[offset]
  result = result.shl(8) or p[offset + 1]

#--- ttSHORT
proc ttShort(p: openArray[byte], offset: Natural): int16 =
  result = cast[int16](p.ttUshort(offset))

#--- ttULONG
proc ttUlong(p: openArray[byte], offset: Natural): uint32 =
  assert(p.len >= offset + 4)
  result = p[offset]
  for i in 1 .. 3:
    result = result.shl(8) or p[offset + i]

#--- ttLONG
proc ttLong(p: openArray[byte], offset: Natural): int32 =
  result = cast[int32](p.ttUlong(offset))

type
  DataBuffer = ref object
    contents: seq[byte]

  TableOffsetAndSize = object
    offset:Natural
    size: Natural

  #--- stbtt__buf
  DataView = object
    ## This is a slice view into an existing array/seq/string
    ## TODO - revisit this when views get out of experimental
    dataSource: DataBuffer  # Keep this reference to avoid a dangling pointer

    data: ptr UncheckedArray[byte]
    size: Natural
    cursor: Natural

  #--- stbtt_fontinfo
  FontInfo* = ref object
    data: DataBuffer          # contents of .ttf file
    fontstart: Natural        # offset of start of font

    numGlyphs: Natural        # number of glyphs, needed for range checking

    loca,head,glyf,hhea,hmtx,kern,gpos,svg: TableOffsetAndSize # table locations as offset from start of .ttf contents
    indexMap: Natural          # a cmap mapping for our chosen character encoding
    indexToLocFormat: Natural   # format needed to map from glyph index to glyph

    # Slice views into the "data" field
    cff: DataView             # cff font data
    charstrings: DataView     # the charstring index
    gsubrs: DataView          # global charstring subroutines index
    subrs: DataView           # private charstring subroutines index
    fontdicts: DataView       # array of font dicts
    fdselect: DataView        # map from glyph to fontdict
  
  # Platform IDs
  PlatformId = enum
    PidUnicode   = 0,   # STBTT_PLATFORM_ID_UNICODE
    PidMac       = 1,   # STBTT_PLATFORM_ID_MAC
    PidIso       = 2,   # STBTT_PLATFORM_ID_ISO
    PidMicrosoft = 3    # STBTT_PLATFORM_ID_MICROSOFT
  
  # Encoding IDs for Microsoft platform ID
  MicrosoftEid = enum
    MsEidSymbol       = 0,   # STBTT_MS_EID_SYMBOL
    MsEidUnicodeBmp   = 1,   # STBTT_MS_EID_UNICODE_BMP
    MsEidShiftJis     = 2,   # STBTT_MS_EID_SHIFTJIS
    MsEidUnicodeFull  = 10   # STBTT_MS_EID_UNICODE_FULL

  VertexType = enum
    Vmove=1,
    Vline,
    Vcurve,
    Vcubic

  #--- stbtt_vertex
  Vertex = object
    x, y, cx, cy, cx1, cy1: int16
    vtype: uint8

  #--- stbtt__csctx
  Csctx = object
    bounds: bool
    started: bool
    firstX, firstY: float
    x, y: float
    minX, maxX, minY, maxY: int

    vertices: seq[Vertex]
    numVertices: Natural
  
  #--- stbtt__bitmap
  # Note that this represents a *portion* of a larger rasterized image,
  # which for us is a texture atlas
  Bitmap = object
    width, height, stride: Natural
    pixels: ptr UncheckedArray[byte]
  
  #--- stbtt__point
  Point = object
    x, y: float
  
  #--- stbtt__edge
  Edge = object
    x0, y0, x1, y1: float
    invert: bool
  
  #--- stbtt__active_edge
  ActiveEdge = object
    next: ptr ActiveEdge    # ptr is used because these objects exist in ActiveEdgePool
    fx, fdx, fdy: float
    direction: float
    sy, ey: float
  
  #--- stbtt__hheap
  ActiveEdgePool = object
    chunkSize: int
    freshChunk: seq[ActiveEdge]
    nextFreshIndex: int
    releasedPtrs: Deque[ptr ActiveEdge]
    savedChunks: seq[seq[ActiveEdge]]


# proc setData*(info: FontInfo, indata: sink string) =
#   info.data = move(indata)

#============= For debugging purposes =======================
proc printAttribs(view: DataView, viewName: string) =
  let sourceOffset:Natural =
    cast[uint](view.data[0].addr) - cast[uint](view.dataSource.contents[0].addr)
  echo viewName, ":   sourceOffset = ", sourceOffset, ":  size = ", view.size,
    "  cursor = ", view.cursor

proc printAttribs(activeEdge: ptr ActiveEdge, prefix: string) =
  echo prefix, "ActiveEdge:"
  echo prefix, "\t fx = ", activeEdge.fx, "   fdx = ", activeEdge.fdx, "   fdy = ", activeEdge.fdy
  echo prefix,  "\t direction = ", activeEdge.direction
  echo prefix,  "\t sy = ", activeEdge.sy, "   ey = ", activeEdge.ey

proc printActiveEdges(headActive: ptr ActiveEdge, prefix: string) =
  var step = headActive
  let ppref = prefix & "\t"
  let pppref = ppref & "\t"
  echo prefix, "ActiveEdge list:"
  var i = 0
  while not step.isNil():
    echo ppref, i
    step.printAttribs(pppref)
    step = step.next    # Advance through list
    inc i
#====================================


#--- stbtt__add_point
proc setFields(point: var Point, x, y: float) =
  point.x = x
  point.y = y

#--- stbtt_setvertex
proc setFields(v: var Vertex, vtype: uint8, x, y, cx, cy: int) =
  v.vtype = vtype
  v.x = x.int16
  v.y = y.int16
  v.cx = cx.int16
  v.cy = cy.int16

#--- STBTT__CSCTX_INIT
proc makeCsctx(bounds: bool): Csctx =
  result.bounds = bounds
  result.vertices = newSeq[Vertex](0)

#--- stbtt__find_table
proc findTable(data: seq[byte], fontstart: Natural, tag: string): TableOffsetAndSize =
  let numTables = data.ttShort(fontstart + 4)
  let tabledir = fontstart + 12
  for i in 0 ..< numTables:
    let loc = tabledir + 16 * i
    if toOpenArrayChar(data, loc.int, (loc + 3).int) == tag:
      result.offset = data.ttUlong(loc + 8)
      result.size = data.ttUlong(loc + 12)
      break

#--- Variants of stbtt__new_buf
#--------------
proc newBufferView(data: DataBuffer, start, size: Natural): DataView =
  assert(start + size <= data.contents.len)
  result.dataSource = data
  result.data = cast[ptr UncheckedArray[byte]](data.contents[start].addr)
  result.size = size
  result.cursor = 0

proc newBufferView(data: DataBuffer, toffsz: TableOffsetAndSize): DataView =
  result = newBufferView(data, toffsz.offset, toffsz.size)
#--------------

#--- stbtt__buf_range
proc newBufferSubView(data: DataView, start, size: Natural): DataView =
  assert(start + size <= data.size)
  result.dataSource = data.dataSource
  result.data = cast[ptr UncheckedArray[byte]](data.data[start].addr)
  result.size = size
  result.cursor = 0

#--- stbtt__buf_get8
proc get8(bv: var DataView): uint8 =
  if bv.cursor < bv.size:
    result = bv.data[bv.cursor]
    inc bv.cursor

#--- stbtt__buf_peek8
proc peek8(bv: DataView): uint8 =
  if bv.cursor < bv.size:
    result = bv.data[bv.cursor]

#--- stbtt__buf_seek
proc seek(bv: var DataView, offset: Natural) =
  assert(offset >= 0 and offset <= bv.size)
  bv.cursor = offset

#--- stbtt__buf_skip
proc skip(bv: var DataView, offset: int) =
  let newOffset: Natural = bv.cursor + offset
  bv.seek(uint32(newOffset))

#--- stbtt__buf_get
proc getValue(bv: var DataView, numBytes: range[1..4]): uint32 =
  # echo "getValue(): numBytes = ", numBytes
  # bv.printAttribs("\tbv")
  for i in 0 ..< numBytes:
    result = result.shl(8) or bv.get8()
  # echo "getValue(): result = ", result

#--- stbtt__buf_get16
template get16(bv: var DataView): uint32 =
  bv.getValue(2)

#--- stbtt__buf_get32
template get32(bv: var DataView): uint32 =
  bv.getValue(4)

#--- stbtt__buf_range
proc bufferRange(buf: DataView, offset, size: Natural): DataView =
  # echo "\nbufferRange:  offset = ", offset, "   size = ", size
  assert(offset + size <= buf.dataSource.contents.len)
  result.dataSource = buf.dataSource
  result.data = cast[ptr UncheckedArray[byte]](buf.data[offset].addr)
  result.size = size
  result.cursor = 0
  # echo "bufferRange result: size = ", result.size, "  cursor = ", result.cursor

# proc get(bv: var DataView, n: range[1..4]): uint32 =
#   # echo "\nget:  n = ", n
#   for i in 0 ..< n:
#     result = result.shl(8) or bv.get8()
#   # echo "get result: ", result

#--- stbtt__cff_get_index
proc cffGetIndex(buf: var DataView): DataView =
  # buf.printAttribs("\ncffGetIndex - buf")
  let start = buf.cursor
  # echo "start = ", start
  let count: Natural = buf.get16().int
  # echo "count = ", count
  if count > 0:
    let offsize: range[1..4] = buf.get8().int
    # echo "offsize = ", offsize
    # echo "First skip by ", offsize * count
    buf.skip(offsize * count)
    buf.printAttribs("After first skip - buf")
    buf.skip(buf.getValue(offsize).int - 1)
    # let iskip = buf.getValue(offsize).int - 1
    # echo "Second skip by ", iskip
    # buf.skip(iskip)
    # buf.printAttribs("After second skip - buf")
  result = buf.newBufferSubView(start, buf.cursor - start)
  # result.printAttribs("cffGetIndex result")

#--- stbtt__cff_int
# ***Note*** The original code returned a uint32 but the CFF encoding is for
#            a SIGNED int
proc cffGetInt(buf: var DataView): int =
  let b0 = buf.get8().int
  # echo "cffGetInt - b0 = ", b0
  if b0 >= 32 and b0 <= 246:
    result = b0 - 139
  elif b0 >= 247 and b0 <= 250:
    result = (b0 - 247) * 256 + buf.get8().int + 108
  elif b0 >= 251 and b0 <= 254:
    result = -(b0 - 251) * 256 - buf.get8().int - 108
  elif b0 == 28:
    result = buf.get16().int
  elif b0 == 29:
    result = buf.get32().int
  else:
    assert(false)
    result = 0

#--- stbtt__cff_skip_operand
proc cffSkipOperand(buf: var DataView) =
  let b0 = buf.peek8()
  assert (b0 >= 28)
  if b0 == 30:
    buf.skip(1)
    while buf.cursor < buf.size:
      let v = buf.get8()
      if ((v and 0xF) == 0xF or v.shr(4) == 0xF):
        break
  else:
    discard buf.cffGetInt()

#--- stbtt__dict_get
proc dictGet(buf: var DataView, key: int): DataView =
  buf.seek(0)
  var found = false
  while buf.cursor < buf.size:
    let start = buf.cursor
    while buf.peek8() >= 28:
      buf.cffSkipOperand()
    let iend = buf.cursor
    var op = buf.get8().int
    if op == 12:
      op = buf.get8().int or 0x100
    if op == key:
      result = buf.newBufferSubView(start, iend - start)
      found = true
      break
  if not found:
    result = buf.newBufferSubView(0,0)

#--- Variants of stbtt__dict_get_ints
#--------------
# Gets a single value
proc dictGetInt(buf: var DataView, key: int, outInt: var Natural) =
  var operands = buf.dictGet(key)
  # operands.printAttribs("dictGetInt - operands")
  if operands.cursor < operands.size:
    outInt = operands.cffGetInt()
    # echo "dictGetInt - outInt = ", outInt

# Retrieves a number of values into an array or seq
proc dictGetInts(buf: var DataView, key: int, outcount: int, outInts: var openArray[Natural]) =
  var operands = buf.dictGet(key)
  let maxout = min(outcount, outInts.len)
  var i = 0
  while i < maxout and operands.cursor < operands.size:
    outInts[i] = operands.cffGetInt()
    inc i
#--------------

#--- stbtt__cff_index_count
proc cffIndexCount(buf: var DataView): Natural =
  buf.seek(0)
  result = buf.get16()

#--- stbtt__cff_index_get
proc cffIndexGet(buf: var DataView, i: Natural): DataView =
  buf.seek(0)
  let count: Natural = buf.get16()
  let offsetSize: range[1..4] = buf.get8()
  assert(i < count)
  buf.skip(i * offsetSize)
  let start: Natural = buf.getValue(offsetSize)
  let iend: Natural = buf.getValue(offsetSize)
  result = buf.newBufferSubView(2 + (count + 1) * offsetSize + start, iend - start)

#--- stbtt__get_subrs
proc getSubrs(cff: var DataView, fontdict: var DataView): DataView =
  var private_loc: array[2, Natural]
  fontdict.dictGetInts(18, 2, private_loc)
  # echo "private_loc = ", private_loc
  if private_loc[1] > 0 and private_loc[0] > 0:
    var pdict = bufferRange(cff, private_loc[1], private_loc[0])
    # pdict.printAttribs("getSubrs - pdict")
    var subrsoff: Natural
    pdict.dictGetInt(19, subrsoff)
    # echo "subrsoff = ", subrsoff
    if subrsoff > 0:
      cff.seek(private_loc[1] + subrsoff)
      # cff.printAttribs("getSubrs - cff")
      result = cff.cffGetIndex()

#--- stbtt_InitFont / stbtt_InitFont_internal
proc initFont*(info: FontInfo, data: sink seq[byte], fontstart: Natural): bool =
  # echo "\ninitFont"
  info.data = new(DataBuffer)
  info.data.contents = move(data)
  data.wasMoved()
  info.fontstart = fontstart

  result = false    # Just in case it isn't already

  let cmap = info.data.contents.findTable(fontstart, "cmap")   # required
  info.loca = info.data.contents.findTable(fontstart, "loca")   # required
  info.head = info.data.contents.findTable(fontstart, "head")   # required
  info.glyf = info.data.contents.findTable(fontstart, "glyf")   # required
  info.hhea = info.data.contents.findTable(fontstart, "hhea")   # required
  info.hmtx = info.data.contents.findTable(fontstart, "hmtx")   # required
  info.kern = info.data.contents.findTable(fontstart, "kern")   # not required
  info.gpos = info.data.contents.findTable(fontstart, "GPOS")   # not required
  # echo "\ncmap = ", cmap
  # echo "info.loca = ", info.loca
  # echo "info.head = ", info.head
  # echo "info.glyf = ", info.glyf
  # echo "info.hhea = ", info.hhea
  # echo "info.hmtx = ", info.hmtx
  # echo "info.kern = ", info.kern
  # echo "info.gpos = ", info.gpos

  if cmap.offset == 0 or info.head.offset == 0 or info.hhea.offset == 0 or info.hmtx.offset == 0:
    return
  if info.glyf.offset > 0 and info.loca.offset == 0:
    # if info.glyf > 0 then info.loca must be > 0 for truetype
    return

  if info.glyf.offset == 0:
    # Initialization for CFF / Type2 fonts (OTF)
    let cff = info.data.contents.findTable(fontstart, "CFF ")
    if cff.offset == 0:
      return
    # echo "\ncff = ", cff
    
    info.cff = newBufferView(info.data, cff)
    # info.cff.printAttribs("info.cff")
    var b = info.cff
    # b.printAttribs("b")

    # Read the header
    b.skip(2)
    # echo "\nAfter skip: "
    # b.printAttribs("b")
    # info.cff.printAttribs("info.cff")
    # echo "Byte at b cursor = ", b.peek8()
    # echo "\nAfter peek: "
    # b.printAttribs("b")
    # info.cff.printAttribs("info.cff")

    b.seek(b.get8())  # hdrsize
    # echo "\nAfter seek: "
    # b.printAttribs("b")
    # info.cff.printAttribs("info.cff")

    # TODO the name INDEX could list multiple fonts,
    # but we just use the first one.
    let nameIndex = b.cffGetIndex()   # name INDEX - not currently used
    # echo "\nAfter cffGetIndex 1 (nameIndex): "
    # b.printAttribs("b")
    # nameIndex.printAttribs("nameIndex")
    
    var topDictIdx = b.cffGetIndex()
    # echo "\nAfter cffGetIndex 2 (topDictIdx): "
    # b.printAttribs("b")
    # topDictIdx.printAttribs("topDictIdx")
    
    var topDict = topDictIdx.cffIndexGet(0)
    # topDict.printAttribs("topDict")

    let stringIndex = b.cffGetIndex()   # string INDEX - not currently used
    # echo "\nAfter cffGetIndex 3 (stringIndex): "
    # b.printAttribs("b")
    # stringIndex.printAttribs("stringIndex")

    info.gsubrs = b.cffGetIndex()
    # echo "\nAfter cffGetIndex 4 (info.gsubrs): "
    # b.printAttribs("b")
    # info.gsubrs.printAttribs("info.gsubrs")

    var charstrings: Natural = 0
    topDict.dictGetInt(17, charstrings)
    # echo "\ncharstrings = ", charstrings
    var cstype: Natural = 2
    topDict.dictGetInt(0x100 or 6, cstype)
    # echo "cstype = ", cstype
    var fdarrayoff: Natural = 0
    topDict.dictGetInt(0x100 or 36, fdarrayoff)
    # echo "fdarrayoff = ", fdarrayoff
    var fdselectoff: Natural = 0
    topDict.dictGetInt(0x100 or 37, fdselectoff)
    # echo "fdselectoff = ", fdselectoff
    info.subrs = b.getSubrs(topDict)
    # info.subrs.printAttribs("info.subrs")

    # We only support Type 2 charstrings
    if cstype != 2:
      return
    if charstrings == 0:
      return

    if fdarrayoff > 0:
      # Looks like a CID font
      # echo "Looks like a CID font"
      if fdselectoff == 0:
        return
      b.seek(fdarrayoff)
      info.fontdicts = b.cffGetIndex()
      # info.fontdicts.printAttribs("info.fontdicts")
      info.fdselect = b.bufferRange(fdselectoff, b.size - fdselectoff)
      # info.fdselect.printAttribs("info.fdselect")

    b.seek(charstrings)
    info.charstrings = b.cffGetIndex()
    # info.charstrings.printAttribs("info.charstrings")

  let t = info.data.contents.findTable(fontstart, "maxp")
  # echo "t = ", t
  if (t.offset > 0 and t.size > 0):
    let offs = t.offset + 4
    info.numGlyphs = info.data.contents.ttUshort(offs)
  else:
    info.numGlyphs = 0xffff
  # echo "info.numGlyphs = ", info.numGlyphs
  
  # Already set by default
  # info.svg = TableOffsetAndSize(offset = 0, size = 0)

  # Find a cmap encoding table we understand *now* to avoid searching later.
  # (todo: could make this installable)
  # The same regardless of glyph.
  # echo "\n##################"
  let offs = cmap.offset + 2
  let numTables = info.data.contents.ttUshort(offs).int
  # echo "numTables = ", numTables
  # The following code gets the LAST encoding we understand
  # TODO Change it to get the FIRST encoding we understand
  info.indexMap = 0
  for i in 0 ..< numTables:
    let encodingRecordOffset = cmap.offset + 4 + 8 * i
    # echo "encodingRecordOffset = ", encodingRecordOffset
    # Find an encoding we understand
    let platformCode = info.data.contents.ttUshort(encodingRecordOffset)
    # echo "platformCode = ", platformCode
    case platformCode:
      of PidMicrosoft.ord:
        # echo "platformCode is PidMicrosoft"
        let encodingId =
          info.data.contents.ttUshort(encodingRecordOffset + 2)
        # echo "encodingId = ", encodingId
        case encodingId:
          of MsEidUnicodeBmp.ord, MsEidUnicodeFull.ord:
            # MS/Unicode
            # echo "encodingId is MS/Unicode"
            info.indexMap = cmap.offset +
              info.data.contents.ttUlong(encodingRecordOffset + 4).int
            # echo "info.indexMap = ", info.indexMap
          else:
            discard
      of PidUnicode.ord:
        # echo "platformCode is PidUnicode"
        # Mac/iOS has these
        # all the encodingIDs are unicode, so we don't bother to check it
        info.indexMap = cmap.offset +
          info.data.contents.ttUlong(encodingRecordOffset + 4).int
        # echo "info.indexMap = ", info.indexMap
      else:
        discard

  # echo "FINAL info.indexMap = ", info.indexMap
  if info.indexMap == 0:
    return

  let indexIdx = info.head.offset + 50
  # echo "indexIdx = ", indexIdx
  info.indexToLocFormat = info.data.contents.ttUshort(indexIdx)
  # echo "info.indexToLocFormat = ", info.indexToLocFormat
  result = true

#--- stbtt_ScaleForMappingEmToPixels
proc scaleForMappingEmToPixels*(info: FontInfo, pixels: float): float =
  let offset = info.head.offset
  let unitsPerEm = info.data.contents.ttUshort(offset + 18)
  result = pixels / (unitsPerEm.float)

#--- stbtt_GetFontVMetrics
proc getFontVMetrics*(info: FontInfo): (int, int, int) =
  let offset = info.hhea.offset
  # echo "getFontVMetrics - offset = ", offset
  let ascent = info.data.contents.ttShort(offset + 4)
  # echo "ascent = ", ascent
  let descent = info.data.contents.ttShort(offset + 6)
  # echo "descent = ", descent
  let lineGap = info.data.contents.ttShort(offset + 8)
  # echo "lineGap = ", lineGap
  result = (ascent, descent, lineGap)

#--- stbtt_FindGlyphIndex
proc findGlyphIndex*(info: FontInfo, unicodeCodepoint: int): int =
  # echo "\n################## findGlyphIndex"
  # echo "unicodeCodepoint = ", unicodeCodepoint, "   \\x", toHex(unicodeCodepoint)
  result = 0    # Default return, just to be clear
  let indexMapOffset = info.indexMap
  # echo "indexMapOffset = ", indexMapOffset

  let format = info.data.contents.ttUshort(indexMapOffset)
  # echo "format = ", format
  case format:
    of 0:   # apple byte encoding
      # echo "Apple byte encoding"
      let bytes: Natural = info.data.contents.ttUshort(indexMapOffset + 2)
      # echo "bytes = ", bytes
      if unicodeCodepoint < bytes - 6:
        result = info.data.contents[indexMapOffset + 6 + unicodeCodepoint].int
    of 6:
      # echo "Whatever format 6 is"
      let first: Natural = info.data.contents.ttUshort(indexMapOffset + 6)
      # echo "first = ", first
      let count: Natural = info.data.contents.ttUshort(indexMapOffset + 8)
      # echo "count = ", count
      if unicodeCodepoint >= first and unicodeCodepoint < first + count:
        result =
          info.data.contents.ttUshort(indexMapOffset + 10 + (unicodeCodepoint - first) * 2).int
    of 2:
      # echo "High-byte mapping for japanese/chinese/korean"
      assert(false)   # Original code TODO: high-byte mapping for japanese/chinese/korean
    of 4:   # standard mapping for windows fonts: binary search collection of ranges
      # echo "Standard mapping for windows fonts"
      let segcount: Natural = info.data.contents.ttUshort(indexMapOffset + 6).shr(1)
      # echo "segcount = ", segcount
      var searchRange: Natural = info.data.contents.ttUshort(indexMapOffset + 8).shr(1)
      # echo "searchRange = ", searchRange
      var entrySelector: Natural = info.data.contents.ttUshort(indexMapOffset + 10)
      # echo "entrySelector = ", entrySelector
      let rangeShift: Natural = info.data.contents.ttUshort(indexMapOffset + 12).shr(1)
      # echo "rangeShift = ", rangeShift

      # do a binary search of the segments
      let endCount = indexMapOffset + 14
      # echo "endCount = ", endCount
      var search = endCount
      # echo "search = ", search

      if unicodeCodepoint > 0xffff:
        return

      # they lie from endCount .. endCount + segCount
      # but searchRange is the nearest power of two, so...
      if unicodeCodepoint >= info.data.contents.ttUshort(search + rangeShift * 2).int:
        search += rangeShift * 2
        # echo "search = ", search

      # now decrement to bias correctly to find smallest
      search -= 2
      # echo "search = ", search
      while entrySelector > 0:
        searchRange = searchRange.shr(1)
        let iend: Natural = info.data.contents.ttUshort(search + searchRange * 2)
        if unicodeCodepoint > iend:
          search += searchRange * 2
        dec entrySelector
      search += 2
      # echo "search = ", search

      # ------------
      # Note: The following chunk of code was originally in its own block.
      # I couldn't figure out why - there don't appear to be any name conflicts,
      # nor large chunks of data that need to be popped off the stack at the end.
      # So I got rid of the separate block
      let item = (search - endCount).shr(1)
      # echo "item = ", item

      let offx = indexMapOffset + 14 + 2 + 2 * item
      let start: Natural =
        info.data.contents.ttUshort(offx + segcount * 2)
      # echo "start = ", start
      let last: Natural = info.data.contents.ttUshort(endCount + 2 * item)
      # echo "last = ", last
      if unicodeCodepoint >= start and unicodeCodepoint <= last:
        let offset: Natural =
          info.data.contents.ttUshort(offx + segcount * 6)
        # echo "offset = ", offset
        if offset == 0:
          result = unicodeCodepoint +
            info.data.contents.ttShort(offx + segcount * 4).int
        else:
          result =
            info.data.contents.ttUshort(offset + (unicodeCodepoint - start) * 2 + offx + segcount * 6).int
      # ------------
    of 12, 13:
      # echo "Whatever format 12 or 13 is"
      let ngroups: Natural = info.data.contents.ttUlong(indexMapOffset + 12)
      # echo "ngroups = ", ngroups
      var ilow: Natural = 0
      var ihigh: Natural = ngroups
      # Binary search the right group
      while ilow < ihigh:
        let mid = ilow + (ihigh - ilow).shr(1)   # rounds down, so low <= mid < high
        let offx = indexMapOffset + 16 + mid * 12
        let startChar: Natural = info.data.contents.ttUlong(offx)
        let endChar: Natural = info.data.contents.ttUlong(offx + 4)
        if unicodeCodepoint < startChar:
          ihigh = mid
        elif unicodeCodepoint > endChar:
          ilow = mid + 1
        else:
          let startGlyph: Natural = info.data.contents.ttUlong(offx + 8)
          # echo "startGlyph = ", startGlyph
          if format == 12:
            # echo "Return format 12 result"
            result = startGlyph + unicodeCodepoint - startChar
          else:   # format == 13
            # echo "Return format 13 result"
            result = startGlyph
          break
    else:
      assert(false)

#--- stbtt_GetGlyphHMetrics
proc getGlyphHMetrics*(info: FontInfo, glyphIndex: int): (int, int) =
  let numOfLongHorMetrics: Natural = info.data.contents.ttUshort(info.hhea.offset + 34)
  if glyphIndex < numOfLongHorMetrics:
    let offx = info.hmtx.offset + 4 * glyphIndex
    let advanceWidth = info.data.contents.ttShort(offx).int
    let leftSideBearing = info.data.contents.ttShort(offx + 2).int
    result = (advanceWidth, leftSideBearing)
  else:
    let offx = info.hmtx.offset + 4 * numOfLongHorMetrics
    let advanceWidth = info.data.contents.ttShort(offx - 4).int
    let leftSideBearing = info.data.contents.ttShort(offx + 2*(glyphIndex - numOfLongHorMetrics)).int
    result = (advanceWidth, leftSideBearing)

#--- stbtt__track_vertex
proc trackVertex(ctx: var Csctx, x, y: int) =
  if x > ctx.maxX or not ctx.started:
    ctx.maxX = x
  if y > ctx.maxY or not ctx.started:
    ctx.maxY = y
  if x < ctx.minX or not ctx.started:
    ctx.minX = x
  if y < ctx.minY or not ctx.started:
    ctx.minY = y
  ctx.started = true

#--- stbtt__csctx_v
proc addVertex(ctx: var Csctx, vtype: uint8, x, y, cx, cy, cx1, cy1: int) =
  if ctx.bounds:
    ctx.trackVertex(x, y)
    if vtype == Vcubic.uint8:
      ctx.trackVertex(cx, cy)
      ctx.trackVertex(cx1, cy1)
  else:
    var v: Vertex
    v.setFields(vtype, x, y, cx, cy)
    v.cx1 = cx1.int16
    v.cy1 = cy1.int16
    ctx.vertices.add(v)
  inc(ctx.numVertices)

#--- stbtt__csctx_close_shape
proc closeShape(ctx: var Csctx) =
  if ctx.firstX != ctx.x or ctx.firstY != ctx.y:
    ctx.addVertex(Vline.uint8, ctx.firstX.int, ctx.firstY.int, 0, 0, 0, 0)

#--- stbtt__csctx_rmove_to
proc rmoveTo(ctx: var Csctx, dx, dy: float) =
  ctx.closeShape()
  ctx.x += dx
  ctx.firstX = ctx.x
  ctx.y += dy
  ctx.firstY = ctx.y
  ctx.addVertex(Vmove.uint8, ctx.x.int, ctx.y.int, 0, 0, 0, 0)

#--- stbtt__csctx_rline_to
proc rlineTo(ctx: var Csctx, dx, dy: float) =
  ctx.x += dx
  ctx.y += dy
  ctx.addVertex(Vline.uint8, ctx.x.int, ctx.y.int, 0, 0, 0, 0)

#--- stbtt__csctx_rccurve_to
proc rccurveTo(ctx: var Csctx, dx1, dy1, dx2, dy2, dx3, dy3: float) =
  let cx1 = ctx.x + dx1
  let cy1 = ctx.y + dy1
  let cx2 = cx1 + dx2
  let cy2 = cy1 + dy2
  ctx.x = cx2 + dx3
  ctx.y = cy2 + dy3
  ctx.addVertex(Vcubic.uint8, ctx.x.int, ctx.y.int, cx1.int, cy1.int, cx2.int, cy2.int)

#--- stbtt__cid_get_glyph_subrs
proc cidGetGlyphSubrs(info: FontInfo, glyphIndex: int): DataView =
  var fdselect = info.fdselect
  var fdselector = -1

  fdselect.seek(0)
  let fmt = fdselect.get8()
  if fmt == 0:
    # From original code: untested
    fdselect.skip(glyphIndex)
    fdselector = fdselect.get8().int
  elif fmt == 3:
    let nranges = fdselect.get16()
    var start: Natural = fdselect.get16()
    for i in 0 ..< nranges:
      let v = fdselect.get8().int
      let iend: Natural  = fdselect.get16()
      if glyphIndex >= start and glyphIndex < iend:
        fdselector = v
        break
      start = iend
  if fdselector != -1:
    var cffIndex = info.fontdicts.cffIndexGet(fdselector)
    result = info.cff.getSubrs(cffIndex)

#--- stbtt__get_subr
proc getSubr(idx: DataView, n: int): DataView =
  var idxt = idx
  let count = idxt.cffIndexCount()
  var bias = 107
  if count >= 33900:
    bias = 32768
  elif count >= 1240:
    bias = 1131
  let m = n + bias
  if m >= 0 and m < count:
    result = idxt.cffIndexGet(m)

#--- stbtt__run_charstring
proc runCharstring(info: FontInfo, glyphIndex: int, ctx: var Csctx): bool =
  result = false

  proc sx5(spi: int, s: float): float =
    if spi == 5:
      result = s

  var inHeader = true
  var maskbits, subrStackHeight, sp, i: Natural
  var hasSubrs = false
  var clearStack = false
  var s: array[0..47, float]
  var subrStack: array[0 .. 9, DataView]
  var b: DataView
  var b0: uint8
  var subrs = info.subrs

  # This is the common part for a couple of "of" branches below
  proc callsubrCommon(): bool =
    if sp < 1:
      stderr.writeLine("ERROR - call(g|)subr stack")
      return
    dec sp
    let v = s[sp].int
    if subrStackHeight >= 10:
      stderr.writeLine("ERROR - recursion limit")
      return
    subrStack[subrStackHeight] = b
    inc subrStackHeight
    var sbrs = subrs
    if b0 != 0x0A:
      sbrs = info.gsubrs
    b = sbrs.getSubr(v)
    if b.size == 0:
      stderr.writeLine("ERROR - subr not found")
      return
    b.cursor = 0
    clearStack = false
    result = true

  # This currently ignores the initial width value, which isn't needed if we have hmtx
  b = cffIndexGet(info.charstrings, glyphIndex)
  while b.cursor < b.size:
    i = 0
    clearStack = true
    b0 = b.get8()
    case b0:
      # From original code: TODO implement hinting
      of 0x13, 0x14:                # hintmask, cntrmask
        if inHeader:
          maskbits += sp /% 2  # Implicit "vstem"
        inHeader = false
        b.skip((maskbits + 7) /% 8)

      of 0x01, 0x03, 0x12, 0x17:    # hstem, vstem, hstemhm, vstemhm
        maskbits += sp /% 2

      of 0x15:                      # rmoveto
        inHeader = false
        if sp < 2:
          stderr.writeLine("ERROR - rmoveto stack")
          return
        ctx.rmoveTo(s[sp - 2], s[sp - 1])
      of 0x04:                      # vmoveto
        inHeader = false
        if sp < 1:
          stderr.writeLine("ERROR - vmoveto stack")
          return
        ctx.rmoveTo(0, s[sp - 1])
      of 0x16:                      # hmoveto
        inHeader = false
        if sp < 1:
          stderr.writeLine("ERROR - hmoveto stack")
          return
        ctx.rmoveTo(s[sp - 1], 0)

      of  0x05:                     # rlineto
        if sp < 2:
          stderr.writeLine("ERROR - rlineto stack")
          return
        while i + 1 < sp:
          ctx.rlineTo(s[i], s[i + 1])
          i += 2
      
      # hlineto/vlineto and vhcurveto/hvcurveto alternate horizontal and vertical
      # starting from a different place

      of 0x07:                      # vlineto
        if sp < 1:
          stderr.writeLine("ERROR - vlineto stack")
          return
        while i < sp:
          ctx.rlineTo(0, s[i])
          inc i
          if i < sp:
            ctx.rlineTo(s[i], 0)
            inc i
      of 0x06:                      # hlineto
        if sp < 1:
          stderr.writeLine("ERROR - hlineto stack")
          return
        while i < sp:
          ctx.rlineTo(s[i], 0)
          inc i
          if i < sp:
            ctx.rlineTo(0, s[i])
            inc i
      
      of 0x1F:                      # hvcurveto
        if sp < 4:
          stderr.writeLine("ERROR - hvcurveto stack")
          return
        while i + 3 < sp:
          let sxt = sx5(sp - i, s[i + 4])
          ctx.rccurveTo(s[i], 0, s[i + 1], s[i + 2], sxt, s[i + 3])
          i += 4
          if i + 3 < sp:
            ctx.rccurveTo(0, s[i], s[i + 1], s[i + 2], s[i + 3], sxt)
            i += 4
      of 0x1E:                      # vhcurveto
        if sp < 4:
          stderr.writeLine("ERROR - vhcurveto stack")
          return
        while i + 3 < sp:
          let sxt = sx5(sp - i, s[i + 4])
          ctx.rccurveTo(0, s[i], s[i + 1], s[i + 2], s[i + 3], sxt)
          i += 4
          if i + 3 < sp:
            ctx.rccurveTo(s[i], 0, s[i + 1], s[i + 2], sxt, s[i + 3])
            i += 4
      
      of 0x08:                      # rrcurveto
        if sp < 6:
          stderr.writeLine("ERROR - rrcurveto stack")
          return
        while i + 5 < sp:
          ctx.rccurveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5])
          i += 6
      
      of 0x18:                      # rcurveline
        if sp < 8:
          stderr.writeLine("ERROR - rcurveline stack")
          return
        while i + 5 < sp - 2:
          ctx.rccurveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5])
          i += 6
        if i + 1 >= sp:
          stderr.writeLine("ERROR - rcurveline stack")
          return
        ctx.rlineTo(s[i], s[i + 1])

      of 0x19:                      # rlinecurve
        if sp < 8:
          stderr.writeLine("ERROR - rlinecurve stack")
          return
        while i + 1 < sp - 6:
          ctx.rlineTo(s[i], s[i + 1])
          i += 2
        if i + 5 >= sp:
          stderr.writeLine("ERROR - rlinecurve stack")
          return
        ctx.rccurveTo(s[i], s[i + 1], s[i + 2], s[i + 3], s[i + 4], s[i + 5])
      
      of 0x1A, 0x1B:                # vvcurveto, hhcurveto
        if sp < 4:
          stderr.writeLine("ERROR - (vv|hh)curveto stack")
          return
        var f = 0.0
        if (sp and 1) > 0:
          f = s[i]
          inc i
        while i + 3 < sp:
          if b0 == 0x1B:    # hhcurveto
            ctx.rccurveTo(s[i], f, s[i + 1], s[i + 2], s[i + 3], 0.0)
          else:             # vvcurveto
            ctx.rccurveTo(f, s[i], s[i + 1], s[i + 2], 0.0, s[i + 3])
          f = 0.0
          i += 4
      
      of 0x0A:                      # callsubr
        if not hasSubrs:
          if info.fdselect.size > 0:
            subrs = info.cidGetGlyphSubrs(glyphIndex)
          hasSubrs = true
        if not callsubrCommon():
          return
      of 0x1D:                      # callgsubr
        if not callsubrCommon():
          return
      
      of 0x0B:                      # return
        if subrStackHeight <= 0:
          stderr.writeLine("ERROR - return outside subr")
          return
        dec subrStackHeight
        b = subrStack[subrStackHeight]
        clearStack = false
      
      of 0x0E:                      # endchar
        ctx.closeShape()
        result = true
        return

      of 0x0C:                      # two-byte escape
        # TODO These "flex" implementations ignore the flex-depth and resolution,
        # and always draw beziers.
        let b1 = b.get8()
        case b1:
          of 0x22:                  # hflex
            if sp < 7:
              stderr.writeLine("ERROR - hflex stack")
              return
            let dx1 = s[0]
            let dx2 = s[1]
            let dy2 = s[2]
            let dx3 = s[3]
            let dx4 = s[4]
            let dx5 = s[5]
            let dx6 = s[6]
            ctx.rccurveTo(dx1, 0, dx2, dy2, dx3, 0)
            ctx.rccurveTo(dx4, 0, dx5, -dy2, dx6, 0)
          
          of 0x23:                  # flex
            if sp < 13:
              stderr.writeLine("ERROR - flex stack")
              return
            let dx1 = s[0]
            let dy1 = s[1]
            let dx2 = s[2]
            let dy2 = s[3]
            let dx3 = s[4]
            let dy3 = s[5]
            let dx4 = s[6]
            let dy4 = s[7]
            let dx5 = s[8]
            let dy5 = s[9]
            let dx6 = s[10]
            let dy6 = s[11]
            # fd is s[12]
            ctx.rccurveTo(dx1, dy1, dx2, dy2, dx3, dy3)
            ctx.rccurveTo(dx4, dy4, dx5, dy5, dx6, dy6)
          
          of 0x24:                  # hflex1
            if sp < 9:
              stderr.writeLine("ERROR - hflex1 stack")
              return
            let dx1 = s[0]
            let dy1 = s[1]
            let dx2 = s[2]
            let dy2 = s[3]
            let dx3 = s[4]
            let dx4 = s[5]
            let dx5 = s[6]
            let dy5 = s[7]
            let dx6 = s[8]
            ctx.rccurveTo(dx1, dy1, dx2, dy2, dx3, 0)
            ctx.rccurveTo(dx4, 0, dx5, dy5, dx6, -(dy1 + dy2 + dy5))

          of 0x25:                  # flex1
            if sp < 11:
              stderr.writeLine("ERROR - flex1 stack")
              return
            let dx1 = s[0]
            let dy1 = s[1]
            let dx2 = s[2]
            let dy2 = s[3]
            let dx3 = s[4]
            let dy3 = s[5]
            let dx4 = s[6]
            let dy4 = s[7]
            let dx5 = s[8]
            let dy5 = s[9]
            var dx6 = s[10]
            var dy6 = s[10]
            let dx = dx1 + dx2 + dx3 + dx4 + dx5
            let dy = dy1 + dy2 + dy3 + dy4 + dy5
            if abs(dx) > abs(dy):
              dy6 = -dy
            else:
              dx6 = -dx
            ctx.rccurveTo(dx1, dy1, dx2, dy2, dx3, dy3)
            ctx.rccurveTo(dx4, dy4, dx5, dy5, dx6, dy6)

          else:
            stderr.writeLine("ERROR - unimplemented")
            return

      else:
        if b0 != 255 and b0 != 28 and b0 < 32:
          stderr.writeLine("ERROR - reserved operator")
          return

        # Push immediate
        var f: float
        if b0 == 255:
          f = (b.get32().int /% 0x10000).float
        else:
          b.skip(-1)
          f = b.cffGetInt().float
        if sp >= 48:
          stderr.writeLine("ERROR - push stack overflow")
          return
        s[sp] = f
        inc sp
        clearStack = false

    if clearStack:
      sp = 0

  stderr.writeLine("ERROR - no endchar")

#--- stbtt__GetGlyphInfoT2
proc getGlyphInfoT2(info: FontInfo, glyphIndex: int, x0, y0, x1, y1: var int): int =
  var c = makeCsctx(true)
  if runCharstring(info, glyphIndex, c):
    x0 = c.minX
    y0 = c.minY
    x1 = c.maxX
    y1 = c.maxY
    result = c.numVertices
  else:
    x0 = 0
    y0 = 0
    x1 = 0
    y1 = 0
    result = 0


#--- stbtt__GetGlyfOffset
proc getGlyfOffset(info: FontInfo, glyphIndex: int): int =
  var g1, g2: int
  assert(info.cff.size == 0)

  result = -1
  if glyphIndex >= info.numGlyphs:
    # glyph index out of range
    return
  if info.indexToLocFormat >= 2:
    # unknown index->glyph map format
    return

  if info.indexToLocFormat == 0:
    let offs = info.loca.offset + glyphIndex * 2
    g1 = info.glyf.offset + info.data.contents.ttUshort(offs).int * 2
    g2 = info.glyf.offset + info.data.contents.ttUshort(offs + 2).int * 2
  else:
    let offs = info.loca.offset + glyphIndex * 4
    g1 = info.glyf.offset + info.data.contents.ttUlong(offs).int
    g2 = info.glyf.offset + info.data.contents.ttUlong(offs + 4).int
  
  if g1 != g2:
    result = g1
  # else (i.e. length is 0) return -1

#--- stbtt_GetGlyphBox
proc getGlyphBox(info: FontInfo, glyphIndex: int, x0, y0, x1, y1: var int): bool =
  # echo "########### getGlyphBox"
  result = false
  # echo "info.cff.size = ", info.cff.size
  if info.cff.size > 0:
    discard info.getGlyphInfoT2(glyphIndex, x0, y0, x1, y1)
  else:
    let g = info.getGlyfOffset(glyphIndex)
    # echo "g = ", g
    if g < 0:
      return

    x0 = info.data.contents.ttShort(g + 2)
    y0 = info.data.contents.ttShort(g + 4)
    x1 = info.data.contents.ttShort(g + 6)
    y1 = info.data.contents.ttShort(g + 8)
  # echo "x0, y0, x1, y1 = ", x0, "  ", y0, "  ", x1, "  ", y1
  result = true
  # echo "... getGlyphBox"

#--- stbtt_GetGlyphBitmapBoxSubpixel
proc getGlyphBitmapBoxSubpixel(info: FontInfo, glyphIndex: int, scaleX, scaleY,
    shiftX, shiftY: float): (int, int, int, int) =
  var x0, y0, x1, y1: int
  if not info.getGlyphBox(glyphIndex, x0, y0, x1, y1):
    # e.g. space character
    result = (0, 0, 0, 0)
  else:
    # MMove to integral bboxes (treating pixels as little squares, what pixels get touched?)
    let ix0 = floor(x0.float * scaleX + shiftX).int
    let iy0 = floor((-y1).float * scaleY + shiftY).int
    let ix1 = ceil(x1.float * scaleX + shiftX).int
    let iy1 = ceil((-y0).float * scaleY + shiftY).int
    result = (ix0, iy0, ix1, iy1)

#--- stbtt_GetGlyphBitmapBox
proc getGlyphBitmapBox*(info: FontInfo, glyphIndex: int, scaleX, scaleY: float): (int, int, int, int) =
  # echo "\n################## getGlyphBitmapBox"
  # echo "scaleX, scaleY = ", scaleX, "  ", scaleY
  result = info.getGlyphBitmapBoxSubpixel(glyphIndex, scaleX, scaleY, 0.0, 0.0)
  # echo "getGlyphBitmapBox result = ", result

#--- stbtt__close_shape
# proc closeShape(vertices: var seq[Vertex], numVertices: int, wasOff, startOff: bool,
    # sx, sy, scx, scy, cx, cy: int): int =
proc closeShape(vertices: var seq[Vertex], wasOff, startOff: bool,
    sx, sy, scx, scy, cx, cy: int) =
  # echo "closeShape numVertices = ", numVertices
  # echo "closeShape vertices.len = ", vertices.len
  # result = numVertices
  if startOff:
    if wasOff:
      # vertices[result].setFields(Vcurve.uint8, (cx + scx).shr(1), (cy + scy).shr(1), cx,cy)
      # inc result
      vertices.add(Vertex(vtype: Vcurve.uint8, x: (cx + scx).shr(1).int16, y: (cy + scy).shr(1).int16, cx: cx.int16, cy: cy.int16))
    # vertices[result].setFields(Vcurve.uint8, sx, sy, scx, scy)
    vertices.add(Vertex(vtype: Vcurve.uint8, x: sx.int16, y: sy.int16, cx: scx.int16, cy: scy.int16))
  else:
    if wasOff:
      # vertices[result].setFields(Vcurve.uint8, sx, sy, cx, cy)
      vertices.add(Vertex(vtype: Vcurve.uint8, x: sx.int16, y: sy.int16, cx: cx.int16, cy: cy.int16))
    else:
      # vertices[result].setFields(Vline.uint8, sx, sy, 0, 0)
      vertices.add(Vertex(vtype: Vline.uint8, x: sx.int16, y: sy.int16))
  # inc result
  # echo "closeShape result = ", result

# Recursive call requires this forward declaration
proc getGlyphShape(info: FontInfo, glyphIndex: int, vertices: var seq[Vertex]): int {.gcsafe.}

#--- stbtt__GetGlyphShapeTT
proc getGlyphShapeTT(info: FontInfo, glyphIndex: int, vertices: var seq[Vertex]): int {.gcsafe.} =
  # echo "\ngetGlyphShapeTT glyphIndex = ", glyphIndex
  result = 0    # Result is number of vertices - Failure return value is 0
  let g = info.getGlyfOffset(glyphIndex)
  # echo "getGlyphShapeTT g = ", g
  if g < 0:
    return

  let numberOfContours = info.data.contents.ttShort(g)
  # echo "getGlyphShapeTT numberOfContours = ", numberOfContours

  if numberOfContours > 0:
    let endPtsOfContoursIdx = g + 10
    let insIdx = endPtsOfContoursIdx + numberOfContours * 2
    let ins = info.data.contents.ttShort(insIdx)
    var pointsIdx = insIdx + 2 + ins

    let n = 1 + info.data.contents.ttShort(insIdx - 2)
    let m = n + 2*numberOfContours    # A loose bound on how many vertices we might need
    # echo "getGlyphShapeTT n = ", n
    # echo "getGlyphShapeTT m = ", m
    # vertices.setLen(m)
    vertices = newSeqOfCap[Vertex](m)

    # In first pass, we load uninterpreted data
    var uninterpreted = newSeq[var Vertex](n)
    # First load flags
    var flags = 0'u8
    var flagCount = 0
    for i in 0 ..< n:
      if flagCount == 0:
        flags = info.data.contents[pointsIdx]
        inc pointsIdx
        if (flags and 8) > 0:
          flagCount += info.data.contents[pointsIdx].int
          inc pointsIdx
      else:
        dec flagCount
      uninterpreted[i].vtype = flags
    # Now load x coordinates
    var x = 0
    for i in 0 ..< n:
      flags = uninterpreted[i].vtype
      if (flags and 2) > 0:
        let dx = info.data.contents[pointsIdx].int16
        inc pointsIdx
        # Note: original code had question marks about the following
        if (flags and 16) > 0:
          x += dx
        else:
          x -= dx
      else:
        if (flags and 16) == 0:
          x += info.data.contents.ttShort(pointsIdx)
          pointsIdx += 2
      uninterpreted[i].x = x.int16
    # Now load y coordinates
    var y = 0
    for i in 0 ..< n:
      flags = uninterpreted[i].vtype
      if (flags and 4) > 0:
        let dy = info.data.contents[pointsIdx].int16
        inc pointsIdx
        # Note: original code had question marks about the following
        if (flags and 32) > 0:
          y += dy
        else:
          y -= dy
      else:
        if (flags and 32) == 0:
          y += info.data.contents.ttShort(pointsIdx)
          pointsIdx += 2
      uninterpreted[i].y = y.int16

    # Now convert the uninterpreted data to our format
    var nextMove: int
    var sx, sy, cx, cy, scx, scy: int
    var wasOff, startOff: bool
    var j = 0
    var i = 0
    while i < n:
      # echo "\t i = ", i, "   nextMove = ", nextMove
      flags = uninterpreted[i].vtype
      let x = uninterpreted[i].x
      let y = uninterpreted[i].y

      if nextMove == i:
        # echo "\t\t nextMove == i"
        if i != 0:
          # numVertices = vertices.closeShape(numVertices, wasOff, startOff,
          #   sx, sy, scx, scy, cx, cy)
          # echo "\t\t numVertices 1 = ", numVertices
          vertices.closeShape(wasOff, startOff, sx, sy, scx, scy, cx, cy)
          # echo "\t\t vertices.len 1 = ", vertices.len
        # Now start the new one
        startOff = (flags and 1) == 0
        let i1 = i + 1
        if startOff:
          # If we start off with an off-curve point, then when we need to find a point on the curve
          # where we can start, and we need to save some state for when we wraparound.
          scx = x
          scy = y
          if (uninterpreted[i1].vtype and 1) == 0:
            # Next point is also a curve point, so interpolate an on-point curve
            sx = (x + uninterpreted[i1].x).shr(1)
            sy = (y + uninterpreted[i1].y).shr(1)
          else:
            # Otherwise just use the next point as our start point
            sx = uninterpreted[i1].x
            sy = uninterpreted[i1].y
            inc i   # We're using point i+1 as the starting point, so skip it
        else:
          sx = x
          sy = y
        # vertices[numVertices].setFields(Vmove.uint8, sx, sy, 0, 0)
        # inc numVertices
        # echo "\t\t numVertices 2 = ", numVertices
        vertices.add(Vertex(vtype: Vmove.uint8, x: sx.int16, y: sy.int16))
        # echo "\t\t vertices.len 2 = ", vertices.len
        wasOff = false
        nextMove = 1 + info.data.contents.ttUshort(endPtsOfContoursIdx + j * 2).int
        # echo "\t\t nextMove = ", nextMove
        inc j
      else:
        # echo "\t\t else (nextMove != i)"
        if (flags and 1) == 0:    # If it's a curve
          # echo "\t\t it's a curve"
          if wasOff:    # Two off-curve control points in a row means interpolate an on-curve midpoint
            # vertices[numVertices].setFields(Vcurve.uint8, (cx + x).shr(1), (cy + y).shr(1), cx, cy)
            # inc numVertices
            # echo "\t\t numVertices 1 = ", numVertices
            vertices.add(Vertex(vtype: Vcurve.uint8, x: (cx + x).shr(1).int16, y: (cy + y).shr(1).int16, cx: cx.int16, cy: cy.int16))
            # echo "\t\t vertices.len 1 = ", vertices.len
          cx = x
          cy = y
          wasOff = true
        else:
          # echo "\t\t it's NOT a curve"
          if wasOff:
            # echo "\t\t Call setFields with Vcurve"
            # vertices[numVertices].setFields(Vcurve.uint8, x, y, cx, cy)
            # echo "\t\t Add a Vertex with Vcurve"
            vertices.add(Vertex(vtype: Vcurve.uint8, x: x.int16, y: y.int16, cx: cx.int16, cy: cy.int16))
          else:
            # echo "\t\t Call setFields with Vline"
            # vertices[numVertices].setFields(Vline.uint8, x, y, 0, 0)
            # echo "\t\t Add a Vertex with Vline"
            vertices.add(Vertex(vtype: Vline.uint8, x: x.int16, y: y.int16))
          # inc numVertices
          # echo "\t\t vertices.len 2 = ", vertices.len
          wasOff = false
      inc i
    # numVertices = vertices.closeShape(numVertices, wasOff, startOff, sx, sy, scx, scy, cx, cy)
    # echo "getGlyphShapeTT numVertices = ", numVertices
    vertices.closeShape(wasOff, startOff, sx, sy, scx, scy, cx, cy)
    # echo "getGlyphShapeTT vertices.len = ", vertices.len
  elif numberOfContours < 0:
    # Compound shapes.
    var more = 1
    var compIdx = g + 10
    vertices.setLen(0)
    var compVerts = newSeq[Vertex](0)

    while more > 0:
      var mtx = [ 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 ]
      let flags = info.data.contents.ttShort(compIdx)
      compIdx += 2
      let gidx = info.data.contents.ttShort(compIdx)
      compIdx += 2

      if (flags and 2) > 0:   # XY values
        if (flags and 1) > 0:   # shorts
          mtx[4] = info.data.contents.ttShort(compIdx).float
          compIdx += 2
          mtx[5] = info.data.contents.ttShort(compIdx).float
          compIdx += 2
        else:
          mtx[4] = info.data.contents.ttInt8(compIdx).float
          compIdx += 1
          mtx[5] = info.data.contents.ttInt8(compIdx).float
          compIdx += 1
      else:
        # From original code: TODO handle matching point
        assert(false)
      if (flags and 1.shl(3)) > 0:    # We have a SCALE
        mtx[0] = info.data.contents.ttShort(compIdx).float / 16384.0
        mtx[3] = mtx[0]
        compIdx += 2
        mtx[1] = 0
        mtx[2] = 0
      elif (flags and 1.shl(6)) > 0:    # We have an X_AND_YSCALE
        mtx[0] = info.data.contents.ttShort(compIdx).float / 16384.0
        compIdx += 2
        mtx[1] = 0
        mtx[2] = 0
        mtx[3] = info.data.contents.ttShort(compIdx).float / 16384.0
        compIdx += 2
      elif (flags and 1.shl(7)) > 0:    # We have a TWO_BY_TWO
        mtx[0] = info.data.contents.ttShort(compIdx).float / 16384.0
        compIdx += 2
        mtx[1] = info.data.contents.ttShort(compIdx).float / 16384.0
        compIdx += 2
        mtx[2] = info.data.contents.ttShort(compIdx).float / 16384.0
        compIdx += 2
        mtx[3] = info.data.contents.ttShort(compIdx).float / 16384.0
        compIdx += 2
      
      # Find transformation scales.
      let m = sqrt(mtx[0] * mtx[0] + mtx[1] * mtx[1])
      let n = sqrt(mtx[2]*mtx[2] + mtx[3]*mtx[3])

      # Get indexed glyph
      let compNumVerts = info.getGlyphShape(gidx, compVerts)
      if compNumVerts > 0:
        # Transform vertices.
        for i in 0 ..< compNumVerts:
          var x = compVerts[i].x.float
          var y = compVerts[i].y.float
          compVerts[i].x = (m * (mtx[0] * x + mtx[2] * y + mtx[4])).int16
          compVerts[i].y = (n * (mtx[1] * x + mtx[3] * y + mtx[5])).int16
          x = compVerts[i].cx.float
          y = compVerts[i].cy.float
          compVerts[i].cx = (m * (mtx[0] * x + mtx[2] * y + mtx[4])).int16
          compVerts[i].cy = (n * (mtx[1] * x + mtx[3] * y + mtx[5])).int16
        # Append vertices.
        vertices.add(compVerts)
        compVerts.setLen(0)

      # More components ?
      more = flags and 1.shl(5)
  else:
    # numberOfContours == 0, do nothing
    discard

  result = vertices.len

#--- stbtt__GetGlyphShapeT2
proc getGlyphShapeT2(info: FontInfo, glyphIndex: int, vertices: var seq[Vertex]): int =
  # Runs the charstring twice, once to count and once to output (to avoid realloc)
  var countCtx = makeCsctx(true)
  var outputCtx = makeCsctx(false)
  # echo "getGlyphShapeT2"
  if info.runCharstring(glyphIndex, countCtx):
    # echo "getGlyphShapeT2 countCtx.numVertices = ", countCtx.numVertices
    outputCtx.vertices = newSeqOfCap[Vertex](countCtx.numVertices)
    if info.runCharstring(glyphIndex, outputCtx):
      # echo "getGlyphShapeT2 outputCtx.numVertices = ", outputCtx.numVertices
      assert(outputCtx.numVertices == countCtx.numVertices)
      result = outputCtx.numVertices
      # echo "getGlyphShapeT2 outputCtx.vertices.len = ", outputCtx.vertices.len
      # echo "getGlyphShapeT2 outputCtx.vertices:"
      # for vertex in outputCtx.vertices:
      #   echo "\t", $vertex
      vertices = move(outputCtx.vertices)
      # echo "getGlyphShapeT2 vertices.len = ", vertices.len
      # echo "vertices:"
      # for vertex in vertices:
      #   echo "\t", $vertex
      return
  result = 0
  vertices.setLen(0)

#--- stbtt_GetGlyphShape
proc getGlyphShape(info: FontInfo, glyphIndex: int, vertices: var seq[Vertex]): int {.gcsafe.} =
  # echo "getGlyphShape info.cff.size = ", info.cff.size
  if info.cff.size == 0:
    result = info.getGlyphShapeTT(glyphIndex, vertices)
  else:
    result = info.getGlyphShapeT2(glyphIndex, vertices)
    # echo "getGlyphShape result = ", result

#--- stbtt__tesselate_curve
proc tesselateCurve(points: var seq[Point], numPoints: var int,
    x0, y0, x1, y1, x2, y2, objspaceFlatnessSquared: float, pass, n: int) =
  # echo "tesselateCurve n = ", n, "    objspaceFlatnessSquared = ", objspaceFlatnessSquared
  # midpoint
  let mx = (x0 + 2.0 * x1 + x2) / 4.0
  let my = (y0 + 2.0 * y1 + y2) / 4.0
  # versus directly drawn line
  let dx = (x0 + x2) / 2.0 - mx
  let dy = (y0 + y2) / 2.0 - my
  if n <= 16:   # Recursion limit - 65536 segments on one curve better be enough!
    if dx * dx + dy * dy > objspaceFlatnessSquared:   # half-pixel error allowed... need to be smaller if AA
      # echo "\t Recursive call 1 to tesselateCurve"
      points.tesselateCurve(numPoints, x0, y0, (x0 + x1) / 2.0, (y0 + y1) / 2.0,
        mx, my, objspaceFlatnessSquared, pass, n + 1)
      # echo "\t Recursive call 2 to tesselateCurve"
      points.tesselateCurve(numPoints, mx, my, (x1 + x2) / 2.0, (y1 + y2) / 2.0,
        x2, y2, objspaceFlatnessSquared, pass, n + 1)
    else:
      # First pass (=0) is counting only
      if pass > 0:
        points[numPoints].setFields(x2, y2)
      inc numPoints
      # echo "\t numPoints = ", numPoints

#--- stbtt__tesselate_cubic
proc tesselateCubic(points: var seq[Point], numPoints: var int,
    x0, y0, x1, y1, x2, y2, x3, y3, objspaceFlatnessSquared: float, pass, n: int) =
  # echo "tesselateCubic n = ", n, "    objspaceFlatnessSquared = ", objspaceFlatnessSquared
  # From orig code:
  #  TODO this "flatness" calculation is just made-up nonsense that seems to work well enough
  let dx0 = x1 - x0
  let dy0 = y1 - y0
  let dx1 = x2 - x1
  let dy1 = y2 - y1
  let dx2 = x3 - x2
  let dy2 = y3 - y2
  let dx = x3 - x0
  let dy = y3 - y0
  let longlen = sqrt(dx0 * dx0 + dy0 * dy0) + sqrt(dx1 * dx1 + dy1 * dy1) +
    sqrt(dx2 * dx2 + dy2 * dy2)
  let shortlensq = dx * dx + dy * dy
  let flatnessSquared = longlen * longlen - shortlensq
  # echo "\t flatnessSquared = ", flatnessSquared

  if n <= 16:   # Recursion limit - 65536 segments on one curve better be enough!
    if flatnessSquared > objspaceFlatnessSquared:
      let x01 = (x0 + x1) / 2.0
      let y01 = (y0 + y1) / 2.0
      let x12 = (x1 + x2) / 2.0
      let y12 = (y1 + y2) / 2.0
      let x23 = (x2 + x3) / 2.0
      let y23 = (y2 + y3) / 2.0

      let xa = (x01 + x12) / 2.0
      let ya = (y01 + y12) / 2.0
      let xb = (x12 + x23) / 2.0
      let yb = (y12 + y23) / 2.0

      let mx = (xa + xb) / 2.0
      let my = (ya + yb) / 2.0

      # echo "\t Recursive call 1 to tesselateCubic"
      points.tesselateCubic(numPoints, x0, y0, x01, y01, xa, ya, mx, my,
        objspaceFlatnessSquared, pass, n + 1)
      # echo "\t Recursive call 2 to tesselateCubic"
      points.tesselateCubic(numPoints, mx, my, xb, yb, x23, y23, x3, y3,
        objspaceFlatnessSquared, pass, n + 1)
    else:
      # First pass (=0) is counting only
      if pass > 0:
        points[numPoints].setFields(x3, y3)
      inc numPoints
      # echo "\t numPoints = ", numPoints

#--- stbtt_FlattenCurves
# Returns number of contours and points in the contours
proc flattenCurves(vertices: openArray[Vertex], numVertices: int, objspaceFlatness: float,
    contourLengths: var seq[int], numContours: var int): seq[Point] =
  # Count how many "moves" there are to get the contour count
  numContours = 0
  # echo "flattenCurves numVertices = ", numVertices
  # echo "flattenCurves vertices.len = ", vertices.len
  # echo "flattenCurves objspaceFlatness = ", objspaceFlatness
  for i in 0 ..< numVertices:
    # echo "\tflattenCurves i = ", i, "    vertices = ", $vertices[i]
    if vertices[i].vtype == Vmove.ord:
      inc numContours
  # echo "flattenCurves numContours = ", numContours
  
  if numContours == 0:
    return

  contourLengths.setLen(numContours)

  # Make two passes through the points so we don't need to realloc
  var numPoints, start: int
  let objspaceFlatnessSquared = objspaceFlatness * objspaceFlatness
  var x, y: float
  for pass in 0 .. 1:
    # echo "\t pass = ", pass
    if pass == 1:
      result.setLen(numPoints)

    numPoints = 0
    var n = -1
    for i in 0 ..< numVertices:
      # echo "\t\t i = ", i
      # echo "\t\t vertices[i] = ", $vertices[i]
      case vertices[i].vtype.VertexType:
        of Vmove:
          # echo "\t\t Vmove - Start the next contour"
          # Start the next contour
          if n >= 0:
            contourLengths[n] = numPoints - start
            # echo "\t\t n = ", n, "    contourLengths[n] = ", contourLengths[n]
          inc n
          start = numPoints

          x = vertices[i].x.float
          y = vertices[i].y.float
          if pass == 1:
            result[numPoints].setFields(x, y)
          inc numPoints
          # echo "\t\t start = ", start, "    numPoints = ", numPoints
        of Vline:
          # echo "\t\t Vline"
          x = vertices[i].x.float
          y = vertices[i].y.float
          if pass == 1:
            result[numPoints].setFields(x, y)
          inc numPoints
          # echo "\t\t numPoints = ", numPoints
        of Vcurve:
          # echo "\t\t Vcurve"
          result.tesselateCurve(numPoints, x, y, vertices[i].cx.float, vertices[i].cy.float,
            vertices[i].x.float,  vertices[i].y.float, objspaceFlatnessSquared, pass, 0)
          x = vertices[i].x.float
          y = vertices[i].y.float
          # echo "\t\t numPoints = ", numPoints
        of Vcubic:
          # echo "\t\t Vcubic"
          result.tesselateCubic(numPoints, x, y,  vertices[i].cx.float, vertices[i].cy.float,
            vertices[i].cx1.float, vertices[i].cy1.float, vertices[i].x.float,  vertices[i].y.float,
            objspaceFlatnessSquared, pass, 0)
          x = vertices[i].x.float
          y = vertices[i].y.float
          # echo "\t\t numPoints = ", numPoints

    contourLengths[n] = numPoints - start
    # echo "\t\t n = ", n, "    contourLengths[n] = ", contourLengths[n]

proc `<`(a, b: Edge): bool =
  a.y0 < b.y0

#--- stbtt__sort_edges_quicksort
# The original code used pointer arithmetic. What we really need is seq views
# - but wemust make do with pointers until views are out of experimental
# proc quickSort(e: var seq[Edge], nt: int) =
proc quickSort(e: ptr UncheckedArray[Edge], nt: int) =
  var n = nt
  var p = e
  while n > 12:   # threshold for transitioning to insertion sort
    # compute median of three
    let m = n.shr(1)
    let n1 = n - 1
    let c12 = p[m] < p[n1]
    # if 0 >= mid >= end, or 0 < mid < end, then use mid
    if (p[0] < p[m]) xor c12:
      # otherwise, we'll need to swap something else to middle
      # Not sure what the following 2 comments are trying to say
      # 0>mid && mid<n:  0>n => n; 0<n => 0
      # 0<mid && mid>n:  0>n => 0; 0<n => n
      var z = 0
      if (p[0] < p[n1]) xor c12:
        z = n1
      
      swap(p[z], p[m])
    # now p[m] is the median-of-three
    # swap it to the beginning so it won't move around
    swap(p[0], p[m])

    #  partition loop
    var i = 1
    var j = n1
    while true:
      # handling of equality is crucial here for sentinels
      # and efficiency with duplicates
      while p[i] < p[0]:
        inc i
      while p[0] < p[j]:
        dec j
      # make sure we haven't crossed
      if i >= j:
        break
      
      swap(p[i], p[j])

      inc i
      dec j
    
    # recurse on smaller side, iterate on larger
    let ni = n - i
    let pi = cast[ptr UncheckedArray[Edge]](p[i].addr)
    if j < ni:
      p.quickSort(j)
      p = pi
      n = ni
    else:
      pi.quickSort(ni)
      n = j

#--- stbtt__sort_edges_ins_sort
proc insSort(e: var seq[Edge], n: int) =
  for i in 1 ..< n:
    let t = e[i]
    var j = i
    while j > 0:
      let j1 = j - 1
      if not(t < e[j1]):
        break
      e[j] = e[j1]
      dec j
    if i != j:
      e[j] = t

#--- stbtt__sort_edges
proc sort(e: var seq[Edge], n: int) =
  let p = cast[ptr UncheckedArray[Edge]](e[0].addr)
  p.quickSort(n)
  e.insSort(n)

proc initActiveEdgePool(chunkSize: int): ActiveEdgePool =
  result.chunkSize = chunkSize
  result.freshChunk = newSeq[ActiveEdge](chunkSize)
  result.nextFreshIndex = 0
  result.releasedPtrs = initDeque[ptr ActiveEdge](chunkSize)
  result.savedChunks = newSeq[seq[ActiveEdge]](0)

#--- stbtt__hheap_alloc
proc nextFreePtr(pool: var ActiveEdgePool): ptr ActiveEdge =
  if pool.releasedPtrs.len > 0:
    result = pool.releasedPtrs.popLast()
  else:
    if pool.nextFreshIndex < pool.freshChunk.len:
      result = cast[ptr ActiveEdge](pool.freshChunk[pool.nextFreshIndex].addr)
      inc pool.nextFreshIndex
    else:
      # echo "Address of original chunk = ", toHex(cast[uint](pool.freshChunk[0].addr))
      pool.savedChunks.add(move(pool.freshChunk))
      # echo "Address of last chunk in savedChunks = ", toHex(cast[uint](pool.savedChunks[^1][0].addr))
      pool.freshChunk = newSeq[ActiveEdge](pool.chunkSize)
      result = cast[ptr ActiveEdge](pool.freshChunk[0].addr)
      pool.nextFreshIndex = 1

#--- stbtt__hheap_free
proc releasePtr(pool: var ActiveEdgePool, ptrForRelease: ptr ActiveEdge) =
  pool.releasedPtrs.addLast(ptrForRelease)

#--- stbtt__new_active
proc getNewActiveEdge(pool: var ActiveEdgePool, e: Edge, offX: int, startPoint: float): ptr ActiveEdge =
  result = pool.nextFreePtr()
  let dxdy = (e.x1 - e.x0) / (e.y1 - e.y0)
  result.fdx = dxdy
  if dxdy != 0.0:
    result.fdy = 1.0 / dxdy
  else:
    result.fdy = 0.0
  result.fx = e.x0 + dxdy * (startPoint - e.y0)
  result.fx -= offX.float
  if e.invert:
    result.direction = 1.0
  else:
    result.direction = -1.0
  result.sy = e.y0
  result.ey = e.y1
  result.next = nil

#--- stbtt__handle_clipped_edge
# The edge passed in here does not cross the vertical line at x or the vertical line at x+1
# (i.e. it has already been clipped to those)
proc handleClippedEdge(scanline: var openArray[float], x: int, activeEdge: ptr ActiveEdge,
    x0p, y0p, x1p, y1p: float) =
  if y0p == y1p:
    return
  assert(y0p < y1p)
  assert(activeEdge.sy <= activeEdge.ey)
  if y0p > activeEdge.ey or y1p < activeEdge.sy:
    return

  var x0 = x0p
  var y0 = y0p
  var x1 = x1p
  var y1 = y1p
  if y0 < activeEdge.sy:
    x0 += (x1 - x0) * (activeEdge.sy - y0) / (y1 - y0)
    y0 = activeEdge.sy
  if y1 > activeEdge.ey:
    x1 += (x1 - x0) * (activeEdge.ey - y1) / (y1 - y0)
    y1 = activeEdge.ey
  
  let xf = x.float
  let xf1 = xf + 1.0
  if x0 == xf:
    assert(x1 <= xf1)
  elif x0 == xf1:
    assert(x1 >= xf)
  elif x0 <= xf:
    assert(x1 <= xf)
  elif x0 >= xf1:
    assert(x1 >= xf1)
  else:
    assert(x1 >= xf and x1 <= xf1)
  
  if x0 <= xf and x1 <= xf:
    scanline[x] += activeEdge.direction * (y1 - y0)
  elif x0 >= xf1 and x1 >= xf1:
    discard
  else:
    assert(x0 >= xf and x0 <= xf1 and x1 >= xf and x1 <= xf1)
    # coverage = 1 - average x position
    scanline[x] += activeEdge.direction * (y1 - y0) * (1.0 - ((x0 - xf) + (x1 - xf)) / 2.0)

#--- stbtt__sized_trapezoid_area
proc sizedTrapezoidArea(height, topWidth, bottomWidth: float): float =
  assert(topWidth >= 0)
  assert(bottomWidth >= 0)
  result = (topWidth + bottomWidth) / 2.0 * height

#--- stbtt__position_trapezoid_area
proc positionTrapezoidArea(height, tx0, tx1, bx0, bx1: float): float =
  result = sizedTrapezoidArea(height, tx1 - tx0, bx1 - bx0)

#--- stbtt__sized_triangle_area
proc sizedTriangleArea(height, width: float): float =
  result = height * width / 2.0

#--- stbtt__fill_active_edges_new
proc fillActiveEdgesNew(scanline, scanlineFill: var openArray[float], length: int,
    activeEdgesHead: ptr ActiveEdge, yTop: float) =
  #### Be careful about indexing for scanlineFill!!!
  let lenf = length.float
  let yBottom = yTop + 1.0
  var activeEdge = activeEdgesHead

  while not activeEdge.isNil:
    # Brute force every pixel

    # Compute intersection points with top & bottom
    assert(activeEdge.ey >= yTop)

    if activeEdge.fdx == 0:
      let x0 = activeEdge.fx
      if x0 < lenf:
        if x0 >= 0.0:
          let x = x0.int
          handleClippedEdge(scanline, x, activeEdge, x0, yTop, x0, yBottom)
          handleClippedEdge(scanlineFill, x + 1, activeEdge, x0, yTop, x0, yBottom)
        else:
          handleClippedEdge(scanlineFill, 0, activeEdge, x0, yTop, x0, yBottom)
    else:
      var x0 = activeEdge.fx
      var dx = activeEdge.fdx
      var xb = x0 + dx
      var xTop, xBottom: float
      var sy0, sy1: float
      var dy = activeEdge.fdy
      assert(activeEdge.sy <= yBottom and activeEdge.ey >= yTop)

      # Compute endpoints of line segment clipped to this scanline (if the
      # line segment starts on this scanline. x0 is the intersection of the
      # line with yTop, but that may be off the line segment
      if activeEdge.sy > yTop:
        xTop = x0 + dx * (activeEdge.sy - yTop)
        sy0 = activeEdge.sy
      else:
        xTop = x0
        sy0 = yTop
      if activeEdge.ey < yBottom:
        xBottom = x0 + dx * (activeEdge.ey - yTop)
        sy1 = activeEdge.ey
      else:
        xBottom = xb
        sy1 = yBottom
      
      if (xTop >= 0.0 and xBottom >= 0.0 and xTop < lenf and xBottom < lenf):
        # From here on, we don't have to range check x values

        if xTop.int == xBottom.int:
          let x = xTop.int
          let height = (sy1 - sy0) * activeEdge.direction
          assert(x >= 0 and x < length)
          let xTop1 = x.float + 1.0
          scanline[x] += positionTrapezoidArea(height, xTop, xTop1, xBottom, xTop1)
          scanlineFill[x + 1] += height   # Everything right of this pixel is filled
        else:
          # Covers 2+ pixels
          if xTop > xBottom:
            # Flip scanline vertically; signed area is the same
            sy0 = yBottom - (sy0 - yTop)
            sy1 = yBottom - (sy1 - yTop)
            swap(sy0, sy1)
            swap(xBottom, xTop)
            dx = -dx
            dy = -dy
            swap(x0, xb)
          assert(dy >= 0.0)
          assert(dx >= 0.0)

          let x1 = xTop.int
          let x1f = x1.float
          let x2 = xBottom.int
          let x2f = x2.float
          # Compute intersection with y axis at x1+1
          var yCrossing = yTop + dy * (x1f + 1.0 - x0)

          # Compute intersection with y axis at x2
          var yFinal = yTop + dy * (x2f - x0)

          #           x1    xTop                             x2     xBottom
          #      yTop  +------|-----+------------+------------+--------|---+------------+
          #            |            |            |            |            |            |
          #            |            |            |            |            |            |
          #       sy0  |      Txxxxx|============|============|============|============|
          #  yCrossing |            *xxxxx=======|============|============|============|
          #            |            |     xxxxx==|============|============|============|
          #            |            |     /-   xx*xxxx========|============|============|
          #            |            | dy <       |    xxxxxx==|============|============|
          #    yFinal  |            |     \-     |          xx*xxx=========|============|
          #       sy1  |            |            |            |   xxxxxB===|============|
          #            |            |            |            |            |            |
          #            |            |            |            |            |            |
          #   yBottom  +------------+------------+------------+------------+------------+
          #
          # goal is to measure the area covered by '=' in each pixel

          # From original code:
          # If x2 is right at the right edge of x1, yCrossing can blow up
          # @TODO: maybe test against sy1 rather than yBottom?
          if yCrossing > yBottom:
            yCrossing = yBottom
          
          let sign = activeEdge.direction

          # Area of the rectangle covered from sy0..y_crossing
          var area = sign * (yCrossing - sy0)

          # Area of the triangle (xTop,sy0), (x1+1,sy0), (x1+1,yCrossing)
          scanline[x1] += sizedTriangleArea(area, x1f + 1.0 - xTop)

          # Check if final yCrossing is blown up; no test case for this
          if yFinal > yBottom:
            yFinal = yBottom
            # Note for below: if denom=0, yFinal = yCrossing, so yFinal <= yBottom
            dy = (yFinal - yCrossing ) / (x2f - (x1f + 1.0))
          
          # In second pixel, area covered by line segment found in first pixel
          # is always a rectangle 1 wide * the height of that line segment; this
          # is exactly what the variable 'area' stores. It also gets a contribution
          # from the line segment within it. The THIRD pixel will get the first
          # pixel's rectangle contribution, the second pixel's rectangle contribution,
          # and its own contribution. The 'own contribution' is the same in every pixel except
          # the leftmost and rightmost, a trapezoid that slides down in each pixel.
          # The second pixel's contribution to the third pixel will be the
          # rectangle 1 wide times the height change in the second pixel, which is dy.

          # Note for below: dy is dy/dx, change in y for every 1 change in x,
          # which multiplied by 1-pixel-width is how much pixel area changes for each step in x
          # so the area advances by 'step' every time
          let step = sign * dy

          for x in (x1 + 1) ..< x2:
            scanline[x] += area + step / 2.0    # Area of trapezoid is 1*step/2
            area += step
          assert(abs(area) <= 1.01)   # Acumulated error from area += step unless we round step down
          assert(sy1 > yFinal - 0.01)

          # Area covered in the last pixel is the rectangle from all the pixels to the left,
          # plus the trapezoid filled by the line segment in this pixel all the way to the right edge
          scanline[x2] += area + sign * positionTrapezoidArea(sy1 - yFinal, x2f, x2f + 1.0, xBottom, x2f + 1.0)

          # The rest of the line is filled based on the total height of the line segment in this pixel
          scanlineFill[x2 + 1] += sign * (sy1 - sy0)
      else:
        # If edge goes outside of box we're drawing, we require
        # clipping logic. Since this does not match the intended use
        # of this library, we use a different, very slow brute
        # force implementation.
        # Note though that this does happen some of the time because
        # xTop and xBottom can be extrapolated at the top & bottom of
        # the shape and actually lie outside the bounding box.
        for x in 0 ..< length:
          # Cases:
          # 
          # There can be up to two intersections with the pixel. Any intersection
          # with left or right edges can be handled by splitting into two (or three)
          # regions. Intersections with top & bottom do not necessitate case-wise logic.
          # 
          # The old way of doing this found the intersections with the left & right edges,
          # then used some simple logic to produce up to three segments in sorted order
          # from top-to-bottom. However, this had a problem: if an x edge was epsilon
          # across the x border, then the corresponding y position might not be distinct
          # from the other y segment, and it might ignored as an empty segment. To avoid
          # that, we need to explicitly produce segments based on x positions.

          # Rename variables to clearly-defined pairs
          let y0 = yTop
          let x1 = x.float
          let x2 = x1 + 1.0
          let x3 = xb
          let y3 = yBottom

          # x = activeEdge.x + activeEdge.dx * (y - yTop)
          # (y-yTop) = (x - activeEdge.x) / activeEdge.dx
          # y = (x - activeEdge.x) / activeEdge.dx + yTop
          let xf = x.float
          let y1 = (xf - x0) / dx + yTop
          let y2 = (xf + 1.0 - x0) / dx + yTop

          if x0 < x1 and x3 > x2:         # three segments descending down-right
            handleClippedEdge(scanline, x, activeEdge, x0, y0, x1, y1)
            handleClippedEdge(scanline, x, activeEdge, x1, y1, x2, y2)
            handleClippedEdge(scanline, x, activeEdge, x2, y2, x3, y3)
          elif x3 < x1 and x0 > x2:       # three segments descending down-left
            handleClippedEdge(scanline, x, activeEdge, x0, y0, x2, y2)
            handleClippedEdge(scanline, x, activeEdge, x2, y2, x1, y1)
            handleClippedEdge(scanline, x, activeEdge, x1, y1, x3, y3)
          elif x0 < x1 and x3 > x1:       # two segments across x, down-right
            handleClippedEdge(scanline, x, activeEdge, x0, y0, x1, y1)
            handleClippedEdge(scanline, x, activeEdge, x1, y1, x3, y3)
          elif x3 < x1 and x0 > x1:       # two segments across x, down-left
            handleClippedEdge(scanline, x, activeEdge, x0, y0, x1, y1)
            handleClippedEdge(scanline, x, activeEdge, x1, y1, x3, y3)
          elif x0 < x2 and x3 > x2:       # two segments across x+1, down-right
            handleClippedEdge(scanline, x, activeEdge, x0, y0, x2, y2)
            handleClippedEdge(scanline, x, activeEdge, x2, y2, x3, y3)
          elif x3 < x2 and x0 > x2:       # two segments across x+1, down-left
            handleClippedEdge(scanline, x, activeEdge, x0, y0, x2, y2)
            handleClippedEdge(scanline, x, activeEdge, x2, y2, x3, y3)
          else:    # one segment
            handleClippedEdge(scanline,x,activeEdge, x0,y0, x3,y3)

    activeEdge = activeEdge.next

#--- stbtt__rasterize_sorted_edges
# Directly AA rasterize edges w/o supersampling
proc rasterizeSortedEdges(bitmap: var Bitmap, edges: var openArray[Edge], n, offX, offY: int) =
  var pool = initActiveEdgePool(1000)

  var scanline = newSeq[float](bitmap.width)
  var scanline2 = newSeq[float](bitmap.width + 1)   #### Be careful about indexing for this!
  var headActive: ptr ActiveEdge = nil    # Pointer to head of list of active edges

  var y = offY
  edges[n].y0 = (offY + bitmap.height + 1).float

  # echo "rasterizeSortedEdges offY = ", offY
  # echo "rasterizeSortedEdges bitmap.height = ", bitmap.height
  var edgeIdx = 0
  var j = 0
  while j < bitmap.height:
    # echo "\n\t j = ", j, "   y = ", y
    # Find center of pixel for this scanline
    let scanYTop = y.float
    let scanYBottom = scanYTop + 1.0
    # echo "\t scanYTop = ", scanYTop, "   scanYBottom = ", scanYBottom

    zeroMem(scanline[0].addr, scanline.len * sizeof(float))
    zeroMem(scanline2[0].addr, scanline2.len * sizeof(float))

    # ----- Update all active edges -----
    # Remove all active edges that terminate before the top of this scanline
    # echo "\n\t Before ActiveEdges pruning"
    # headActive.printActiveEdges("\t\t")
    # echo ""
    var step = headActive
    var prevActive: ptr ActiveEdge = nil    # Pointer to previous confirmed active edge
    while not step.isNil:
      let z = step
      if z.ey <= scanYTop:
        # Delete from list
        step = z.next
        if prevActive.isNil:
          headActive = step
        else:
          prevActive.next = step
        assert(z.direction != 0.0)
        z.direction = 0.0
        pool.releasePtr(z)
      else:
        if prevActive.isNil:
          headActive = step
        prevActive = step
        step = step.next    # Advance through list
    
    # echo "\n\t After ActiveEdges pruning"
    # headActive.printActiveEdges("\t\t")
    # echo ""

    # Insert all edges that start before the bottom of this scanline
    while edges[edgeIdx].y0 <= scanYBottom:
      # echo "\t\t edgeIdx = ", edgeIdx
      # echo "\t\t edges[edgeIdx].y0 = ", edges[edgeIdx].y0, "   edges[edgeIdx].y1 = ", edges[edgeIdx].y1
      if edges[edgeIdx].y0  != edges[edgeIdx].y1:
        # echo "\t\t edges[edgeIdx] = \n\t\t\t", edges[edgeIdx]
        let z = pool.getNewActiveEdge(edges[edgeIdx], offX, scanYTop)
        # echo "\t\t z.ey = ", z.ey
        if j == 0 and offY != 0:
          if z.ey < scanYTop:
            # From original code:
            # This can happen due to subpixel positioning and some kind of fp rounding error i think
            # echo "\t\t Set z.ey to ", scanYTop
            z.ey = scanYTop
        # echo "\t\t z.ey = ", z.ey, "    scanYTop = ", scanYTop
        # z.printAttribs("\t\t")
        assert(z.ey >= scanYTop)  # If we get really unlucky a tiny bit of an edge can be out of bounds
        # Insert at front
        z.next = headActive
        headActive = z
      inc edgeIdx
    # ----------

    # Now process all active edges
    if not headActive.isNil:
      fillActiveEdgesNew(scanline, scanline2, bitmap.width, headActive, scanYTop)
    
    var sum = 0.0
    for i in 0 ..< bitmap.width:
      sum += scanline2[i]
      var k = scanline[i] + sum
      k = abs(k) * 255.0 + 0.5
      let m = min(k.int, 255)
      bitmap.pixels[j * bitmap.stride + i] = m.byte
    # Advance all the edges
    step = headActive
    while not step.isNil():
      step.fx += step.fdx   # Advance to position for current scanline
      step = step.next    # Advance through list
    
    inc y
    inc j

  # Original code had de-allocations here - we let destructors do the work instead

#--- stbtt__rasterize
proc rasterize2(bitmap: var Bitmap, pts: openArray[Point], wcount: openArray[int], windings: int,
    scaleX, scaleY, shiftX, shiftY: float, offX, offY : int, invert: bool) =
  var yScaleInv = scaleY
  if invert:
    yScaleInv = -scaleY

  # echo "\nrasterize2 windings = ", windings
  # Now we have to blow out the windings into explicit edge lists
  var n = 0
  for i in 0 ..< windings:
    # echo "\t i = ", i, "   wcount[i] = ", wcount[i]
    n += wcount[i]
  # echo "rasterize2 n = ", n
  var edges = newSeq[Edge](n + 1)   # add an extra one as a sentinel

  n = 0
  var m = 0
  for i in 0 ..< windings:
    let pidx = m
    m += wcount[i]
    var j = wcount[i] - 1
    for k in 0 ..< wcount[i]:
      var a = k
      var b = j
      let pidxj = pidx + j
      let pidxk = pidx + k
      if pts[pidxj].y != pts[pidxk].y:    # skip the edge if horizontal
        # add edge from j to k to the list
        edges[n].invert = false
        if (invert and pts[pidxj].y > pts[pidxk].y) or ((not invert) and pts[pidxj].y > pts[pidxk].y):
          edges[n].invert = true
          a = j
          b = k
        let pidxa = pidx + a
        let pidxb = pidx + b
        edges[n].x0 = pts[pidxa].x * scaleX + shiftX
        edges[n].y0 = (pts[pidxa].y * yScaleInv + shiftY)
        edges[n].x1 = pts[pidxb].x * scaleX + shiftX
        edges[n].y1 = (pts[pidxb].y * yScaleInv + shiftY)
        inc n
      j = k
  
  # Now sort the edges by their highest point (should snap to integer, and then by x)
  edges.sort(n)

  # Now, traverse the scanlines and find the intersections on each scanline, use xor winding rule
  bitmap.rasterizeSortedEdges(edges, n, offX, offY)

  # Original code de-allocated "edges" here - we let seq destructor do the work instead

#--- stbtt_Rasterize
# Rasterize a shape with quadratic beziers into a bitmap
proc rasterize1(bitmap: var Bitmap, flatnessInPixels: float, vertices: openArray[Vertex],
    numVertices: int, scaleX, scaleY, shiftX, shiftY: float, xOff, yOff: int, invert: bool) =
  var scale = scaleX
  if scaleX > scaleY:
    scale = scaleY
  
  var windingLengths = newSeq[int](0)
  var windingCount = 0
  let windings = vertices.flattenCurves(numVertices, flatnessInPixels / scale, windingLengths,
    windingCount)
  # echo "rasterize1 windingLengths.len = ", windingLengths.len
  # echo "rasterize1 windings.len = ", windings.len
  # echo "rasterize1 windingCount = ", windingCount
  if windings.len > 0:
    bitmap.rasterize2(windings, windingLengths, windingCount, scaleX, scaleY, shiftX, shiftY,
      xOff, yOff, invert)

  # ORC/ARC should take care of the following
  # windingLengths.setLen(0)
  # windings.setLen(0)

#--- stbtt_MakeGlyphBitmapSubpixel
proc makeGlyphBitmapSubpixel(info: FontInfo, output: ptr UncheckedArray[byte], outWidth, outHeight, outStride: Natural,
    scaleX, scaleY, shiftX, shiftY: float, glyphIndex: int) =
  # echo "makeGlyphBitmapSubpixel output addr = ", toHex(cast[uint](output))
  var vertices = newSeq[Vertex](0)
  let numVertices = info.getGlyphShape(glyphIndex, vertices)
  # echo "makeGlyphBitmapSubpixel vertices.len = ", vertices.len
  # echo "makeGlyphBitmapSubpixel numVertices = ", numVertices

  let (ix0, iy0, _, _) = info.getGlyphBitmapBoxSubpixel(glyphIndex, scaleX, scaleY, shiftX, shiftY)
  # echo "makeGlyphBitmapSubpixel ix0, iy0 = ", ix0, "  ", iy0
  var gbm = Bitmap(width: outWidth, height: outHeight, stride: outStride, pixels: output)
  # echo "makeGlyphBitmapSubpixel gbm.pixels addr = ", toHex(cast[uint](gbm.pixels))

  if gbm.width > 0 and gbm.height > 0:
    gbm.rasterize1(0.35, vertices, numVertices, scaleX, scaleY, shiftX, shiftY, ix0, iy0, true)

#--- stbtt_MakeGlyphBitmap
proc makeGlyphBitmap*(info: FontInfo, output: ptr UncheckedArray[byte], outWidth, outHeight, outStride: Natural,
    scaleX, scaleY: float, glyphIndex: int) =
  # echo "makeGlyphBitmap output addr = ", toHex(cast[uint](output))
  info.makeGlyphBitmapSubpixel(output, outWidth, outHeight, outStride, scaleX, scaleY, 0.0, 0.0, glyphIndex)

when isMainModule:

  when false:
    import std/strutils
    block:
      var bytes: array[0..3, byte]
      # Test set 1
      bytes[0] = 1
      bytes[1] = 150
      bytes[2] = 150
      bytes[3] = 1

      var msg = "bytes = " & $bytes & "    ["
      for i in 0 .. 2:
        msg &= "0x" & toHex(bytes[i]) & ", "
      msg &= "0x" & toHex(bytes[3]) & "]"
      echo msg
      let su1 = bytes.ttUshort(0)
      echo "\t shortu 1 = ", su1, "   0x", toHex(su1)
      let su2 = bytes.ttUshort(2)
      echo "\t shortu 2 = ", su2, "   0x", toHex(su2)
      let si1 = bytes.ttShort(0)
      echo "\t shorti 1 = ", si1, "   0x", toHex(si1)
      let si2 = bytes.ttShort(2)
      echo "\t shorti 2 = ", si2, "   0x", toHex(si2)
      let lu = bytes.ttUlong(0)
      echo "\t longu = ", lu, "   0x", toHex(lu)
      let li = bytes.ttLong(0)
      echo "\t longi = ", li, "   0x", toHex(li)

  when true:
    import std/os
    import std/terminal
    import std/strutils
    import std/strformat

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
    
    proc promptForHexMode(): bool =
      result = false
      stdout.write("Hex mode? (Y or N): ")
      let ch = getch()
      echo ch
      if ch == 'Y' or ch == 'y':
        echo "Hex mode"
        result = true
      else:
        echo "ASCII (keyboard char) mode"
        result = false

    proc promptAndGetChar(): char =
      result = '\0'
      var done = false
      while not done:
        stdout.write("Enter character to display (Esc or Ctrl-C to quit): ")
        let ch = getch()
        if ch >= '\x20' and ch <= '\x7E':
          echo ch
          result = ch
          done = true
        elif ch == '\x1B' or ch == '\x03':
          echo ""
          done = true
        else:
          echo "... Not a printable character"

    proc promptAndGetCharHex(): char =
      result = '\0'
      var done = false
      while not done:
        stdout.write("Enter character hex code (1B or 03 to quit): ")
        let line = stdin.readLine()
        try:
          let ch = fromHex[uint8](line).char
          if ch != '\x1B' and ch != '\x03':
            result = ch
          done = true
        except:
          echo "'", line, "' is not valid hex"
    
    proc printColumns(maxCol: int) =
      let offset = 2
      let lineLen = maxCol + offset + 1
      let digits = "0123456789"
      var line = spaces(lineLen)
      for i in 0 .. maxCol:
        line[offset + i] = digits[i %% 10]
      echo line

      line = spaces(lineLen)
      for i in 0 .. (maxCol /% 10):
        line[offset + 10 * i] = digits[i]
      echo line

    echo ""
    # let fontpath = "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
    let fontpath = "/usr/share/fonts/gnu-free/FreeSans.otf"
    let fontData = readFileBytes(fontpath)
    echo "Number of bytes in fontData = ", fontData.len

    let fontinfo = new(FontInfo)
    if fontInfo.initFont(fontData, 0):
      echo "\nInitialized font"
    else:
    # if not fontInfo.initFont(fontData, 0):
      echo "\nCould not init font"
      raise newException(Exception, "Could not init font")

    let size = 16.0
    let scale = fontInfo.scaleForMappingEmToPixels(size)
    echo "Mapping scale = ", scale

    let (ascent, descent, lineGap) = fontInfo.getFontVMetrics()
    echo "FontVMetrics:   ascent = ", ascent, "  descent = ", descent, "  lineGap = ", lineGap

    let hexMode = promptForHexMode()
    var ch: char
    if hexMode:
      ch = promptAndGetCharHex()
    else:
      ch = promptAndGetChar()
    while ch > '\0':
      # let codepoint = ' '.int
      # let codepoint = 'a'.int
      let codepoint = ch.int
      let g = fontInfo.findGlyphIndex(codepoint)
      # echo "g = ", g

      let (advance, lsb) = fontInfo.getGlyphHMetrics(g)
      # echo "advance = ", advance
      # echo "lsb = ", lsb

      let (x0, y0, x1, y1) = fontInfo.getGlyphBitmapBox(g, scale, scale)
      # echo "x0 = ", x0
      # echo "y0 = ", y0
      # echo "x1 = ", x1
      # echo "y1 = ", y1
      # echo ""

      var screen = newSeq[byte](20 * 20)
      let swidth = 20
      let sheight = 20
      let stride = swidth
      let scptr = cast[ptr UncheckedArray[byte]](screen[0].addr)
      # echo "scptr = ", toHex(cast[uint](scptr))
      fontInfo.makeGlyphBitmap(scptr, x1 - x0, y1 - y0, stride, scale, scale, g)

      printColumns(swidth)
      var idx = 0
      let shades = " .:ioVM@"
      for j in 0 ..< sheight:
        stdout.write(fmt"{j:3d}")
        for i in 0 ..< swidth:
          stdout.write(shades[screen[idx].shr(5)])
          # stdout.write($screen[idx] & " ")
          inc idx
        stdout.write('\n')

      echo "\n"
      if hexMode:
        ch = promptAndGetCharHex()
      else:
        ch = promptAndGetChar()

  echo "\n...Done"
