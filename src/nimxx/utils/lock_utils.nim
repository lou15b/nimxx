##[
  Note that in nimxx we are only using **re-entrant** locks, to prevent a deadlock
  from occurring when an attempt is made to acquire a lock when it has already been
  acquired in the same thread
]##

import rlocks

template withRLockGCsafe*(lock: RLock, body: untyped) =
  ## Wraps withRLock in a gcsafe block.
  ## Based on https://gist.github.com/treeform/3e8c3be53b2999d709dadc2bc2b4e097, with thanks.
  {.gcsafe.}:
    withRLock lock:
      body
