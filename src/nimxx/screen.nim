when defined(ios):
  import pkg/darwin/ui_kit
elif defined(macosx):
  import pkg/darwin/app_kit
elif defined(android):
  import pkg/android/util/display_metrics
  import pkg/android/app/activity
  import pkg/android/content/context_wrapper
  import pkg/android/content/res/resources

proc screenScaleFactor*(): float =
  when defined(macosx) or defined(ios):
    result = mainScreen().scaleFactor()
  elif defined(android):
    let sm = currentActivity().getResources().getDisplayMetrics()
    result = sm.scaledDensity
  else:
    result = 1.0
