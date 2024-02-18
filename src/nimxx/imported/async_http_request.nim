##[
  Copied from https://github.com/yglukhov/async_http_request, with
  the following changes:
  - code for javascript/enscripten targets has been stripped out
  - updated to remove compile warnings for nim 2.0.0
]##

# When compiled to native target, async_http_request will not provide
# sendRequest proc by default.
# Run nim with -d:asyncHttpRequestAsyncIO to enable sendRequest proc,
# which will call out to asyncio loop on the main thread

type Response* = tuple[statusCode: int, status: string, body: string]

type Handler* = proc (data: Response) {.gcsafe.}
type ErrorHandler* = proc (e: ref Exception) {.gcsafe.}

import std / [ httpclient, parseutils, uri ]
export HttpMethod

type AsyncHttpRequestError* = object of CatchableError

when defined(ssl):
  import std/net
else:
  type SSLContext = ref object
var defaultSslContext {.threadvar.}: SSLContext

# TODO: Remove the "used" pragma when this proc actually gets called
proc getDefaultSslContext(): SSLContext {.used.} =
  when defined(ssl):
    if defaultSslContext.isNil:
      defaultSslContext =
        when defined(windows) or defined(linux) or defined(ios):
          newContext(verifyMode = CVerifyNone)
        else:
          newContext()
      if defaultSslContext.isNil:
        raise newException(AsyncHttpRequestError, "Unable to initialize SSL context.")
  result = defaultSslContext

proc parseStatusCode(s: string): int {.inline.} =
  discard parseInt(s, result)

when defined(asyncHttpRequestAsyncIO):
  import std/strtabs

  proc doAsyncRequest(cl: AsyncHttpClient, meth, url, body: string,
            handler: Handler, onError: ErrorHandler) {.async.} =
    var r: AsyncResponse
    var rBody: string
    try:
      r = await cl.request(url, meth, body)
      rBody = await r.body
      cl.close()
      handler((statusCode: parseStatusCode(r.status), status: r.status, body: rBody))
    except Exception as e:
      if onError != nil:
        onError(e)
      else:
        raise e

  proc doSendRequest(meth, url, body: string, headers: openarray[(string, string)],
            sslContext: SSLContext,
            handler: Handler, onError: ErrorHandler) =
    when defined(ssl):
      var client = newAsyncHttpClient(sslContext = sslContext)
    else:
      if url.parseUri.scheme == "https":
        raise newException(AsyncHttpRequestError,
          "SSL support is not available. Compile with -d:ssl to enable.")
      var client = newAsyncHttpClient()

    client.headers = newHttpHeaders(headers)
    client.headers["Content-Length"] = $body.len
    client.headers["Connection"] = "close"
    asyncCheck doAsyncRequest(client, meth, url, body, handler, onError)

  proc sendRequest*(meth, url, body: string, headers: openarray[(string, string)],
      handler: Handler) =
    doSendRequest(meth, url, body, headers, getDefaultSslContext(), handler, nil)

  proc sendRequest*(meth, url, body: string, headers: openarray[(string, string)],
      sslContext: SSLContext, handler: Handler) =
    doSendRequest(meth, url, body, headers, sslContext, handler, nil)

  proc sendRequestWithErrorHandler*(meth, url, body: string,
      headers: openarray[(string, string)], onSuccess: Handler, onError: ErrorHandler) =
    doSendRequest(meth, url, body, headers, getDefaultSslContext(), onSuccess, onError)

  proc sendRequestWithErrorHandler*(meth, url, body: string,
      headers: openarray[(string, string)], sslContext: SSLContext, onSuccess: Handler,
      onError: ErrorHandler) =
    doSendRequest(meth, url, body, headers, sslContext, onSuccess, onError)
elif compileOption("threads"):
  import pkg/malebolgia

  var asyncMaster = createMaster()
  var asyncHandle = asyncMaster.getHandle() # Used to avoid gc-safety complaints

  type ThreadedHandler* = proc(r: Response, ctx: pointer) {.nimcall, gcsafe.}

  proc asyncHTTPRequest(url: string, httpMethod: HttpMethod, body: string,
      headers: seq[(string, string)], handler: ThreadedHandler, ctx: pointer) {.gcsafe.}=
    try:
      when defined(ssl):
        var client = newHttpClient(sslContext = getDefaultSslContext())
      else:
        if url.parseUri.scheme == "https":
          raise newException(AsyncHttpRequestError,
            "SSL support is not available. Compile with -d:ssl to enable.")
        var client = newHttpClient()

      client.headers = newHttpHeaders(headers)
      client.headers["Content-Length"] = $body.len
      # client.headers["Connection"] = "close" # This triggers nim bug #9867
      let resp = client.request(url, httpMethod, body)
      client.close()
      handler((parseStatusCode(resp.status), resp.status, resp.body), ctx)
    except:
      let msg = getCurrentExceptionMsg()
      handler((-1, "Exception caught: " & msg, getCurrentException().getStackTrace()),
        ctx)

  proc sendRequestThreaded*(meth: HttpMethod, url, body: string,
      headers: openarray[(string, string)], handler: ThreadedHandler,
      ctx: pointer = nil) =
    ## handler might not be called on the invoking thread
    asyncHandle.spawn asyncHTTPRequest(url, meth, body, @headers, handler, ctx)
else:
  {.warning: "async_http_requests requires either --threads:on or -d:asyncHttpRequestAsyncIO".}
