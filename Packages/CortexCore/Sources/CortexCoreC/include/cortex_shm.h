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

#endif // CORTEX_SHM_H
