import ../ [ view, context, button ]
import math

type ExpandButton* = ref object of Button
    expanded*: bool
    onExpandAction*: proc(state: bool) {.gcsafe.}

method getClassName*(v: ExpandButton): string =
    result = "ExpandButton"

method init*(b: ExpandButton, r: Rect) =
    procCall b.Button.init(r)

    b.enable()
    b.onAction() do():
        b.expanded = not b.expanded
        if not b.onExpandAction.isNil:
            b.onExpandAction(b.expanded)

proc newExpandButton*(r: Rect): ExpandButton =
    result.new()
    result.init(r)

proc newExpandButton*(v: View, r: Rect): ExpandButton =
    result = newExpandButton(r)
    v.addSubview(result)

method draw*(b: ExpandButton, r: Rect) =
    let c = b.window.renderingContext
    c.fillColor = newColor(0.9, 0.9, 0.9)
    c.drawTriangle(r, if b.expanded: Coord(PI / 2.0) else: Coord(0))
