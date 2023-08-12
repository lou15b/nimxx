import ../ [
    view, toolbar, button, undo_manager,
    inspector_panel, event, view_event_handling
]

import ./grid_drawing

type
    EventCatchingView* = ref object of View
        keyUpDelegate*: proc (event: var Event) {.gcsafe.}
        keyDownDelegate*: proc (event: var Event) {.gcsafe.}
        mouseScrrollDelegate*: proc (event: var Event) {.gcsafe.}
        panningView*: View # View that we're currently moving/resizing with `panOp`
        editor*: Editor
        panOp*: PanOperation
        dragStartTime*: float
        origPanRect*: Rect
        origPanPoint*: Point
        mGridSize*: float

    EditView* = ref object of View
        editor*: Editor

    UIDocument* = ref object
        view*: View
        undoManager*: UndoManager
        path*: string
        takenViewNames*: seq[string] #used only for propose default names

    Editor* = ref object
        eventCatchingView*: EventCatchingView
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
