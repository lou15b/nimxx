import ./context_base
import ./types
import ./matrixes
import ./image
import std/math
import ./opengl_etc
import pkg/nimsl/nimsl

export matrixes, context_base
import ./composition

const roundedRectComposition = newComposition """
uniform vec4 uFillColor;
uniform vec4 uStrokeColor;
uniform float uStrokeWidth;
uniform float uRadius;

void compose() {
  drawInitialShape(sdRoundedRect(bounds, uRadius), uStrokeColor);
  drawShape(sdRoundedRect(insetRect(bounds, uStrokeWidth), uRadius - uStrokeWidth), uFillColor);
}
"""

proc drawRoundedRect*(c: GraphicsContext, r: Rect, radius: Coord) =
  roundedRectComposition.draw(c, r):
    setUniform("uFillColor", c.fillColor)
    setUniform("uStrokeColor", if c.strokeWidth == 0: c.fillColor else: c.strokeColor)
    setUniform("uStrokeWidth", c.strokeWidth)
    setUniform("uRadius", radius)

proc drawRect(bounds, uFillColor, uStrokeColor: Vec4,
          uStrokeWidth: float32,
          vPos: Vec2): Vec4 =
  result.drawInitialShape(sdRect(vPos, bounds), uStrokeColor);
  result.drawShape(sdRect(vPos, insetRect(bounds, uStrokeWidth)), uFillColor);

const rectComposition = newCompositionWithNimsl(drawRect)

proc drawRect*(c: GraphicsContext, r: Rect) =
  rectComposition.draw(c, r):
    setUniform("uFillColor", c.fillColor)
    setUniform("uStrokeColor", if c.strokeWidth == 0: c.fillColor else: c.strokeColor)
    setUniform("uStrokeWidth", c.strokeWidth)

proc drawEllipse(bounds, uFillColor, uStrokeColor: Vec4,
          uStrokeWidth: float32,
          vPos: Vec2): Vec4 =
  result.drawInitialShape(sdEllipseInRect(vPos, bounds), uStrokeColor);
  result.drawShape(sdEllipseInRect(vPos, insetRect(bounds, uStrokeWidth)), uFillColor);

const ellipseComposition = newCompositionWithNimsl(drawEllipse)

proc drawEllipseInRect*(c: GraphicsContext, r: Rect) =
  ellipseComposition.draw(c, r):
    setUniform("uFillColor", c.fillColor)
    setUniform("uStrokeColor", if c.strokeWidth == 0: c.fillColor else: c.strokeColor)
    setUniform("uStrokeWidth", c.strokeWidth)

proc imageVertexShader(aPosition: Vec2, uModelViewProjectionMatrix: Mat4, uBounds, uImage_texCoords, uFromRect: Vec4, vPos, vImageUV: var Vec2): Vec4 =
  let f = uFromRect
  let t = uImage_texCoords
  vPos = uBounds.xy + aPosition * uBounds.zw
  vImageUV = t.xy + (t.zw - t.xy) * (f.xy + (f.zw - f.xy) * aPosition)
  result = uModelViewProjectionMatrix * newVec4(vPos, 0.0, 1.0)

const imageVertexShaderCode = getGLSLVertexShader(imageVertexShader)

const imageComposition = newComposition(imageVertexShaderCode, """
uniform sampler2D uImage_tex;
uniform float uAlpha;
varying vec2 vImageUV;

void compose() {
  gl_FragColor = texture2D(uImage_tex, vImageUV);
  gl_FragColor.a *= uAlpha;
}
""")

proc bindVertexData*(c: GraphicsContext, length: int) =
  glBindBuffer(GL_ARRAY_BUFFER, c.sharedBuffer)
  copyDataToGLBuffer(GL_ARRAY_BUFFER, c.vertexes, length, GL_DYNAMIC_DRAW)

proc drawImage*(c: GraphicsContext, i: Image, toRect: Rect, fromRect: Rect = zeroRect, alpha: ColorComponent = 1.0) =
  if i.isLoaded:
    var fr = newRect(0, 0, 1, 1)
    if fromRect != zeroRect:
      let s = i.size
      fr = newRect(fromRect.x / s.width, fromRect.y / s.height, fromRect.maxX / s.width, fromRect.maxY / s.height)
    imageComposition.draw(c, toRect):
      setUniform("uImage", i)
      setUniform("uAlpha", alpha * c.alpha)
      setUniform("uFromRect", fr)

