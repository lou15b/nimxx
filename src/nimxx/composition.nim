import ./ [ context_base, types, opengl_etc, image ]
import ./private/helper_macros
import std / [ strutils, tables, hashes ]
import pkg/nimsl/nimsl
import pkg/malebolgia/lockers


const commonDefinitions = """
#define PI 3.14159265359
#define TWO_PI 6.28318530718

vec4 insetRect(vec4 rect, float by) {
  return vec4(rect.xy + by, rect.zw - by * 2.0);
}

"""

const distanceSetOperations = """
float sdAnd(float d1, float d2) {
  return max(d1, d2);
}

float sdOr(float d1, float d2) {
  return min(d1, d2);
}

float sdOr(float d1, float d2, float d3) {
  return sdOr(sdOr(d1, d2), d3);
}

float sdOr(float d1, float d2, float d3, float d4) {
  return sdOr(sdOr(d1, d2, d3), d4);
}

float sdOr(float d1, float d2, float d3, float d4, float d5) {
  return sdOr(sdOr(d1, d2, d3, d4), d5);
}

float sdOr(float d1, float d2, float d3, float d4, float d5, float d6) {
  return sdOr(sdOr(d1, d2, d3, d4, d5), d6);
}

float sdSub(float d1, float d2) {
  return max(d1, -d2);
}
"""

const distanceFunctions = """
float sdRect(vec2 p, vec4 rect) {
  vec2 b = rect.zw / 2.0;
  p -= rect.xy + b;
  vec2 d = abs(p) - b;
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdRect(vec4 rect) {
  return sdRect(vPos, rect);
}

float sdCircle(vec2 pos, vec2 center, float radius) {
  return distance(pos, center) - radius;
}

float sdCircle(vec2 center, float radius) {
  return sdCircle(vPos, center, radius);
}

float sdRoundedRect(vec2 pos, vec4 rect, float radius) {
  vec4 hRect = vec4(rect.x + radius, rect.y, rect.z - radius * 2.0, rect.w);
  vec4 vRect = vec4(rect.x, rect.y + radius, rect.z, rect.w - radius * 2.0);
  return sdOr(
    sdRect(pos, hRect), sdRect(pos, vRect),
    sdCircle(pos, rect.xy + radius, radius),
    sdCircle(pos, vec2(rect.x + radius, rect.y + rect.w - radius), radius),
    sdCircle(pos, rect.xy + rect.zw - radius, radius),
    sdCircle(pos, vec2(rect.x + rect.z - radius, rect.y + radius), radius));
}

float sdRoundedRect(vec4 rect, float radius) {
  return sdRoundedRect(vPos, rect, radius);
}

float sdEllipseInRect(vec2 pos, vec4 rect) {
  vec2 ab = rect.zw / 2.0;
  vec2 center = rect.xy + ab;
  vec2 p = pos - center;
  float res = dot(p * p, 1.0 / (ab * ab)) - 1.0;
  res *= min(ab.x, ab.y);
  return res;
}

float sdEllipseInRect(vec4 rect) {
  return sdEllipseInRect(vPos, rect);
}

float sdRegularPolygon(vec2 st, vec2 center, float radius, int n, float angle) {
  st -= center;
  float innerAngle = float(n - 2) * PI / float(n);
  float pointAngle = atan(st.y, st.x) - angle;

  float s = floor(pointAngle / (PI - innerAngle));
  float iiAngle = PI - innerAngle;
  float startAngle = angle + iiAngle * s;
  float endAngle = startAngle + iiAngle;

  vec2 p1 = vec2(cos(startAngle), sin(startAngle));
  vec2 p2 = vec2(cos(endAngle), sin(endAngle));

  vec2 d = p2 - p1;

  return ((d.y * st.x - d.x * st.y) + (p2.x * p1.y - p2.y * p1.x)*radius) / distance(p1, p2);
}

float sdRegularPolygon(vec2 center, float radius, int n) {
  return sdRegularPolygon(vPos, center, radius, n, 0.0);
}

float sdRegularPolygon(vec2 center, float radius, int n, float angle) {
  return sdRegularPolygon(vPos, center, radius, n, angle);
}

float sdStrokeRect(vec2 pos, vec4 rect, float width) {
  return sdSub(sdRect(pos, rect),
        sdRect(pos, insetRect(rect, width)));
}

float sdStrokeRect(vec4 rect, float width) {
  return sdStrokeRect(vPos, rect, width);
}

float sdStrokeRoundedRect(vec2 pos, vec4 rect, float radius, float width) {
  return sdSub(sdRoundedRect(pos, rect, radius),
        sdRoundedRect(pos, insetRect(rect, width), radius - width));
}

float sdStrokeRoundedRect(vec4 rect, float radius, float width) {
  return sdStrokeRoundedRect(vPos, rect, radius, width);
}
"""

