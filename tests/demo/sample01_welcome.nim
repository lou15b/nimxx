import ./ [ sample_registry, autotest_runner ]

import nimxx / [ view, font, context, composition, button, autotest,
        gesture_detector, view_event_handling ]

import pkg/malebolgia/lockers

const welcomeMessage = "Welcome to nimX"

type WelcomeView = ref object of View
  welcomeFont: Font

proc `=destroy`*(x: typeof WelcomeView()[]) =
  try:
    `=destroy`(x.welcomeFont)
  except Exception as e:
    echo "Exception encountered destroying WelcomeView welcomeFont:", e.msg
  `=destroy`((typeof View()[])(x))

type CustomControl* = ref object of Control

proc `=destroy`*(x: typeof CustomControl()[]) =
  `=destroy`((typeof Control()[])(x))

method getClassName*(v: WelcomeView): string =
  result = "WelcomeView"

method getClassName*(v: CustomControl): string =
  result = "CustomControl"

method onScroll*(v: CustomControl, e: var Event): bool =
  echo "custom scroll ", e.offset
  result = true

method init(v: WelcomeView, r: Rect) =
  procCall v.View.init(r)
  let autoTestButton = newButton(newRect(20, 20, 150, 20))
  let secondTestButton = newButton(newRect(20, 50, 150, 20))
  autoTestButton.title = "Start Auto Tests"
  secondTestButton.title = "Second button"
  let tapd = newTapGestureDetector do(tapPoint : Point):
    echo "tap on second button"
    discard
  secondTestButton.addGestureDetector(tapd)
  autoTestButton.onAction do() {.gcsafe.}:
    echo "Autotest clicked"
    lock testRunner as runner:
      runner.startRegisteredTests()
  secondTestButton.onAction do():
    echo "second click"
  v.addSubview(autoTestButton)
  v.addSubview(secondTestButton)
  let vtapd = newTapGestureDetector do(tapPoint : Point):
    echo "tap on welcome view"
    discard
  v.addGestureDetector(vtapd)
  var cc: CustomControl
  cc.new
  cc.init(newRect(20, 80, 150, 20))
  cc.clickable = true
  cc.backgroundColor = newColor(1.0,0.0,0.0,1.0)
  cc.onAction do():
    echo "custom control clicked"
  let lis = newBaseScrollListener do(e : var Event):
    echo "tap down at: ",e.position
  do(dx, dy : float32, e : var Event):
    echo "scroll: ",e.position
  do(dx, dy : float32, e : var Event):
    echo "scroll end at: ",e.position
  let flingLis = newBaseFlingListener do(vx, vy: float):
    echo "flinged with velo: ",vx, " ",vy
  cc.addGestureDetector(newScrollGestureDetector(lis))
  cc.addGestureDetector(newFlingGestureDetector(flingLis))
  v.addSubview(cc)
  cc.trackMouseOver(true)

const gradientComposition = newComposition """
void compose() {
  vec4 color = gradient(smoothstep(bounds.x, bounds.x + bounds.z, vPos.x),
    newGrayColor(0.7),
    0.3, newGrayColor(0.5),
    0.5, newGrayColor(0.7),
    0.7, newGrayColor(0.5),
    newGrayColor(0.7)
  );
  drawShape(sdRect(bounds), color);
}
"""

method draw(v: WelcomeView, r: Rect) =
  let c = v.window.renderingContext
  if v.welcomeFont.isNil:
    v.welcomeFont = systemFontOfSize(64)
  gradientComposition.draw(c, v.bounds)
  let s = v.welcomeFont.sizeOfString(welcomeMessage)
  c.fillColor = whiteColor()
  c.drawText(v.welcomeFont, s.centerInRect(v.bounds), welcomeMessage)

registerSample(WelcomeView, "Welcome")
