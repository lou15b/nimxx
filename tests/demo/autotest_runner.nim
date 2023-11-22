import nimxx / autotest
import malebolgia/lockers
# This module exists so that both main.nim and sample01_welcome.nim can
# refer to the same TestRunner object

var testRunner* = initLocker(newTestRunner())
