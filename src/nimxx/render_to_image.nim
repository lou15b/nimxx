import ./ [ image, types, context, opengl_etc ]

type
  RTIContext* = object
    clearColor*: array[4, GLfloat]
    viewportSize*: array[4, GLint]
    framebuffer*: FramebufferGLRef
    bStencil*: bool
    skipClear*: bool

  ImageRenderTarget* = ref ImageRenderTargetObj
  ImageRenderTargetObj = object
    framebuffer*: FramebufferGLRef
    depthbuffer*: RenderbufferGLRef
    stencilbuffer*: RenderbufferGLRef
    vpX*, vpY*: GLint # Viewport geometry
    vpW*, vpH*: GLsizei
    texWidth*, texHeight*: int16
    needsDepthStencil*: bool

proc `=destroy`*(r: RTIContext) =
  if r.framebuffer != invalidGLFrameBuffer:
    try:
      deleteGLFramebuffer(r.framebuffer)
    except Exception as e:
      echo "Exception encountered destroying RTIContext framebuffer:", e.msg


proc `=destroy`*(r: ImageRenderTargetObj) {.raises: [GLerror].} =
  if r.framebuffer != invalidGLFrameBuffer:
    deleteGLFramebuffer(r.framebuffer)
  if r.depthbuffer != invalidGLRenderbuffer:
    deleteGLRenderbuffer(r.depthbuffer)
  if r.stencilbuffer != invalidGLRenderbuffer:
    deleteGLRenderbuffer(r.stencilbuffer)

proc newImageRenderTarget*(needsDepthStencil: bool = true): ImageRenderTarget {.inline.} =
  result.new()
  result.needsDepthStencil = needsDepthStencil

proc init(rt: ImageRenderTarget, texWidth, texHeight: int16) =
  rt.texWidth = texWidth
  rt.texHeight = texHeight
  rt.framebuffer = createGLFramebuffer()

  if rt.needsDepthStencil:
    let oldFramebuffer = getBoundGLFramebuffer()
    let oldRB = getBoundGLRenderbuffer()
    glBindFramebuffer(GL_FRAMEBUFFER, rt.framebuffer)
    when defined(ios):
      # SDL on iOS relies on its renderbuffer being bound after drawing
      # the frame but before swapping buffers.
      # See swapBuffers in SDL_uikitopenglview.m
      let oldRenderBuffer = getBoundGLRenderbuffer()

    let depthBuffer = createGLRenderbuffer()
    glBindRenderbuffer(GL_RENDERBUFFER, depthBuffer)
    let depthStencilFormat = GL_DEPTH24_STENCIL8

    # The following tries to use GL_DEPTH_STENCIL_ATTACHMENT, but it may fail
    # on some devices, so for those we're creating a separate stencil buffer.
    var needsStencil = false
    when NoAutoGLerrorCheck:
      discard glGetError()
      glRenderbufferStorage(GL_RENDERBUFFER, depthStencilFormat, texWidth, texHeight)
      if glGetError() == 0.GLenum:
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
          GL_RENDERBUFFER, depthBuffer)
      else:
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, texWidth, texHeight)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER,
          depthBuffer)
        needsStencil = true
    else:
      try:
        glRenderbufferStorage(GL_RENDERBUFFER, depthStencilFormat, texWidth, texHeight)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
          GL_RENDERBUFFER, depthBuffer)
      except:
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, texWidth, texHeight)
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER,
          depthBuffer)
        needsStencil = true

    rt.depthbuffer = depthBuffer

    if needsStencil:
      let stencilBuffer = createGLRenderbuffer()
      glBindRenderbuffer(GL_RENDERBUFFER, stencilBuffer)
      glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, texWidth, texHeight)
      glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER,
        stencilBuffer)
      rt.stencilbuffer = stencilBuffer

    glBindFramebuffer(GL_FRAMEBUFFER, oldFramebuffer)
    glBindRenderbuffer(GL_RENDERBUFFER, oldRB)
    when defined(ios):
      glBindRenderbuffer(GL_RENDERBUFFER, oldRenderBuffer)

