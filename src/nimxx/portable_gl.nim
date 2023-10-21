
import opengl
# export opengl

export GLuint, GLint, GLfloat, GLenum, GLsizei, GLushort, GLbitfield, opengl.`or`

type
    FramebufferRef* = GLuint
    RenderbufferRef* = GLuint
    BufferRef* = GLuint
    TextureRef* = GLuint
    UniformLocation* = GLint
    ProgramRef* = GLuint
    ShaderRef* = GLuint

const invalidUniformLocation* : UniformLocation = -1
const invalidProgram* : ProgramRef = 0
const invalidShader* : ShaderRef = 0
const invalidBuffer* : BufferRef = 0
const invalidFrameBuffer* : FramebufferRef = 0
const invalidRenderBuffer* : RenderbufferRef = 0
const invalidTexture* : TextureRef = 0

template VERTEX_SHADER*(): GLenum = GL_VERTEX_SHADER
template FRAGMENT_SHADER*(): GLenum = GL_FRAGMENT_SHADER
template TEXTURE_2D*(): GLenum = GL_TEXTURE_2D
template CONSTANT_COLOR*(): GLenum = GL_CONSTANT_COLOR
template ONE_MINUS_SRC_COLOR*(): GLenum = GL_ONE_MINUS_SRC_COLOR
template ONE_MINUS_SRC_ALPHA*(): GLenum = GL_ONE_MINUS_SRC_ALPHA
template ONE_MINUS_DST_ALPHA*(): GLenum = GL_ONE_MINUS_DST_ALPHA
template SRC_ALPHA*(): GLenum = GL_SRC_ALPHA
template DST_ALPHA*(): GLenum = GL_DST_ALPHA
template DST_COLOR*(): GLenum = GL_DST_COLOR
template ONE*(): GLenum = GL_ONE
template BLEND*(): GLenum = GL_BLEND
template TRIANGLES*(): GLenum = GL_TRIANGLES
template TRIANGLE_FAN*(): GLenum = GL_TRIANGLE_FAN
template TRIANGLE_STRIP*(): GLenum = GL_TRIANGLE_STRIP
template LINES*(): GLenum = GL_LINES
template LINE_LOOP*(): GLenum = GL_LINE_LOOP
template COLOR_BUFFER_BIT*(): GLbitfield = GL_COLOR_BUFFER_BIT
template STENCIL_BUFFER_BIT*(): GLbitfield = GL_STENCIL_BUFFER_BIT
template DEPTH_BUFFER_BIT*(): GLbitfield = GL_DEPTH_BUFFER_BIT
template TEXTURE_MIN_FILTER*(): GLenum = GL_TEXTURE_MIN_FILTER
template TEXTURE_MAG_FILTER*(): GLenum = GL_TEXTURE_MAG_FILTER
template TEXTURE_WRAP_S*(): GLenum = GL_TEXTURE_WRAP_S
template TEXTURE_WRAP_T*(): GLenum = GL_TEXTURE_WRAP_T
template LINEAR*(): GLint = GL_LINEAR
template NEAREST*(): GLint = GL_NEAREST
template CLAMP_TO_EDGE*(): GLint = GL_CLAMP_TO_EDGE
template LINEAR_MIPMAP_NEAREST*(): GLint = GL_LINEAR_MIPMAP_NEAREST
template PACK_ALIGNMENT*(): GLenum = GL_PACK_ALIGNMENT
template UNPACK_ALIGNMENT*(): GLenum = GL_UNPACK_ALIGNMENT
template FRAMEBUFFER*(): GLenum = GL_FRAMEBUFFER
template RENDERBUFFER*(): GLenum = GL_RENDERBUFFER
template ARRAY_BUFFER*(): GLenum = GL_ARRAY_BUFFER
template ELEMENT_ARRAY_BUFFER*(): GLenum = GL_ELEMENT_ARRAY_BUFFER
template RED*(): GLenum = GL_RED
template R16F*(): GLenum = GL_R16F
template R32F*(): GLenum = GL_R32F
template RGBA*(): GLenum = GL_RGBA
template RGBA16F*(): GLenum = GL_RGBA16F
template ALPHA*(): GLenum = GL_ALPHA
template LUMINANCE*(): GLenum = GL_LUMINANCE
template UNSIGNED_BYTE*(): GLenum = GL_UNSIGNED_BYTE
template COLOR_ATTACHMENT0*(): GLenum = GL_COLOR_ATTACHMENT0
template DEPTH_ATTACHMENT*(): GLenum = GL_DEPTH_ATTACHMENT
template STENCIL_ATTACHMENT*(): GLenum = GL_STENCIL_ATTACHMENT
template DEPTH_STENCIL_ATTACHMENT*(): GLenum = GL_DEPTH_STENCIL_ATTACHMENT
template DEPTH_COMPONENT16*(): GLenum = GL_DEPTH_COMPONENT16
template STENCIL_INDEX8*(): GLenum = GL_STENCIL_INDEX8
template DEPTH_STENCIL*(): GLenum = GL_DEPTH_STENCIL
template DEPTH24_STENCIL8*(): GLenum = GL_DEPTH24_STENCIL8
#template FRAMEBUFFER_BINDING(): GLenum = GL_FRAMEBUFFER_BINDING
#template RENDERBUFFER_BINDING(): GLenum = GL_RENDERBUFFER_BINDING
template STENCIL_TEST*(): GLenum = GL_STENCIL_TEST
template DEPTH_TEST*(): GLenum = GL_DEPTH_TEST
template SCISSOR_TEST*(): GLenum = GL_SCISSOR_TEST
template MAX_TEXTURE_SIZE*(): GLenum = GL_MAX_TEXTURE_SIZE
template BLEND_SRC_RGB*(): GLenum = GL_BLEND_SRC_RGB
template BLEND_SRC_ALPHA*(): GLenum = GL_BLEND_SRC_ALPHA
template BLEND_DST_RGB*(): GLenum = GL_BLEND_DST_RGB
template BLEND_DST_ALPHA*(): GLenum = GL_BLEND_DST_ALPHA
template NEVER*(): GLenum = GL_NEVER
template LESS*(): GLenum = GL_LESS
template LEQUAL*(): GLenum = GL_LEQUAL
template GREATER*(): GLenum = GL_GREATER
template GEQUAL*(): GLenum = GL_GEQUAL
template EQUAL*(): GLenum = GL_EQUAL
template NOTEQUAL*(): GLenum = GL_NOTEQUAL
template ALWAYS*(): GLenum = GL_ALWAYS

