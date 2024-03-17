import std / [ tables, macros ]
import pkg/variant
import std/typetraits except getTypeid, Typeid # see https://github.com/nim-lang/Nim/pull/13305

export variant

proc skipPtrRef(n: NimNode): NimNode =
  let ty = getImpl(n)
  result = n
  if ty[2].kind in {nnkRefTy, nnkPtrTy} and ty[2][0].kind == nnkSym:
    result = ty[2][0].skipPtrRef()

proc nodeTypedefInheritsFrom(n: NimNode): NimNode =
  n.expectKind(nnkTypeDef)
  if n[2].kind == nnkRefTy and n[2][0].kind == nnkObjectTy and
      n[2][0][1].kind == nnkOfInherit:
    result = n[2][0][1][0]

proc `*`(s: string, i: int): string {.compileTime, used.} =
  result = ""
  for ii in 0 ..< i: result &= s

proc superTypeAux(t: NimNode, indent: int): NimNode =
  doAssert(indent < 10, "Recursion too deep")

  # if indent == 0:
  #   echo "\n superTypeAux input AST = ", treerepr(t)

  template superTypeAux(t: NimNode): NimNode = superTypeAux(t, indent + 1)
  proc log(args: varargs[string, `$`]) =
    discard
    # echo "- ", "  " * indent, args.join(" ")

  log "superTypeAux: ", treeRepr(t)
  case t.kind
  of nnkSym:
    if $t == "RootRef": return t
    let ty = getTypeImpl(t)
    log "TypeKind: ", ty.typeKind
    result = superTypeAux(ty)
  of nnkBracketExpr:
    result = superTypeAux(getImpl(t[1]))
  of nnkTypeDef:
    result = nodeTypedefInheritsFrom(t)
    if result.isNil:
      result = superTypeAux(getTypeInst(t[2]))
  of nnkRefTy:
    result = superTypeAux(getTypeImpl(t[^1]))
  of nnkObjectTy:
    t[1].expectKind(nnkOfInherit)
    result = t[1][0]
  else:
    log "unknown node : ", treeRepr(t)
    doAssert(false, "Unknown node")

  log "result ", repr(result)
  # if indent == 0:
  #   echo " superTypeAux final AST result = ", treerepr(result)

macro superType*(t: typed): untyped =
  result = superTypeAux(t, 0)

method className*(o: RootRef): string {.base, gcsafe.} = discard
method classTypeId*(o: RootRef): TypeId {.base, gcsafe.} = getTypeId(RootRef)

type ClassInfo = tuple
  creatorProc: proc(): RootRef {.nimcall.}
  typ: TypeId

# Locks aren't needed for these, because they are initialized at start-up
# and are not changed afterward
# ***But note*** that any code referring to them in a proc, etc. that is
#   called from outside code that is not top level must be inside a
#   "{.gcsafe.}:" block.
#   See proc newObjectOfClass and the registeredX iterators
var classFactory: Table[string, ClassInfo]
var superTypeRelations*: Table[TypeId, TypeId]

proc addSuperTypeRelation*(typeId, superTypeId: TypeId) =
  discard superTypeRelations.hasKeyOrPut(typeId, superTypeId)

proc isRootSym(typeSym: NimNode): bool =
  ## Determines whether the symbol is RootObj or RootRef
  typeSym.expectKind(nnkSym)
  let symName = typeSym.strVal
  result = symName == "RootObj" or symName == "RootRef"

macro registerSuperTypeRelations(a: untyped): untyped =
  ## Generates an AST equivalent to a sequence of statements that adds
  ## supertype entries to the superTypeRelations table, for all of the supertypes
  ## of the argument a to the root type (RootObj or RootRef)
  a.expectKind(nnkSym)
  if a.isRootSym:
    discard

  result = newNimNode(nnkStmtList)
  var typeSym = a
  while not typeSym.isRootSym:
    let superTypeSym = superTypeAux(typeSym, 0)

    # Set 'addSuperTypeRelationCall' to an AST equivalent to the call:
    #   'addSuperTypeRelation(getTypeId(type), getTypeId(supertype))'
    let addSuperTypeRelationCall = newNimNode(nnkCall).add(
      ident("addSuperTypeRelation"),
      newNimNode(nnkCall).add(
        ident("getTypeId"),
        ident($typeSym)
      ),
      newNimNode(nnkCall).add(
        ident("getTypeId"),
        ident($superTypeSym)
      )
    )
    result.add(addSuperTypeRelationCall)

    # Loop back to generate the next call - for the supertype
    typeSym = superTypeSym
    
  # echo "=== registerSuperTypeRelations generated the calls:", repr(result), "\n"

proc isTypeOf(tself, tsuper: TypeId): bool =
  var t = tself
  while t != tsuper and t != 0:
    t = superTypeRelations.getOrDefault(t)
  result = t != 0

proc isSubtypeOf(tself, tsuper: TypeId): bool =
  tself != tsuper and isTypeOf(tself, tsuper)

template registerClassImpl(a: typedesc, creator: proc(): RootRef) =
  const TName = typetraits.name(a)
  # static: echo "registerClass: ", TName
  const tid = getTypeId(a)
  method className*(o: a): string = TName
  method classTypeId*(o: a): TypeId = tid
  registerSuperTypeRelations(a)
  var info: ClassInfo
  info.creatorProc = creator
  info.typ = tid
  classFactory[TName] = info

template registerClassImpl(a: typedesc) =
  let c = proc(): RootRef =
    var res: a
    res.new()
    return res
  registerClassImpl(a, c)