proc resize(rt: ImageRenderTarget, texWidth, texHeight: int16) =
  rt.texWidth = max(rt.texWidth, texWidth)
  rt.texHeight = max(rt.texHeight, texHeight)

  when defined(ios):
    # SDL on iOS relies on its renderbuffer being bound after drawing the frame
    # but before swapping buffers.
    # See swapBuffers in SDL_uikitopenglview.m
    let oldRenderBuffer = getBoundGLRenderbuffer()
  if rt.depthbuffer != invalidGLRenderbuffer:
    let depthStencilFormat = if rt.stencilbuffer == invalidGLRenderbuffer:
        GL_DEPTH24_STENCIL8
      else:
        GL_DEPTH_COMPONENT16

    glBindRenderbuffer(GL_RENDERBUFFER, rt.depthbuffer)
    glRenderbufferStorage(GL_RENDERBUFFER, depthStencilFormat, rt.texWidth, rt.texHeight)

  if rt.stencilBuffer != invalidGLRenderbuffer:
    glBindRenderbuffer(GL_RENDERBUFFER, rt.stencilBuffer)
    glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, rt.texWidth, rt.texHeight)
  when defined(ios):
    glBindRenderbuffer(GL_RENDERBUFFER, oldRenderBuffer)

proc setImage*(rt: ImageRenderTarget, i: SelfContainedImage) =
  assert(i.texWidth != 0 and i.texHeight != 0)

  var texCoords: array[4, GLfloat]
  var texture = i.getTextureQuad(texCoords)
  if texture.isEmptyGLRef:
    texture = createGLTexture()
    i.texture = texture
    glBindTexture(GL_TEXTURE_2D, texture)
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA.GLint, i.texWidth, i.texHeight, 0,
      GL_RGBA, GL_UNSIGNED_BYTE, nil)

  if rt.framebuffer.isEmptyGLRef:
    rt.init(i.texWidth, i.texHeight)
  elif rt.texWidth < i.texWidth or rt.texHeight < i.texHeight:
    rt.resize(i.texWidth, i.texHeight)

  let br = i.backingRect()

  rt.vpX = br.x.GLint
  rt.vpY = br.y.GLint
  rt.vpW = br.width.GLsizei
  rt.vpH = br.height.GLsizei

  let oldFramebuffer = getBoundGLFramebuffer()

  glBindFramebuffer(GL_FRAMEBUFFER, rt.framebuffer)
  glBindTexture(GL_TEXTURE_2D, texture)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0)

  glBindFramebuffer(GL_FRAMEBUFFER, oldFramebuffer)

proc beginDraw*(t: ImageRenderTarget, state: var RTIContext) =
  assert(t.vpW != 0 and t.vpH != 0)

  state.framebuffer = getBoundGLFramebuffer()
  state.viewportSize = getGLViewport()
  state.bStencil = getGLParamb(GL_STENCIL_TEST)
  if not state.skipClear:
    getGLClearColor(state.clearColor)

  glBindFramebuffer(GL_FRAMEBUFFER, t.framebuffer)
  glViewport(t.vpX, t.vpY, t.vpW, t.vpH)
  if not state.skipClear:
    glStencilMask(0xFF) # Android requires setting stencil mask to clear
    glClearColor(0, 0, 0, 0)
    glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT or GL_STENCIL_BUFFER_BIT)
    glStencilMask(0x00) # Android requires setting stencil mask to clear
    glDisable(GL_STENCIL_TEST)

proc beginDrawNoClear*(t: ImageRenderTarget, state: var RTIContext) =
  state.skipClear = true
  t.beginDraw(state)

proc endDraw*(t: ImageRenderTarget, state: var RTIContext) =
  if state.bStencil:
    glEnable(GL_STENCIL_TEST)
  if not state.skipClear:
    glClearColor(state.clearColor[0], state.clearColor[1], state.clearColor[2],
      state.clearColor[3])
  setGLViewport(state.viewportSize)
  glBindFramebuffer(GL_FRAMEBUFFER, state.framebuffer)

template draw*(rt: ImageRenderTarget, sci: SelfContainedImage, c: GraphicsContext,
    drawBody: untyped) =
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
