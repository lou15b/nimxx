## Provides access to opengl, plus a number of helpers to aid convenient access
## using idiomatic nim

import pkg/opengl
export opengl


type
  FramebufferGLRef* = GLuint
  RenderbufferGLRef* = GLuint
  BufferGLRef* = GLuint
  TextureGLRef* = GLuint
  UniformGLLocation* = GLint
  ProgramGLRef* = GLuint
  ShaderGLRef* = GLuint

const invalidGLUniformLocation* : UniformGLLocation = -1
const invalidGLProgram* : ProgramGLRef = 0
const invalidGLShader* : ShaderGLRef = 0
const invalidGLBuffer* : BufferGLRef = 0
const invalidGLFrameBuffer* : FramebufferGLRef = 0
const invalidGLRenderBuffer* : RenderbufferGLRef = 0
const invalidGLTexture* : TextureGLRef = 0

# This is intended to be used by code that calls opengl procs, but that also
# may be called by unit tests with no opengl context established.
# It is set once when opengl is set up, and read thereafter. So no lock needed.
var openglInitializedFlag: bool = false
proc isOpenglInitialized*(): bool = openglInitializedFlag
proc markOpenglInitialized*() = openglInitializedFlag = true

template drawGLElements*(mode: GLenum, count: GLsizei, typ: GLenum, offset: int = 0) =
  glDrawElements(mode, count, typ, cast[pointer](offset))
proc createGLTexture*(): GLuint = glGenTextures(1, addr result)
proc createGLFramebuffer*(): GLuint {.inline.} =
  glGenFramebuffers(1, addr result)
proc createGLRenderbuffer*(): GLuint {.inline.} =
  glGenRenderbuffers(1, addr result)
proc createGLBuffer*(): GLuint {.inline.} = glGenBuffers(1, addr result)
template allocateGLBufferData*(target: GLenum, size: int32, usage: GLenum) =
  glBufferData(target, size, nil, usage)

proc deleteGLFramebuffer*(name: FramebufferGLRef) {.inline.} =
  glDeleteFramebuffers(1, unsafeAddr name)

proc deleteGLRenderbuffer*(name: RenderbufferGLRef) {.inline.} =
  glDeleteRenderbuffers(1, unsafeAddr name)

proc deleteGLBuffer*(name: BufferGLRef) {.inline.} =
  glDeleteBuffers(1, unsafeAddr name)

proc deleteGLTexture*(name: TextureGLRef) {.inline.} =
  glDeleteTextures(1, unsafeAddr name)

template vertexGLAttribPointer*(index: GLuint, size: GLint, typ: GLenum,
    normalized: GLboolean, stride: GLsizei, offset: int) =
  glVertexAttribPointer(index, size, typ, normalized, stride, cast[pointer](offset))

template uniformGL2fv*(location: UniformGLLocation, data: openarray[GLfloat]) =
  glUniform2fv(location, GLSizei(data.len / 2), unsafeAddr data[0])
template uniformGL3fv*(location: UniformGLLocation, data: openarray[GLfloat]) =
  glUniform3fv(location, GLSizei(data.len / 3), unsafeAddr data[0])
template uniformGL3iv*(location: UniformGLLocation, data: openarray[GLint]) =
  glUniform3iv(location, GLSizei(data.len / 3), unsafeAddr data[0])
template uniformGL4fv*(location: UniformGLLocation, data: openarray[GLfloat]) =
  glUniform4fv(location, GLsizei(data.len / 4), unsafeAddr data[0])
template uniformGL1fv*(location: UniformGLLocation, data: openarray[GLfloat]) =
  glUniform1fv(location, GLsizei(data.len), unsafeAddr data[0])
proc uniformGLMatrix4fv*(location: UniformGLLocation, transpose: GLboolean,
    data: array[16, GLfloat]) {.inline.} =
  glUniformMatrix4fv(location, 1, transpose, unsafeAddr data[0])
proc uniformGLMatrix3fv*(location: UniformGLLocation, transpose: GLboolean,
    data: array[9, GLfloat]) {.inline.} =
  glUniformMatrix3fv(location, 1, transpose, unsafeAddr data[0])

template texGLImage2D*(target: GLenum, level, internalformat: GLint,
    width, height: GLsizei, border: GLint, format, t: GLenum, pixels: openarray) =
  glTexImage2D(target, level, internalformat, width, height, border, format, t,
    unsafeAddr pixels[0])
