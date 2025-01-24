import std/strutils
import ./sample_registry
import nimxx / [ view, timer, text_field, button ]
import pkg/destructor

type TimersSampleView = ref object of View
  timer: Timer
  intervalTextField: TextField

TimersSampleView.traceDestructor(tagfield = x.name):
  TimersSampleView.destroyFields(x.timer, x.intervalTextField)

method getClassName*(v: TimersSampleView): string =
  result = "TimersSampleView"

method init(t: TimersSampleView, r: Rect) =
  procCall t.View.init(r)

  discard t.newLabel(newPoint(20, 20), newSize(120, 20), "interval: ")
  let intervalTextField = t.newTextField(newPoint(150, 20), newSize(120, 20), "5")

  discard t.newLabel(newPoint(20, 50), newSize(120, 20), "periodic: ")

  let periodicButton = newCheckbox(newRect(150, 50, 20, 20))
  t.addSubview(periodicButton)

  var firesLabel: TextField

  let startButton = newButton(newRect(20, 80, 100, 20))
  startButton.title = "Start"
  let tx {.cursor.} = t
  let intervalTextFieldx {.cursor.} = intervalTextField
  let periodicButtonx {.cursor.} = periodicButton
  let startButtonx {.cursor.} = startButton
  var firesLabelx {.cursor.} = firesLabel
  startButtonx.onAction do():
    tx.timer.clear()
    firesLabelx.text = "fires: "
    tx.timer = newTimer(parseFloat(intervalTextFieldx.text), periodicButtonx.boolValue,
      proc() =
        firesLabelx.text = firesLabelx.text & "O"
      )
  t.addSubview(startButton)

  let clearButton = newButton(newRect(20, 110, 100, 20))
  clearButton.title = "Clear"
  let clearButtonx {.cursor.} = clearButton
  clearButtonx.onAction do():
    tx.timer.clear()
  t.addSubview(clearButton)

  let pauseButton = newButton(newRect(20, 140, 100, 20))
  pauseButton.title = "Pause"
  let pauseButtonx {.cursor.} = pauseButton
  pauseButtonx.onAction do():
    if not tx.timer.isNil:
      tx.timer.pause()
  t.addSubview(pauseButton)

  let resumeButton = newButton(newRect(20, 170, 100, 20))
  resumeButton.title = "Resume"
  let resumeButtonx {.cursor.} = resumeButton
  resumeButtonx.onAction do():
    if not tx.timer.isNil:
      tx.timer.resume()
  t.addSubview(resumeButton)

  let secondsLabel = t.newLabel(newPoint(20, 200), newSize(120, 20), "seconds: ")
  var secs = 0
  let secondsLabelx {.cursor.} = secondsLabel
  setInterval 1.0, proc() =
    inc secs
    if secs >= 10:
      secs = 0
    secondsLabelx.text = "seconds: "
    for i in 0 ..< secs:
      secondsLabelx.text = secondsLabelx.text & "O"

  firesLabel = t.newLabel(newPoint(20, 230), newSize(120, 20), "fires: ")
  firesLabelx = firesLabel

registerSample(TimersSampleView, "Timers")