const colorOperations = """
vec4 newGrayColor(float v, float a) {
  return vec4(v, v, v, a);
}

vec4 newGrayColor(float v) {
  return newGrayColor(v, 1.0);
}

vec4 gradient(float pos, vec4 startColor, vec4 endColor) {
  return mix(startColor, endColor, pos);
}

vec4 gradient(float pos, vec4 startColor, float sN, vec4 cN, vec4 endColor) {
  return mix(gradient(pos / sN, startColor, cN),
    endColor, smoothstep(sN, 1.0, pos));
}

vec4 gradient(float pos, vec4 startColor, float s1, vec4 c1, float sN, vec4 cN, vec4 endColor) {
  return mix(gradient(pos / sN, startColor, s1 / sN, c1, cN),
    endColor, smoothstep(sN, 1.0, pos));
}

vec4 gradient(float pos, vec4 startColor, float s1, vec4 c1, float s2, vec4 c2,
    float sN, vec4 cN, vec4 endColor) {
  return mix(gradient(pos / sN, startColor, s1 / sN, c1, s2 / sN, c2, cN),
    endColor, smoothstep(sN, 1.0, pos));
}

// Color conversions
//http://gamedev.stackexchange.com/questions/59797/glsl-shader-change-hue-saturation-brightness
vec3 rgb2hsv(vec3 c)
{
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
"""

const compositionFragmentFunctions = """
float fillAlpha(float dist) {
  float d = fwidth(dist);
  return 1.0 - smoothstep(-d, d, dist);
//    return 1.0 - step(0.0, dist); // No antialiasing
}

vec4 composeDistanceFuncDebug(float dist) {
  vec4 result = vec4(smoothstep(-30.0, -10.0, dist), 0, 0, 1.0);
  if (dist > 0.0) {
    result = vec4(0.5, 0.5, 1.0 - smoothstep(0.0, 30.0, dist), 1.0);
  }
  if (dist > -5.0 && dist <= 0.0) result = vec4(0.0, 1, 0, 1);
  return result;
}

// Draw shape depending on underlying fragments
void drawShape(float dist, vec4 color) {
  gl_FragColor = mix(gl_FragColor, color, fillAlpha(dist));
}

// Draw shape without taking underlying fragments in account
void drawInitialShape(float dist, vec4 color) {
  gl_FragColor = color;
  gl_FragColor.w *= fillAlpha(dist);
}

// Same as drawShape, but respects source alpha
void blendShape(float dist, vec4 color) {
  gl_FragColor = mix(gl_FragColor, color, fillAlpha(dist) * color.a);
}
"""

proc fillAlpha*(dist: float32): float32 =
  let d = fwidth(dist)
  result = 1.0 - smoothstep(-d, d, dist)
  #    return 1.0 - step(0.0, dist); # No antialiasing

proc drawShape*(res: var Vec4, dist: float32, color: Vec4) =
  res = mix(res, color, fillAlpha(dist))

proc drawInitialShape*(res: var Vec4, dist: float32, color: Vec4) =
  res = color
  res.w *= fillAlpha(dist)

proc sdRect*(p: Vec2, rect: Vec4): float32 =
  let b = rect.zw / 2.0
  let dp = p - (rect.xy + b)
  let d = abs(dp) - b
  result = min(max(d.x, d.y), 0.0) + length(max(d, 0.0))

