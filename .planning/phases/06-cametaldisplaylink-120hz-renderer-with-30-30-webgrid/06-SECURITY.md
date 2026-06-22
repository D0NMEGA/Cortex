---
phase: 6
slug: cametaldisplaylink-120hz-renderer-with-30-30-webgrid
status: verified
threats_open: 0
asvs_level: 2
created: 2026-06-22
---

# Phase 6 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Verified retroactively by `/gsd-secure-phase 6`. Threat categories/dispositions
> are sourced from each plan's `<threat_model>` block (the authoritative STRIDE
> register); evidence is the `gsd-security-auditor` code grep, spot-checked by the
> orchestrator against the live files.

**Surface note:** Phase 6 is in-process native Swift/Metal + CI tooling. There is
no network, auth, persistence, SQL, or external/untrusted-input surface — classic
web-app threat classes (SQLi/XSS/CSRF/authz) do not apply. The real surface is
**GPU write-scope, cross-thread memory ordering, semaphore deadlock-safety, CI
regression-tripwires, and honest attribution of load-bearing credibility numbers.**

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| WebgridParams (CPU) → Metal compute kernel | A uniforms struct crosses into the GPU kernel; the kernel writes the drawable based on it. | cursor position + grid dims (non-sensitive, in-process) |
| Compute kernel → CAMetalDrawable texture | Kernel writes pixels into the drawable (`framebufferOnly = false` opens the write scope). | pixel data |
| Velocity producer thread → VelocityRing → display-link consumer thread | A `CursorVelocity` frame crosses threads via the SPSC ring (synthetic producer now, Rust decoder later). | `(vx, vy)` trivial value type |
| CursorVelocity (untrusted once the real decoder lands) → CursorIntegrator | The integrator is the validation point at the seam — a future decoder may emit NaN/Inf/out-of-range. | velocity (potentially non-finite) |
| Display-link callback → `value:1` semaphore → GPU completion handler | The semaphore gates CPU encode against GPU completion; a wait/signal imbalance deadlocks. | frame-in-flight token |
| Source tree → CI structural gate (`render-policy.sh`) | The gate prevents a future commit from silently regressing the latency / 120Hz / zero-copy commitments. | source diffs |
| project.yml → generated Info.plist / scheme | XcodeGen translates project.yml into build artifacts; a wrong/missing key silently disables 120Hz or the HUD. | build-config keys |
| Measured device → committed SC claim (evidence doc + ROADMAP/REQUIREMENTS) | Translates measured numbers into the spec's credibility claim; misattribution fabricates a load-bearing number. | perf measurements + device identity |
| Bench compute kernel → offscreen MTLTexture | Out-of-bounds writes would corrupt adjacent allocations. | pixel data |
| Checkpoint gate → phase-completion record | The never-auto-approve checkpoint prevents recording an unmeasured iPad-M4 number as captured. | human sign-off |

---

## Threat Register

