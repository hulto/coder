# Coder iOS Client — Progress Tracker

## Current Phase: 5 (Polish) — AppShell bootstrap complete, real polish tasks not yet decomposed

## AppShell Bootstrap (TASK-016) — Resolved the Missing-App Gap
`project.yml` declared an app target `CoderApp` sourced from
`Sources/AppShell`, depending on all five existing SPM packages, but that
directory did not exist anywhere in the repo. Phases 0-4 built five
library modules and their tests in complete isolation; there was no
`@main` entry point, no `WindowGroup`/`UIScene` composition, and no DI
wiring connecting them into a runnable app. (No `TASK-001.md` spec file
exists for what Phase 0 "Scaffolding" supposedly did, despite it being
marked COMPLETE in the Task Index above — left as-is, not backfilled.)

TASK-016 closed this: `Sources/AppShell/CoderApp.swift` (`@main` App, one
`WindowGroup`, one `AuthService` instance), `Sources/AppShell/RootView.swift`
(3-case launch-state enum, one-time Keychain check via `hasStoredToken()`,
switches between `LoginView` and a placeholder `SignedInPlaceholderView`),
and `Sources/AppShell/Info.plist`. Also closed a real gap in
`LoginViewModel` (it had no way to signal login success to a caller) with
one additive `isAuthenticated: Bool` property. Approved by both reviewers
on the first pass, no remediation needed. See
`reviews/TASK-016-adjudication.md`.

