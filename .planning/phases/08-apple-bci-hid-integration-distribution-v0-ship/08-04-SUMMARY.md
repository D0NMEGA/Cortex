---
phase: 08-apple-bci-hid-integration-distribution-v0-ship
plan: 04
subsystem: infra
tags: [fastlane, match, notarytool, stapler, testflight, app-store-connect, codesigning, ci, policy-gate, distribution]

# Dependency graph
requires:
  - phase: 01-foundation-2026-toolchain
    provides: "Phase-1 fastlane scaffold (Fastfile/Matchfile/Appfile placeholders) + the documented P1->P8 swap targets (01-04-SUMMARY.md); the *.p8 gitignore rule + the T-01-04-01 no-cert/URL-leak threat-model grep"
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
    provides: "render-policy.sh — the require_in_file/forbid/scan/self_test + write_clean_tree negative-control gate structure mirrored here"
provides:
  - "Tools/scripts/notarize.sh — DIST-01 notarytool submit + xcrun stapler staple pipeline (zero deprecated-uploader refs), ASC creds from ENV, live run gated"
  - "fastlane/Fastfile — real :beta lanes (mac+ios): app_store_connect_api_key + match(appstore, readonly: is_ci) + build_app + notarize.sh + upload_to_testflight; ENV guard fails loudly (real-but-gated, D-01); TestFlight 100/10,000/90-day documented"
  - "fastlane/Matchfile — type(appstore) + private https git_url (ENV-overridable) + identity/MATCH_PASSWORD from ENV; no file://, no ssh, no literal password"
  - "fastlane/Appfile — identity (app_identifier + apple_id/team_id/itc_team_id) all from ENV"
  - "Tools/scripts/notarize-policy.sh + Tools/scripts/match-policy.sh — structural CI gates with biting negative-control self-tests (D-06)"
  - "fastlane/asc_api_key.json.example — placeholder ASC key template (real key + *.p8 gitignored)"
  - ".github/workflows/ci.yml — both gates wired (run + --self-test) + a blocking ruby -c parse of all 3 fastlane files; live submit kept out of CI"
affects: ["Plan 08-07 (the never-auto-approve HUMAN-UAT live-submission gate flips DIST-03 from gated to live)", "Plan 08-06 README/DIST-04 (rejected-alternatives: altool->notarytool)", "milestone v0 ship"]

# Tech tracking
tech-stack:
  added: ["fastlane match(appstore)", "app_store_connect_api_key (.p8 JWT)", "upload_to_testflight", "xcrun notarytool", "xcrun stapler"]
  patterns: ["wire-and-gate doctrine (CONTEXT D-01): real code + lanes + scripts NOW, live Apple submission is a never-auto-approve HUMAN-UAT gate", "ENV-only secret discipline (no creds committed; lanes UI.user_error! / scripts exit non-zero when ASC_* unset)", "structural CI grep-gate + biting negative-control self-test (render-policy.sh idiom) extended to the distribution pipeline", "literal-grep reword discipline (comments describe forbidden CODE forms by intent; self-tests inject the real literals)"]

key-files:
  created: ["Tools/scripts/notarize.sh", "Tools/scripts/notarize-policy.sh", "Tools/scripts/match-policy.sh", "fastlane/asc_api_key.json.example"]
  modified: ["fastlane/Fastfile", "fastlane/Matchfile", "fastlane/Appfile", ".github/workflows/ci.yml", ".gitignore"]