proc sdEllipseInRect*(pos: Vec2, rect: Vec4): float32 =
  let ab = rect.zw / 2.0
  let center = rect.xy + ab
  let p = pos - center
  result = dot(p * p, 1.0 / (ab * ab)) - 1.0
  result *= min(ab.x, ab.y)

proc insetRect*(r: Vec4, by: float32): Vec4 = newVec4(r.xy + by, r.zw - by * 2.0)

proc vertexShader(aPosition: Vec2, uModelViewProjectionMatrix: Mat4, uBounds: Vec4,
    vPos: var Vec2): Vec4 =
  vPos = uBounds.xy + aPosition * uBounds.zw
  result = uModelViewProjectionMatrix * newVec4(vPos, 0.0, 1.0);

const vertexShaderCode = getGLSLVertexShader(vertexShader)

type
  PostEffectObj* = object
    source*: string
    setupProc*: proc(cc: CompiledComposition) {.gcsafe.}
    mainProcName*: string
    seenFlag: bool # Used on compilation phase, should not be used elsewhere.
    id*: int
    argTypes*: seq[string]

  PostEffect* = ref PostEffectObj

  CompiledCompositionObj* = object
    program*: ProgramGLRef
    uniformLocations*: seq[UniformGLLocation]
    iTexIndex*: GLint
    iUniform*: int

  CompiledComposition* = ref CompiledCompositionObj

  Composition* = object
    definition: string
    vsDefinition: string # Vertex shader source code
    precision: string
    requiresPrequel: bool
    id*: int
    
  # "Table" doesn't currently have a destructor, so we wrap it in an object to
  # ensure proper cleanup
  ProgramCache = object
    entries: Table[Hash, CompiledComposition]

proc `=destroy`*(x: PostEffectObj) =
  `=destroy`(x.source)
  `=destroy`(x.setupProc.addr[])
  `=destroy`(x.mainProcName)
  `=destroy`(x.argTypes)

proc `=destroy`*(x: CompiledCompositionObj) =
  if x.program != invalidGLProgram:
    try:
      glDeleteProgram(x.program)
    except Exception as e:
      echo "Exception encountered destroying CompiledCompositionObj program:", e.msg
  `=destroy`(x.uniformLocations)  # How to clean up UniformGLLocation entries?

proc `=destroy`*(x: Composition) =
  `=destroy`(x.definition)
  `=destroy`(x.vsDefinition)
  `=destroy`(x.precision)

proc `=destroy`(x:ProgramCache) =
  `=destroy`(x.entries.addr[])

var programCache = initLocker(ProgramCache.new())


const posAttr : GLuint = 0

proc replaceSymbolsInLine(syms: openarray[string], ln: string): string {.compileTime.} =
  result = ln
  if result.len != 0:
    for s in syms:
      result = result.replaceWord(s & ".tex", s & "_tex")
      result = result.replaceWord(s & ".texCoords", s & "_texCoords")

#[
proc uniforNamesFromShaderCode(code: string): seq[string] =
  result = newSeq[string]()
  var loc = 0
  while true:
    const prefix = "uniform "
    loc = code.find(prefix, loc)
    if loc < 0: break
    loc += prefix.len
    loc = code.find(" ", loc)
    if loc < 0: break
    inc loc
    let e = code.find(";", loc)
    if e < 0: break
    result.add(code.substr(loc, e - 1))
    loc = e
]#

proc preprocessDefinition(definition: string): string {.compileTime.} =
  result = ""
  var symbolsToReplace = newSeq[string]()
  for ln in definition.splitLines():
    const prefix = "uniform Image "
    if ln.startsWith(prefix):
      let uniformName = ln.substr(prefix.len, ln.len - 2)
      symbolsToReplace.add(uniformName)
      result &= "\Luniform sampler2D " & uniformName & "_tex;\Luniform vec4 " &
        uniformName & "_texCoords;"
    else:
      result &= "\L" & replaceSymbolsInLine(symbolsToReplace, ln)

