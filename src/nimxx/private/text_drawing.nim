import std/unicode
import ../font, ../composition, ../context, ../types
import ../opengl_etc

# The value in this global (bool) is retrieved and set atomically, so doesn't need a lock
var textSubpixelDrawing = true
proc enableTextSubpixelDrawing*(state: bool) =
  textSubpixelDrawing = state

const fontComposition = newComposition("""
attribute vec4 aPosition;

uniform mat4 uModelViewProjectionMatrix;
varying vec2 vTexCoord;

varying vec2 vPos;

void main() {
  vPos = aPosition.xy;
  vTexCoord = aPosition.zw;
  gl_Position = uModelViewProjectionMatrix * vec4(aPosition.xy, 0, 1);
}
""",
"""
uniform sampler2D texUnit;
uniform vec4 fillColor;
uniform float preScale;

varying vec2 vTexCoord;

varying vec2 vPos;

float thresholdFunc(float glyphScale)
{
  float base = 0.5;
  float baseDev = 0.065;
  float devScaleMin = 0.15;
  float devScaleMax = 0.3;
  return base - ((clamp(glyphScale, devScaleMin, devScaleMax) - devScaleMin) / (devScaleMax - devScaleMin) * -baseDev + baseDev);
}

float spreadFunc(float glyphScale)
{
  float range = 0.06;
  return range / glyphScale;
}

void compose()
{
  float scale = preScale / fwidth(vTexCoord.x);
  scale = abs(scale);
  float aBase = thresholdFunc(scale);
  float aRange = spreadFunc(scale);
  float aMin = max(0.0, aBase - aRange);
  float aMax = min(aBase + aRange, 1.0);

  float dist = texture2D(texUnit, vTexCoord).a;
  float alpha = smoothstep(aMin, aMax, dist);
  gl_FragColor = vec4(fillColor.rgb, alpha * fillColor.a);
}
""", false)

when false:
  let fontSubpixelComposition = newComposition("""
  attribute vec4 aPosition;

  uniform mat4 uModelViewProjectionMatrix;
  varying vec2 vTexCoord;

  varying vec2 vPos;

  void main() {
    vPos = aPosition.xy;
    vTexCoord = aPosition.zw;
    gl_Position = uModelViewProjectionMatrix * vec4(aPosition.xy, 0, 1);
  }
  """,
  """
  uniform sampler2D texUnit;
  uniform vec4 fillColor;
  uniform float alphaMin;
  uniform float alphaMax;

  varying vec2 vTexCoord;

  varying vec2 vPos;

  void subpixelCompose()
  {
    vec4 n;
    float shift = dFdx(vTexCoord.x);

    n.x = texture2D(texUnit, vTexCoord.xy - vec2(0.667 * shift, 0.0)).a;
    n.y = texture2D(texUnit, vTexCoord.xy - vec2(0.333 * shift, 0.0)).a;
    n.z = texture2D(texUnit, vTexCoord.xy + vec2(0.333 * shift, 0.0)).a;
    n.w = texture2D(texUnit, vTexCoord.xy + vec2(0.667 * shift, 0.0)).a;
    float c = texture2D(texUnit, vTexCoord.xy).a;

  #if 0
    // Blurrier, faster.
    n = smoothstep(alphaMin, alphaMax, n);
    c = smoothstep(alphaMin, alphaMax, c);
  #else
    // Sharper, slower.
    vec2 d = min(abs(n.yw - n.xz) * 2., 0.67);
    vec2 lo = mix(vec2(alphaMin), vec2(0.5), d);
    vec2 hi = mix(vec2(alphaMax), vec2(0.5), d);
    n = smoothstep(lo.xxyy, hi.xxyy, n);
    c = smoothstep(lo.x + lo.y, hi.x + hi.y, 2. * c);
  #endif

    gl_FragColor = vec4(0.333 * (n.xyz + n.yzw + c), c) * fillColor.a;
  }

  void compose()
  {
    subpixelCompose();
  }
  """, false)

