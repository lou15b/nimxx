import nimxx/window
import nimxx/autotest
import nimxx/button, nimxx/text_field
import nimxx/editor/edit_view

import pkg/malebolgia/lockers

const isMobile = defined(ios) or defined(android)

var testRunner* = initLocker(newTestRunner())

proc runAutoTestsIfNeeded() =
    uiTest generalUITest:
        discard
        quitApplication()

    lock testRunner as runner:
        runner.registerTest(generalUITest)
        when defined(runAutoTests):
            runner.startRegisteredTests()

proc startApplication() =
    when isMobile:
        var mainWindow = newFullscreenWindow()
    else:
        var mainWindow = newWindow(newRect(40, 40, 1200, 600))
    mainWindow.title = "nimx"
    startNimxEditor(mainWindow)
    runAutoTestsIfNeeded()

runApplication:
    startApplication()