| Threat ID | Category (STRIDE) | Component | Disposition | Mitigation (evidence: file:line) | Status |
|-----------|-------------------|-----------|-------------|-----------------------------------|--------|
| T-06-01-01 | Tampering | WebgridParams uniforms (NaN / off-grid cursor) | mitigate | NaN cursor fails the disc distance-test → no disc drawn (`Webgrid.metal:99`); authoritative upstream clamp `guard vx.isFinite, vy.isFinite` (`CursorIntegrator.swift:75`). | closed |
| T-06-01-02 | Information Disclosure / Elevation | Compute kernel OOB write to drawable | mitigate | Pixel-bounds guard `if (gid.x >= w \|\| gid.y >= h) { return; }` before any `out.write` (`Webgrid.metal:46-54`, write at `:109`); `framebufferOnly=false` rationale cites T-06-01-02 (`MetalLayerConfig.swift:26`). | closed |
| T-06-01-03 | Denial of Service | Zero `gridColumns/gridRows` → divide-by-zero | **accept** | Cheap defensive zero-clamp present anyway: `float(max(p.gridColumns,1u))` / `max(p.gridRows,1u)` (`Webgrid.metal:68-69`); `WebgridParams` defaults 30×30 → unreachable in-process. See Accepted Risks Log. | closed |
| T-06-02-01 | Tampering / Elevation | CursorIntegrator consuming NaN/Inf/unclamped velocity | mitigate | `guard vx.isFinite, vy.isFinite else { return position }` (`CursorIntegrator.swift:75`); per-axis finite guard (`:84-85`); `clampFinite` to `[0,1]` (`:97-100`); TDD tests `integrateRejectsNaN`/`integrateRejectsInfinity` (`CursorIntegratorTests.swift:57,68`). | closed |
| T-06-02-02 | Information Disclosure / Tampering | Torn read across the SPSC seam | mitigate | Producer `buffer[t]=v` then `tail.store(…, .releasing)` (`VelocityRing.swift:91-92`); consumer `tail.load(.acquiring)` then read (`:103-106`); `Atomic<Int>` from built-in `Synchronization` (`:56-58`); 200k-frame cross-thread stress test (`VelocityRingTests.swift:82-119`). | closed |
| T-06-02-03 | Denial of Service | Producer outpaces consumer, filling the ring | **accept** | Bounded push `if next == h { return false }` never overwrites an unconsumed frame (`VelocityRing.swift:90`); caller drops surplus (docstring `:82`). See Accepted Risks Log. | closed |
| T-06-03-01 | Denial of Service | `nextDrawable()` nil → `value:1` semaphore deadlock | mitigate | macOS nil-drawable skip path calls `signal()` so every `waitForNextFrame()` is balanced by exactly one signal (`FrameSynchronizer.swift:63-70`); normal path signals via `addCompletedHandler` (`:57-61`). | closed |
| T-06-03-02 | Denial of Service | Drawable-retention stutter holding the 2-deep pool | mitigate | macOS `MacDisplayLinkAdapter` callback body wrapped in `autoreleasepool` (`WebgridView.swift` macOS adapter, instantiated `:127`); grep-asserted per SUMMARY. | closed |
| T-06-03-03 | Tampering | A maintainer raising `value:1`→3 or `maximumDrawableCount` 2→3 (+~8.3ms latency) | mitigate | Multi-line "DO NOT raise to 3" annotation + inline comment (`FrameSynchronizer.swift:9-21,42`); matching annotation (`MetalLayerConfig.swift:29-36`); CI tripwire (`render-policy.sh:174`). | closed |
| T-06-03-04 | Information Disclosure | Torn read at the callback consumer | mitigate | Consumer `pop()` acquires the tail before reading the slot — Release-publish/Acquire-observe discipline documented (`VelocityRing.swift:18-25`); same ring used by both platform adapters (`WebgridView.swift:42`). | closed |
| T-06-04-01 | Tampering | CI gate omits the `value:1` / `maximumDrawableCount=2` asserts | mitigate | `require_in_file` asserts both tokens (`render-policy.sh:174-175`); self-test controls 1a/1b strip them → assert exit 1 (`:263-270`); CI runs gate + `--self-test` (`ci.yml:211-214`). | closed |
| T-06-04-02 | Tampering / Spoofing | `CADisplayLink`-on-iOS or `storageModeManaged` regression | mitigate | iOS-scoped `forbid_in_file "$IOS_ADAPTER" 'CADisplayLink'` (`render-policy.sh:185-187`); self-test 2a' proves the sanctioned macOS `CADisplayLink` does NOT trip the gate (`:316-319`). | closed |
| T-06-04-03 | Tampering | 120Hz plist key dropped from project.yml | mitigate | `require_in_project 'CADisableMinimumFrameDurationOnPhone:…true'` (`render-policy.sh:181`); two-layer CI check — project.yml grep + `plutil -extract` on the built Info.plist (`ci.yml:225-237`). | closed |
| T-06-04-04 | Tampering | The gate itself silently weakened (a check deleted) | mitigate | `self_test()` — 9 required-strip + 4 forbidden-inject negative controls (`render-policy.sh:204-339`); `--self-test` is a separate CI invocation so a deleted check stops biting → non-zero exit (`ci.yml:213-214`). | closed |
| T-06-05-01 | Repudiation / Spoofing | M5 Pro number reported as the canonical iPad-M4 claim | mitigate | Device-annotated header + "what this is NOT" paragraph labeling M5 Pro "corroborating-canonical (D-11)" and iPad-M4 "deferred/optional (D-12)" (`06-render-evidence.md:4-7,17,51`); JSON carries `device_tier`/`canonical_device_deferred` (`GPUTimeHistogram.swift:234-235`, `FrameSoak.swift:185-186`). | closed |
| T-06-05-02 | Information Disclosure / Elevation | Bench kernel OOB write of the offscreen texture | mitigate | Offscreen texture uses the identical `framebufferOnly=false`-equivalent write scope and reuses the bounds-guarded Plan-01 kernel + `WebgridFrameEncoder` unchanged, `dispatchThreads` sized exactly to extent (`GPUTimeHistogram.swift:109-118,144-145`; `06-render-evidence.md:116`). | closed |
| T-06-05-03 | Tampering | Non-deterministic soak → unreproducible numbers | mitigate | Closed-form `LissajousProducer.velocity(at:)` drive, no RNG/`Date()` in workload; only 60s wall-clock is time-based (`FrameSoak.swift:27-31,87,111`; `GPUTimeHistogram.swift:151`); two runs p99 0.1615/0.1618 ms (`06-render-evidence.md:114`). | closed |
| T-06-06-01 | Repudiation / Spoofing | iPad-M4 canonical capture auto-approved | mitigate | CRITICAL "NEVER AUTO-APPROVE (D-12)" banner (`06-HUMAN-UAT.md:9-13`); all 3 capture tests stay `pending` (`:85,113,137`); checkpoint:human-verify in an `autonomous:false` plan. | closed |
| T-06-06-02 | Tampering | Silent SC/requirements rewrite without sign-off | mitigate | Reframe is sign-off-gated wording, IDs + `[x]` states preserved (`ROADMAP.md:124-126`; `REQUIREMENTS.md:61-69`); checkpoint:decision `approve-reframe` selected before any edit (`06-06-SUMMARY.md`). | closed |
| T-06-06-03 | Information Disclosure | Reframe wording overstates M5 Pro as the M4 spec number | **accept** | "What this is / is NOT" separation + never-fabricate language (`06-render-evidence.md:17-28`; `06-HUMAN-UAT.md:18-23`). Residual interpretation risk low + documented. See Accepted Risks Log. | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