template registerClass*(a: typedesc, creator: proc(): RootRef) =
  when (a isnot RootObj) and (a isnot RootRef):
    {.error: "registerClass is restricted to objects derived from RootObj or RootRef".}
  elif (RootObj isnot a) and (RootRef isnot a):
    registerClassImpl(a, creator)

template registerClass*(a: typedesc) =
  when (a isnot RootObj) and (a isnot RootRef):
    {.error: "registerClass is restricted to objects derived from RootObj or RootRef".}
  elif (RootObj isnot a) and (RootRef isnot a):
    registerClassImpl(a)

template isClassRegistered*(name: string): bool = name in classFactory

proc newObjectOfClass*(name: string): RootRef =
  {.gcsafe.}:
    let c = classFactory.getOrDefault(name)
    if c.creatorProc.isNil:
      raise newException(Exception, "Class '" & name & "' is not registered")
    result = c.creatorProc()

iterator registeredClasses*(): string =
  for k in classFactory.keys: yield k

iterator registeredClassesOfType*(T: typedesc): string =
  {.gcsafe.}:
    const typ = getTypeId(T)
    for k, v in pairs(classFactory):
      if isTypeOf(v.typ, typ):
        yield k

iterator registeredSubclassesOfType*(T: typedesc): string =
  {.gcsafe.}:
    const typ = getTypeId(T)
    for k, v in pairs(classFactory):
      if isSubtypeOf(v.typ, typ):
        yield k

when isMainModule:
  # # Should get a compile error when attempting to register a type that is
  # # not derived from RootObj or RootRef
  # type X = object
  #   name: string = "Xname"
  # registerClass(X)

  template sameType(t1, t2: typedesc): bool =
    t1 is t2 and t2 is t1

  proc isSubtypeOf(tself, tsuper: string): bool =
    isSubtypeOf(classFactory[tself].typ, classFactory[tsuper].typ)

  # =========================

  type A = ref object of RootRef
  type B = ref object of A
  type C = ref object of B

  echo "typeId RootRef: ", getTypeId(RootRef)
  echo "typeId RootObj: ", getTypeId(RootObj)
  echo "typeId A: ", getTypeId(A)
  echo "typeId B: ", getTypeId(B)
  echo "typeId C: ", getTypeId(C)

  echo "typeId superType(A): ", getTypeId(superType(A))
  echo "typeId superType(B): ", getTypeId(superType(B))

  assert sameType(superType(A), RootRef)
  assert sameType(superType(B), A)
  assert sameType(superType(C), B)

  registerClass(A)
  registerClass(B)
  registerClass(C)

  doAssert(superTypeRelations[getTypeId(A)] == getTypeId(RootRef))
  doAssert(superTypeRelations[getTypeId(B)] == getTypeId(A))

  doAssert("B".isSubtypeOf("A"))
  doAssert(not "A".isSubtypeOf("B"))

  echo "Supertype relations: ", superTypeRelations

  echo "Subclasses of RootObj:"
  for t in registeredClassesOfType(RootObj):
    echo t
  echo "Subclasses of RootRef:"
  for t in registeredClassesOfType(RootRef):
    echo t
  echo "Subclasses of A:"
  for t in registeredClassesOfType(A):
    echo t
  echo "Subclasses of B:"
  for t in registeredClassesOfType(B):
    echo t

  let a = newObjectOfClass("A")
  let b = newObjectOfClass("B")
  let c = newObjectOfClass("C")

  doAssert(a.className() == "A")
  doAssert(b.className() == "B")
  doAssert(c.className() == "C")

  doAssert(a.classTypeId() == getTypeId(A))
  doAssert(b.classTypeId() == getTypeId(B))
  doAssert(c.classTypeId() == getTypeId(C))

  # =========================
  superTypeRelations.clear()
  echo "========================="

  type AA = object of RootObj
  type AAR = ref AA
  type BBR = ref object of AAR
  type CCR = ref object of BBR

  echo "typeId AA: ", getTypeId(AA)
  echo "typeId AAR: ", getTypeId(AAR)
  echo "typeId BBR: ", getTypeId(BBR)
  echo "typeId CCR: ", getTypeId(CCR)

  echo "typeId superType(A): ", getTypeId(superType(A))
  echo "typeId superType(B): ", getTypeId(superType(B))

  assert sameType(superType(AA), RootObj)
  assert sameType(superType(AAR), RootObj)
  assert sameType(superType(BBR), AAR)
  assert sameType(superType(CCR), BBR)

  registerClass(AAR)
  registerClass(BBR)
  registerClass(CCR)

  doAssert(superTypeRelations[getTypeId(AAR)] == getTypeId(RootObj))
  doAssert(superTypeRelations[getTypeId(BBR)] == getTypeId(AAR))

  doAssert("BBR".isSubtypeOf("AAR"))
  doAssert(not "AAR".isSubtypeOf("BBR"))

  echo "Supertype relations: ", superTypeRelations

  echo "Subclasses of RootObj:"
  for t in registeredClassesOfType(RootObj):
    echo t
  echo "Subclasses of RootRef:"
  for t in registeredClassesOfType(RootRef):
    echo t
  echo "Subclasses of AAR:"
  for t in registeredClassesOfType(AAR):
    echo t
  echo "Subclasses of BBR:"
  for t in registeredClassesOfType(BBR):
    echo t

  let aa = newObjectOfClass("AAR")
  let bb = newObjectOfClass("BBR")
  let cc = newObjectOfClass("CCR")

  doAssert(aa.className() == "AAR")
  doAssert(bb.className() == "BBR")
  doAssert(cc.className() == "CCR")

  doAssert(aa.classTypeId() == getTypeId(AAR))
  doAssert(bb.classTypeId() == getTypeId(BBR))
  doAssert(cc.classTypeId() == getTypeId(CCR))
