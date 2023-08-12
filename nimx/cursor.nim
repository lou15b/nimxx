const appKit = defined(macosx) and not defined(ios)

when appKit:    # ??????
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
        when appKit:
            c: pointer
        else:
            c: CursorPtr

when appKit:
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
    when appKit:
        result.c = NSCursorOfKind(k).retain()
    else:
        result.c = createSystemCursor(cursorKindToSdl(k))

var gCursor {.threadvar.}: ref Cursor
proc currentCursor*(): ref Cursor =
    if gCursor.isNil:
        gCursor = newCursor(ckArrow)
    result = gCursor

proc setCurrent*(c: ref Cursor) =
    gCursor = c
    when appKit:
        cast[NSCursor](c.c).setCurrent()
    else:
        setCursor(c.c)