const ninePartImageComposition = newComposition("""
attribute vec4 aPosition;

uniform mat4 uModelViewProjectionMatrix;
varying vec2 vTexCoord;

void main() {
  vTexCoord = aPosition.zw;
  gl_Position = uModelViewProjectionMatrix * vec4(aPosition.xy, 0, 1);
}
""",
"""
varying vec2 vTexCoord;

uniform sampler2D texUnit;
uniform float uAlpha;

void compose() {
  gl_FragColor = texture2D(texUnit, vTexCoord);
  gl_FragColor.a *= uAlpha;
}
""", false)

proc drawNinePartImage*(c: GraphicsContext, i: Image, toRect: Rect, ml, mt, mr, mb: Coord, fromRect: Rect = zeroRect,
    alpha: ColorComponent = 1.0) =
  if i.isLoaded:
    var cc = getCompiledComposition(ninePartImageComposition)

    var fuv : array[4, GLfloat]
    let tex = getTextureQuad(i, fuv)

    let sz = i.size
    if fromRect != zeroRect:
      fuv[0] = fuv[0] + fromRect.x / sz.width
      fuv[1] = fuv[1] + fromRect.y / sz.height
      fuv[2] = fuv[2] - (sz.width - fromRect.maxX) / sz.width
      fuv[3] = fuv[3] - (sz.height - fromRect.maxY) / sz.height

    template setVertex(index: int, x, y, u, v: GLfloat) =
      c.vertexes[index * 2 * 2 + 0] = x
      c.vertexes[index * 2 * 2 + 1] = y
      c.vertexes[index * 2 * 2 + 2] = u
      c.vertexes[index * 2 * 2 + 3] = v

    let duvx = fuv[2] - fuv[0]
    let duvy = fuv[3] - fuv[1]

    let tml = ml / sz.width * duvx
    let tmr = mr / sz.width * duvx
    let tmt = mt / sz.height * duvy
    let tmb = mb / sz.height * duvy

    0.setVertex(toRect.x, toRect.y, fuv[0], fuv[1])
    1.setVertex(toRect.x + ml, toRect.y, fuv[0] + tml, fuv[1])
    2.setVertex(toRect.maxX - mr, toRect.y, fuv[2] - tmr, fuv[1])
    3.setVertex(toRect.maxX, toRect.y, fuv[2], fuv[1])

    4.setVertex(toRect.x, toRect.y + mt, fuv[0], fuv[1] + tmt)
    5.setVertex(toRect.x + ml, toRect.y + mt, fuv[0] + tml, fuv[1] + tmt)
    6.setVertex(toRect.maxX - mr, toRect.y + mt, fuv[2] - tmr, fuv[1] + tmt)
    7.setVertex(toRect.maxX, toRect.y + mt, fuv[2], fuv[1] + tmt)

    8.setVertex(toRect.x, toRect.maxY - mb, fuv[0], fuv[3] - tmb)
    9.setVertex(toRect.x + ml, toRect.maxY - mb, fuv[0] + tml, fuv[3] - tmb)
    10.setVertex(toRect.maxX - mr, toRect.maxY - mb, fuv[2] - tmr, fuv[3] - tmb)
    11.setVertex(toRect.maxX, toRect.maxY - mb, fuv[2], fuv[3] - tmb)

    12.setVertex(toRect.x, toRect.maxY, fuv[0], fuv[3])
    13.setVertex(toRect.x + ml, toRect.maxY, fuv[0] + tml, fuv[3])
    14.setVertex(toRect.maxX - mr, toRect.maxY, fuv[2] - tmr, fuv[3])
    15.setVertex(toRect.maxX, toRect.maxY, fuv[2], fuv[3])

    glUseProgram(cc.program)
    compositionDrawingDefinitions(cc, c)

    setUniform("uAlpha", alpha * c.alpha)

    uniformGLMatrix4fv(uniformLocation("uModelViewProjectionMatrix"), false, c.transform)
    setupPosteffectUniforms(cc)

    glActiveTexture(GLenum(int(GL_TEXTURE0) + cc.iTexIndex))
    glUniform1i(uniformLocation("texUnit"), cc.iTexIndex)
    glBindTexture(GL_TEXTURE_2D, tex)

    glEnableVertexAttribArray(ShaderAttribute.saPosition.GLuint)
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, c.gridIndexBuffer4x4)

    const componentsCount = 4
    const vertexCount = (4 - 1) * 4 * 2
    c.bindVertexData(componentsCount * vertexCount)
    vertexGLAttribPointer(ShaderAttribute.saPosition.GLuint, componentsCount, cGL_FLOAT, false, 0, 0)
    drawGLElements(GL_TRIANGLE_STRIP, vertexCount, GL_UNSIGNED_SHORT)