const fontSubpixelCompositionWithDynamicBase = newComposition("""
attribute vec4 aPosition;

uniform mat4 uModelViewProjectionMatrix;
varying vec2 vTexCoord;

varying vec2 vPos;

void main() {
  vPos = aPosition.xy;
  vTexCoord = aPosition.zw;
  gl_Position = uModelViewProjectionMatrix * vec4(aPosition.xy, 0, 1);
}
""",
"""
uniform sampler2D texUnit;
uniform vec4 fillColor;
uniform float preScale;

varying vec2 vTexCoord;

varying vec2 vPos;

float thresholdFunc(float glyphScale)
{
  float base = 0.5;
  float baseDev = 0.065;
  float devScaleMin = 0.15;
  float devScaleMax = 0.3;
  return base - ((clamp(glyphScale, devScaleMin, devScaleMax) - devScaleMin) / (devScaleMax - devScaleMin) * -baseDev + baseDev);
}

float spreadFunc(float glyphScale)
{
  float range = 0.055;
  return range / glyphScale;
}

void subpixelCompose()
{
  float scale = preScale / fwidth(vTexCoord.x); // 0.25 * 1.0 / (dFdx(vTexCoord.x) / (16.0 / 1280.0));
  scale = abs(scale);
  float aBase = thresholdFunc(scale);
  float aRange = spreadFunc(scale);
  float aMin = max(0.0, aBase - aRange);
  float aMax = min(aBase + aRange, 1.0);

  vec4 n;
  vec2 shift_vec = vec2(0.0);
  shift_vec.x = dFdx(vTexCoord.x);
  n.x = texture2D(texUnit, vTexCoord.xy - shift_vec * 0.667).a;
  n.y = texture2D(texUnit, vTexCoord.xy - shift_vec * 0.333).a;
  n.z = texture2D(texUnit, vTexCoord.xy + shift_vec * 0.333).a;
  n.w = texture2D(texUnit, vTexCoord.xy + shift_vec * 0.667).a;
  float c = texture2D(texUnit, vTexCoord.xy).a;

#if 0
  // Blurrier, faster.
  n = smoothstep(aMin, aMax, n);
  c = smoothstep(aMin, aMax, c);
#else
  // Sharper, slower.
  vec2 d = min(abs(n.yw - n.xz) * 2., 0.67);
  vec2 lo = mix(vec2(aMin), vec2(0.5), d);
  vec2 hi = mix(vec2(aMax), vec2(0.5), d);
  n = smoothstep(lo.xxyy, hi.xxyy, n);
  c = smoothstep(lo.x + lo.y, hi.x + hi.y, 2. * c);
#endif

  gl_FragColor = vec4(0.333 * (n.xyz + n.yzw + c), c) * fillColor.a;
}

void compose()
{
  subpixelCompose();
}
""", false, "mediump")

proc drawTextBase*(c: GraphicsContext, font: Font, pt: var Point, text: string) =
  glEnableVertexAttribArray(saPosition.GLuint)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, c.quadIndexBuffer)
  glBindBuffer(GL_ARRAY_BUFFER, c.sharedBuffer)

  var texture: TextureGLRef
  var newTexture: TextureGLRef
  var n : GLint = 0

  template flush() =
    const componentCount = 4
    copyDataToGLBuffer(GL_ARRAY_BUFFER, c.vertexes, componentCount * n * 4, GL_DYNAMIC_DRAW)
    vertexGLAttribPointer(saPosition.GLuint, componentCount, cGL_FLOAT, false, 0, 0)
    drawGLElements(GL_TRIANGLES, n * 6, GL_UNSIGNED_SHORT)

  for ch in text.runes:
    if n > 127:
      flush()
      n = 0

    let off = n * 16
    font.getQuadDataForRune(ch, c.vertexes, off, newTexture, pt)
    if texture != newTexture:
      if n > 0:
        flush()
        for i in 0 ..< 16: c.vertexes[i] = c.vertexes[i + off]
        n = 0

      texture = newTexture
      glBindTexture(GL_TEXTURE_2D, texture)
    inc n
    pt.x += font.horizontalSpacing

  if n > 0: flush()

proc drawText*(c: GraphicsContext, font: Font, pt: var Point, text: string) =
  # assume orthographic projection with units = screen pixels, origin at top left
  var cc : CompiledComposition
  var subpixelDraw = textSubpixelDrawing

  if hasPostEffect():
    subpixelDraw = false

  when defined(android) or defined(ios):
    subpixelDraw = false

  let preScale = 1.0 / 320.0 # magic constant...

  if subpixelDraw:
    if getGLParami(GL_BLEND_SRC_ALPHA) != GL_SRC_ALPHA.GLint or getGLParami(GL_BLEND_DST_ALPHA) != GL_ONE_MINUS_SRC_ALPHA.GLint:
      subpixelDraw = false

  if subpixelDraw:
    cc = getCompiledComposition(fontSubpixelCompositionWithDynamicBase)
    glBlendColor(c.fillColor.r, c.fillColor.g, c.fillColor.b, c.fillColor.a)
    glBlendFunc(GL_CONSTANT_COLOR, GL_ONE_MINUS_SRC_COLOR)
  else:
    cc = getCompiledComposition(fontComposition)

  glUseProgram(cc.program)

  compositionDrawingDefinitions(cc, c)
  setUniform("fillColor", c.fillColor)
  setUniform("preScale", preScale)

  uniformGLMatrix4fv(uniformLocation("uModelViewProjectionMatrix"), false, c.transform)
  setupPosteffectUniforms(cc)

  glActiveTexture(GLenum(int(GL_TEXTURE0) + cc.iTexIndex))
  glUniform1i(uniformLocation("texUnit"), cc.iTexIndex)

  c.drawTextBase(font, pt, text)

  if subpixelDraw:
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)

proc drawText*(c: GraphicsContext, font: Font, pt: Point, text: string) {.gcsafe.}=
  var p = pt
  c.drawText(font, p, text)
