import std/math # for PI
import ./sample_registry
import nimxx / [ view, context, animation, window, button, progress_indicator ]
import pkg/destructor

type AnimationSampleView = ref object of View
  rotation: Coord
  animation: Animation

AnimationSampleView.traceDestructor(tagfield = x.name):
  AnimationSampleView.destroyFields(x.animation)

method getClassName*(v: AnimationSampleView): string =
  result = "AnimationSampleView"

method init*(v: AnimationSampleView, r: Rect) =
  procCall v.View.init(r)
  v.animation = newAnimation()

  # Start/Stop button
  let startStopButton = newButton(newRect(20, 20, 50, 50))
  startStopButton.title = "Stop"
  let startStopButtonx {.cursor.} = startStopButton
  let vx {.cursor.} = v
  startStopButtonx.onAction do():
    if vx.animation.finished:
      vx.window.addAnimation(vx.animation)
      startStopButtonx.title = "Stop"
    else:
      vx.animation.cancel()
  v.addSubview(startStopButton)

  v.animation.timingFunction = bezierTimingFunction(0.53,-0.53,0.38,1.52)
  vx.animation.onAnimate = proc(p: float) =
    vx.rotation = p * PI * 2
  v.animation.loopDuration = 2.0
  vx.animation.onComplete do():
    startStopButtonx.title = "Start"
  #v.animation.numberOfLoops = 2

  let playPauseButton = newButton(newRect(80, 20, 70, 50))
  playPauseButton.title = "Pause"
  let playPauseButtonx {.cursor.} = playPauseButton
  playPauseButtonx.onAction do():
    if playPauseButtonx.title == "Pause":
      vx.animation.pause()
      playPauseButtonx.title = "Resume"
    else:
      vx.animation.resume()
      playPauseButtonx.title = "Pause"
  v.addSubview(playPauseButton)


  let progressBar = ProgressIndicator.new(newRect(160, 20, 90, 20))
  v.addSubview(progressBar)

  # Loop progress handlers are called when animation reaches specified loop progress.
  let progressBarx {.cursor.} = progressBar
  v.animation.addLoopProgressHandler 1.0, false, proc() =
    progressBarx.value = 1.0

  v.animation.addLoopProgressHandler 0.5, false, proc() =
    progressBarx.value = 0.5

  v.animation.continueUntilEndOfLoopOnCancel = true

method draw(v: AnimationSampleView, r: Rect) =
  let c = v.window.renderingContext
  c.fillColor = newGrayColor(0.5)
  var tmpTransform = c.transform
  tmpTransform.translate(newVector3(v.bounds.width/2, v.bounds.height/3, 0))
  tmpTransform.rotateZ(v.rotation)
  tmpTransform.translate(newVector3(-50, -50, 0))
  c.withTransform tmpTransform:
    c.fillColor = newColor(0, 1, 1)
    c.strokeColor = newColor(0, 0, 0, 1)
    c.strokeWidth = 9.0
    c.drawEllipseInRect(newRect(0, 0, 100, 200))

  tmpTransform = c.transform

  tmpTransform.translate(newVector3(v.bounds.width/2, v.bounds.height/3 * 2, 0))
  tmpTransform.rotateZ(-v.rotation)
  tmpTransform.translate(newVector3(-50, -50, 0))

  c.fillColor = newColor(0.5, 0.5, 0)
  c.strokeWidth = 0
  c.withTransform tmpTransform:
    c.drawRoundedRect(newRect(0, 0, 100, 200), 20)

  c.strokeWidth = 10
  c.strokeColor = blackColor()
  c.fillColor = clearColor()
  c.drawArc(newPoint(100, 300), 50, v.rotation, v.rotation + Pi / 2)

method viewWillMoveToWindow*(v: AnimationSampleView, w: Window) =
  if w.isNil:
    v.animation.cancel()
  else:
    w.addAnimation(v.animation)

registerSample(AnimationSampleView, "Animation")
