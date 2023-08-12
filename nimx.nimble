# Package

version     = "0.2"
author      = "Yuriy Glukhov"
description = "GUI framework"
license     = "MIT"

# Directory configuration
installDirs = @["nimx", "assets"]

# Dependencies

requires "sdl2"
requires "opengl"
requires "winim"
requires "nimsl >= 0.3"
requires "jnim" # For android target
requires "x11" # For linux target - pasteboard
requires "nake"
requires "closure_compiler >= 0.3.1"
requires "plists"
requires "variant >= 0.2 & < 0.3"
requires "kiwi"
requires "https://github.com/yglukhov/ttf >= 0.2.9 & < 0.3"
requires "https://github.com/yglukhov/async_http_request"
# requires "jsbind"   # Indirectly required by async_http_request above
requires "rect_packer"
requires "https://github.com/yglukhov/android"
requires "darwin"
# requires "os_files"   # Used for os-specific file dialog(!!) - requires oldgtk3, which doesn't compile in 2.0.0 
requires "https://github.com/tormund/nester"
requires "nimwebp"
requires "https://github.com/yglukhov/clipboard"
