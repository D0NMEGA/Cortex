#!/usr/bin/env bash
# Regenerate vendored FlatBuffers Swift from sample.fbs (D-13). Run locally when the schema
# changes; the generated Swift is COMMITTED in-repo. CF#7: the flatc version MUST match the
# FlatBuffers SwiftPM runtime pinned in Packages/CortexIPC/Package.resolved (currently 25.12.19).
set -euo pipefail
SCHEMA="Packages/CortexIPC/Schemas/sample.fbs"
OUT="Packages/CortexIPC/Sources/CortexIPCSession/generated"
if ! command -v flatc >/dev/null 2>&1; then
  echo "flatc not found — skipping regen (vendored Swift is committed; install flatc matching the SwiftPM pin to regen)."
  exit 0
fi
echo "flatc version: $(flatc --version)"
mkdir -p "$OUT"
flatc --swift -o "$OUT" "$SCHEMA"

# Post-process (deterministic, idempotent): mark the generated table struct `nonisolated`.
# The CortexIPCSession SwiftPM target sets `.defaultIsolation(MainActor.self)` (Plan 02-01), which
# would otherwise make flatc's pure-value accessors MainActor-isolated — breaking the nonisolated
# SampleCodec that the Foundation-free Transport consumer (Plan 02-04) calls off the main actor.
# flatc emits no isolation annotation, so we inject `nonisolated` on the struct decl here. This keeps
# regeneration reproducible (the committed file == flatc output + this one scripted transform) without
# hand-editing generated code. Re-running is safe: the sed only matches the un-annotated form.
GEN="$OUT/sample_generated.swift"
if [ -f "$GEN" ]; then
  /usr/bin/sed -i '' -E 's/^public struct (Cortex_IPC_[A-Za-z0-9_]+):/public nonisolated struct \1:/' "$GEN"
  echo "post-processed: injected 'nonisolated' on generated table struct(s) in $GEN"
fi
echo "OK: regenerated $OUT from $SCHEMA"
