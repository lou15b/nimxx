##[
  Note that in nimxx we are only using **re-entrant** locks, to prevent a
  deadlock from occurring where an attempt is made to acquire a lock when it has
  already been acquired in the same thread
]##

import std/rlocks

template withRLockGCsafe*(lock: RLock, code: untyped) =
  ## A version of "withRLock" that adds gcsafe to the locks pragma.
  ## Inspired by Mastering Nim 2nd ed (p.269)
  acquire(lock)
  {.locks: [lock], gcsafe.}:
    try:
      code
    finally:
      release(lock)
