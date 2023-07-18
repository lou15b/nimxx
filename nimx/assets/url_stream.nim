import streams, strutils, tables, locks
import ../utils/lock_utils

export streams

type Error = string
type Handler* = proc(s: Stream, error: Error) {.gcsafe.}
type UrlHandler = proc(url: string, handler: Handler) {.gcsafe.}

var urlHandlersLock: Lock
var urlHandlers {.guard: urlHandlersLock.}: TableRef[string, UrlHandler]

template getUrlHandlers(): TableRef[string, UrlHandler] =
    urlHandlers

proc urlScheme(s: string): string =
    let i = s.find(':') - 1
    if i > 0:
        result = s.substr(0, i)

proc openStreamForUrl*(url: string, handler: Handler) {.gcsafe.} =
    assert(not handler.isNil)
    let scheme = url.urlScheme
    if scheme.len == 0:
        raise newException(Exception, "Invalid url: \"" & url & "\"")
    var uh: UrlHandler
    withLockGCsafe(urlHandlersLock):
        uh = getUrlHandlers().getOrDefault(scheme)
    if uh.isNil:
        raise newException(Exception, "No url handler for scheme " & scheme)
    uh(url, handler)

proc registerUrlHandler*(scheme: string, handler: UrlHandler) =
    withLockGCsafe(urlHandlersLock):
        if urlHandlers.isNil:
            urlHandlers = newTable[string, UrlHandler]()
        assert(scheme notin urlHandlers)
        urlHandlers[scheme] = handler

proc getPathFromFileUrl(url: string): string =
    const prefixLen = len("file://")
    result = substr(url, prefixLen)

registerUrlHandler("file") do(url: string, handler: Handler) {.gcsafe.}:
    let p = getPathFromFileUrl(url)
    let s = newFileStream(p, fmRead)
    if s.isNil:
        handler(nil, "Could not open file: " & p)
    else:
        handler(s, "")
