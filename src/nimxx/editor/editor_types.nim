import ../ [
  view, toolbar, button, undo_manager,
  inspector_panel, event, view_event_handling
]

import ./grid_drawing

import pkg/destructor

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

UIDocument.traceDestructor():
  UIDocument.destroyFields(x.view, x.undoManager, x.path, x.takenViewNames)

EditorWorkspace.traceDestructor(tagfield = x.name):
  # No fields to destroy
  discard

Editor.traceDestructor():
  Editor.destroyFields(x.inspector, x.mSelectedView, x.document, x.workspace)

EventCatchingView.traceDestructor(tagfield = x.name):
  EventCatchingView.destroyFields(x.keyUpDelegate, x.keyDownDelegate,
    x.mouseScrollDelegate, x.panningView, x.editor)

EditView.traceDestructor(tagfield = x.name):
  EditView.destroyFields(x.editor)

method getClassName*(v: EventCatchingView): string =
  result = "EventCatchingView"

method getClassName*(v: EditView): string =
  result = "EditView"

method getClassName*(v: EditorWorkspace): string =
  result = "EditorWorkspace"