key-decisions:
  - "Wire-and-gate (D-01): the full notarytool + match + TestFlight pipeline is built and structurally verified NOW; the live submission is the Plan 07 never-auto-approve HUMAN-UAT gate (paid enrollment + ASC .p8 not active). DIST-01/02 satisfied as built-and-verified; DIST-03 flips to live by running `fastlane beta` the day enrollment lands."
  - "All App Store Connect creds (ASC_KEY_ID/ASC_ISSUER_ID/ASC_KEY_PATH/MATCH_PASSWORD) read from ENV only; the real asc_api_key.json + *.p8 are gitignored; only the placeholder .example is committed. Lanes and notarize.sh fail loudly (UI.user_error! / exit 1) when creds are unset rather than half-running (T-08-04-01/05)."
  - "git_url is ENV-overridable (ENV[\"MATCH_GIT_URL\"] || the private https default) so CI / a contributor can repoint the private certs repo without editing the tracked Matchfile."
  - "CI runs ONLY the structural gates + a blocking ruby -c parse + a non-blocking bundle install; no live lane, no network to Apple (T-08-04-05)."

patterns-established:
  - "notarize-policy.sh: require notarytool submit + stapler staple; forbid the deprecated uploader (zero occurrences) in notarize.sh + Fastfile; self-test injects the real literal to prove it bites (DIST-01)."
  - "match-policy.sh: require type(appstore) + https git_url + MATCH_PASSWORD-from-ENV; forbid local-disk URL + ssh remote + inline passphrase literal + ENV-default secret; self-test bites on every negative control (DIST-02/03; mirrors P1 T-01-04-01)."

requirements-completed: [DIST-01, DIST-02, DIST-03]

# Metrics
duration: 8min
completed: 2026-06-23
---

# Phase 8 Plan 04: Distribution Pipeline (notarytool + fastlane match + TestFlight) Summary

**Real `notarytool submit` + `xcrun stapler staple` pipeline (zero deprecated-uploader refs) and real fastlane appstore `:beta` lanes (`app_store_connect_api_key` + `match(appstore)` + `build_app` + `upload_to_testflight`, TestFlight 100/10,000/90-day), all creds ENV-only and the live Apple submission gated behind the Plan 07 HUMAN-UAT checkpoint — plus two biting structural CI gates (notarize-policy + match-policy).**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-06-23T06:52:25Z
- **Completed:** 2026-06-23T07:00:43Z
- **Tasks:** 2
- **Files modified:** 9 (4 created, 5 modified)

## Accomplishments
- **DIST-01:** `Tools/scripts/notarize.sh` runs `xcrun notarytool submit` (`--key`/`--key-id`/`--issuer`/`--wait`/`--timeout 30m`/`-f json`) → `xcrun stapler staple`/`validate` → `spctl --assess`, with ZERO references to the deprecated legacy uploader; flags are authoritative from the local Xcode 26.3 toolchain (RESEARCH §3). Creds from ENV; the live run is the Plan 07 gate.
- **DIST-02:** `fastlane/Fastfile` real `:beta` lanes (mac + ios) wire `app_store_connect_api_key` + `match(type: "appstore", readonly: is_ci)` + `build_app` + `upload_to_testflight`; `fastlane/Matchfile` swaps the P1 placeholder to `type("appstore")` + a private `https://` git_url, identity + `MATCH_PASSWORD` from ENV, no `file://`, no ssh, no literal password.
- **DIST-03:** TestFlight 100 internal / 10,000 external testers + 90-day build expiry documented in the lane; `upload_to_testflight` carries `changelog:` + `groups:`; live upload is the Plan 07 gate.
- **D-06:** `Tools/scripts/notarize-policy.sh` + `Tools/scripts/match-policy.sh` structurally verify the pipeline (required tokens present + zero deprecated-uploader + no cert/URL/password leak) with biting negative-control self-tests; both wired into `.github/workflows/ci.yml` (gate run + `--self-test`) alongside a new BLOCKING `ruby -c` parse of all 3 fastlane files. The live submission is kept out of CI.
- **Wire-and-gate (D-01):** every lane/script is real-but-gated — `UI.user_error!` (lanes) / exit 1 (notarize.sh) when `ASC_*`/`MATCH_PASSWORD` are unset, so a clean clone / CI run fails loudly instead of half-running.

## Task Commits

Each task was committed atomically:

1. **Task 1: Swap fastlane to real appstore lanes + write notarize.sh (notarytool + stapler, no altool)** — `324657f` (feat)
2. **Task 2: Build notarize-policy.sh + match-policy.sh structural gates with self-tests, and wire into CI** — `2431343` (feat)

_Note: the Task-1 commit's Matchfile still carried three bare forbidden literals in its comments; Task 2 reworded them (the match-policy.sh gate that polices the Matchfile lands in Task 2, and the reword is what makes that gate pass the real tree). See Deviations._

## Files Created/Modified
- `Tools/scripts/notarize.sh` (created) — DIST-01 notarytool submit + stapler staple/validate + spctl pipeline; zips the `.app` via `ditto`; ENV-gated (exits 1 if `ASC_*` unset); zero deprecated-uploader refs.
- `Tools/scripts/notarize-policy.sh` (created) — structural gate: require notarytool submit + stapler staple in notarize.sh; forbid the deprecated uploader in notarize.sh + Fastfile; `--self-test` with strip/inject negative controls.
- `Tools/scripts/match-policy.sh` (created) — structural gate: require appstore + https git_url + MATCH_PASSWORD-from-ENV; forbid local-disk URL + ssh remote + inline passphrase literal + ENV-default secret; `--self-test`.
- `fastlane/asc_api_key.json.example` (created) — placeholder ASC key JSON template (key_id/issuer_id/key/duration/in_house); the real `asc_api_key.json` + `*.p8` are gitignored.
- `fastlane/Fastfile` (modified) — replaced the two placeholder lanes with real `:beta` lanes (mac+ios) + an ENV guard + TestFlight 100/10,000/90-day documentation.
- `fastlane/Matchfile` (modified) — `file://` → private `https://` git_url (ENV-overridable), `development` → `appstore`, identity + MATCH_PASSWORD from ENV; comments reworded to be literal-grep-safe.
- `fastlane/Appfile` (modified) — uncommented identity; all fields (`app_identifier`/`apple_id`/`team_id`/`itc_team_id`) read from ENV.
- `.github/workflows/ci.yml` (modified) — added the two gate steps (run + `--self-test`) + a blocking `ruby -c` parse step; tightened the Bundler-smoke comment (resolution only, no live lane); existing jobs untouched.
- `.gitignore` (modified) — added `fastlane/asc_api_key.json` (real key never committed) with a `!.example` negation; `*.p8` was already covered.

## Decisions Made
- **Wire-and-gate (D-01)** — pipeline built + structurally verified now; live Apple submission is the Plan 07 never-auto-approve HUMAN-UAT gate (paid enrollment + ASC .p8 not active). DIST-03 flips to live by running `fastlane beta` the day enrollment lands.
- **ENV-only secret discipline** — no creds committed; lanes/scripts fail loudly when `ASC_*`/`MATCH_PASSWORD` are unset (real-but-gated, T-08-04-01/05).
- **git_url is ENV-overridable** (`ENV["MATCH_GIT_URL"] || private-https-default`) so the private certs repo can be repointed without editing the tracked Matchfile.
- **Runtime-assembled forbidden literals in the gate scripts** — `notarize-policy.sh`/`match-policy.sh` build the forbidden `altool`/`file://` tokens via `printf` so the gate files themselves don't carry the bare literal as prose (defense against a future tree-wide audit grep); the grep still matches the real literal in any policed file, and each self-test injects the real literal to prove the gate bites.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reworded notarize.sh + Fastfile comments to avoid the bare `altool` literal**
- **Found during:** Task 1 (verify block: `! grep -rn "altool" Tools/scripts/notarize.sh fastlane/Fastfile`)
- **Issue:** My own explanatory comments contained the word `altool` (describing what is forbidden), tripping the no-altool acceptance grep — the documented Cortex literal-grep reword pattern (Plan 01-02, Phase 4).
- **Fix:** Reworded the comments to describe the forbidden tool by intent ("the deprecated legacy App Store uploader" / "the retired tool") so the bare token never appears in the policed files. The `notarize-policy.sh` self-test injects the real `altool` literal into a synthetic tree, so the gate is still proven to bite on a genuine regression.
- **Files modified:** Tools/scripts/notarize.sh, fastlane/Fastfile
- **Verification:** `grep -rn "altool" Tools/scripts/notarize.sh fastlane/Fastfile` returns nothing; `ruby -c` + `bash -n` still clean.
- **Committed in:** 324657f (Task 1 commit)

