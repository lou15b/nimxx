import ./sample_registry

import nimxx / [ view, segmented_control, color_picker, button, image, image_view,
        text_field, slider, popup_button, progress_indicator ]
import nimxx/assets/asset_manager

import pkg/malebolgia/lockers
import pkg/destructor

type ControlsSampleView = ref object of View

ControlsSampleView.traceDestructor(tagfield = x.name):
  # No fields that require destruction by Nim
  discard

method getClassName*(v: ControlsSampleView): string =
  result = "ControlsSampleView"

method init(v: ControlsSampleView, r: Rect) =
  procCall v.View.init(r)

  let label = newLabel(newRect(10, 10, 100, 20))
  let textField = newTextField(newRect(120, 10, v.bounds.width - 130, 20))
  textField.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  label.text = "Text field:"
  v.addSubview(label)
  v.addSubview(textField)

  let textFieldx {.cursor.} = textField

  let button = newButton(newRect(10, 40, 100, 22))
  button.title = "Button"
  let buttonx {.cursor.} = button
  buttonx.onAction do():
    textFieldx.text = "Click! "
  v.addSubview(button)

  let sc = SegmentedControl.new(newRect(120, 40, v.bounds.width - 130, 22))
  sc.segments = @["This", "is", "a", "segmented", "control"]
  sc.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  let scx  {.cursor.} = sc
  scx.onAction do():
    textFieldx.text = "Seg " & $scx.selectedSegment & "! "

  v.addSubview(sc)

  let checkbox = newCheckbox(newRect(10, 70, 50, 16))
  checkbox.title = "Checkbox"
  v.addSubview(checkbox)

  let progress = ProgressIndicator.new(newRect(120, 130, v.bounds.width - 130, 16))
  progress.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  v.addSubview(progress)

  let slider = Slider.new(newRect(120, 70, v.bounds.width - 130, 16))
  slider.autoresizingMask = { afFlexibleWidth, afFlexibleMaxY }
  let sliderx {.cursor.} = slider
  let progressx {.cursor.} = progress
  sliderx.onAction do():
    textFieldx.text = "Slider value: " & $sliderx.value & " "
    progressx.value = sliderx.value
  v.addSubview(slider)

  let vertSlider = Slider.new(newRect(v.bounds.width - 26, 150, 16, v.bounds.height - 160))
  vertSlider.autoresizingMask = { afFlexibleMinX, afFlexibleHeight }
  v.addSubview(vertSlider)

  let radiobox = newRadiobox(newRect(10, 90, 50, 16))
  radiobox.title = "Radiobox"
  v.addSubview(radiobox)

  let indeterminateCheckbox = newCheckbox(newRect(10, 130, 100, 16))
  indeterminateCheckbox.title = "Indeterminate"
  let indeterminateCheckboxx {.cursor.} = indeterminateCheckbox
  indeterminateCheckboxx.onAction do():
    progressx.indeterminate = indeterminateCheckboxx.boolValue
  v.addSubview(indeterminateCheckbox)

  let pb = PopupButton.new(newRect(120, 90, 120, 20))
  pb.items = @["Popup button", "Item 1", "Item 2"]
  v.addSubview(pb)

  let vx {.cursor.} = v
  lock sharedAssetManager as sam:
    sam.getAssetAtPath("cat.jpg") do(i: Image, err: string):
      discard newImageButton(vx, newPoint(260, 90), newSize(32, 32), i)

  let tfLabel = newLabel(newRect(330, 150, 150, 20))
  tfLabel.text = "<-- Enter some text"
  let tf1 = newTextField(newRect(10, 150, 150, 20))
  let tf2 = newTextField(newRect(170, 150, 150, 20))
  let tfLabelx {.cursor.} = tfLabel
  let tf1x {.cursor.} = tf1
  let tf2x {.cursor.} = tf2
  tf1x.onAction do():
    tfLabelx.text = "Left textfield: " & tf1x.text
  tf2x.onAction do():
    tfLabelx.text = "Right textfield: " & tf2x.text

  v.addSubview(tfLabel)
  v.addSubview(tf1)
  v.addSubview(tf2)

  let cp = newColorPickerView(newRect(0, 0, 400, 170))
  cp.setFrameOrigin(newPoint(10, 200))
  let cpx {.cursor.} = cp
  cpx.onColorSelected = proc(c: Color) =
    discard
  v.addSubview(cp)

  lock sharedAssetManager as sam:
    sam.getAssetAtPath("tile.png") do(i: Image, err: string):
      let imageView = newImageView(newRect(0, 400, 300, 150), i)
      vx.addSubview(imageView)

      let popupFillRule = newPopupButton(vx, newPoint(420, 400), newSize(100, 20),
        ["NoFill", "Stretch", "Tile", "FitWidth", "FitHeight"])
      let imageViewx {.cursor.} = imageView
      let popupFillRulex {.cursor.} = popupFillRule
      popupFillRulex.onAction do():
        imageViewx.fillRule = popupFillRulex.selectedIndex().ImageFillRule

registerSample(ControlsSampleView, "Controls")
