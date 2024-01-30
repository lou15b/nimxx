import ./linear_layout
import ./property_visitor
import ./property_editors/propedit_registry

import pkg/variant

export linear_layout

type InspectorView* = ref object of LinearLayout
    onPropertyChanged*: proc(name: string) {.gcsafe.}

method getClassName*(v: InspectorView): string =
    result = "InspectorView"

method init*(v: InspectorView, r: Rect) =
    procCall v.LinearLayout.init(r)
    v.horizontal = false

proc setInspectedObject*[T](v: InspectorView, o: T) =
    v.removeAllSubviews()
    if o.isNil: return

    proc onChanged(p: PropertyVisitor): proc() {.gcsafe.} =
        let name = p.name
        result = proc() {.gcsafe.} =
            if not v.onPropertyChanged.isNil:
                v.onPropertyChanged(name)

    let oo = newVariant(o)
    var visitor : PropertyVisitor
    visitor.requireName = true
    visitor.requireSetter = true
    visitor.requireGetter = true
    visitor.flags = { pfEditable }
    visitor.commit = proc() {.gcsafe.} =
        v.addSubview(propertyEditorForProperty(oo, visitor.name, visitor.setterAndGetter, onChange = onChanged(visitor)))

    o.visitProperties(visitor)
