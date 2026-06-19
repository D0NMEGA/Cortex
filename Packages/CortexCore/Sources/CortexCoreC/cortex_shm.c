// Translation unit anchor for the CortexCoreC C target.
// All compile-time invariants live in the corresponding header.
// Phase 2 will add real C functions (POSIX shm_open helpers) here.
#include "cortex_shm.h"
#include <sys/mman.h> // shm_open

// Non-variadic shim so Swift can call shm_open (see cortex_shm.h for rationale).
int cortex_shm_open(const char *name, int oflag, mode_t mode) {
  return shm_open(name, oflag, mode);
}