const simpleComposition = newComposition("""
attribute vec4 aPosition;
uniform mat4 uModelViewProjectionMatrix;

void main() {
  gl_Position = uModelViewProjectionMatrix * vec4(aPosition.xy, 0, 1);
}
""",
"""
#ifdef GL_ES
#extension GL_OES_standard_derivatives : enable
precision mediump float;
#endif
uniform vec4 uStrokeColor;

void compose() {
  gl_FragColor = uStrokeColor;
}
""", false)

proc bezierPoint(p0, p1, p2, p3, t: float32): float32 =
  result = (pow((1-t), 3.0) * p0) +
    (3 * pow((1-t),2) * t * p1) +
    (3 * (1-t) * t * t * p2) +
    (pow(t, 3) * p3)

proc drawBezier*(c: GraphicsContext, p0, p1, p2, p3: Point) =
  var cc = getCompiledComposition(simpleComposition)

  template setVertex(index: int, p: Point) =
    c.vertexes[index * 2 + 0] = p.x.GLfloat
    c.vertexes[index * 2 + 1] = p.y.GLfloat

  let vertexCount = 300
  for i in 0..<vertexCount:
    let t = i / (vertexCount - 1)
    let p = newPoint(bezierPoint(p0.x, p1.x, p2.x, p3.x, t), bezierPoint(p0.y, p1.y, p2.y, p3.y, t))
    setVertex(i, p)

  glUseProgram(cc.program)
  compositionDrawingDefinitions(cc, c)

  uniformGLMatrix4fv(uniformLocation("uModelViewProjectionMatrix"), false, c.transform)
  setUniform("uStrokeColor", c.strokeColor)
  setupPosteffectUniforms(cc)

  const componentsCount = 2
  glEnableVertexAttribArray(ShaderAttribute.saPosition.GLuint)
  c.bindVertexData(componentsCount * vertexCount)
  vertexGLAttribPointer(ShaderAttribute.saPosition.GLuint, componentsCount, cGL_FLOAT, false, 0, 0)

  glEnable(GL_LINE_SMOOTH)
  glHint(GL_LINE_SMOOTH_HINT, GL_NICEST)

  glLineWidth(c.strokeWidth)

  glDrawArrays(GL_LINE_STRIP, 0.GLint, vertexCount.GLsizei)
  glLineWidth(1.0)


const lineComposition = newComposition """
uniform float uStrokeWidth;
uniform vec4  uStrokeColor;
uniform vec2  A;
uniform vec2  B;

float drawLine(vec2 p1, vec2 p2) {
  vec2 va = B - A;
  vec2 vb = vPos - A;
  vec2 vc = vPos - B;

  vec3 tri = vec3(distance(A, B), distance(vPos, A), distance(vPos, B));
  float p = (tri.x + tri.y + tri.z) / 2.0;
  float h = 2.0 * sqrt(p * (p - tri.x) * (p - tri.y) * (p - tri.z)) / tri.x;

  vec2 angles = acos(vec2(dot(normalize(-va), normalize(vc)), dot(normalize(va), normalize(vb))));
  vec2 anglem = 1.0 - step(PI / 2.0, angles);
  float pixelValue = 1.0 - smoothstep(0.0, uStrokeWidth, h);

  float res = anglem.x * anglem.y * pixelValue;
  return res;
}

void compose() {
  gl_FragColor = vec4(uStrokeColor.xyz, uStrokeColor.a * drawLine(A, B));
}
"""

