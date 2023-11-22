import macros, logging, strutils
import ./ [ timer, app, event, abstract_window, button ]
import ./utils/lock_utils

type UITestSuiteStep* = object
    code : proc() {.gcsafe.}
    astrepr: string
    lineinfo: string

type UITestSuiteObj* = object
    name: string
    steps: seq[UITestSuiteStep]

type UITestSuite* = ref UITestSuiteObj

type TestRunnerContext = object
    curStep: int
    curTimeout: float
    waitTries: int

type TestRunnerObj = object
    context: TestRunnerContext
    registeredTests: seq[UITestSuite]

type TestRunner* = ref TestRunnerObj

proc `=destroy`(x: UITestSuiteStep) =
    `=destroy`(x.astrepr)
    `=destroy`(x.lineinfo)

proc `=destroy`(x: UITestSuiteObj) =
    `=destroy`(x.name)
    `=destroy`(x.steps)

proc `=destroy`(x: TestRunnerObj) =
    # No destructor call needed for x.context, its fields are numbers
    `=destroy`(x.registeredTests)

proc init(context: var TestRunnerContext, curTimeout: float = 0.5, waitTries: int = -1) =
    context.curStep = 0
    context.curTimeout = curTimeout
    context.waitTries = waitTries

proc newTestRunner*(): TestRunner =
    result = TestRunnerObj.new()
    result.context.init()
    result.registeredTests = @[]

proc newTestSuite(name: string, steps: openarray[UITestSuiteStep]): UITestSuite =
    result.new()
    result.name = name
    result.steps = @steps

proc makeStep(code: proc() {.gcsafe.}, astrepr, lineinfo: string): UITestSuiteStep {.inline.} =
    result.code = code
    result.astrepr = astrepr
    result.lineinfo = lineinfo

proc registerTest*(runner: TestRunner, ts: UITestSuite) =
    runner.registeredTests.add(ts)

proc registeredTest*(runner: TestRunner, name: string): UITestSuite =
    for t in runner.registeredTests:
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

    proc waitUntil*(runner: TestRunner, e: bool) =
        if not e:
            dec runner.context.curStep

    proc waitUntil*(runner: TestRunner, e: bool, maxTries: int) =
        if e:
            runner.context.waitTries = -1
        else:
            dec runner.context.curStep
            if maxTries != -1:
                if runner.context.waitTries + 2 > maxTries:
                    runner.context.waitTries = -1
                    when defined(android):
                        info "---AUTO-TEST-FAIL---"
                    else:
                        raise newException(Exception, "Wait tries exceeded!")
                else:
                    inc runner.context.waitTries

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
    
    var trunner = newTestRunner()

    trunner.registerTest(myTest)

when defined(android):
    import jnim
    import android/app/activity, android/content/intent, android/os/base_bundle
else:
    import os

proc getAllTestNames(runner: TestRunner): seq[string] =
    result = newSeq[string](runner.registeredTests.len)
    for i, t in runner.registeredTests: result[i] = t.name

proc getTestsToRun*(runner: TestRunner): seq[string] =
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
        result = getAllTestNames(runner)

proc hasTestsToRun*(runner: TestRunner): bool =
    runner.registeredTests.len != 0

proc prep(runner: TestRunner) = runner.context.curStep = 0

proc startTest*(runner: TestRunner, t: UITestSuite, onComplete: proc() {.gcsafe.} = nil) =
    runner.prep()

    var tim : Timer
    tim = setInterval(0.5) do():
        info t.steps[runner.context.curStep].lineinfo, ": RUNNING ", t.steps[runner.context.curStep].astrepr
        t.steps[runner.context.curStep].code()
        inc runner.context.curStep
        if runner.context.curStep == t.steps.len:
            tim.clear()
            if not onComplete.isNil: onComplete()

proc testWithName(runner: TestRunner, name: string): UITestSuite =
    for t in runner.registeredTests:
        if t.name == name: return t

proc startTests(runner: TestRunner, tests: seq[UITestSuite], onComplete: proc() {.gcsafe.}) =
    for test in tests:
        runner.startTest(test)
    if not onComplete.isNil:
        onComplete()

proc startRequestedTests*(runner: TestRunner, onComplete: proc() {.gcsafe.} = nil) =
    let testsToRun = getTestsToRun(runner)
    var tests = newSeq[UITestSuite](testsToRun.len)
    for i, n in testsToRun:
        let t = runner.testWithName(n)
        if t.isNil:
            raise newException(Exception, "Test " & n & " not registered")
        tests[i] = t

    runner.startTests(tests, onComplete)

proc startRegisteredTests*(runner: TestRunner, onComplete: proc() {.gcsafe.} = nil) {.inline.} =
    runner.startTests(runner.registeredTests, onComplete)