template KEEP*(): GLenum = GL_KEEP
template ZERO*(): GLenum = GL_ZERO
template REPLACE*(): GLenum = GL_REPLACE
template INCR*(): GLenum = GL_INCR
template INCR_WRAP*(): GLenum = GL_INCR_WRAP
template DECR*(): GLenum = GL_DECR
template DECR_WRAP*(): GLenum = GL_DECR_WRAP
template INVERT*(): GLenum = GL_INVERT

template STREAM_DRAW*(): GLenum = GL_STREAM_DRAW
template STREAM_READ*(): GLenum = GL_STREAM_READ
template STREAM_COPY*(): GLenum = GL_STREAM_COPY
template STATIC_DRAW*(): GLenum = GL_STATIC_DRAW
template STATIC_READ*(): GLenum = GL_STATIC_READ
template STATIC_COPY*(): GLenum = GL_STATIC_COPY
template DYNAMIC_DRAW*(): GLenum = GL_DYNAMIC_DRAW
template DYNAMIC_READ*(): GLenum = GL_DYNAMIC_READ
template DYNAMIC_COPY*(): GLenum = GL_DYNAMIC_COPY

template FLOAT*(): GLenum = cGL_FLOAT
template UNSIGNED_SHORT*(): GLenum = GL_UNSIGNED_SHORT

template TEXTURE0*(): GLenum = GL_TEXTURE0

template CULL_FACE*() : GLenum = GL_CULL_FACE
template FRONT*() : GLenum = GL_FRONT
template BACK*() : GLenum = GL_BACK
template FRONT_AND_BACK*() : GLenum = GL_FRONT_AND_BACK

template BUFFER_SIZE*() : GLenum = GL_BUFFER_SIZE