**Important, unresolved:** `Sources/AppShell/*.swift` has never been
compiled anywhere in this project. It has no `Package.swift` (by design;
it's an Xcode app target, not an SPM package) and this Linux dev sandbox
has no XcodeGen, no Apple SDK, no `xcodebuild`.
`AuthService()`'s zero-arg initializer doesn't even exist as a symbol here.
Both reviewers did careful manual code review instead of gate verification
for these two files. **Before anything else in Phase 5 proceeds, a human
or CI on a real Apple toolchain should run:**
1. `xcodegen generate`
2. `xcodebuild -scheme CoderApp -destination 'platform=iOS Simulator,name=iPhone 15' build`
3. Launch smoke test: fresh install → `LoginView` renders; successful
   login → placeholder screen; relaunch after a prior successful login →
   placeholder screen without re-prompting (validates the Keychain path).

Real Phase 5 work (multi-window `UIScene`, Stage Manager, external
display, privacy screen on background, clipboard/file bridges, settings,
icon/launch) still needs to be decomposed into further tasks now that
there is a baseline app to attach them to.

## Task Index

| TASK-### | Phase | Module | Status | Worktree | Last Gate |
|----------|-------|--------|--------|----------|-----------|
| TASK-001 | 0 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-002 | 1 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-003 | 1 | CoderAuth | ✅ COMPLETE | main | All gates green |
| TASK-004 | 1 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-005 | 1 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-006 | 1 | CoderUI | ✅ COMPLETE | main | All gates green |
| TASK-007 | 2 | TerminalFeature | ✅ COMPLETE | main | All gates green |
| TASK-008 | 2 | TerminalFeature | ✅ COMPLETE | main | All gates green |
| TASK-009 | 2 | TerminalFeature | ✅ COMPLETE | main | All gates green |
| TASK-010 | 3 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| TASK-011 | 3 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| TASK-012 | 3 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| TASK-013 | 4 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| TASK-014 | 4 | WebAppFeature | ✅ COMPLETE | main | All gates green (1 remediation iteration) |
| TASK-015 | 4 | WebAppFeature | ✅ COMPLETE | main | All gates green (1 remediation iteration) |
| TASK-016 | 5 | AppShell | ✅ COMPLETE | main | All gates green (first-pass approval, no remediation) |
| (none yet) | | | | | |

## Phase State
- [ ] Phase 0: Scaffolding (0.5–1 wk)
- [ ] Phase 1: Auth + workspace list + start/stop (1–2 wk)
- [ ] Phase 2: Terminal (1–2 wk)
- [ ] Phase 3: VS Code Web (1 wk)
- [x] Phase 4: VNC (0.5–1 wk) — TASK-013/014/015 all complete
- [ ] Phase 5: Polish (1–2 wk) — Multi-window UIScene, Stage Manager, external display; privacy screen on background; clipboard/file bridges; error/offline states; settings; icon/launch (see PLAN.md)

Note: Phase 0-3 checkboxes remain unchecked above despite all their tasks
showing COMPLETE in the Task Index; this tracker was stale (said "Current
Phase: 2") before this session reconciled it against actual task state.
Leaving unchecked pending an explicit human/orchestrator confirmation pass
per phase, rather than assuming; the Task Index is the source of truth for
per-task status.

## Standing Environment Caveat
This dev sandbox runs Linux. `canImport(WebKit)` is false here, so every
`#if canImport(WebKit)` body across TerminalFeature/WebAppFeature (all
WKWebView-based code and its tests) compiles to an empty stub and has never
actually executed. All gates reported "green" in this tracker were run on
Linux and only prove the non-WebKit-gated code compiles and its tests pass.
Before shipping, run the full gate suite on a real macOS/iOS toolchain or
CI to validate the WebKit-dependent code paths for real. First flagged
during TASK-014 review (see `reviews/TASK-014-adjudication.md` finding B1).

## Outstanding Human Device-Testing Checklist (VNC, Phase 4)
Cannot be verified by any agent in this sandbox (device-only, per this
skill's "Agents cannot verify these" list). Test on a real iPad before
shipping VNC:
- One-finger drag inside the guest desktop (should reach noVNC, not pan
  the native WKWebView).
- Two-finger pinch (should reach noVNC's own zoom, not trigger WebKit
  page-zoom).
- Two-finger pan/scroll inside a guest app.
- Trackpad hover (cursor precision over the remote canvas).
- Trackpad left-click and right-click.
- Stage Manager / Split View / home-indicator occlusion, since
  `contentInsetAdjustmentBehavior = .never` (TASK-015) lays the canvas out
  under safe-area chrome; confirm nothing important is hidden or steals
  drags at the bottom edge.
- Trackpad two-finger scroll specifically (delivered via the pan
  recognizer, believed unaffected by TASK-015's pinch-recognizer changes,
  but unverified on a real device).
- On a real Apple SDK build: confirm the `Double`→`CGFloat` implicit
  conversion for zoom-scale fields in `VNCInputConfiguration` compiles
  without warning (flagged in `reviews/TASK-015-adjudication.md` finding
  B10; the Linux gate cannot check this since the code path is entirely
  inside `#if canImport(WebKit)`).

## Known Repo Hygiene Debt (not task-specific, flagged for cleanup)
- `Modules/WebAppFeature/.build/` (and likely other modules' `.build/`) is
  tracked in git from the "first agent" commit; `.gitignore` excludes
  `build/` but not `.build/` (the actual SwiftPM artifact directory).
- No `.swiftlint.yml` exists anywhere in the repo to exclude `.build/`
  derived sources from `swiftlint lint --strict`, so that gate command as
  literally written in every task's Definition of Done has never been
  fully clean for any module once `.build/` exists. Reviewers scope
  swiftlint runs to source/test paths explicitly to work around this;
  a real fix (add `.build/` to `.gitignore` + untrack it, add a
  `.swiftlint.yml` excluding it repo-wide) should be its own task.

## Architectural Invariants
- Swift 6, strict concurrency = complete
- Min iOS/iPadOS 17
- Local SPM packages under Modules/
- XcodeGen for project generation (never edit .pbxproj)
- Module boundaries: CoderKit, CoderAuth, TerminalFeature, WebAppFeature, CoderUI, AppShell
- All public types Sendable
- Actors for mutable shared state
- @MainActor for UI updates

## Adjudication Rules
- Union of REQUIRED findings from both reviewers must be addressed
- Deterministic gates are supreme (any failed gate = REQUEST_CHANGES)
- Genuine conflict → orchestrator decides, record as ADR
- OPTIONAL findings logged but not blocking
- MAX_REMEDIATION_ITERATIONS = 3 per task
