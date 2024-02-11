import ./ [ view, render_to_image, image, types, context ]

proc renderToImage*(v: View, image: SelfContainedImage)=
  let c = v.window.renderingContext
  image.draw(c):
    v.recursiveDrawSubviews()

proc screenShot*(v: View):SelfContainedImage=
  var image = imageWithSize(v.bounds.size)
  v.renderToImage(image)
  result = image