template compileShader*(shader: ShaderRef) = glCompileShader(shader)
template deleteShader*(shader: ShaderRef) = glDeleteShader(shader)
template deleteProgram*(prog: ProgramRef) = glDeleteProgram(prog)
template attachShader*(prog: ProgramRef, shader: ShaderRef) = glAttachShader(prog, shader)
template detachShader*(prog: ProgramRef, shader: ShaderRef) = glDetachShader(prog, shader)


template linkProgram*(prog: ProgramRef) = glLinkProgram(prog)

template drawArrays*(mode: GLenum, first: GLint, count: GLsizei) = glDrawArrays(mode, first, count)
template drawElements*(mode: GLenum, count: GLsizei, typ: GLenum, offset: int = 0) =
    glDrawElements(mode, count, typ, cast[pointer](offset))
template createShader*(shaderType: GLenum): ShaderRef = glCreateShader(shaderType)
template createProgram*(): ProgramRef = glCreateProgram()
proc createTexture*(): GLuint = glGenTextures(1, addr result)
proc createFramebuffer*(): GLuint {.inline.} = glGenFramebuffers(1, addr result)
proc createRenderbuffer*(): GLuint {.inline.} = glGenRenderbuffers(1, addr result)
proc createGLBuffer*(): GLuint {.inline.} = glGenBuffers(1, addr result)
template allocateGLBufferData*(target: GLenum, size: int32, usage: GLenum) =
    glBufferData(target, size, nil, usage)

proc deleteFramebuffer*(name: FramebufferRef) {.inline.} =
    glDeleteFramebuffers(1, unsafeAddr name)

proc deleteRenderbuffer*(name: RenderbufferRef) {.inline.} =
    glDeleteRenderbuffers(1, unsafeAddr name)

proc deleteGLBuffer*(name: BufferRef) {.inline.} =
    glDeleteBuffers(1, unsafeAddr name)

proc deleteTexture*(name: TextureRef) {.inline.} =
    glDeleteTextures(1, unsafeAddr name)

template bindAttribLocation*(program: ProgramRef, index: GLuint, name: cstring) = glBindAttribLocation(program, index, name)
template enableVertexAttribArray*(attrib: GLuint) = glEnableVertexAttribArray(attrib)
template disableVertexAttribArray*(attrib: GLuint) = glDisableVertexAttribArray(attrib)
template vertexAttribPointer*(index: GLuint, size: GLint, typ: GLenum,
        normalized: GLboolean, stride: GLsizei, offset: int) =
    glVertexAttribPointer(index, size, typ, normalized, stride, cast[pointer](offset))

template getUniformLocation*(prog: ProgramRef, name: cstring): UniformLocation = glGetUniformLocation(prog, name)
template useProgram*(prog: ProgramRef) = glUseProgram(prog)
template enableCapability*(flag: GLenum) = glEnable(flag)
template disableCapability*(flag: GLenum) = glDisable(flag)
template isCapabilityEnabled*(flag: GLenum): bool = glIsEnabled(flag)
template viewport*(x, y: GLint, width, height: GLsizei) = glViewport(x, y, width, height)
template clearGLBuffers*(mask: GLbitfield) = glClear(mask)
template activeTexture*(t: GLenum) = glActiveTexture(t)
template bindTexture*(target: GLenum, name: TextureRef) = glBindTexture(target, name)
template bindFramebuffer*(target: GLenum, name: FramebufferRef) = glBindFramebuffer(target, name)
template bindRenderbuffer*(target: GLenum, name: RenderbufferRef) = glBindRenderbuffer(target, name)
template bindGLBuffer*(target: GLenum, name: BufferRef) = glBindBuffer(target, name)

