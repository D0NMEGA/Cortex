# CortexRender

Reserved for Phase 6: `CAMetalDisplayLink`-driven 120Hz beam-raced Metal renderer.
The 30x30 webgrid compute shader (~900 cells) and `MTLBuffer storageModeShared`
zero-copy unified-memory drawables land here.

Empty in Phase 1 — see `.planning/REQUIREMENTS.md` RENDER-01 through RENDER-09.

## Performance budget (Phase 6)

GPU frame time at most 0.4ms on M4. Frame pacing via `dispatch_semaphore_t(value: 1)`
per Apple's "Synchronizing CPU and GPU Work" pattern. ProMotion 120Hz unlocked via
`CADisableMinimumFrameDurationOnPhone = YES` in Info.plist.
