import ./ [ image, types, context, portable_gl ]
import pkg/opengl

type
    RTIContext* = tuple
        clearColor: array[4, GLfloat]
        viewportSize: array[4, GLint]
        framebuffer: FramebufferRef
        bStencil: bool
        skipClear: bool

    GlFrameState* {.deprecated.} = RTIContext

    ImageRenderTarget* = ref ImageRenderTargetObj
    ImageRenderTargetObj = object
        framebuffer*: FramebufferRef
        depthbuffer*: RenderbufferRef
        stencilbuffer*: RenderbufferRef
        vpX*, vpY*: GLint # Viewport geometry
        vpW*, vpH*: GLsizei
        texWidth*, texHeight*: int16
        needsDepthStencil*: bool

proc `=destroy`(r: ImageRenderTargetObj) {.raises: [GLerror].} =
    if r.framebuffer != invalidFrameBuffer:
        deleteFramebuffer(r.framebuffer)
    if r.depthbuffer != invalidRenderbuffer:
        deleteRenderbuffer(r.depthbuffer)
    if r.stencilbuffer != invalidRenderbuffer:
        deleteRenderbuffer(r.stencilbuffer)

proc newImageRenderTarget*(needsDepthStencil: bool = true): ImageRenderTarget {.inline.} =
    result.new()
    result.needsDepthStencil = needsDepthStencil

proc init(rt: ImageRenderTarget, texWidth, texHeight: int16) =
    rt.texWidth = texWidth
    rt.texHeight = texHeight
    rt.framebuffer = createFramebuffer()

    if rt.needsDepthStencil:
        let oldFramebuffer = boundFramebuffer()
        let oldRB = boundRenderBuffer()
        bindFramebuffer(FRAMEBUFFER, rt.framebuffer)
        when defined(ios):
            # SDL on iOS relies on its renderbuffer bound after drawing the frame before swapping buffers.
            # See swapBuffers in SDL_uikitopenglview.m
            let oldRenderBuffer = boundRenderBuffer()

        let depthBuffer = createRenderbuffer()
        bindRenderbuffer(RENDERBUFFER, depthBuffer)
        let depthStencilFormat = DEPTH24_STENCIL8

        # The following tries to use DEPTH_STENCIL_ATTACHMENT, but it may fail on some devices,
        # so for those we're creating a separate stencil buffer.
        var needsStencil = false
        when NoAutoGLerrorCheck:
            discard getGLError()
            renderbufferStorage(RENDERBUFFER, depthStencilFormat, texWidth, texHeight)
            if getGLError() == 0.GLenum:
                framebufferRenderbuffer(FRAMEBUFFER, DEPTH_STENCIL_ATTACHMENT, RENDERBUFFER, depthBuffer)
            else:
                renderbufferStorage(RENDERBUFFER, DEPTH_COMPONENT16, texWidth, texHeight)
                framebufferRenderbuffer(FRAMEBUFFER, DEPTH_ATTACHMENT, RENDERBUFFER, depthBuffer)
                needsStencil = true
        else:
            try:
                renderbufferStorage(RENDERBUFFER, depthStencilFormat, texWidth, texHeight)
                framebufferRenderbuffer(FRAMEBUFFER, DEPTH_STENCIL_ATTACHMENT, RENDERBUFFER, depthBuffer)
            except:
                renderbufferStorage(RENDERBUFFER, DEPTH_COMPONENT16, texWidth, texHeight)
                framebufferRenderbuffer(FRAMEBUFFER, DEPTH_ATTACHMENT, RENDERBUFFER, depthBuffer)
                needsStencil = true

        rt.depthbuffer = depthBuffer

        if needsStencil:
            let stencilBuffer = createRenderbuffer()
            bindRenderbuffer(RENDERBUFFER, stencilBuffer)
            renderbufferStorage(RENDERBUFFER, STENCIL_INDEX8, texWidth, texHeight)
            framebufferRenderbuffer(FRAMEBUFFER, STENCIL_ATTACHMENT, RENDERBUFFER, stencilBuffer)
            rt.stencilbuffer = stencilBuffer

        bindFramebuffer(FRAMEBUFFER, oldFramebuffer)
        bindRenderbuffer(RENDERBUFFER, oldRB)
        when defined(ios):
            bindRenderbuffer(RENDERBUFFER, oldRenderBuffer)

