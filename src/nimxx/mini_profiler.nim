import tables, rlocks, threading/smartptrs

#[
    This code gathers user-defined global statistics.
    Currently there is code gathering data in abstract_window.nim, image.nim, timer.nim, and the data is displayed
    (in an overlay section) by abstract_window.nim.
    Running the demo with "-d:miniProfiler" shows a set of profile data displayed in the upper right corner of each window.
]#

type
    SourceDataType = SomeOrdinal | SomeFloat | string

    ProfilerDataSourceBaseObj* {.inheritable, pure.} = object
        stringifiedValue: string
        isDirty: bool
        # In effect, the following members emulate a virtual function table
        syncStringifiedValue: proc(ds: ProfilerDataSourceBase) {.nimcall, gcsafe.}
        incValue*: proc(ds: ProfilerDataSourceBase) {.nimcall, gcsafe.}
        decValue*: proc(ds: ProfilerDataSourceBase) {.nimcall.}

    ProfilerDataSourceBase* {.inheritable, pure.} = ref ProfilerDataSourceBaseObj

    ProfilerDataSourceObj[T: SourceDataType] = object of ProfilerDataSourceBase
        mValue: T

    ProfilerDataSource[T: SourceDataType] = ref ProfilerDataSourceObj[T]

    ProfilerObj* = object
        values: Table[string, ProfilerDataSourceBase]
        enabled*: bool

    Profiler* = SharedPtr[ProfilerObj]

proc `=destroy`(x: ProfilerDataSourceBaseObj) =
    `=destroy`(x.stringifiedValue)

proc `=destroy`[T: SourceDataType](x: ProfilerDataSourceObj[T]) =
    when T is string:
        `=destroy`(x.mvalue)
    `=destroy`(x.ProfilerDataSourceBaseObj)

proc `=destroy`(x: ProfilerObj) =
    echo "Destroying Profiler"
    `=destroy`(x.values.addr[])

proc setStringifiedValue(ds: ProfilerDataSourceBase, stringVal: string) =
    ds.stringifiedValue = stringVal
    ds.isDirty = false

proc syncStringifiedValue[T: SourceDataType](dsb: ProfilerDataSourceBase) {.nimcall, gcsafe.} =
    var ds = cast[ProfilerDataSource[T]](dsb)
    setStringifiedValue(dsb, $ds.mValue)

proc incValue[T: SourceDataType](dsb: ProfilerDataSourceBase) {.nimcall.} =
    when T is SomeInteger:
        var ds = cast[ProfilerDataSource[T]](dsb)
        inc(ds.mvalue)
        ds.isDirty = true
    else:
        discard

proc decValue[T: SourceDataType](dsb: ProfilerDataSourceBase) {.nimcall.} =
    when T is SomeInteger:
        var ds = cast[ProfilerDataSource[T]](dsb)
        dec(ds.mvalue)
        ds.isDirty = true
    else:
        discard

proc newProfiler*(): Profiler =
    var prof = ProfilerObj.new()
    prof.values = initTable[string, ProfilerDataSourceBase]()
    when defined(miniProfiler):
        prof.enabled = true
    result = newSharedPtr(prof[])

var sharedProfilerLock*: RLock
sharedProfilerLock.initRLock()
var sharedProfiler* {.guard: sharedProfilerLock.} = newProfiler()

proc newDataSource[T: SourceDataType](p: Profiler, name: string): ProfilerDataSource[T] =
    result = ProfilerDataSource[T].new()
    result.stringifiedValue = ""
    result.syncStringifiedValue = syncStringifiedValue[T]
    result.incValue = incValue[T]
    result.decValue = decValue[T]
    when T is string:
        result.mvalue = ""
    p[].values[name] = result

proc setValueForKey*(p: Profiler, key: string, value: SourceDataType) =
    type TT = typeof(value)
    var ds: ProfilerDataSource[TT]
    var dsb = p[].values.getOrDefault(key)
    if dsb.isNil:
        ds = newDataSource[TT](p, key)
        p[].values[key] = ds
    else:
        ds = cast[ProfilerDataSource[TT]](dsb)
    ds.mValue = value
    ds.isDirty = true

proc `[]`*(p: Profiler, key: string): ProfilerDataSourceBase =
    result = p[].values[key]

proc `[]=`*(p: Profiler, key: string, value: SourceDataType) =
    p.setValueForKey(key, value)

proc valueForKey*(p: Profiler, key: string): string =
    let v = p[].values.getOrDefault(key)
    if not v.isNil:
        if v.isDirty: v.syncStringifiedValue(v)
        result = v.stringifiedValue

iterator pairs*(p: Profiler): tuple[key, value: string] =
    for k, v in p[].values:
        if v.isDirty: v.syncStringifiedValue(v)
        yield (k, v.stringifiedValue)

proc allPairs*(p: Profiler): seq[tuple[key, value: string]] =
    result = @[]
    for pair in p.pairs:
        result.add(pair)

template len*(p: Profiler): int = p[].values.len

template enabled*(p: Profiler): bool = p[].enabled

template `value=`*[T: SourceDataType](ds: ProfilerDataSource[T], v: T) =
    ds.mValue = v
    ds.isDirty = true

template value*[T: SourceDataType](ds: ProfilerDataSource[T]): T = ds.mValue

template inc*(dsb: ProfilerDataSourceBase) =
    var ds = dsb    # Just in case the argument is an expression
    ds.incValue(ds)

template dec*(dsb: ProfilerDataSourceBase) =
    var ds = dsb    # Just in case the argument is an expression
    ds.decValue(ds)