proc newPostEffect*(definition: static[string], mainProcName: string,
    argTypes: openarray[string]): PostEffect =
  const preprocessedDefinition = preprocessDefinition(definition)
  result.new()
  result.source = preprocessedDefinition
  result.mainProcName = mainProcName
  result.argTypes = @argTypes
  result.id = hash(preprocessedDefinition)

template newPostEffect*(definition: static[string], mainProcName: string): PostEffect =
  newPostEffect(definition, mainProcName, [])

proc newComposition*(vsDef, fsDef: static[string], requiresPrequel: bool = true,
    precision: string = "highp"): Composition =
  const preprocessedDefinition = preprocessDefinition(fsDef)
  result.definition = preprocessedDefinition
  result.vsDefinition = vsDef
  result.requiresPrequel = requiresPrequel
  result.precision = precision
  result.id = hash(preprocessedDefinition)

template newComposition*(definition: static[string], requiresPrequel: bool = true): Composition =
  newComposition("", definition, requiresPrequel)

template newCompositionWithNimsl*(mainProc: typed): Composition =
  newComposition(getGLSLFragmentShader(mainProc, "compose"), false)

type PostEffectStackElem = object
  postEffect: PostEffect
  setupProc*: proc(cc: CompiledComposition) {.gcsafe.}

proc `=destroy`(x:PostEffectStackElem) =
  `=destroy`(x.postEffect)
  `=destroy`(x.setupProc.addr[])

type PostEffectStack = object
  postEffects: seq[PostEffectStackElem]
  postEffectIds: seq[Hash]

proc `=destroy`(x:PostEffectStack) =
  `=destroy`(x.postEffects)
  `=destroy`(x.postEffectIds)

var postEffectStack = initLocker(PostEffectStack.new())

proc getPostEffectUniformName(postEffectIndex, argIndex: int, output: var string) =
  output &= "uPE_"
  output &= $postEffectIndex
  output &= "_"
  output &= $argIndex

proc postEffectUniformName(postEffectIndex, argIndex: int): string =
  result = ""
  getPostEffectUniformName(postEffectIndex, argIndex, result)

proc compileComposition(comp: Composition, cchash: Hash,
    compOptions: int): CompiledComposition =
  var fragmentShaderCode = ""

  if (comp.definition.len != 0 and
      comp.definition.find("GL_OES_standard_derivatives") < 0) or
      comp.requiresPrequel:
    fragmentShaderCode &= """
      #ifdef GL_ES
      #extension GL_OES_standard_derivatives : enable
      precision """ & comp.precision & """ float;
      #endif
      """

  if comp.requiresPrequel:
    fragmentShaderCode &= """
      varying vec2 vPos;
      uniform vec4 bounds;
      """
    fragmentShaderCode &= commonDefinitions &
      distanceSetOperations &
      distanceFunctions &
      compositionFragmentFunctions &
      colorOperations

  var options = ""
  if compOptions != 0:
    for i in 0 ..< 32:
      if ((1 shl i) and compOptions) != 0:
        options &= "#define OPTION_" & $(i + 1) & "\n"
    fragmentShaderCode &= options

  fragmentShaderCode &= comp.definition

  lock postEffectStack as pest:
    let pes = pest.postEffects
    let ln = pes.len
    var i = 0
    while i < ln:
      let pe = pes[i].postEffect
      if not pe.seenFlag:
        fragmentShaderCode &= pe.source
        pe.seenFlag = true
      for j, argType in pe.argTypes:
        fragmentShaderCode &= "uniform " & argType & " "
        getPostEffectUniformName(i, j, fragmentShaderCode)
        fragmentShaderCode &= ";";
      inc i

    i = 0
    while i < ln:
      pes[i].postEffect.seenFlag = false
      inc i

    fragmentShaderCode &= """void main() { gl_FragColor = vec4(0.0); compose(); """
    i = pes.len - 1
    while i >= 0:
      fragmentShaderCode &= pes[i].postEffect.mainProcName & "("
      for j in 0 ..< pes[i].postEffect.argTypes.len:
        if j != 0:
          fragmentShaderCode &= ","
        getPostEffectUniformName(i, j, fragmentShaderCode)
      fragmentShaderCode &= ");"
      dec i

  fragmentShaderCode &= "}"

  result.new()
  let vsCode = if comp.vsDefinition.len == 0:
      options & vertexShaderCode
    else:
      options & comp.vsDefinition
  result.program = newShaderProgram(vsCode, fragmentShaderCode, [(posAttr, "aPosition")])
  result.uniformLocations = newSeq[UniformGLLocation]()
  lock programCache as pc:
    pc.entries[cchash] = result

