import std / [ streams, strutils, tables ]
import pkg/malebolgia/lockers

export streams

type Error = string
type Handler* = proc(s: Stream, error: Error) {.gcsafe.}
type UrlHandler = proc(url: string, handler: Handler) {.gcsafe.}

var urlHandlers = initLocker(newTable[string, UrlHandler]())

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
  lock urlHandlers as uhs:
    uh = uhs.getOrDefault(scheme)
  if uh.isNil:
    raise newException(Exception, "No url handler for scheme " & scheme)
  uh(url, handler)

proc registerUrlHandler*(scheme: string, handler: UrlHandler) =
  lock urlHandlers as uhs:
    assert(scheme notin uhs)
    uhs[scheme] = handler

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
