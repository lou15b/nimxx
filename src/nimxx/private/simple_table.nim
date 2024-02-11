# This is a table implementation that is more native to JS. It has a lot of
# limitations as to key and value types. Please use with caution.

import std/tables
export tables
type SimpleTable*[TKey, TVal] = TableRef[TKey, TVal]
template newSimpleTable*(TKey, TVal: typedesc): SimpleTable[TKey, TVal] = newTable[TKey, TVal]()

when isMainModule:
  let t = newSimpleTable(int, int)
  t[1] = 123
  doAssert(t[1] == 123)
  doAssert(t.hasKey(1))
