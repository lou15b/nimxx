when defined(macosx) and not defined(ios):
  import ./pasteboard_mac
  export pasteboard_mac

elif defined(windows):
  import ./pasteboard_win
  export pasteboard_win

elif defined(linux) and not defined(android):
  import ./pasteboard_x11
  export pasteboard_x11

else:
  import ./abstract_pasteboard
  export abstract_pasteboard
  proc pasteboardWithName*(name: string): Pasteboard = result.new()


when isMainModule:
  # Some tests...
  let pb = pasteboardWithName(PboardGeneral)
  # Note: For Linux the following calls do not write or read anything
  #   to the clipboard, because the internal display variable has not
  #   been initialized. So in this case, success criterion is merely that
  #   there is no exception
  pb[].writeString("Hello world!")
  let s = pb[].readString()
  echo s
