---
donny_state_version: 1.0
milestone: v1.1
milestone_name: Technical Narrative and Decode-Gap Analysis
status: executing
stopped_at: Phases 11 and 12 delivered and committed; milestone deliverables complete
last_updated: "2026-09-17T15:50:58.000Z"
last_activity: 2026-09-17 -- Started milestone v1.1 (hard deadline 2026-09-18, Neuralink onsite)
progress:
  total_phases: 2
  completed_phases: 2
  total_plans: 2
  completed_plans: 2
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-09-17)

**Core value:** A real-neural-data decoder running end-to-end under 25ms, reproducibly — NDT1 decoding real primate M1 spikes (O'Doherty/Makin Indy, Zenodo 3854034) through the sub-25ms software-timed pipeline. *Re-pointed 2026-08-28: the photodiode-instrumented "24.7 ± 1.3 ms" claim is RETIRED to Future work (hardware-gated); it stays a spec target and may not be cited as achieved.*
**Current focus:** v1.1 Technical Narrative and Decode-Gap Analysis, started 2026-09-17, hard deadline 2026-09-18. Compilation plus one bounded measurement; no product capability added, no shipped code path touched.

**Re-plan 2026-08-28 (user-directed).** Phases 9-10 were the photodiode rig build + 10k-trial campaign. Both are retired to ROADMAP "Future work" (LAT-01..08 preserved, not deleted) — hardware-gated on the ~$110 BOM plus the provisioned iPad Pro M4 that already deferred three Phase-8 HUMAN-UAT gates. Replaced by real-data work, because the repo's largest credibility hole is that **every decoder number was produced on a synthetic Poisson fallback** (`04-training-evidence.md`: "No real `.mat` was present under `Decoder/data/`"), so co-bps 0.3804, ReFIT 0.374-vs-0.161 and 1.953 BPS are all synthetic-data numbers. New requirements RD-01..RD-10. Infrastructure is already in place and unused: `download_indy.py` works, `data.py` is a real h5py v7.3 loader, the manifest lists 4 sessions with `sha256: "PENDING"`, and Zenodo is live (verified 2026-08-28: HTTP 200, ~1.5 GB total). Known blocker for Phase 10: `Tools/scripts/readme-policy.sh` **requires** the tokens `photodiode` and `24.7` in the README and its `--self-test` proves the gate bites when they are stripped — retiring the claim means rewriting the gate and its negative controls in lockstep (RD-10).

## Current Position

Milestone: v1.1 Technical Narrative and Decode-Gap Analysis
Phase: 12 of 12 - both phases delivered 2026-09-17
Status: Deliverables complete and committed; onsite is 2026-09-18
Last activity: 2026-09-17

Progress: Milestone v1.1 [##########] 100% (2/2 phases)

**Delivered**
- `773f6df` milestone scoped (PROJECT/STATE/ROADMAP/REQUIREMENTS + research/NEURALINK-JD.md, all 7
  postings from the Greenhouse API; three of seven name Rust, which was under-weighted before)
- `054cdd3` Phase 12. `docs/architecture-walkthrough.md` was found already drafted and UNTRACKED,
  authored by the concurrent `neurorust-8c` session, not this one. Verified rather than rewritten:
  all 19 numeric claims traced to committed sources, architectural claims (CORTEX_DECODER default,
  export probe-window parity test, 64 targets at 15 mm pitch) traced to code. Added to
  `SWEEP_CITED_FILES` so honesty-sweep now gate-covers it; `--self-test` still bites all 14 controls
- `f3a7fb2` Phase 11. `11-decode-gap-evidence.md`: the 0 of 1,025 decomposes into a geometry term
  (1,025 -> 147, the recorded hand's own score at the canonical radius) and a decode term
  (147 -> 0). The decode term is not marginal: target-blind p1 distance is 16.58 mm, 5.80x the
  2.8614 mm acceptance radius and 1.11x even the 15 mm radius where the recorded hand scores
  1,023/1,025. Correcting the mis-specified geometry would not produce a hit
- Walkthrough Stage 4 now discloses that this is NOT a Wu/Gilja neural-observation Kalman decoder.
  `full_measurement()` returns `H = [0 I 0]`, a velocity-only observation of an already-decoded
  `(vx, vy)`, so it is a post-decoder kinematic smoother plus intent rotation. The repo had no
  public disclosure of that distinction. Flagged by the `project-moltgrid-5a` session and verified
  here before acting on it

**Open, deliberately not done**
- Exact per-sample radius sweep. Phase 11 bounds the 7.50 and 15.00 mm claims from distance
  percentiles rather than proving them; percentiles carry no run-length information and dwell needs
  75 consecutive samples. Converting the bound to an exact sweep is the natural next task
- Manifold / population-dynamics analysis. A real gap against the Neuroengineer posting, cut for
  time, first candidate for v1.2
- Phase 3 SC#1 Instruments System Trace, INT-02, INT-03. All out of scope this milestone

**Note.** `Decoder/scripts/ane_scale_sweep.py` and `Decoder/artifacts/` are untracked in-flight work
belonging to the `neurorust-8c` session and were deliberately left uncommitted by this one.

CI on HEAD is green (run 35137114434, both jobs, 8m9s). The earlier red was a GitHub spending-limit
rejection with zero steps executed, not a code defect. All 12 policy gates pass locally.


## Performance Metrics

**Velocity:**

- Total plans completed: 55 (Phases 1-4)
- Average duration: ~5.3m
- Total execution time: ~32 minutes

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 7 | - | - |
| 02 | 5 | - | - |
| 03 | 4 | - | - |
| 04 | 5 | - | - |
| 06 | 6 | - | - |
| 07 | 3 | - | - |
| 08 | 7 | - | - |
| 10 | 18 | - | - |

**Recent Trend:**

- Last 5 plans (Phase 4): 04-01 (~6m), 04-02 (~12m), 04-03 (~12m), 04-04 (~16m), 04-05 (~14m). Waves 2 & 3 each ran 2 plans concurrently in isolated worktrees.
- Trend: Phase 4 plans ran ~6-16m (heavier ML implementation — torch model, training loop, CoreML conversion) vs Phase 1's 3-6m. 04-04 (training loop + slow co-bps evidence run) was the longest. Across the phase: 7 deviations total, all auto-fixed (mostly literal-grep comment rewordings, the documented project pattern), no scope creep, no new deps beyond the planned torch/coremltools/h5py.

*Updated after each plan completion*
| Phase 05 P01 | 13 min | 3 tasks | 6 files |
| Phase 05 P04 | 13 min | 3 tasks | 10 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent architectural commitments shaping all phases:

- CoreML on ANE (not MLX) — only path meeting <2ms p99 budget
- pthread + `QOS_CLASS_USER_INTERACTIVE` (not Swift Task) — Swift cooperative scheduling cannot meet 1ms deadlines
- `kqueue`+`recvmsg` + POSIX shm in App Group container (not Network.framework) — sub-µs vs 50-200µs
- `CAMetalDisplayLink` (not `CADisplayLink`) — beam-raced 120Hz with bundled drawable/encode/present callback
- AES-GCM via CryptoKit (not ChaCha20-Poly1305) — Apple Silicon FEAT_AES makes AES-GCM faster
- NDT1 with h=1-2 heads (not h=4 miscitation) and BC1S `(B,C,1,S)` layout (not vanilla `(B,S,C)`)
- 30×30 webgrid (not 6×6) — modern Bliss Chapman / Neuralink reference

**Plan 01-01:**

- Manifest version stays at 6.2 verbatim per artifact contract; toolchain mismatch on local executor (Swift 6.0.3) is environmental — Plan 01-06 CI on macos-15 with Xcode 26.3 is the canonical execution environment for Swift-side smoke
- `.defaultIsolation(MainActor.self)` retained on all four packages per Approachable Concurrency (drop only if Xcode 26.3 rejects, per Assumption A9 — no evidence of rejection yet)
- `_Static_assert` diagnostic message includes the authoritative reference inline (cortex-spec.md §9 + the header path) so a silent regression is structurally impossible — proven via clang negative test (53 bytes → exit 1, expression evaluates to `'53 <= 32'`)
- Used `git mv` for cortex-spec.md → docs/cortex-spec.md so rename is recorded as single R operation (not D+A); `git log --follow` traces back to commit 4605b83

**Plan 01-03:**

- CA92.1 (Approximate time interval) chosen over 35F9.1 (Measuring performance) and 3D61.1 (Obvious functionality) for `NSPrivacyAccessedAPICategorySystemBootTime` — RESEARCH.md Q5 documents all three are valid; CA92.1 most accurately frames Cortex's latency-arithmetic use case and matches CONTEXT.md FOUND-03 verbatim
- Daemon target gets NO `PrivacyInfo.xcprivacy` in Phase 1 — daemon ships no required-reason API usage; manifest arrives in Phase 2/3 when daemon code lands. Variadic-argv design in the validator script makes adding the daemon manifest a one-line CI tweak
- iOS and Mac manifests are byte-for-byte identical (`diff` returns empty) — both apps consume `mach_absolute_time` via the same `CortexCore.Time.machAbsoluteNanoseconds()` wrapper and have no other required-reason API usage in Phase 1
- Validator script uses only macOS-bundled `plutil` + `grep` — no homebrew installs, no Python, no jq. Runs on bare `macos-15` GitHub Actions runner per FOUND-05
- Negative-control test executed: stripping `<string>CA92.1</string>` from a temp copy made the validator exit 1 with `ERROR: ... missing CA92.1 reason code (required for mach_absolute_time)`. The trap is armed and proven to bite — Phase 1 has structural defense against future drift the moment Plan 01-06 wires this into CI

**Plan 01-04:**

- fastlane pinned via `gem "fastlane", "~> 2.226"` in Gemfile; Bundler resolved to fastlane 2.233.0 + 94 transitive deps; Gemfile.lock committed as canonical pin with sha256 checksums
- Matchfile uses `git_url("file:///Users/donmega/Library/Cortex-fastlane-certs")` per RESEARCH.md Q8 — local-only, never traverses network. Negative-grep verified no `https://github.com/` and no `git@github.com:` substrings in Matchfile (Phase 1 threat-model T-01-04-01 mitigated)
- Appfile keeps `app_identifier`, `apple_id`, `team_id`, `itc_team_id` all commented out per D-09 (deferred enrollment); negative-grep verified no uncommented `team_id "..."` or `apple_id "..."` lines
- Fastfile defines exactly two placeholder lanes (mac + ios), each prints a deferral `UI.message` and contains zero calls to `match`, `gym`, `pilot`, `deliver`, or `notarize`
- Rule 3 (blocking) auto-fix: macOS system Ruby 2.6 cannot build json-2.7.6 native extension; ran `brew install ruby` (Ruby 4.0.3) and re-ran `bundle install` cleanly. Plan explicitly anticipated this case in Step 5; documented in 01-04-SUMMARY.md
- All four Ruby files (Gemfile + Fastfile + Matchfile + Appfile) parse cleanly under `ruby -c`
- Phase 8 swap targets explicitly documented in 01-04-SUMMARY.md: replace Matchfile `file:///` with private GitHub URL + `MATCH_PASSWORD`, change `type("development")` to `type("appstore")`, uncomment Appfile identity fields, add real lanes to Fastfile

**Plan 01-05:**

- README kept minimal (Phase 1 foundation); credibility-grade README with architectural commitments table is DIST-04 (Phase 8)
- ADR-0001 explicitly documents fastlane as Phase-1 placeholder per D-09/D-10 (honoring 01-04 cross-phase note)
- ADR-0001 is the format precedent for ADR-0002+: ## Context / ## Decision / ## Consequences / ## Alternatives considered; sequential numbering 0001-0002-...; no decimals; supersession via new ADR
- PR template's architectural commitment checklist mirrors Plan 06 CI gates (defense-in-depth)

**Plan 01-02:**

- `project.yml` is the single source of truth for Xcode topology — three targets (CortexiOS application iOS, CortexMac application macOS native AppKit, CortexDaemon type-bundle background helper) plus four CortexCore/CortexIPC/CortexRender/CortexDecoder packages plus three schemes; generated `.xcodeproj` and `.xcworkspace` are gitignored. PRs review YAML diffs, never pbxproj
- Defense-in-depth Mac Catalyst opt-out: `SUPPORTS_MACCATALYST: NO` in project.yml AND `NSApplicationDelegateAdaptor` in Apps/CortexMac/App.swift. Either alone could be regressed silently; together the pair is durable. Phase 6 RENDER-08 `NSScreen.displayLink` requirement is now defensible
- All three Cortex.entitlements files declare `group.com.donovansantine.cortex.shared` (D-07 verbatim). NONE declare `com.apple.security.app-sandbox` (Critical Finding #1 mitigation). Plan 06 CI grep will catch any future regression
- CortexMac depends on `target: CortexDaemon` (cross-target dependency, not just package) — building the CortexMac scheme transitively builds the daemon as a peer artifact. Single xcodebuild scheme build exercises the daemon-bundle SPM consumption (Critical Finding #4 verification surface)
- Two Rule 1 (auto-fix bug) deviations applied during execution to satisfy literal acceptance criteria: (a) reworded a comment in `project.yml` to avoid the literal `com.apple.security.app-sandbox` token while preserving Phase-1-no-sandbox intent; (b) reworded comments in Apps/CortexMac/App.swift to avoid the case-sensitive `Catalyst` token while preserving native-AppKit-not-iOS-bridge intent. Build setting `SUPPORTS_MACCATALYST: NO` in project.yml is allowed (uppercase MACCATALYST does not match case-sensitive grep)
- Toolchain-deferral disposition for the dynamic xcodebuild verification: local executor environment is CommandLineTools + Swift 6.0.3 (no Xcode 26, no xcodegen). Structural verification done locally to the maximum extent (plutil -lint clean × 6, YAML parses with 3 targets / 4 packages / 3 schemes, App Group grep == 3, app-sandbox grep empty across project.yml + 3 entitlements, case-sensitive Catalyst grep empty in Mac App.swift, swiftc -parse exits 0 on 5 Swift files). Dynamic xcodebuild build verification gate captured as a verbatim seven-step re-run command set in 01-02-daemon-spm-smoke.md — closed by Plan 01-06 CI on macos-15 + setup-xcode@v1 pinning 26.3 OR by a human on a Xcode 26 dev machine. Matches Plan 01-01 toolchain-deferral precedent
- PrivacyInfo.xcprivacy auto-bundling pattern: relying on XcodeGen's directory recursion of `Apps/CortexiOS/` and `Apps/CortexMac/` to add the `.xcprivacy` to Copy Bundle Resources. Step 7 of the smoke command set explicitly verifies bundling on the Xcode 26 environment
- [Phase 05]: DEC-11 latency is measured in-process in a dedicated CortexDecoderBench executable (10k ContinuousClock passes), NOT a swift test timing gate (D-18); the Mac number is device-annotated and CORROBORATING (CPU-placed at 1.29M params — the scale trap), with the canonical sub-2ms-p99-on-ANE claim handed to the iPad-M4 run of the same bench (Plan 05). — Keeps a flaky latency assertion out of CI and prevents a Mac CPU-latency number from being misrepresented as the canonical ANE claim (mirrors the 05-02 eligibility/placement split + THREAD-02/SC#1 device-gating).

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 260621-32u | Set DEVELOPMENT_TEAM to 57YW6M29S7 on all three targets in project.yml and regenerate | 2026-06-21 | c9478e0 | [260621-32u-set-development-team-to-y4a54395nz-on-al](./quick/260621-32u-set-development-team-to-y4a54395nz-on-al/) |
| 260621-3y0 | Remove dead ShmCheck references from CortexMac ContentView so the target compiles | 2026-06-21 | dd67fd0 | [260621-3y0-remove-dead-shmcheck-references-from-cor](./quick/260621-3y0-remove-dead-shmcheck-references-from-cor/) |
| 260621-iyg | Set CortexMac scheme run.executable=CortexMac so it launches the app window, not the daemon | 2026-06-21 | c0a3b2c | [260621-iyg-set-cortexmac-scheme-run-executable-to-c](./quick/260621-iyg-set-cortexmac-scheme-run-executable-to-c/) |
| 260915-fk9 | Land the Phase 10 radius-rule figure and analysis scripts | 2026-09-15 | cf2ba1e | [260915-fk9-land-the-phase-10-radius-rule-figure-and](./quick/260915-fk9-land-the-phase-10-radius-rule-figure-and/) |

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Build config | `xcodebuild` of the CortexDaemon Xcode target fails on `'Float16' is unavailable in macOS` in CortexIPCSession (SampleCodec) — generated-project deployment/arch config, NOT a code defect (`swift build`/SwiftPM + CI `swift test` are clean) | RESOLVED 2026-09-16 — CI run 34188028835 shows "Build CortexDaemon scheme" and "Verify CortexDaemon bundle artifact exists" both green under Xcode 26.3 | 2026-06-20 (Plan 02-05 finding; 02-05-SUMMARY.md + sc1-evidence.md anomaly #2) |
| Security | ~~Phase 2 `SECURITY.md` not yet created~~ — RESOLVED: `02-SECURITY.md` created & verified (28/28 threats closed, ASVS L1, 2 accepted risks → Phase 8), committed `02e2b9c` | Resolved 2026-06-20 (`/gsd-secure-phase 02`) | 2026-06-20 (Phase 2 completion) |
| Verification | SC#1 timing measured on M5 Pro (≥ M4) under a live dev session; a quiet-machine / dedicated iPad-Pro-M4 re-run via the sc1-evidence.md runbook would refine the tail (not the sub-µs verdict) | Open — optional refinement | 2026-06-20 (Plan 02-05; sc1-evidence.md) |
| Verification | Plan 01-02 dynamic xcodebuild build smoke (CortexMac/CortexiOS/CortexDaemon `BUILD SUCCEEDED` under `CODE_SIGNING_ALLOWED=NO` + four sibling overrides + two `-skip*Validation` flags; CortexDaemon.bundle artifact existence on disk; PrivacyInfo.xcprivacy presence in built `.app` bundles) | RESOLVED 2026-09-16 — closed by CI run 34188028835 on macos-15 / Xcode 26.3; CortexMac, CortexiOS and CortexDaemon schemes all build green | 2026-04-30 (Plan 01-02 toolchain-deferral disposition) — closed by Plan 01-06 CI on macos-15 + Xcode 26.3, OR by human on Xcode 26 dev machine. Verbatim re-run command set captured in `.planning/phases/01-foundation-2026-toolchain/01-02-daemon-spm-smoke.md` |

## Session Continuity

Last session: 2026-09-16
Stopped at: v1.0 milestone complete - archived, tagged, nothing in flight
Resume file: .planning/MILESTONES.md (v1.0 entry, including its Known Gaps)
