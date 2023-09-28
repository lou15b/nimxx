import ./types
import opengl
import ./system_logger
import ./matrixes
import ./portable_gl
import nimsl/nimsl

export matrixes

type ShaderAttribute* = enum
    saPosition
    saColor

type Transform3D* = Matrix4


proc loadShader(gl: GL, shaderSrc: string, kind: GLenum): ShaderRef =
    result = gl.createShader(kind)
    if result == invalidShader:
        return

    # Load the shader source
    gl.shaderSource(result, shaderSrc)
    # Compile the shader
    gl.compileShader(result)
    # Check the compile status
    let compiled = gl.isShaderCompiled(result)
    let info = gl.shaderInfoLog(result)
    if not compiled:
        logi "Shader compile error: ", info
        logi "The shader: ", shaderSrc
        gl.deleteShader(result)
    elif info.len > 0:
        logi "Shader compile log: ", info

proc newShaderProgram*(gl: GL, vs, fs: string,
        attributes: openarray[tuple[index: GLuint, name: string]]): ProgramRef =
    result = gl.createProgram()
    if result == invalidProgram:
        logi "Could not create program: ", gl.getError().int
        return
    let vShader = gl.loadShader(vs, gl.VERTEX_SHADER)
    if vShader == invalidShader:
        gl.deleteProgram(result)
        return invalidProgram
    gl.attachShader(result, vShader)
    let fShader = gl.loadShader(fs, gl.FRAGMENT_SHADER)
    if fShader == invalidShader:
        gl.deleteProgram(result)
        return invalidProgram
    gl.attachShader(result, fShader)

    for a in attributes:
        gl.bindAttribLocation(result, a.index, cstring(a.name))

    gl.linkProgram(result)
    gl.deleteShader(vShader)
    gl.deleteShader(fShader)

    let linked = gl.isProgramLinked(result)
    let info = gl.programInfoLog(result)
    if not linked:
        logi "Could not link: ", info
        result = invalidProgram
    elif info.len > 0:
        logi "Program linked: ", info

type Transform3DRef = ptr Transform3D

type GraphicsContext* = ref object of RootObj
    gl*: GL
    pTransform: Transform3DRef
    fillColor*: Color
    strokeColor*: Color
    strokeWidth*: Coord
    debugClipColor: Color
    alpha*: Coord
    quadIndexBuffer*: BufferRef
    gridIndexBuffer4x4*: BufferRef      #### Made public
    singleQuadBuffer*: BufferRef
    sharedBuffer*: BufferRef
    vertexes*: array[4 * 4 * 128, Coord]

var gCurrentContext {.threadvar.}: GraphicsContext

proc transformToRef(t: Transform3D): Transform3DRef =
    {.emit: "`result` = `t`;".}

template withTransform*(c: GraphicsContext, t: Transform3DRef, body: typed) =
    let old = c.pTransform
    c.pTransform = t
    body
    c.pTransform = old

template withTransform*(c: GraphicsContext, t: Transform3D, body: typed) = c.withTransform(transformToRef(t), body)

template transform*(c: GraphicsContext): var Transform3D = c.pTransform[]

proc createQuadIndexBuffer*(c: GraphicsContext, numberOfQuads: int): BufferRef =
    result = c.gl.createBuffer()
    c.gl.bindBuffer(c.gl.ELEMENT_ARRAY_BUFFER, result)

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

    c.gl.bufferData(c.gl.ELEMENT_ARRAY_BUFFER, indexData, c.gl.STATIC_DRAW)

proc createGridIndexBuffer(c: GraphicsContext, width, height: static[int]): BufferRef =
    result = c.gl.createBuffer()
    c.gl.bindBuffer(c.gl.ELEMENT_ARRAY_BUFFER, result)

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

    c.gl.bufferData(c.gl.ELEMENT_ARRAY_BUFFER, indexData, c.gl.STATIC_DRAW)

proc createQuadBuffer(c: GraphicsContext): BufferRef =
    result = c.gl.createBuffer()
    c.gl.bindBuffer(c.gl.ARRAY_BUFFER, result)
    let vertexes = [0.GLfloat, 0, 0, 1, 1, 1, 1, 0]
    c.gl.bufferData(c.gl.ARRAY_BUFFER, vertexes, c.gl.STATIC_DRAW)

proc newGraphicsContext*(canvas: ref RootObj = nil): GraphicsContext =
    result.new()
    result.gl = newGL(canvas)
    when not defined(ios) and not defined(android):
        loadExtensions()

    result.gl.clearColor(0, 0, 0, 0.0)
    result.alpha = 1.0

    result.gl.enable(result.gl.BLEND)
    # We're using 1s + (1-s)d for alpha for proper alpha blending e.g. when rendering to texture.
    result.gl.blendFuncSeparate(result.gl.SRC_ALPHA, result.gl.ONE_MINUS_SRC_ALPHA, result.gl.ONE, result.gl.ONE_MINUS_SRC_ALPHA)

    #result.gl.enable(result.gl.CULL_FACE)
    #result.gl.cullFace(result.gl.BACK)

    result.quadIndexBuffer = result.createQuadIndexBuffer(128)
    result.gridIndexBuffer4x4 = result.createGridIndexBuffer(4, 4)
    result.singleQuadBuffer = result.createQuadBuffer()
    result.sharedBuffer = result.gl.createBuffer()

    if gCurrentContext.isNil:
        gCurrentContext = result

proc setCurrentContext*(c: GraphicsContext): GraphicsContext {.discardable.} =
    result = gCurrentContext
    gCurrentContext = c

template currentContext*(): GraphicsContext = gCurrentContext

proc setTransformUniform*(c: GraphicsContext, program: ProgramRef) =
    c.gl.uniformMatrix4fv(c.gl.getUniformLocation(program, "modelViewProjectionMatrix"), false, c.transform)

proc setColorUniform*(c: GraphicsContext, loc: UniformLocation, color: Color) =
    var arr = [color.r, color.g, color.b, color.a * c.alpha]
    glUniform4fv(loc, 1, addr arr[0]);

proc setColorUniform*(c: GraphicsContext, program: ProgramRef, name: cstring, color: Color) =
    c.setColorUniform(c.gl.getUniformLocation(program, name), color)

proc setRectUniform*(c: GraphicsContext, loc: UniformLocation, r: Rect) =
    glUniform4fv(loc, 1, cast[ptr GLfloat](unsafeAddr r));

template setRectUniform*(c: GraphicsContext, prog: ProgramRef, name: cstring, r: Rect) =
    c.setRectUniform(c.gl.getUniformLocation(prog, name), r)

proc setPointUniform*(c: GraphicsContext, loc: UniformLocation, r: Point) =
    glUniform2fv(loc, 1, cast[ptr GLfloat](unsafeAddr r));

template setPointUniform*(c: GraphicsContext, prog: ProgramRef, name: cstring, r: Point) =
    c.setPointUniform(c.gl.getUniformLocation(prog, name), r)