# Kept in case it's needed someday - if it does get used then remove the .used pragma
proc unwrapPointArray(a: openarray[Point]): seq[GLfloat] {.used.} =
  result = newSeq[GLfloat](a.len * 2)
  var i = 0
  for p in a:
    result[i] = p.x
    inc i
    result[i] = p.y
    inc i

# This variable is used in template setUniform below - which means that it gets
# referenced from elsewhere. It appears to be some kind of shared working memory.
# And it works, despite the fact that it isn't public.
# I made it a threadvar instead of a global, so that if images are getting drawn
# concurrently in different threads they won't tramp on each other's feet.
# I ***really*** don't like this way of doing things. Need to figure out
# how we can get rid of it.
var texQuad {.threadvar.} : array[4, GLfloat]

template compositionDrawingDefinitions*(cc: CompiledComposition, ctx: GraphicsContext) =
  ## This template inserts the following templates into the code where it was
  ## invoked
  # It gets invoked when the "draw" template below is invoked
  template uniformLocation(name: string): UniformGLLocation =
    inc cc.iUniform
    if cc.uniformLocations.len - 1 < cc.iUniform:
      cc.uniformLocations.add(glGetUniformLocation(cc.program, name))
    cc.uniformLocations[cc.iUniform]

  template setUniform(name: string, v: Rect) {.hint[XDeclaredButNotUsed]: off.} =
    setRectUniform(uniformLocation(name), v)

  template setUniform(name: string, v: Point) {.hint[XDeclaredButNotUsed]: off.} =
    setPointUniform(uniformLocation(name), v)

  template setUniform(name: string, v: Size) {.hint[XDeclaredButNotUsed]: off.} =
    setUniform(name, newPoint(v.width, v.height))

  template setUniform(name: string, v: openarray[Point]) {.hint[XDeclaredButNotUsed]: off.} =
    glUniform2fv(uniformLocation(name), GLsizei(v.len), cast[ptr GLfloat](unsafeAddr v[0]))

  template setUniform(name: string, v: Color) {.hint[XDeclaredButNotUsed]: off.} =
    ctx.setColorUniform(uniformLocation(name), v)

  template setUniform(name: string, v: GLfloat) {.hint[XDeclaredButNotUsed]: off.}  =
    glUniform1f(uniformLocation(name), v)

  template setUniform(name: string, v: GLint) {.hint[XDeclaredButNotUsed]: off.}  =
    glUniform1i(uniformLocation(name), v)

  template setUniform(name: string, v: Vector3) {.hint[XDeclaredButNotUsed]: off.}  =
    uniformGL3fv(uniformLocation(name), v)

  template setUniform(name: string, v: Vector2) {.hint[XDeclaredButNotUsed]: off.}  =
    uniformGL2fv(uniformLocation(name), v)

  template setUniform(name: string, v: Matrix4) {.hint[XDeclaredButNotUsed]: off.}  =
    uniformGLMatrix4fv(uniformLocation(name), false, v)

  template setUniform(name: string, tex: TextureGLRef) {.hint[XDeclaredButNotUsed]: off.} =
    glActiveTexture(GLenum(int(GL_TEXTURE0) + cc.iTexIndex))
    glBindTexture(GL_TEXTURE_2D, tex)
    glUniform1i(uniformLocation(name), cc.iTexIndex)
    inc cc.iTexIndex

  template setUniform(name: string, i: Image) {.hint[XDeclaredButNotUsed]: off.} =
    glActiveTexture(GLenum(int(GL_TEXTURE0) + cc.iTexIndex))
    glBindTexture(GL_TEXTURE_2D, getTextureQuad(i, texQuad))
    uniformGL4fv(uniformLocation(name & "_texCoords"), texQuad)
    glUniform1i(uniformLocation(name & "_tex"), cc.iTexIndex)
    inc cc.iTexIndex

