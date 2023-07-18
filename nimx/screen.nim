when defined(ios):
    import darwin/ui_kit
elif defined(macosx):
    import darwin/app_kit
elif defined(android):
    import android/util/display_metrics
    import android/app/activity
    import android/content/context_wrapper
    import android/content/res/resources

proc screenScaleFactor*(): float =
    when defined(macosx) or defined(ios):
        result = mainScreen().scaleFactor()
    elif defined(android):
        let sm = currentActivity().getResources().getDisplayMetrics()
        result = sm.scaledDensity
    else:
        result = 1.0
