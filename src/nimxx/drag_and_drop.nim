import ./view
import ./types

import ./image
import ./pasteboard/pasteboard_item

import malebolgia/lockers

type DragSystem* = ref object
    itemPosition*: Point
    pItem*: PasteboardItem
    prevTarget*: View
    image*: Image

# Only one object is being dragged at any one time, so only one DragSystem object is ever needed
var dragSystem* = initLocker(new(DragSystem))

proc startDrag*(item: PasteboardItem, ds: DragSystem, image: Image = nil) =
    ds.pItem = item
    ds.image = image
    ds.prevTarget = nil

proc stopDrag*(ds: DragSystem) =
    ds.pItem = nil
    ds.prevTarget = nil

proc newDragDestinationDelegate*(): DragDestinationDelegate =
    result.new()

method onDrag*(dd: DragDestinationDelegate, target: View, i: PasteboardItem) {.base, gcsafe.} = discard
method onDrop*(dd: DragDestinationDelegate, target: View, i: PasteboardItem) {.base, gcsafe.} = discard
method onDragEnter*(dd: DragDestinationDelegate, target: View, i: PasteboardItem) {.base, gcsafe.} = discard
method onDragExit*(dd: DragDestinationDelegate, target: View, i: PasteboardItem) {.base, gcsafe.} = discard

proc findSubviewAtPoint*(v: View, p: Point, res: var View) =
    for i in countdown(v.subviews.len - 1, 0):
        let s = v.subviews[i]
        var pp = s.convertPointFromParent(p)
        if pp.inRect(s.bounds):
            s.findSubviewAtPoint(pp, res)
            if not res.isNil:
                break


proc findSubviewAtPointAux*(v: View, p: Point, target: var View): View =
    for i in countdown(v.subviews.len - 1, 0):
        let s = v.subviews[i]
        var pp = s.convertPointFromParent(p)
        if pp.inRect(s.bounds):
            if not v.dragDestination.isNil:
                target = v
            result = s.findSubviewAtPointAux(pp, target)
            if not result.isNil:
                break

    if result.isNil:
        result = v
        if not result.dragDestination.isNil:
            target = result


proc findSubviewAtPoint*(v: View, p: Point): View =
    discard v.findSubviewAtPointAux(p, result)
    if result == v: result = nil


