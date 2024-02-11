import std / [ json, logging ]
import ./url_stream

proc loadJsonFromURL*(url: string, handler: proc(j: JsonNode) {.gcsafe.}) =
  openStreamForUrl(url) do(s: Stream, err: string):
    if err.len == 0:
      handler(parseJson(s, url))
      s.close()
    else:
      error "Error loading json from url (", url, "): ", err
      handler(nil)
