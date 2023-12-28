import ../ [ types, view ]
import ./grid_drawing
import ./editor_types

method draw*(v: EditorWorkspace, r: Rect)=
    procCall v.View.draw(r)

    if v.gridSize != zeroSize:
        let c = v.window.renderingContext
        drawGrid(c, v.bounds, v.gridSize)


