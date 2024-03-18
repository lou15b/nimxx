import ./view
import ./meta_extensions / [ property_desc, visitors_gen, serializers_gen ]

type ClipView* = ref object of View

proc `=destroy`*(x: typeof ClipView()[]) =
  `=destroy`((typeof View()[])(x))

proc newClipView*(r: Rect): ClipView =
  result.new()
  result.init(r)
  result.autoresizingMask = { afFlexibleWidth, afFlexibleHeight }

method getClassName*(v: ClipView): string =
  result = "ClipView"

method subviewDidChangeDesiredSize*(v: ClipView, sub: View, desiredSize: Size) =
  v.superview.subviewDidChangeDesiredSize(v, desiredSize)

method clipType*(v: ClipView): ClipType = ctDefaultClip

proc enclosingClipView*(v: View): ClipView = v.enclosingViewOfType(ClipView)

registerClass(ClipView)
genVisitorCodeForView(ClipView)
genSerializeCodeForView(ClipView)