template texGLSubImage2D*(target: GLenum, level: GLint, xoffset, yoffset: GLint,
    width, height: GLsizei, format, t: GLenum, pixels: openarray) =
  glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, t,
    unsafeAddr pixels[0])

template isEmptyGLRef*(obj: TextureGLRef or FramebufferGLRef or RenderbufferGLRef): bool =
  obj == 0

proc shaderGLInfoLog*(s: ShaderGLRef): string =
  var infoLen: GLint
  var dummy: string
  dummy.setLen(1)
  glGetShaderInfoLog(s, sizeof(dummy).GLint, addr infoLen, cstring(dummy))
  if infoLen > 0:
    result.setLen(infoLen + 1)
    glGetShaderInfoLog(s, infoLen, nil, cstring(result))

proc programGLInfoLog*(s: ProgramGLRef): string =
  var infoLen: GLint
  var dummy: string
  dummy.setLen(1)
  glGetProgramInfoLog(s, sizeof(dummy).GLint, addr infoLen, cstring(dummy))
  if infoLen > 0:
    result.setLen(infoLen + 1)
    glGetProgramInfoLog(s, infoLen, nil, cstring(result))

proc shaderGLSource*(s: ShaderGLRef, src: cstring) =
  var srcArray = [src]
  glShaderSource(s, 1, cast[cstringArray](addr srcArray), nil)

proc isGLShaderCompiled*(shader: ShaderGLRef): bool {.inline.} =
  var compiled: GLint
  glGetShaderiv(shader, GL_COMPILE_STATUS, addr compiled)
  result = GLboolean(compiled) == GLboolean(GL_TRUE)

proc isGLProgramLinked*(prog: ProgramGLRef): bool {.inline.} =
  var linked: GLint
  glGetProgramiv(prog, GL_LINK_STATUS, addr linked)
  result = GLboolean(linked) == GLboolean(GL_TRUE)

proc copyDataToGLBuffer*[T](target: GLenum, data: openarray[T], size: int,
    usage: GLenum) {.inline.} =
  assert(size <= data.len)
  glBufferData(target, GLsizei(size * sizeof(T)), cast[pointer](data), usage);

proc copyDataToGLBuffer*[T](target: GLenum, data: openarray[T], usage: GLenum) {.inline.} =
  glBufferData(target, GLsizei(data.len * sizeof(T)), cast[pointer](data), usage);

proc copyDataToGLSubBuffer*[T](target: GLenum, offset: int32, data: openarray[T]) {.inline.} =
  glBufferSubData(target, offset, GLsizei(data.len * sizeof(T)), cast[pointer](data));

proc getGLBufferParameteriv*(target, value: GLenum): GLint {.inline.} =
  glGetBufferParameteriv(target, value, addr result)

proc vertexGLAttribPointer*(index: GLuint, size: GLint, normalized: GLboolean,
            stride: GLsizei, data: openarray[GLfloat]) =
  glVertexAttribPointer(index, size, cGL_FLOAT, normalized, stride, cast[pointer](data));

proc getGLParami*(pname: GLenum): GLint =
  glGetIntegerv(pname, addr result)

proc getGLParamf*(pname: GLenum): GLfloat =
  glGetFloatv(pname, addr result)

proc getGLParamb*(pname: GLenum): GLboolean =
  glGetBooleanv(pname, addr result)

proc getGLViewport*(): array[4, GLint] =
  glGetIntegerv(GL_VIEWPORT, addr result[0])

template setGLViewport*(vp: array[4, GLint]) = glViewport(vp[0], vp[1], vp[2], vp[3])

template getBoundGLFramebuffer*(): FramebufferGLRef =
  cast[FramebufferGLRef](getGLParami(GL_FRAMEBUFFER_BINDING))
template getBoundGLRenderbuffer*(): RenderbufferGLRef =
  cast[RenderbufferGLRef](getGLParami(GL_RENDERBUFFER_BINDING))

proc getGLClearColor*(colorComponents: var array[4, GLfloat]) =
  glGetFloatv(GL_COLOR_CLEAR_VALUE, cast[ptr GLfloat](addr colorComponents))

proc clearGLWithColor*(r, g, b, a: GLfloat) =
  var oldColor: array[4, GLfloat]
  getGLClearColor(oldColor)
  glClear(GL_COLOR_BUFFER_BIT or GL_STENCIL_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  glClearColor(oldColor[0], oldColor[1], oldColor[2], oldColor[3])

proc clearGLDepthStencil*() =
  glClear(GL_STENCIL_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