template uniform1f*(location: UniformLocation, data: GLfloat) = glUniform1f(location, data)
template uniform1i*(location: UniformLocation, data: GLint) = glUniform1i(location, data)
template uniform2fv*(location: UniformLocation, data: openarray[GLfloat]) = glUniform2fv(location, GLSizei(data.len / 2), unsafeAddr data[0])
template uniform2fv*(location: UniformLocation, length: GLsizei, data: ptr GLfloat) = glUniform2fv(location, length, data)
template uniform3fv*(location: UniformLocation, data: openarray[GLfloat]) = glUniform3fv(location, GLSizei(data.len / 3), unsafeAddr data[0])
template uniform3iv*(location: UniformLocation, data: openarray[GLint]) = glUniform3iv(location, GLSizei(data.len / 3), unsafeAddr data[0])
template uniform4fv*(location: UniformLocation, data: openarray[GLfloat]) = glUniform4fv(location, GLsizei(data.len / 4), unsafeAddr data[0])
template uniform1fv*(location: UniformLocation, data: openarray[GLfloat]) = glUniform1fv(location, GLsizei(data.len), unsafeAddr data[0])
template uniform1fv*(location: UniformLocation, length: GLsizei, data: ptr GLfloat) = glUniform1fv(location, length, data)
proc uniformMatrix4fv*(location: UniformLocation, transpose: GLboolean, data: array[16, GLfloat]) {.inline.} =
    glUniformMatrix4fv(location, 1, transpose, unsafeAddr data[0])
proc uniformMatrix3fv*(location: UniformLocation, transpose: GLboolean, data: array[9, GLfloat]) {.inline.} =
    glUniformMatrix3fv(location, 1, transpose, unsafeAddr data[0])

template clearColor*(r, g, b, a: GLfloat) = glClearColor(r, g, b, a)
template clearStencil*(s: GLint) = glClearStencil(s)

template blendFunc*(sfactor, dfactor: GLenum) = glBlendFunc(sfactor, dfactor)
template blendColor*(r, g, b, a: Glfloat) = glBlendColor(r, g, b, a)
template blendFuncSeparate*(sfactor, dfactor, sfactorA, dfactorA: GLenum) = glBlendFuncSeparate(sfactor, dfactor, sfactorA, dfactorA)
template texParameteri*(target, pname: GLenum, param: GLint) = glTexParameteri(target, pname, param)

template texImage2D*(target: GLenum, level, internalformat: GLint, width, height: GLsizei, border: GLint, format, t: GLenum, pixels: pointer) =
    glTexImage2D(target, level, internalformat, width, height, border, format, t, pixels)
template texImage2D*(target: GLenum, level, internalformat: GLint, width, height: GLsizei, border: GLint, format, t: GLenum, pixels: openarray) =
    glTexImage2D(target, level, internalformat, width, height, border, format, t, unsafeAddr pixels[0])
template texSubImage2D*(target: GLenum, level: GLint, xoffset, yoffset: GLint, width, height: GLsizei, format, t: GLenum, pixels: pointer) =
    glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, t, pixels)
template texSubImage2D*(target: GLenum, level: GLint, xoffset, yoffset: GLint, width, height: GLsizei, format, t: GLenum, pixels: openarray) =
    glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, t, unsafeAddr pixels[0])

template generateMipmap*(target: GLenum) = glGenerateMipmap(target)
template pixelStorei*(pname: GLenum, param: GLint) = glPixelStorei(pname, param)

template framebufferTexture2D*(target, attachment, textarget: GLenum, texture: TextureRef, level: GLint) =
    glFramebufferTexture2D(target, attachment, textarget, texture, level)
template renderbufferStorage*(target, internalformat: GLenum, width, height: GLsizei) = glRenderbufferStorage(target, internalformat, width, height)
template framebufferRenderbuffer*(target, attachment, renderbuffertarget: GLenum, renderbuffer: RenderbufferRef) =
    glFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer)

template stencilFunc*(fun: GLenum, refe: GLint, mask: GLuint) = glStencilFunc(fun, refe, mask)
template stencilOp*(fail, zfail, zpass: GLenum) = glStencilOp(fail, zfail, zpass)
template colorMask*(r, g, b, a: bool) = glColorMask(r, g, b, a)
template depthMask*(d: bool) = glDepthMask(d)
template stencilMask*(m: GLuint) = glStencilMask(m)
template cullFace*(mode: GLenum) = glCullFace(mode)
template scissor*(x, y: GLint, width, height: GLsizei) = glScissor(x, y, width, height)

template getGLError*(): GLenum = glGetError()

template isEmpty*(obj: TextureRef or FramebufferRef or RenderbufferRef): bool = obj == 0

