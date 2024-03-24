{.used.}
import ./context
import ./view_dragging_listener
import ./linear_layout

type Toolbar* = ref object of LinearLayout

proc `=destroy`*(x: typeof Toolbar()[]) =
  `=destroy`((typeof LinearLayout()[])(x))

method getClassName*(v: Toolbar): string =
  result = "Toolbar"

method init*(v: Toolbar, r: Rect) =
  procCall v.LinearLayout.init(r)
  v.horizontal = true
  v.leftMargin = 10
  v.padding = 3
  v.topMargin = 3
  v.bottomMargin = 3
  v.rightMargin = 3
  v.enableDraggingByBackground()

method draw*(view: Toolbar, rect: Rect) =
  let c = view.window.renderingContext
  c.strokeWidth = 2
  c.strokeColor = newGrayColor(0.6, 0.7)
  c.fillColor = newGrayColor(0.3, 0.7)
  c.drawRoundedRect(view.bounds, 5)
