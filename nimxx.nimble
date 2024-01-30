# Package

version     = "0.2"
author      = "Yuriy Glukhov"
description = "GUI framework"
license     = "MIT"

# Directory configuration
srcDir = "src"
installDirs = @["nimxx", "assets"]
# Need to work out how to install the nimxedit binary (source in src/editor)
### bin = @["nimxedit"]   

# Dependencies
requires "nim >= 2.0.0"
requires "sdl2"
requires "opengl"
requires "winim"
requires "nimsl >= 0.3"
requires "jnim"   # For android target
requires "x11"    # For linux target - pasteboard/clipboard
# requires "nake"   # Use nimble for building instead of nake
# requires "closure_compiler >= 0.3.1"   # Used for web API - not used here
requires "plists"
requires "variant >= 0.2 & < 0.3"
requires "kiwi"
requires "https://github.com/yglukhov/ttf >= 0.2.9 & < 0.3"   # Replace by Pixie
# requires "jsbind"   # Indirectly required by async_http_request above
requires "rect_packer"
requires "https://github.com/yglukhov/android"    # For android target
requires "darwin"
# requires "os_files"   # Used for os-specific file dialog(!!) - requires oldgtk3, which doesn't compile in 2.0.0 
# requires "https://github.com/tormund/nester"  # Used by naketools.nim
requires "nimwebp"  # Used (indirectly) by image.nim to decode an image being downloaded from the Web
requires "https://github.com/yglukhov/clipboard"  # Used for copy/paste functionality
requires "threading"


# "Unpublished" packages that have been copied to local "imported" directory
# Used (indirectly) by image.nim for downloading images from the Web
# requires "https://github.com/yglukhov/async_http_request"   
