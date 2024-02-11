import std/sequtils
import pkg/threading/smartptrs
import std/isolation

import ./abstract_window
import ./event
import ./window_event_handling
import std / [ rlocks, logging ]

type EventFilterControl* = enum
  efcContinue
  efcBreak

type EventFilter* = proc(evt: var Event, control: var EventFilterControl): bool {.gcsafe.}

type ApplicationObj* = object of RootObj
  windows : seq[Window]
  eventFilters: seq[EventFilter]
  inputState: set[VirtualKey]
  modifiers: ModifiersSet
type Application* = SharedPtr[ApplicationObj]

proc `=destroy`(x: ApplicationObj) =
  `=destroy`(x.windows)
  `=destroy`(x.eventFilters)

proc pushEventFilter*(a: Application, f: EventFilter) = a[].eventFilters.add(f)

# proc newApplication(): ref ApplicationObj =
#     result.new()
#     result.windows = @[]
#     result.eventFilters = @[]
#     result.inputState = {}

# This global is only set at startup but its contents may be changed, so it needs to be guarded by a lock
# And that lock needs to be re-entrant
var mainAppLock*: RLock
mainAppLock.initRLock()
var mainApp* {.guard: mainAppLock.} =
    newSharedPtr(ApplicationObj(windows: @[], eventFilters: @[], inputState: {}))

proc addWindow*(a: Application, w: Window) =
  a[].windows.add(w)

proc removeWindow*(app: Application, w: Window) =
  let i = app[].windows.find(w)
  if i >= 0: app[].windows.delete(i)

proc handleEvent*(app: Application, e: var Event): bool =
  if numberOfActiveTouches() == 0 and e.kind == etMouse and e.buttonState == bsUp:
    # There may be cases when mouse up is not paired with mouse down.
    # This behavior may be observed in Web and native platforms, when clicking on canvas in menu-modal
    # mode. We just ignore such events.
    warn "Mouse up event ignored"
    return false

  if e.kind == etMouse and e.buttonState == bsDown and e.keyCode in app[].inputState:
    # There may be cases when mouse down is not paired with mouse up.
    # This behavior may be observed in Web and native platforms
    # We just send mouse bsUp fake event

    var fakeEvent = newMouseButtonEvent(e.position, e.keyCode, bsUp, e.timestamp)
    fakeEvent.window = e.window
    discard app.handleEvent(fakeEvent)

  beginTouchProcessing(e)

  if e.kind == etMouse or e.kind == etTouch or e.kind == etKeyboard:
    let kc = e.keyCode
    let isModifier = kc.isModifier
    if e.buttonState == bsDown:
      if isModifier:
        app[].modifiers.incl(kc)
      app[].inputState.incl(kc)
    else:
      if isModifier:
        app[].modifiers.excl(kc)
      app[].inputState.excl(kc)

  e.modifiers = app[].modifiers

  var control = efcContinue
  var cleanupEventFilters = false
  for i in 0 ..< app[].eventFilters.len:
    result = app[].eventFilters[i](e, control)
    if control == efcBreak:
      app[].eventFilters[i] = nil
      cleanupEventFilters = true
      control = efcContinue
    if result:
      break

  if cleanupEventFilters:
    app[].eventFilters.keepItIf(not it.isNil)

  if not result:
    if not e.window.isNil:
      result = e.window.handleEvent(e)
    elif e.kind in { etAppWillEnterBackground, etAppDidEnterBackground }:
      for w in app[].windows: w.enableAnimation(false)
    elif e.kind in { etAppWillEnterForeground, etAppDidEnterForeground }:
      for w in app[].windows: w.enableAnimation(true)

  endTouchProcessing(e)

proc drawWindows*(app: Application) =
  for w in app[].windows:
    if w.needsLayout:
      w.updateWindowLayout()

    if w.needsDisplay:
      w.drawWindow()

proc runAnimations*(app: Application) =
  for w in app[].windows: w.runAnimations()

proc keyWindow*(app: Application): Window =
  if app[].windows.len > 0:
    result = app[].windows[^1]
