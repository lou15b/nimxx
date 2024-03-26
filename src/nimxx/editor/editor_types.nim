import ../ [
  view, toolbar, button, undo_manager,
  inspector_panel, event, view_event_handling
]

import ./grid_drawing

# TODO Rework this design
type
  EventCatchingView* = ref object of View
    keyUpDelegate*: proc (event: var Event) {.gcsafe.}
    keyDownDelegate*: proc (event: var Event) {.gcsafe.}
    mouseScrollDelegate*: proc (event: var Event) {.gcsafe.}
    panningView*: View # View that we're currently moving/resizing with `panOp`
    editor*: Editor
    panOp*: PanOperation
    dragStartTime*: float
    origPanRect*: Rect
    origPanPoint*: Point
    mGridSize*: float

  # This type doesn't appear to be used. Keeping it around for future
  # design re-work
  EditView* = ref object of View
    editor*: Editor

  UIDocument* = ref object
    view*: View
    undoManager*: UndoManager
    path*: string
    takenViewNames*: seq[string] #used only for propose default names

  # The Editor type is a composition of the various functional components
  # for an editor. However, it has no external ownership, which poses a problem
  # for memory management. So the object's owner is set to be EventCatchingView,
  # which *does* have external ownership (see startNimxEditorAsync in
  # edit_view.nim). A bit backwards, but hey.
  Editor* = ref object
    eventCatchingView* {.cursor.}: EventCatchingView
    inspector*: InspectorPanel
    mSelectedView*: View # View that we currently draw selection rect around
    document*: UIDocument
    workspace*: EditorWorkspace

  PanOperation* = enum
    poDrag
    poDragTL
    poDragT
    poDragTR
    poDragB
    poDragBR
    poDragBL
    poDragL
    poDragR

  EditorWorkspace* = ref object of View
    gridSize*: Size

proc `=destroy`*(x: typeof UIDocument()[]) =
  try:
    `=destroy`(x.view)
  except Exception as e:
    echo "Exception encountered destroying UIDocument view:", e.msg
  try:
    `=destroy`(x.undoManager)
  except Exception as e:
    echo "Exception encountered destroying UIDocument undoManager:", e.msg
  `=destroy`(x.path)
  `=destroy`(x.takenViewNames)

proc `=destroy`*(x: typeof EditorWorkspace()[]) =
  `=destroy`((typeof View()[])(x))

proc `=destroy`*(x: typeof Editor()[]) =
  try:
    `=destroy`(x.inspector)
  except Exception as e:
    echo "Exception encountered destroying Editor inspector:", e.msg
  try:
    `=destroy`(x.mSelectedView)
  except Exception as e:
    echo "Exception encountered destroying Editor mSelectedView:", e.msg
  `=destroy`(x.document)
  `=destroy`(x.workspace)

proc `=destroy`*(x: typeof EventCatchingView()[]) =
  `=destroy`(x.keyUpDelegate.addr[])
  `=destroy`(x.keyDownDelegate.addr[])
  `=destroy`(x.mouseScrollDelegate.addr[])
  try:
    `=destroy`(x.panningView)
  except Exception as e:
    echo "Exception encountered destroying Editor mSelectedView panningView:", e.msg
  `=destroy`(x.editor)
  `=destroy`((typeof View()[])(x))

proc `=destroy`*(x: typeof EditView()[]) =
  try:
    `=destroy`(x.editor)
  except Exception as e:
    echo "Exception encountered destroying Editor EditView editor:", e.msg
  `=destroy`((typeof View()[])(x))

method getClassName*(v: EventCatchingView): string =
  result = "EventCatchingView"

method getClassName*(v: EditView): string =
  result = "EditView"

method getClassName*(v: EditorWorkspace): string =
  result = "EditorWorkspace"