proc drawLine*(c: GraphicsContext, pointFrom: Point, pointTo: Point) =
  let xfrom = min(pointFrom.x, pointTo.x)
  let yfrom = min(pointFrom.y, pointTo.y)
  let xsize = max(pointFrom.x, pointTo.x) - xfrom
  let ysize = max(pointFrom.y, pointTo.y) - yfrom
  let r = newRect(xfrom - c.strokeWidth, yfrom - c.strokeWidth, xsize + 2 * c.strokeWidth, ysize + 2 * c.strokeWidth)

  lineComposition.draw(c, r):
    setUniform("uStrokeWidth", c.strokeWidth)
    setUniform("uStrokeColor", c.strokeColor)
    setUniform("A", pointFrom)
    setUniform("B", pointTo)

const arcComposition = newComposition """
uniform float uStrokeWidth;
uniform vec4 uStrokeColor;
uniform vec4 uFillColor;
uniform float uStartAngle;
uniform float uEndAngle;

void compose() {
  vec2 center = bounds.xy + bounds.zw / 2.0;
  float radius = min(bounds.z, bounds.w) / 2.0 - 1.0;
  float centerDist = distance(vPos, center);
  vec2 delta = vPos - center;
  float angle = atan(delta.y, delta.x);
  angle += step(angle, 0.0) * PI * 2.0;

  float angleDist1 = step(step(angle, uStartAngle) + step(uEndAngle, angle), 0.0);
  angle += PI * 2.0;
  float angleDist2 = step(step(angle, uStartAngle) + step(uEndAngle, angle), 0.0);

  drawInitialShape((centerDist - radius) / radius, uStrokeColor);
  drawShape((centerDist - radius + uStrokeWidth) / radius, uFillColor);
  gl_FragColor.a *= max(angleDist1, angleDist2);
}
"""

proc drawArc*(c: GraphicsContext, center: Point, radius: Coord, fromAngle, toAngle: Coord) =
  if abs(fromAngle - toAngle) < 0.0001: return
  var fromAngle = fromAngle
  var toAngle = toAngle
  fromAngle = fromAngle mod (2 * Pi)
  toAngle = toAngle mod (2 * Pi)
  if fromAngle < 0: fromAngle += Pi * 2
  if toAngle < 0: toAngle += Pi * 2
  if toAngle < fromAngle:
    toAngle += Pi * 2

  let rad = radius + 1
  let r = newRect(center.x - rad, center.y - rad, rad * 2, rad * 2)
  arcComposition.draw(c, r):
    setUniform("uStrokeWidth", c.strokeWidth)
    setUniform("uFillColor", c.fillColor)
    setUniform("uStrokeColor", if c.strokeWidth == 0: c.fillColor else: c.strokeColor)
    setUniform("uStartAngle", fromAngle)
    setUniform("uEndAngle", toAngle)

const triangleComposition = newComposition """
uniform float uAngle;
uniform vec4 uColor;
void compose() {
  vec2 center = vec2(bounds.x + bounds.z / 2.0, bounds.y + bounds.w / 2.0 - 1.0);
  float triangle = sdRegularPolygon(center, 4.0, 3, uAngle);
  drawShape(triangle, uColor);
}
"""

proc drawTriangle*(c: GraphicsContext, rect: Rect, angleRad: Coord) =
  ## Draws equilateral triangle with current `fillColor`, pointing at `angleRad`
  var color = c.fillColor
  color.a *= c.alpha
  triangleComposition.draw(c, rect):
    setUniform("uAngle", angleRad)
    setUniform("uColor", color)

# Clipping
proc applyClippingRect*(c: GraphicsContext, r: Rect, on: bool) =
  glEnable(GL_STENCIL_TEST)
  glColorMask(false, false, false, false)
  glDepthMask(false)
  glStencilMask(0xFF)
  if on:
    inc c.clippingDepth
    glStencilOp(GL_INCR, GL_KEEP, GL_KEEP)
  else:
    dec c.clippingDepth
    glStencilOp(GL_DECR, GL_KEEP, GL_KEEP)

  glStencilFunc(GL_NEVER, 1, 0xFF)
  c.drawRect(r)

  glColorMask(true, true, true, true)
  glDepthMask(true)
  glStencilMask(0x00)

  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP)
  glStencilFunc(GL_EQUAL, c.clippingDepth, 0xFF)
  if c.clippingDepth == 0:
    glDisable(GL_STENCIL_TEST)

template withClippingRect*(c: GraphicsContext, r: Rect, body: typed) =
  c.applyClippingRect(r, true)
  body
  c.applyClippingRect(r, false)
