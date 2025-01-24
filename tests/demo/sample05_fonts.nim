import std/strutils
import ./sample_registry
import nimxx / [ view, font, context, button, text_field, slider, popup_button ]
import pkg/destructor

type FontsView = ref object of View
  curFont: Font
  caption: string
  showBaseline: bool
  curFontSize: float
  baseline: Baseline

FontsView.traceDestructor(tagfield = x.name):
  FontsView.destroyFields(x.curFont, x.caption)

# template createSlider(fv: FontsView, title: string, y: var Coord, fr, to: Coord,
#     val: typed) =
proc createSlider(fv: FontsView, title: string, y: var Coord, fr, to: Coord) =
  let lb = newLabel(newRect(20, y, 120, 20))
  lb.text = title & ":"
  let s = Slider.new(newRect(140, y, 120, 20))
  let ef = newTextField(newRect(280, y, 120, 20))
  let fvx {.cursor.} = fv
  let sx {.cursor.} = s
  let efx {.cursor.} = ef
  sx.onAction do():
    let v = fr + (to - fr) * sx.value
    efx.text = $v
    # val = v
    fvx.curFontSize = v
    fvx.setNeedsDisplay()
  ef.onAction do():
    try:
      let v = parseFloat(efx.text)
      sx.value = (v - fr) / (to - fr)
      # val = v
      fvx.curFontSize = v
      fvx.setNeedsDisplay()
    except:
      discard
  fv.addSubview(lb)
  fv.addSubview(s)
  fv.addSubview(ef)
  y += 22

method getClassName*(v: FontsView): string =
  result = "FontsView"

method init(v: FontsView, r: Rect) =
  procCall v.View.init(r)
  let captionTf = newTextField(newRect(20, 20, r.width - 40, 20))
  captionTf.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  captionTf.text = "A Quick Brown $@#&¿"
  let vx {.cursor.} = v
  let captionTfx {.cursor.} = captionTf
  captionTfx.onAction do():
    vx.caption = captionTfx.text
    vx.setNeedsDisplay()
  v.addSubview(captionTf)
  captionTf.sendAction()

  var y = 44.Coord
  # vx.createSlider("size", y, 8.0, 80.0, vx.curFontSize)
  vx.createSlider("size", y, 8.0, 80.0)

  let showBaselineBtn = newCheckbox(newRect(20, y, 120, 16))
  showBaselineBtn.title = "Show baseline"
  let showBaselineBtnx {.cursor.} = showBaselineBtn
  showBaselineBtnx.onAction do():
    vx.showBaseline = showBaselineBtnx.boolValue
    vx.setNeedsDisplay()

  v.addSubview(showBaselineBtn)
  y += 16 + 5

  let baselineSelector = PopupButton.new(newRect(20, y, 120, 20))
  var items = newSeq[string]()
  for i in Baseline.low .. Baseline.high:
    items.add($i)
  baselineSelector.items = items
  let baselineSelectorx {.cursor.} = baselineSelector
  baselineSelectorx.onAction do():
    vx.baseline = Baseline(baselineSelectorx.selectedIndex)
    vx.setNeedsDisplay()
  v.addSubview(baselineSelector)

method draw(v: FontsView, r: Rect) =
  let c = v.window.renderingContext

  if v.curFont.isNil:
    v.curFont = systemFontOfSize(v.curFontSize)
  v.curFont.size = v.curFontSize

  let s = v.curFont.sizeOfString(v.caption)
  var origin = s.centerInRect(v.bounds)

  if v.showBaseline:
    c.fillColor = newGrayColor(0.5)
    c.drawRect(newRect(origin, newSize(s.width, 1)))

  c.fillColor = blackColor()
  let oldBaseline = v.curFont.baseline
  v.curFont.baseline = v.baseline
  c.drawText(v.curFont, origin, v.caption)
  v.curFont.baseline = oldBaseline

registerSample(FontsView, "Fonts")
