import pkg/destructor

type PasteboardItem* = ref object
    kind*: string
    data*: string

PasteboardItem.traceDestructor():
  PasteboardItem.destroyFields(x.kind, x.data)

const PboardKindString* = "string"

proc newPasteboardItem*(kind, data: string): PasteboardItem =
  result.new()
  result.kind = kind
  result.data = data

proc newPasteboardItem*(s: string): PasteboardItem =
  newPasteboardItem(PboardKindString, s)