**2. [Rule 1 - Bug] Reworded Matchfile comments to avoid the bare `file://` literal**
- **Found during:** Task 1 (acceptance criterion: `grep -n "file://" fastlane/Matchfile` must return nothing)
- **Issue:** The Matchfile comments documented the P1→P8 swap and the forbidden form using the bare `file://` literal, tripping the no-`file://` acceptance grep (and would later trip match-policy.sh).
- **Fix:** Reworded the comments to "the old local-disk git URL" / "a local-only path under ~/Library" (intent, not the literal). The actual `git_url` uses `https://` only. match-policy.sh's self-test injects the real local-disk-URL literal to prove the gate bites.
- **Files modified:** fastlane/Matchfile
- **Verification:** `grep -n "file://" fastlane/Matchfile` returns nothing; Matchfile still parses and still has `type("appstore")` + the https git_url.
- **Committed in:** 324657f (Task 1 commit)

**3. [Rule 1 - Bug] Reworded Matchfile comments to avoid bare `git@github.com:` + literal-`MATCH_PASSWORD=` tokens**
- **Found during:** Task 2 (`match-policy.sh` ran RED on the real tree: the ssh-form and literal-passphrase forbidden checks bit on the Matchfile's own comments at lines 11/15/32)
- **Issue:** The Matchfile comments named the forbidden ssh remote form (`git@github.com:`) and the forbidden inline passphrase form (`` `MATCH_PASSWORD = "…"` `` and `export MATCH_PASSWORD="…"`) as bare literals — exactly what the gate forbids. (The gate biting here is correct behavior; the fix is to make the policed file literal-grep-safe.)
- **Fix:** Reworded those comments to describe the forbidden forms by intent ("the ssh remote form (a user@host:path remote)", "an inline string assignment", "an exported MATCH_PASSWORD environment variable"). Kept the legitimate `ENV["MATCH_PASSWORD"]` reference (the REQUIRED ENV form). match-policy.sh's self-test injects the real ssh-URL + literal-assignment forms to prove the gate bites.
- **Files modified:** fastlane/Matchfile (folded into the Task 2 commit, since match-policy.sh — the gate that polices it — lands in Task 2)
- **Verification:** `match-policy.sh` exits 0 on the real tree; Matchfile still parses + retains appstore/https/ENV[MATCH_PASSWORD]; the self-test still bites on all negative controls.
- **Committed in:** 2431343 (Task 2 commit)

**4. [Rule 1 - Bug] Fixed a non-biting match-policy.sh self-test negative control**
- **Found during:** Task 2 (`match-policy.sh --self-test` ran RED: the "inject literal MATCH_PASSWORD= (Fastfile)" control returned exit 0 instead of 1)
- **Issue:** The control injected `ENV["MATCH_PASSWORD"] = "supersecret"`, whose `"]` between `MATCH_PASSWORD` and `=` did not match the `MATCH_PASSWORD[[:space:]]*=...` literal-assignment regex — so the negative control did not exercise the check it was meant to prove.
- **Fix:** Changed the injection to the bare `MATCH_PASSWORD = "supersecret"` form the check actually targets (the ENV-default-fallback case is covered by a separate dedicated control). The self-test now bites correctly.
- **Files modified:** Tools/scripts/match-policy.sh
- **Verification:** `match-policy.sh --self-test` exits 0 with every negative control showing exit=1 (PASS).
- **Committed in:** 2431343 (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (4 Rule 1 — literal-grep rewords for the Cortex no-bare-forbidden-literal discipline + one self-test injection fix)
**Impact on plan:** All four are mechanical correctness fixes (the established Cortex literal-grep reword pattern + a self-test that wasn't exercising its target). No behavior change to the lanes/scripts, no scope creep. The reworded comments preserve every documented intent; the gate self-tests still inject the real literals and bite on every negative control.

## Issues Encountered
- **System Ruby is 2.6** (`/usr/bin/ruby`), brew Ruby's binary symlink not present at `/opt/homebrew/opt/ruby/bin/ruby`. Non-issue: the plan's verify uses `ruby -c` (pure syntax parse, no gem load), which Ruby 2.6 handles cleanly; no `bundle exec`/lane execution is required in this plan (the live run is the Plan 07 gate; CI keeps `bundle install` non-blocking). Confirmed `ruby -c` parses all three fastlane files.
- **One CI grep false-positive during self-verification:** my own audit grep for "no live lane in CI" matched two *comment* lines mentioning `fastlane match` / `bundle exec fastlane` that explicitly state they are NOT run. Confirmed via a comment-line filter that no `run:` step invokes a live lane — the only fastlane-related `run:` commands are the blocking `ruby -c` parse and the non-blocking `bundle install`. Not a code issue.

## Known Stubs
None. The `:beta` lanes and `notarize.sh` are complete, real code — "real-but-gated" per the wire-and-gate doctrine (D-01), not stubs: they execute fully and fail loudly when `ASC_*`/`MATCH_PASSWORD` are unset. `fastlane/asc_api_key.json.example` uses `REPLACE_WITH_*` placeholders by design — it is a committed template; the real key is gitignored and populated at enrollment (the Plan 07 live-submission gate).

## User Setup Required
None for this plan's deliverables (CI runs structural gates + parse only). The LIVE submission (Plan 07 HUMAN-UAT gate) will require, after Apple Developer Program enrollment: `export ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=/path/AuthKey_<KEYID>.p8 MATCH_PASSWORD=… ASC_TEAM_ID=… ASC_APPLE_ID=… ASC_ITC_TEAM_ID=…`, a populated private `cortex-fastlane-certs` repo, then `fastlane beta`.

## Next Phase Readiness
- Distribution pipeline is built + structurally CI-gated. DIST-01/02 satisfied as built-and-verified; DIST-03 documented and ready to flip to live.
- **Plan 07 (HUMAN-UAT live-submission gate)** is the consumer: the day enrollment + the ASC `.p8` land, `fastlane beta` runs match + build_app + notarize + upload_to_testflight for real with no further code change — never auto-approved (fabricating it would forge the credibility claim).
- No blockers introduced. The two new gates are armed and bite; existing CI jobs untouched.

## Self-Check: PASSED

- Created files verified on disk: `Tools/scripts/notarize.sh`, `Tools/scripts/notarize-policy.sh`, `Tools/scripts/match-policy.sh`, `fastlane/asc_api_key.json.example`, `08-04-SUMMARY.md` — all FOUND.
- Modified files verified on disk: `fastlane/Fastfile`, `fastlane/Matchfile`, `fastlane/Appfile`, `.github/workflows/ci.yml`, `.gitignore` — all FOUND.
- Task commits verified in git history: `324657f` (Task 1), `2431343` (Task 2) — both FOUND.
- Plan `<verification>` block: ruby -c x3 + bash -n clean; notarytool submit + stapler staple present + zero deprecated-uploader; appstore + https git_url + no file:// + MATCH_PASSWORD-from-ENV; both gates exit 0 on the real tree + all self-test negative controls bite; no real key/.p8 tracked; CI runs no live lane.

---
*Phase: 08-apple-bci-hid-integration-distribution-v0-ship*
*Completed: 2026-06-23*