proc shaderInfoLog*(s: ShaderRef): string =
    var infoLen: GLint
    var dummy: string
    dummy.setLen(1)
    glGetShaderInfoLog(s, sizeof(dummy).GLint, addr infoLen, cstring(dummy))
    if infoLen > 0:
        result.setLen(infoLen + 1)
        glGetShaderInfoLog(s, infoLen, nil, cstring(result))

proc programInfoLog*(s: ProgramRef): string =
    var infoLen: GLint
    var dummy: string
    dummy.setLen(1)
    glGetProgramInfoLog(s, sizeof(dummy).GLint, addr infoLen, cstring(dummy))
    if infoLen > 0:
        result.setLen(infoLen + 1)
        glGetProgramInfoLog(s, infoLen, nil, cstring(result))

proc shaderSource*(s: ShaderRef, src: cstring) =
    var srcArray = [src]
    glShaderSource(s, 1, cast[cstringArray](addr srcArray), nil)

proc isShaderCompiled*(shader: ShaderRef): bool {.inline.} =
    var compiled: GLint
    glGetShaderiv(shader, GL_COMPILE_STATUS, addr compiled)
    result = GLboolean(compiled) == GLboolean(GL_TRUE)

proc isProgramLinked*(prog: ProgramRef): bool {.inline.} =
    var linked: GLint
    glGetProgramiv(prog, GL_LINK_STATUS, addr linked)
    result = GLboolean(linked) == GLboolean(GL_TRUE)

proc copyDataToGLBuffer*[T](target: GLenum, data: openarray[T], size: int, usage: GLenum) {.inline.} =
    assert(size <= data.len)
    glBufferData(target, GLsizei(size * sizeof(T)), cast[pointer](data), usage);

proc copyDataToGLBuffer*[T](target: GLenum, data: openarray[T], usage: GLenum) {.inline.} =
    glBufferData(target, GLsizei(data.len * sizeof(T)), cast[pointer](data), usage);

proc copyDataToGLSubBuffer*[T](target: GLenum, offset: int32, data: openarray[T]) {.inline.} =
    glBufferSubData(target, offset, GLsizei(data.len * sizeof(T)), cast[pointer](data));

proc getGLBufferParameteriv*(target, value: GLenum): GLint {.inline.} =
    glGetBufferParameteriv(target, value, addr result)

proc vertexAttribPointer*(index: GLuint, size: GLint, normalized: GLboolean,
                        stride: GLsizei, data: openarray[GLfloat]) =
    glVertexAttribPointer(index, size, cGL_FLOAT, normalized, stride, cast[pointer](data));

proc getParami*(pname: GLenum): GLint =
    glGetIntegerv(pname, addr result)

proc getParamf*(pname: GLenum): GLfloat =
    glGetFloatv(pname, addr result)

proc getParamb*(pname: GLenum): GLboolean =
    glGetBooleanv(pname, addr result)

proc getViewport*(): array[4, GLint] =
    glGetIntegerv(GL_VIEWPORT, addr result[0])

template viewport*(vp: array[4, GLint]) = viewport(vp[0], vp[1], vp[2], vp[3])

template boundFramebuffer*(): FramebufferRef =
    cast[FramebufferRef](getParami(GL_FRAMEBUFFER_BINDING))
template boundRenderbuffer*(): RenderbufferRef =
    cast[RenderbufferRef](getParami(GL_RENDERBUFFER_BINDING))

proc getClearColor*(colorComponents: var array[4, GLfloat]) =
    glGetFloatv(GL_COLOR_CLEAR_VALUE, cast[ptr GLfloat](addr colorComponents))

proc clearWithColor*(r, g, b, a: GLfloat) =
    var oldColor: array[4, GLfloat]
    getClearColor(oldColor)
    clearGLBuffers(COLOR_BUFFER_BIT or STENCIL_BUFFER_BIT or DEPTH_BUFFER_BIT)
    clearColor(oldColor[0], oldColor[1], oldColor[2], oldColor[3])

proc clearDepthStencil*() =
    clearGLBuffers(STENCIL_BUFFER_BIT or DEPTH_BUFFER_BIT)
