import times, ./mini_profiler

when defined(macosx):
    type TimerID = pointer
else:
    import sdl2

type TimerState = enum
    tsInvalid
    tsRunning
    tsPaused

when defined(debugLeaks):
    var allTimers {.threadvar.}: seq[pointer]

type
    Timer* = ref TimerObj
    TimerObj = object
        callback: proc() {.gcsafe.}
        origCallback: proc() {.gcsafe.}
        timer: TimerID
        interval: float
        isPeriodic: bool
        scheduleTime: float
        state: TimerState
        ready: bool
        when defined(debugLeaks):
            instantiationStackTrace*: string


const profileTimers = not defined(release)

when profileTimers or defined(debugLeaks):
    var totalTimers {.threadvar.}: ProfilerDataSource[int]

    proc `=destroy`(t: TimerObj) =
        dec totalTimers
        when defined(debugLeaks):
            let p = cast[pointer](addr t)
            let i = allTimers.find(p)
            assert(i != -1)
            allTimers.del(i)

when defined(macosx):
    type
        CFTimeInterval = cdouble
        CFAbsoluteTime = CFTimeInterval
        CFIndex = clong
        CFOptionFlags = culong
        CFRunLoopTimerContext = object
            version: CFIndex
            info: pointer
            retain: pointer
            release: pointer
            copyDescription: pointer
        CFTypeRef = pointer
        CFRunLoopTimerRef = CFTypeRef
        CFAllocatorRef = CFTypeRef
        CFRunLoopRef = CFTypeRef
        CFStringRef = CFTypeRef
        CFRunLoopMode = CFStringRef

        CFRunLoopTimerCallBack = proc(cfTimer: CFRunLoopTimerRef, info: pointer) {.cdecl.}

    var kCFRunLoopCommonModes {.importc.}: CFRunLoopMode

    proc CFAbsoluteTimeGetCurrent(): CFAbsoluteTime {.importc.}
    proc CFRunLoopGetCurrent(): CFRunLoopRef {.importc.}
    proc CFRunLoopAddTimer(rl: CFRunLoopRef, timer: CFRunLoopTimerRef, mode: CFRunLoopMode) {.importc.}
    proc CFRunLoopTimerCreate(allocator: CFAllocatorRef, fireDate: CFAbsoluteTime, interval: CFTimeInterval, flags: CFOptionFlags, order: CFIndex, callout: CFRunLoopTimerCallBack, context: ptr CFRunLoopTimerContext): CFRunLoopTimerRef {.importc.}
    proc CFRunLoopTimerInvalidate(t: CFRunLoopTimerRef) {.importc.}
    proc CFRelease(o: CFTypeRef) {.importc.}

    proc cftimerCallback(cfTimer: CFRunLoopTimerRef, t: pointer) {.cdecl.} =
        let t = cast[Timer](t)
        t.callback()

    proc schedule(t: Timer) =
        var interval = t.interval
        let nextFireTime = CFAbsoluteTimeGetCurrent() + interval
        if not t.isPeriodic: interval = 0
        var context: CFRunLoopTimerContext
        context.info = cast[pointer](t)
        let cfTimer = CFRunLoopTimerCreate(nil, nextFireTime, interval, 0, 0, cftimerCallback, addr context)
        CFRunLoopGetCurrent().CFRunLoopAddTimer(cfTimer, kCFRunLoopCommonModes)
        CFRelease(cfTimer)
        t.timer = cfTimer

    proc cancel(t: Timer) {.inline.} =
        CFRunLoopTimerInvalidate(t.timer)

else:
    import ./perform_on_main_thread

    proc fireCallback(timer: pointer) {.cdecl.} =
        let t = cast[Timer](timer)
        if t.state == tsRunning:
            t.callback()
            t.ready = true

    # Nim is hostile when it's callbacks are called from an "unknown" thread.
    # The following function can not use nim's stack trace and GC.

    {.push stackTrace: off.}
    proc timeoutThreadCallback(interval: uint32, timer: pointer): uint32 {.cdecl.} =
        # This proc is run on a foreign thread!
        let t = cast[ptr TimerObj](timer)

        if t.ready:
            t.ready = false
            performOnMainThread(fireCallback, timer)

        if t.isPeriodic:
            result = interval
        else:
            result = 0
    {.pop.}

    proc schedule(t: Timer) =
        t.ready = true
        t.timer = addTimer(uint32(t.interval * 1000), timeoutThreadCallback, cast[pointer](t))

    template cancel(t: Timer) =
        discard removeTimer(t.timer)
        t.ready = false

proc clear*(t: Timer) =
    if not t.isNil:
        var emptyId: TimerID
        if t.timer != emptyId:
            t.cancel()
            t.timer = emptyId
            t.state = tsInvalid
            t.callback = nil
            t.origCallback = nil
            GC_unref(t)

proc newTimer*(interval: float, repeat: bool, callback: proc() {.gcsafe.}): Timer =
    assert(not callback.isNil)
    when profileTimers:
        result.new()
        if totalTimers.isNil:
            totalTimers = sharedProfiler().newDataSource(int, "Timers")
        inc totalTimers
    else:
        result.new()

    when defined(debugLeaks):
        result.instantiationStackTrace = getStackTrace()
        allTimers.add(cast[pointer](result))

    result.origCallback = callback

    let t = result
    GC_ref(t)
    if repeat:
        t.callback = callback
    else:
        t.callback = proc() =
            t.origCallback()
            t.clear()

    result.isPeriodic = repeat
    result.interval = interval
    result.scheduleTime = epochTime()
    result.state = tsRunning
    result.schedule()

proc setTimeout*(interval: float, callback: proc() {.gcsafe.}): Timer {.discardable.} =
    newTimer(interval, false, callback)

proc setInterval*(interval: float, callback: proc() {.gcsafe.}): Timer {.discardable.} =
    newTimer(interval, true, callback)

proc timeLeftUntilNextFire(t: Timer): float =
    let curTime = epochTime()
    result = max(t.scheduleTime + t.interval - curTime, 0.0)

proc pause*(t: Timer) =
    if t.state == tsRunning:
        var emptyId: TimerID
        if t.timer != emptyId:
            t.cancel()
            t.timer = emptyId
            t.scheduleTime = t.timeLeftUntilNextFire()
            t.state = tsPaused
            GC_unref(t)

proc resume*(t: Timer) =
    if t.state == tsPaused:
        GC_ref(t)
        # At this point t.scheduleTime is equal to number of seconds remaining
        # until next fire.
        let interval = t.interval
        t.interval = t.scheduleTime
        t.scheduleTime = epochTime() - (interval - t.scheduleTime)
        if t.isPeriodic:
            t.isPeriodic = false
            t.callback = proc() =
                t.callback = t.origCallback
                t.origCallback()
                t.cancel()
                t.schedule()
            t.schedule()
            t.isPeriodic = true
        else:
            t.schedule()
        t.interval = interval
        t.state = tsRunning

when defined(debugLeaks):
    iterator activeTimers*(): Timer =
        for t in allTimers:
            yield cast[Timer](t)