**Totals:** 20 threats — 17 mitigate (all verified present in code), 3 accept (documented below). `threats_open: 0`.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-06-01 | T-06-01-03 | Zero `gridColumns/gridRows` divide-by-zero. Phase-6 producer is in-process and trusted; `grid30x30` hard-codes 30×30, and `Webgrid.metal` already applies a `max(dim,1u)` clamp. A stricter guard is cheap to add if the field ever becomes externally driven (Phase 7+). | d0nmega (plan disposition `accept`) | 2026-06-22 |
| AR-06-02 | T-06-02-03 | Producer outpaces consumer filling the SPSC ring. Bounded `push` returns `false` and the synthetic producer drops the surplus; the integrator's zero-order hold keeps the cursor smooth, and 50Hz velocity vs 120Hz render means the consumer drains faster than the producer fills. | d0nmega (plan disposition `accept`) | 2026-06-22 |
| AR-06-03 | T-06-06-03 | Residual risk that a reader over-reads the M5-Pro "corroborating-canonical" number as the canonical iPad-M4 spec number. Mitigated by wording: the evidence doc + UAT runbook explicitly label the tiers and never claim the M5 number IS the M4 spec number; backing JSON is device-annotated. Residual interpretation risk is low and documented. | d0nmega (plan disposition `accept`) | 2026-06-22 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-22 | 20 | 20 | 0 | gsd-security-auditor (sonnet) + orchestrator spot-check |

**Method:** State B (created from PLAN `<threat_model>` blocks + SUMMARY threat flags).
Auditor grepped the 17 `mitigate` mitigation patterns against the cited implementation
files; orchestrator spot-checked the load-bearing claims (T-06-01-02 bounds guard,
T-06-02-01 `isFinite` reject, T-06-02-02 release/acquire ordering, T-06-04-01
REQUIRED-PRESENT + self-test, T-06-06-01 never-auto-approve banner) against the live
files. The 3 `accept` threats are documented in the Accepted Risks Log above.
No unregistered threat flags (all 6 SUMMARYs declare "none beyond the plan's threat_model").

---

## Sign-Off

- [x] All threats have a disposition (17 mitigate / 3 accept / 0 transfer)
- [x] Accepted risks documented in Accepted Risks Log (AR-06-01/02/03)
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-22