template pushPostEffect*(pe: PostEffect, ctx: GraphicsContext, args: varargs[untyped]) =
  lock postEffectStack as pest:
    var peids = pest.postEffectIds
    let stackLen = peids.len
    pest.postEffects.add(
      PostEffectStackElem(postEffect: pe,
        setupProc: proc(cc: CompiledComposition) =
          compositionDrawingDefinitions(cc, ctx)
          var j = 0
          staticFor uni in args:
            setUniform(postEffectUniformName(stackLen, j), uni)
            inc j
    ))

    let oh = if stackLen > 0: peids[^1] else: 0
    peids.add(oh !& pe.id)

template popPostEffect*() =
  lock postEffectStack as pest:
    pest.postEffects.setLen(pest.postEffects.len - 1)
    pest.postEffectIds.setLen(pest.postEffectIds.len - 1)

proc hasPostEffect*(): bool =
  lock postEffectStack as pest:
    result = pest.postEffects.len > 0

proc getCompiledComposition*(comp: Composition, options: int = 0): CompiledComposition =
  var pehash: Hash
  lock postEffectStack as pest:
    pehash = if pest.postEffectIds.len > 0: pest.postEffectIds[^1] else: 0
  let cchash = !$(pehash !& comp.id !& options)
  var cc: CompiledComposition
  lock programCache as pc:
    cc = pc.entries.getOrDefault(cchash)
  if cc.isNil:
    cc = compileComposition(comp, cchash, options)
  cc.iUniform = -1
  cc.iTexIndex = 0
  cc

template setupPosteffectUniforms*(cc: CompiledComposition) =
  lock postEffectStack as pest:
    for pe in pest.postEffects:
      pe.setupProc(cc)

# ******************************************
# The following 2 globals (overdrawValue and DIPValue) should actually be
# attributes of Window. They are only used for mini-profiler display, so
# it's not worth the bother to rationalize them until we decide whether to
# keep the mini-profiler at all.

# It is *assumed* that store and retrieve operations for 32-bit float are atomic
var overdrawValue = 0'f32   # Total no. of pixels overdrawn when the window is drawn
template GetOverdrawValue*() : float32 = overdrawValue / 1000

template ResetOverdrawValue*() =
  overdrawValue = 0

# It is ***assumed*** that store and retrieve operations for int are atomic
var DIPValue = 0   # Total number of images processed when the window is drawn
template GetDIPValue*() : int =
  DIPValue

template ResetDIPValue*() =
  DIPValue = 0
# ******************************************

template draw*(comp: Composition, ctx: GraphicsContext, r: Rect, code: untyped) =
  block:
    let cc = getCompiledComposition(comp)
    glUseProgram(cc.program)

    overdrawValue += r.size.width * r.size.height
    DIPValue += 1

    const componentCount = 2
    const vertexCount = 4
    glBindBuffer(GL_ARRAY_BUFFER, ctx.singleQuadBuffer)
    glEnableVertexAttribArray(posAttr)
    vertexGLAttribPointer(posAttr, componentCount, cGL_FLOAT, false, 0, 0)

    compositionDrawingDefinitions(cc, ctx)

    uniformGLMatrix4fv(uniformLocation("uModelViewProjectionMatrix"), false, ctx.transform)

    setUniform("bounds", r) # This is for fragment shader
    setUniform("uBounds", r) # This is for vertex shader

    setupPosteffectUniforms(cc)

    code
    glDrawArrays(GL_TRIANGLE_FAN, 0, vertexCount)
    glBindBuffer(GL_ARRAY_BUFFER, invalidGLBuffer)

template draw*(comp: Composition, ctx: GraphicsContext, r: Rect) =
  comp.draw(ctx, r):
    discard