proc resize(rt: ImageRenderTarget, texWidth, texHeight: int16) =
    rt.texWidth = max(rt.texWidth, texWidth)
    rt.texHeight = max(rt.texHeight, texHeight)

    when defined(ios):
        # SDL on iOS relies on its renderbuffer bound after drawing the frame before swapping buffers.
        # See swapBuffers in SDL_uikitopenglview.m
        let oldRenderBuffer = boundRenderBuffer()
    if rt.depthbuffer != invalidRenderbuffer:
        let depthStencilFormat = if rt.stencilbuffer == invalidRenderbuffer:
                DEPTH24_STENCIL8
            else:
                DEPTH_COMPONENT16

        bindRenderbuffer(RENDERBUFFER, rt.depthbuffer)
        renderbufferStorage(RENDERBUFFER, depthStencilFormat, rt.texWidth, rt.texHeight)

    if rt.stencilBuffer != invalidRenderbuffer:
        bindRenderbuffer(RENDERBUFFER, rt.stencilBuffer)
        renderbufferStorage(RENDERBUFFER, STENCIL_INDEX8, rt.texWidth, rt.texHeight)
    when defined(ios):
        bindRenderbuffer(RENDERBUFFER, oldRenderBuffer)

proc setImage*(rt: ImageRenderTarget, i: SelfContainedImage) =
    assert(i.texWidth != 0 and i.texHeight != 0)

    var texCoords: array[4, GLfloat]
    var texture = i.getTextureQuad(texCoords)
    if texture.isEmpty:
        texture = createTexture()
        i.texture = texture
        bindTexture(TEXTURE_2D, texture)
        texImage2D(TEXTURE_2D, 0, RGBA.GLint, i.texWidth, i.texHeight, 0, RGBA, UNSIGNED_BYTE, nil)

    if rt.framebuffer.isEmpty:
        rt.init(i.texWidth, i.texHeight)
    elif rt.texWidth < i.texWidth or rt.texHeight < i.texHeight:
        rt.resize(i.texWidth, i.texHeight)

    let br = i.backingRect()

    rt.vpX = br.x.GLint
    rt.vpY = br.y.GLint
    rt.vpW = br.width.GLsizei
    rt.vpH = br.height.GLsizei

    let oldFramebuffer = boundFramebuffer()

    bindFramebuffer(FRAMEBUFFER, rt.framebuffer)
    bindTexture(TEXTURE_2D, texture)
    texParameteri(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR)
    framebufferTexture2D(FRAMEBUFFER, COLOR_ATTACHMENT0, TEXTURE_2D, texture, 0)

    bindFramebuffer(FRAMEBUFFER, oldFramebuffer)

proc beginDraw*(t: ImageRenderTarget, state: var RTIContext) =
    assert(t.vpW != 0 and t.vpH != 0)

    state.framebuffer = boundFramebuffer()
    state.viewportSize = getViewport()
    state.bStencil = getParamb(STENCIL_TEST)
    if not state.skipClear:
        getClearColor(state.clearColor)

    bindFramebuffer(FRAMEBUFFER, t.framebuffer)
    viewport(t.vpX, t.vpY, t.vpW, t.vpH)
    if not state.skipClear:
        stencilMask(0xFF) # Android requires setting stencil mask to clear
        clearColor(0, 0, 0, 0)
        clearGLBuffers(COLOR_BUFFER_BIT or DEPTH_BUFFER_BIT or STENCIL_BUFFER_BIT)
        stencilMask(0x00) # Android requires setting stencil mask to clear
        disableCapability(STENCIL_TEST)

proc beginDrawNoClear*(t: ImageRenderTarget, state: var RTIContext) =
    state.skipClear = true
    t.beginDraw(state)

proc endDraw*(t: ImageRenderTarget, state: var RTIContext) =
    if state.bStencil:
        enableCapability(STENCIL_TEST)
    if not state.skipClear:
        clearColor(state.clearColor[0], state.clearColor[1], state.clearColor[2], state.clearColor[3])
    viewport(state.viewportSize)
    bindFramebuffer(FRAMEBUFFER, state.framebuffer)

template draw*(rt: ImageRenderTarget, sci: SelfContainedImage, c: GraphicsContext, drawBody: untyped) =
    var gfs: RTIContext
    rt.setImage(sci)
    rt.beginDraw(gfs)

    c.withTransform ortho(0, sci.size.width, sci.size.height, 0, -1, 1):
        drawBody

    rt.endDraw(gfs)
    # OpenGL framebuffer coordinate system is flipped comparing to how we load
    # and handle the rest of images. Compensate for that by flipping texture
    # coords here.
    if not sci.flipped:
        sci.flipVertically()

template draw*(sci: SelfContainedImage, c: GraphicsContext, drawBody: untyped) =
    let rt = newImageRenderTarget()
    rt.draw(sci, c, drawBody)
