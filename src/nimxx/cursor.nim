import rlocks
import utils/lock_utils

const useAppKit = defined(macosx) and not defined(ios)

when useAppKit:
    import darwin/app_kit as apkt
else:
    import sdl2


type
    CursorKind* = enum
        ckArrow
        ckText
        ckWait
        ckCrosshair
        ckWaitArrow
        ckSizeTRBL # Diagonal size top-right - bottom-left
        ckSizeTLBR # Diagonal size top-left - bottom-right
        ckSizeHorizontal
        ckSizeVertical
        ckSizeAll
        ckNotAllowed
        ckHand

    Cursor* = object
        when useAppKit:
            c: pointer
        else:
            c: CursorPtr

when useAppKit:
    proc NSCursorOfKind(c: CursorKind): NSCursor =
        case c
        of ckArrow: arrowCursor()
        of ckText: IBeamCursor()
        of ckWait: arrowCursor()
        of ckCrosshair: crosshairCursor()
        of ckWaitArrow: arrowCursor()
        of ckSizeTRBL: arrowCursor()
        of ckSizeTLBR: arrowCursor()
        of ckSizeHorizontal: resizeLeftRightCursor()
        of ckSizeVertical: resizeUpDownCursor()
        of ckSizeAll: arrowCursor()
        of ckNotAllowed: operationNotAllowedCursor()
        of ckHand: pointingHandCursor()

    proc `=destroy`(c: Cursor) =
        cast[NSCursor](c.c).release()
else:
    proc cursorKindToSdl(c: CursorKind): SystemCursor =
        case c
        of ckArrow: SDL_SYSTEM_CURSOR_ARROW
        of ckText: SDL_SYSTEM_CURSOR_IBEAM
        of ckWait: SDL_SYSTEM_CURSOR_WAIT
        of ckCrosshair: SDL_SYSTEM_CURSOR_CROSSHAIR
        of ckWaitArrow: SDL_SYSTEM_CURSOR_WAITARROW
        of ckSizeTRBL: SDL_SYSTEM_CURSOR_SIZENWSE
        of ckSizeTLBR: SDL_SYSTEM_CURSOR_SIZENESW
        of ckSizeHorizontal: SDL_SYSTEM_CURSOR_SIZEWE
        of ckSizeVertical: SDL_SYSTEM_CURSOR_SIZENS
        of ckSizeAll: SDL_SYSTEM_CURSOR_SIZEALL
        of ckNotAllowed: SDL_SYSTEM_CURSOR_NO
        of ckHand: SDL_SYSTEM_CURSOR_HAND

    proc `=destroy`(c: Cursor) =
        freeCursor(c.c)

proc newCursor*(k: CursorKind): ref Cursor =
    result = new(Cursor)
    when useAppKit:
        result.c = NSCursorOfKind(k).retain()
    else:
        result.c = createSystemCursor(cursorKindToSdl(k))

proc updateScreenCursor(c: ref Cursor) =
    when useAppKit:
        cast[NSCursor](c.c).setCurrent()
    else:
        setCursor(c.c)

# There is only one cursor for the entire display, and it only has one shape at a time.
# So it is a guarded global here
# Note that the variable in question is a *reference*, whose internal pointer is being used
# by a foreign library. So I don't think it is suitable for a malebolgia Locker in its
# current form.
var currentCursorLock: RLock
currentCursorLock.initRLock()
var currentCursor* {.guard: currentCursorLock.}: ref Cursor = newCursor(ckArrow)
updateScreenCursor(currentCursor)

proc setCurrent*(c: ref Cursor) =
    withRLockGCsafe(currentCursorLock):
        currentCursor = c
        updateScreenCursor(c)
