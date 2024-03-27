import std/strutils
import ./sample_registry
import nimxx / [ view, font, button, text_field, slider, popup_button,
        formatted_text, segmented_control, scroll_view ]

type TextView = ref object of View
  text: FormattedText

proc `=destroy`*(x: typeof TextView()[]) =
  try:
    `=destroy`(x.text)
  except Exception as e:
    echo "Exception encountered destroying TextView text:", e.msg
  `=destroy`((typeof View()[])(x))

type TextSampleView = ref object of View

proc `=destroy`*(x: typeof TextSampleView()[]) =
  `=destroy`((typeof View()[])(x))

const textSample = """Nim is statically typed, with a simple syntax. It supports compile-time metaprogramming features such as syntactic macros and term rewriting macros.
  Term rewriting macros enable library implementations of common data structures such as bignums and matrixes to be implemented with an efficiency as if they would have been builtin language facilities.
  Iterators are supported and can be used as first class entities in the language as can functions, these features allow for functional programming to be used.
  Object-oriented programming is supported by inheritance and multiple dispatch. Functions can be generic and can also be overloaded, generics are further enhanced by the support for type classes.
  Operator overloading is also supported. Nim includes automatic garbage collection based on deferred reference counting with cycle detection.
  Andrew Binstock (editor-in-chief of Dr. Dobb's) says Nim (formerly known as Nimrod) "presents a most original design that straddles Pascal and Python and compiles to C code or JavaScript.
  And realistic Soft Shadow :)"""

iterator rangesOfSubstring(haystack, needle: string): (int, int) =
  var start = 0
  while true:
    let index = haystack.find(needle, start)
    if index == -1:
      break
    else:
      let b = index + needle.len
      yield (index, b)
      start = b

method getClassName*(v: TextView): string =
  result = "TextView"

method getClassName*(v: TextSampleView): string =
  result = "TextSampleView"

method init(v: TextSampleView, r: Rect) =
  procCall v.View.init(r)

  let tv = TextField.new(v.bounds.inset(50, 50))
  tv.resizingMask = "wh"
  tv.text = textSample
  tv.backgroundColor = newColor(0.5, 0, 0, 0.5)
  tv.multiline = true

  for a, b in tv.text.rangesOfSubstring("Nim"):
    tv.formattedText.setFontInRange(a, b, systemFontOfSize(40))
    tv.formattedText.setStrokeInRange(a, b, newColor(1, 0, 0), 5)

  for a, b in tv.text.rangesOfSubstring("programming"):
    tv.formattedText.setTextColorInRange(a, b, newColor(1, 0, 0))
    tv.formattedText.setShadowInRange(a, b, newGrayColor(0.5, 0.5), newSize(2, 3),
      0.0, 0.0)

  for a, b in tv.text.rangesOfSubstring("supported"):
    tv.formattedText.setTextColorInRange(a, b, newColor(0, 0.6, 0))

  for a, b in tv.text.rangesOfSubstring("Soft Shadow"):
    tv.formattedText.setFontInRange(a, b, systemFontOfSize(40))
    tv.formattedText.setShadowInRange(a, b, newColor(0.0, 0.0, 1.0, 1.0),
      newSize(2, 3), 5.0, 0.8)

  let sv = newScrollView(tv)
  v.addSubview(sv)

  let hAlignChooser = SegmentedControl.new(newRect(5, 5, 200, 25))
  hAlignChooser.segments = @[$haLeft, $haCenter, $haRight]
  v.addSubview(hAlignChooser)
  hAlignChooser.onAction do():
    tv.formattedText.horizontalAlignment =
      parseEnum[HorizontalTextAlignment](hAlignChooser.segments[hAlignChooser.selectedSegment])

  let vAlignChooser = SegmentedControl.new(newRect(hAlignChooser.frame.maxX + 5,
    5, 200, 25))
  vAlignChooser.segments = @[$vaTop, $vaCenter, $vaBottom]
  vAlignChooser.selectedSegment = 0
  v.addSubview(vAlignChooser)
  vAlignChooser.onAction do():
    tv.formattedText.verticalAlignment =
      parseEnum[VerticalAlignment](vAlignChooser.segments[vAlignChooser.selectedSegment])
  tv.formattedText.verticalAlignment = vaTop

method draw(v: TextView, r: Rect) =
  procCall v.View.draw(r)
  let c = v.window.renderingContext
  v.text.boundingSize = v.bounds.size
  c.drawText(newPoint(0, 0), v.text)

registerSample(TextSampleView, "Text")
