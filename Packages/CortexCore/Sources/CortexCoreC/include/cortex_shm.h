// Source: project-defined; pattern verified via Clang C11 standard (ISO/IEC 9899:2011 §6.7.10)
// Authoritative reference: cortex-spec.md §9 (Darwin PSHMNAMLEN 31-byte limit)
//
// COMPILE-TIME GUARANTEE: This header refuses to compile if CORTEX_SHM_NAME ever exceeds
// the 31-byte Darwin PSHMNAMLEN cap (32 bytes including null terminator). Phase 2 SC#4
// ("a unit test fails the build if the constant is changed to a name that would silently
// break on Darwin") is therefore structurally impossible to violate — the C precompile
// fails before any test runs.
//
// DO NOT replace this _Static_assert with a runtime check or a unit test.
// See .planning/phases/01-foundation-2026-toolchain/01-CONTEXT.md cross-phase commitment.

#ifndef CORTEX_SHM_H
#define CORTEX_SHM_H

#define CORTEX_SHM_NAME "/cortex.samples"

_Static_assert(sizeof(CORTEX_SHM_NAME) <= 32,
               "CORTEX_SHM_NAME exceeds Darwin PSHMNAMLEN (31 bytes + null terminator). "
               "See cortex-spec.md §9 and Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h.");

#include <sys/types.h> // mode_t

// Non-variadic wrapper around POSIX shm_open(2). Swift cannot import the C variadic
// `shm_open(const char *, int, ...)` (it surfaces as "'shm_open' is unavailable:
// Variadic function is unavailable"), so CortexCore calls this fixed-arity shim
// instead. `mode` is only consulted by shm_open when O_CREAT is set in `oflag`,
// matching the POSIX contract. Returns the fd on success, -1 with errno set on failure.
int cortex_shm_open(const char *name, int oflag, mode_t mode);

// COMPILE-TIME GUARANTEE (D-11): the channel count is fixed at compile time so the shm
// ring slot stride is constant (D-03) and the FlatBuffers channel_data vector length is
// asserted == CORTEX_CHANNEL_COUNT * 2 (D-10, raw f16 byte-pairs). The VALUE here is a
// Phase-2 placeholder; the real count (~96 for O'Doherty Indy/Loco) is confirmed against
// Zenodo 3854034 in Phase 4 (D-11). The MECHANISM (compile-time assert) is fixed in Phase 2.
//
// The assert below refuses to compile if the count is non-positive or so large that a single
// frame's f16 payload would exceed a conservative 64 KiB slot budget (CORTEX_CHANNEL_COUNT*2
// bytes). This makes a silent fixed-stride/half-pair regression structurally impossible,
// exactly as the CORTEX_SHM_NAME assert does for the shm name (Phase 1 cross-phase commitment:
// "compile-time guarantees beat runtime ones").
#define CORTEX_CHANNEL_COUNT 96

_Static_assert(CORTEX_CHANNEL_COUNT > 0 && (CORTEX_CHANNEL_COUNT * 2) <= 65536,
               "CORTEX_CHANNEL_COUNT must be positive and its f16 payload "
               "(CORTEX_CHANNEL_COUNT * 2 bytes) must fit a 64 KiB shm ring slot. "
               "See .planning/phases/02-ipc-primitive-.../02-CONTEXT.md D-10/D-11 and "
               "Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h.");

#endif // CORTEX_SHM_H
