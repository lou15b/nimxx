import kiwi
import threading/smartptrs

type
  LayoutVars* = object
    x*, y*, width*, height*: Variable

proc init*(phs: var LayoutVars) =
  phs.x = newVariable("x", 0)
  phs.y = newVariable("y", 0)
  phs.width = newVariable("width", 0)
  phs.height = newVariable("height", 0)

proc centerX*(phs: LayoutVars): Expression = phs.x + phs.width / 2
proc centerY*(phs: LayoutVars): Expression = phs.y + phs.height / 2

proc left*(phs: LayoutVars): Variable {.inline.} = phs.x
proc right*(phs: LayoutVars): Expression {.inline.} = phs.x + phs.width

proc top*(phs: LayoutVars): Variable {.inline.} = phs.y
proc bottom*(phs: LayoutVars): Expression = phs.y + phs.height

const leftToRight = true

proc leading*(phs: LayoutVars): Expression =
  if leftToRight: newExpression(phs.left) else: -phs.right

proc trailing*(phs: LayoutVars): Expression =
  if leftToRight: phs.right else: -newExpression(phs.left)

proc origin*(phs: LayoutVars): array[2, Expression] = [newExpression(phs.x), newExpression(phs.y)]
proc center*(phs: LayoutVars): array[2, Expression] = [phs.centerX, phs.centerY]
proc size*(phs: LayoutVars): array[2, Expression] = [newExpression(phs.width), newExpression(phs.height)]

proc topLeading*(phs: LayoutVars): array[2, Expression] = [phs.leading, newExpression(phs.y)]
proc bottomTrailing*(phs: LayoutVars): array[2, Expression] = [phs.trailing, phs.bottom]

proc frame*(phs: LayoutVars): array[4, Expression] = [newExpression(phs.x), newExpression(phs.y), newExpression(phs.width), newExpression(phs.height)]

proc inset*(fr: array[4, Expression], left, top, right, bottom: float32): array[4, Expression] =
  [fr[0] + left, fr[1] + top, fr[2] - (left + right), fr[3] - (top + bottom)]

proc inset*(fr: array[4, Expression], byX, byY: float32): array[4, Expression] {.inline.} =
  inset(fr, byX, byY, byX, byY)

proc inset*(fr: array[4, Expression], by: float32): array[4, Expression] {.inline.} = inset(fr, by, by)

# ***********************
# What is the role of the LayoutVars objects represented by prevPHS, nextPHS, superPHS, selfPHS???
# They are global objects - in the original code they were threadvars, but their initialization
# was at top level, so only the ones in the main thread were valid.
# As far as I can tell they are never mutated after initialization, so locks aren't needed even
# in a multi-threaded situation. The following code is intended to allow their use without
# complaints about GC safety.
let prevPHSPtr = newConstPtr(new LayoutVars)
let nextPHSPtr = newConstPtr(new LayoutVars)
let superPHSPtr = newConstPtr(new LayoutVars)
let selfPHSPtr = newConstPtr(new LayoutVars)

template prevPHS*(): LayoutVars = prevPHSPtr[][]
template nextPHS*(): LayoutVars = nextPHSPtr[][]
template superPHS*(): LayoutVars = superPHSPtr[][]
template selfPHS*(): LayoutVars = selfPHSPtr[][]

init(prevPHS)
init(nextPHS)
init(superPHS)
init(selfPHS)
# ***********************

proc isNan(f: float32): bool {.inline.} = f != f

proc assertARDimentions(a, b, c: float32) =
  # Verifies that exactly one of the dimensions is NaN
  var i = 0
  if a.isNan: inc i
  if b.isNan: inc i
  if c.isNan: inc i
  assert(i == 1, "Exactly one of the dimensions must be NaN")

proc autoresizingFrame*(leading, width, trailing, top, height, bottom: float32): array[4, Expression] =
  assertARDimentions(leading, width, trailing)
  assertARDimentions(top, height, bottom)

  if leading.isNan:
    result[0] = superPHS.trailing - selfPHS.width - trailing
    result[2] = newExpression(width)
  elif width.isNan:
    result[0] = superPHS.leading + leading
    result[2] = superPHS.trailing - selfPHS.leading - trailing
  else: # trailing.isNan
    result[0] = superPHS.leading + leading
    result[2] = newExpression(width)

  if top.isNan:
    result[1] = superPHS.bottom - selfPHS.height - bottom
    result[3] = newExpression(height)
  elif height.isNan:
    result[1] = superPHS.top + top
    result[3] = superPHS.bottom - selfPHS.top - bottom
  else: # bottom.isNan
    result[1] = superPHS.top + top
    result[3] = newExpression(height)

