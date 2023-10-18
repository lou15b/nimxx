import macros, logging, strutils
import ./ [ timer, app, event, abstract_window, button ]
import ./utils/lock_utils

type UITestSuiteStep* = tuple
    code : proc() {.gcsafe.}
    astrepr: string
    lineinfo: string

type UITestSuite* = ref object
    name: string
    steps: seq[UITestSuiteStep]

type TestRunnerContext = ref object
    curStep: int
    curTimeout: float
    waitTries: int

# ***Presumably*** these variables are threadvar because it's possible that different
# test sets could be executed concurrently in different threads
# IF NOT, it is most likely because of gcsafe specifications on the callback in the
# arguments for the setInterval proc in timer.nim
var testRunnerContext {.threadvar.}: TestRunnerContext
var registeredTests {.threadvar.}: seq[UITestSuite]

proc newTestSuite(name: string, steps: openarray[UITestSuiteStep]): UITestSuite =
    result.new()
    result.name = name
    result.steps = @steps

proc makeStep(code: proc() {.gcsafe.}, astrepr, lineinfo: string): UITestSuiteStep {.inline.} =
    result.code = code
    result.astrepr = astrepr
    result.lineinfo = lineinfo

proc registerTest*(ts: UITestSuite) =
    registeredTests.add(ts)

proc registeredTest*(name: string): UITestSuite =
    for t in registeredTests:
        if t.name == name: return t

proc collectAutotestSteps(result, body: NimNode) =
    for n in body:
        if n.kind == nnkStmtList:
            collectAutotestSteps(result, n)
        else:
            let procDef = newProc(body = newStmtList().add(n), procType = nnkLambda)

            let step = newCall(bindSym"makeStep", procDef, toStrLit(n), newLit(n.lineinfo))
            result.add(step)

proc testSuiteDefinitionWithNameAndBody(name, body: NimNode): NimNode =
    result = newNimNode(nnkBracket)
    collectAutotestSteps(result, body)
    return newNimNode(nnkLetSection).add(
        newNimNode(nnkIdentDefs).add(name, bindSym"UITestSuite", newCall(bindSym"newTestSuite", newLit($name), result)))

macro uiTest*(name: untyped, body: typed): untyped =
    result = testSuiteDefinitionWithNameAndBody(name, body)

macro registeredUiTest*(name: untyped, body: typed): untyped =
    result = newStmtList()
    result.add(testSuiteDefinitionWithNameAndBody(name, body))
    result.add(newCall(bindSym"registerTest", name))

when true:
    proc sendMouseEvent*(wnd: Window, p: Point, bs: ButtonState) =
        var evt = newMouseButtonEvent(p, VirtualKey.MouseButtonPrimary, bs)
        evt.window = wnd
        withRLockGCsafe(mainAppLock):
            discard mainApp.handleEvent(evt)

    proc sendMouseDownEvent*(wnd: Window, p: Point) = sendMouseEvent(wnd, p, bsDown)
    proc sendMouseUpEvent*(wnd: Window, p: Point) = sendMouseEvent(wnd, p, bsUp)

    proc findButtonWithTitle*(v: View, t: string): Button =
        if v of Button:
            let btn = Button(v)
            if btn.title == t:
                result = btn
        else:
            for s in v.subviews:
                result = findButtonWithTitle(s, t)
                if not result.isNil: break

    proc quitApplication*() =
        when defined(android):
            # Hopefully we're using nimx automated testing in Firefox
            info "---AUTO-TEST-QUIT---"
        else:
            quit()

    proc waitUntil*(e: bool) =
        if not e:
            dec testRunnerContext.curStep

    proc waitUntil*(e: bool, maxTries: int) =
        if e:
            testRunnerContext.waitTries = -1
        else:
            dec testRunnerContext.curStep
            if maxTries != -1:
                if testRunnerContext.waitTries + 2 > maxTries:
                    testRunnerContext.waitTries = -1
                    when defined(android):
                        info "---AUTO-TEST-FAIL---"
                    else:
                        raise newException(Exception, "Wait tries exceeded!")
                else:
                    inc testRunnerContext.waitTries

when false:
    macro tdump(b: typed): typed =
        echo treeRepr(b)

    tdump:
        let ts : UITestSuite = @[
            (
                (proc() {.closure.} = echo "hi"),
                "hello"
            )
        ]

    uiTest myTest:
        echo "hi"
        echo "bye"

    registerTest(myTest)

when defined(android):
    import jnim
    import android/app/activity, android/content/intent, android/os/base_bundle
else:
    import os

proc getAllTestNames(): seq[string] =
    result = newSeq[string](registeredTests.len)
    for i, t in registeredTests: result[i] = t.name

proc getTestsToRun*(): seq[string] =
    when defined(android):
        let act = currentActivity()
        assert(not act.isNil)
        let extras = act.getIntent().getExtras()
        if not extras.isNil:
            let r = extras.getString("nimxAutoTest")
            if r.len != 0:
                result = r.split(',')
    else:
        var i = 0
        while i < paramCount():
            if paramStr(i) == "--nimxAutoTest":
                inc i
                result.add(paramStr(i).split(','))
            inc i
    if "all" in result:
        result = getAllTestNames()

proc haveTestsToRun*(): bool =
    getTestsToRun().len != 0

proc startTest*(t: UITestSuite, onComplete: proc() {.gcsafe.} = nil) =
    testRunnerContext.new()
    testRunnerContext.curTimeout = 0.5
    testRunnerContext.waitTries = -1

    var tim : Timer
    tim = setInterval(0.5) do():
        info t.steps[testRunnerContext.curStep].lineinfo, ": RUNNING ", t.steps[testRunnerContext.curStep].astrepr
        t.steps[testRunnerContext.curStep].code()
        inc testRunnerContext.curStep
        if testRunnerContext.curStep == t.steps.len:
            tim.clear()
            testRunnerContext = nil
            if not onComplete.isNil: onComplete()

proc testWithName(name: string): UITestSuite =
    for t in registeredTests:
        if t.name == name: return t

proc startTests(tests: seq[UITestSuite], onComplete: proc() {.gcsafe.}) =
    var curTestSuite = 0
    proc startNextSuite() {.gcsafe.} =
        if curTestSuite < tests.len:
            startTest(tests[curTestSuite], startNextSuite)
            inc curTestSuite
        elif not onComplete.isNil:
            onComplete()
    startNextSuite()

proc startRequestedTests*(onComplete: proc() {.gcsafe.} = nil) =
    let testsToRun = getTestsToRun()
    var tests = newSeq[UITestSuite](testsToRun.len)
    for i, n in testsToRun:
        let t = testWithName(n)
        if t.isNil:
            raise newException(Exception, "Test " & n & " not registered")
        tests[i] = t

    startTests(tests, onComplete)

proc startRegisteredTests*(onComplete: proc() {.gcsafe.} = nil) {.inline.} =
    startTests(registeredTests, onComplete)
