import ./types
import ./system_logger
import ./matrixes
import ./opengl_etc
import pkg/nimsl/nimsl

export matrixes

type ShaderAttribute* = enum
    saPosition
    saColor

type Transform3D* = Matrix4


proc loadShader(shaderSrc: string, kind: GLenum): ShaderGLRef =
    result = glCreateShader(kind)
    if result == invalidGLShader:
        return

    # Load the shader source
    shaderGLSource(result, shaderSrc)
    # Compile the shader
    glCompileShader(result)
    # Check the compile status
    let compiled = isGLShaderCompiled(result)
    let info = shaderGLInfoLog(result)
    if not compiled:
        logi "Shader compile error: ", info
        logi "The shader: ", shaderSrc
        glDeleteShader(result)
    elif info.len > 0:
        logi "Shader compile log: ", info

proc newShaderProgram*(vs, fs: string,
        attributes: openarray[tuple[index: GLuint, name: string]]): ProgramGLRef =
    result = glCreateProgram()
    if result == invalidGLProgram:
        logi "Could not create program: ", glGetError().int
        return
    let vShader = loadShader(vs, GL_VERTEX_SHADER)
    if vShader == invalidGLShader:
        glDeleteProgram(result)
        return invalidGLProgram
    glAttachShader(result, vShader)
    let fShader = loadShader(fs, GL_FRAGMENT_SHADER)
    if fShader == invalidGLShader:
        glDeleteProgram(result)
        return invalidGLProgram
    glAttachShader(result, fShader)

    for a in attributes:
        glBindAttribLocation(result, a.index, cstring(a.name))

    glLinkProgram(result)
    glDeleteShader(vShader)
    glDeleteShader(fShader)

    let linked = isGLProgramLinked(result)
    let info = programGLInfoLog(result)
    if not linked:
        logi "Could not link: ", info
        result = invalidGLProgram
    elif info.len > 0:
        logi "Program linked: ", info

type Transform3DRef = ptr Transform3D

type GraphicsContext* = ref object of RootObj
    pTransform: Transform3DRef
    fillColor*: Color
    strokeColor*: Color
    strokeWidth*: Coord
    clippingDepth*: GLint
    debugClipColor: Color
    alpha*: Coord
    quadIndexBuffer*: BufferGLRef
    gridIndexBuffer4x4*: BufferGLRef      #### Made public
    singleQuadBuffer*: BufferGLRef
    sharedBuffer*: BufferGLRef
    vertexes*: array[4 * 4 * 128, Coord]

proc transformToRef(t: Transform3D): Transform3DRef =
    {.emit: "`result` = `t`;".}

template withTransform*(c: GraphicsContext, t: Transform3DRef, body: typed) =
    let old = c.pTransform
    c.pTransform = t
    body
    c.pTransform = old

template withTransform*(c: GraphicsContext, t: Transform3D, body: typed) = c.withTransform(transformToRef(t), body)

template transform*(c: GraphicsContext): var Transform3D = c.pTransform[]

proc createQuadIndexBuffer*(numberOfQuads: int): BufferGLRef =
    result = createGLBuffer()
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, result)

    var indexData = newSeq[GLushort](numberOfQuads * 6)
    var i = 0
    while i < numberOfQuads:
        let id = i * 6
        let vd = GLushort(i * 4)
        indexData[id + 0] = vd + 0
        indexData[id + 1] = vd + 1
        indexData[id + 2] = vd + 2
        indexData[id + 3] = vd + 2
        indexData[id + 4] = vd + 3
        indexData[id + 5] = vd + 0
        inc i

    copyDataToGLBuffer(GL_ELEMENT_ARRAY_BUFFER, indexData, GL_STATIC_DRAW)

proc createGridIndexBuffer(width, height: static[int]): BufferGLRef =
    result = createGLBuffer()
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, result)

    const numberOfQuadColumns = width - 1
    const numberOIndices = numberOfQuadColumns * height * 2

    var indexData : array[numberOIndices, GLushort]
    var i = 0

    var y, toRow: int
    var dir = 1

    for iCol in 0 ..< numberOfQuadColumns:
        if dir == 1:
            y = 0
            toRow = height
        else:
            y = height - 1
            toRow = -1

        while y != toRow:
            indexData[i] = GLushort(y * width + iCol)
            inc i
            indexData[i] = GLushort(y * width + iCol + 1)
            inc i
            y += dir
        dir = -dir

    copyDataToGLBuffer(GL_ELEMENT_ARRAY_BUFFER, indexData, GL_STATIC_DRAW)

proc createQuadBuffer(): BufferGLRef =
    result = createGLBuffer()
    glBindBuffer(GL_ARRAY_BUFFER, result)
    let vertexes = [0.GLfloat, 0, 0, 1, 1, 1, 1, 0]
    copyDataToGLBuffer(GL_ARRAY_BUFFER, vertexes, GL_STATIC_DRAW)

proc newGraphicsContext*(canvas: ref RootObj = nil): GraphicsContext =
    result.new()
    when not defined(ios) and not defined(android):
        loadExtensions()

    glClearColor(0, 0, 0, 0.0)
    result.alpha = 1.0

    glEnable(GL_BLEND)
    # We're using 1s + (1-s)d for alpha for proper alpha blending e.g. when rendering to texture.
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)

    #glEnable(GL_CULL_FACE)
    #glCullFace(GL_BACK)

    result.quadIndexBuffer = createQuadIndexBuffer(128)
    result.gridIndexBuffer4x4 = createGridIndexBuffer(4, 4)
    result.singleQuadBuffer = createQuadBuffer()
    result.sharedBuffer = createGLBuffer()

proc setTransformUniform*(c: GraphicsContext, program: ProgramGLRef) =
    uniformGLMatrix4fv(glGetUniformLocation(program, "modelViewProjectionMatrix"), false, c.transform)

proc setColorUniform*(c: GraphicsContext, loc: UniformGLLocation, color: Color) =
    var arr = [color.r, color.g, color.b, color.a * c.alpha]
    glUniform4fv(loc, 1, addr arr[0]);

proc setColorUniform*(c: GraphicsContext, program: ProgramGLRef, name: cstring, color: Color) =
    c.setColorUniform(glGetUniformLocation(program, name), color)

proc setRectUniform*(loc: UniformGLLocation, r: Rect) =
    glUniform4fv(loc, 1, cast[ptr GLfloat](unsafeAddr r));

template setRectUniform*(c: GraphicsContext, prog: ProgramGLRef, name: cstring, r: Rect) =
    setRectUniform(c.gl.glGetUniformLocation(prog, name), r)

proc setPointUniform*(loc: UniformGLLocation, r: Point) =
    glUniform2fv(loc, 1, cast[ptr GLfloat](unsafeAddr r));

template setPointUniform*(prog: ProgramGLRef, name: cstring, r: Point) =
    setPointUniform(glGetUniformLocation(prog, name), r)

