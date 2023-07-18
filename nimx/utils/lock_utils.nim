import locks

template withLockGCsafe*(lock: Lock, body: untyped) =
  ## Wraps withLock in a gcsafe block.
  ## From https://gist.github.com/treeform/3e8c3be53b2999d709dadc2bc2b4e097, with thanks.
  {.gcsafe.}:
    withLock lock:
      body
