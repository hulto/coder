# Adjudication TASK-016

**Gate Status:** PASSED (with a documented, spec-sanctioned exception)
- `swift build --package-path Modules/CoderUI -Xswiftc -strict-concurrency=complete` — PASS
- `swift test --package-path Modules/CoderUI` — PASS, 14/14 (8 pre-existing +
  6 new `isAuthenticated` tests)
- `swift build --package-path Modules/{CoderKit,CoderAuth,TerminalFeature,WebAppFeature} -Xswiftc -strict-concurrency=complete` — all four PASS (regression check: unchanged)
- `swiftlint lint --strict` on `Sources/AppShell/*.swift` and the new test
  additions — 0 violations. On `LoginViewModel.swift` — 10 violations
  (`redundant_sendable`, trailing whitespace), confirmed via `git show HEAD`
  by both the implementer and reviewer-A to be pre-existing (13 before this
  diff, same categories, net reduced not increased). Matches
  `PROGRESS.md`'s documented repo-wide swiftlint/`.build` hygiene debt; not
  attributable to this task.
- `swift-format lint -r` on touched files — warnings-only, exit 0
  (established baseline).
- `Info.plist` — valid XML via `plistlib`, all 9 required keys present, no
  entitlement/privacy keys.
- **`Sources/AppShell/{CoderApp,RootView}.swift` were never compiled**, by
  spec design: no `Package.swift` exists for this location (an Xcode
  application target, not an SPM package), and this Linux sandbox has no
  XcodeGen, no Apple SDK, no `xcodebuild`. `AuthService()`'s zero-arg
  initializer doesn't exist as a compilable symbol here at all (gated
  behind `canImport(Security) && canImport(AuthenticationServices)`). Per
  the spec's explicit instruction, no throwaway `Package.swift` was
  invented to fake a gate here. Both reviewers independently performed
  manual code review of these two files instead (checking against the
  real `AuthService`/`LoginView` public signatures, SwiftUI/concurrency
  correctness, and the frozen-contract requirements) and both explicitly
  flagged this as unverified-until-Apple-SDK, consistent with the
  standing environment caveat carried since TASK-014.

## Reviewer Verdicts
- Reviewer A: APPROVE
- Reviewer B: APPROVE

## REQUIRED Findings
None. Both reviewers independently reached zero blocker/major findings.

## OPTIONAL Findings (Logged, Not Blocking)

### From Reviewer A
- A1: Additional edge-case test (loading-state transition during a failed
  login) would be nice-to-have; current coverage already adequate via
  pre-existing `loadingStateTransitions` test.
- A2: A one-line clarifying comment above `.onChange` noting it only
  observes `isAuthenticated` while `.signedOut` is rendered, and that the
  flag intentionally never resets on transition to `.signedIn`.

### From Reviewer B
- B1: `State(initialValue: LoginViewModel(...))` re-allocates a
  `LoginViewModel` on every `RootView.init` call that is then discarded by
  SwiftUI's `@State` box-reuse; harmless (the discarded object holds no
  resources), but could be commented for clarity.
- B2: `.onChange(of: loginViewModel.isAuthenticated)` won't re-fire if a
  future sign-out flow returns to `.signedOut` with a stale
  `isAuthenticated == true`, since `onChange` ignores the initial value.
  Flagged as a trap for whichever future task adds sign-out, not a defect
  in this task.
- B3: `SignedInPlaceholderView` displays `loginViewModel.serverURL`
  untrimmed; cosmetic only, no security implication (plain `Text`, no
  markup parsing).
- B4: `.task`'s Keychain check has no explicit `Task.isCancelled` check
  after the `await`; harmless since `hasStoredToken()` is fast,
  non-throwing, and swallows its own errors.

None of the eight OPTIONAL findings across both reviewers overlap in a way
that would escalate any single item to REQUIRED under the union rule; each
was independently rated OPTIONAL/minor-or-nit by its own reviewer with a
sound "no change required for correctness" rationale.

## Decision
**APPROVED on first pass.** No remediation iteration needed, unlike
TASK-014 and TASK-015. Both reviewers independently verified: the frozen
`LoginView`/`LoginViewModel` public contract is intact except for the one
sanctioned additive property; exactly one `AuthService` actor instance is
constructed at the correct scope; the three-state launch contract is
implemented correctly with a genuinely single-resolution Keychain check;
no secrets are logged, stored, or rendered anywhere in the new code; all
grep-based structural criteria (single `@main`, single `WindowGroup`, no
force unwraps, diff scope) pass; and the additive `LoginViewModel` change
is fully gate-verified with 6 new tests covering all required scenarios
without touching any of the 8 existing tests.

Ready for INTEGRATE. All 8 OPTIONAL findings logged above for a future
polish pass; none block merge.

Standing caveats carried forward:
- `Sources/AppShell/` code is written but has never been compiled in this
  environment. Before this can ship, a human/CI on a real Apple toolchain
  must run, in order: `xcodegen generate`, then
  `xcodebuild -scheme CoderApp -destination 'platform=iOS Simulator,name=iPhone 15' build`,
  then a launch smoke test covering: fresh install → `LoginView` renders;
  successful login → placeholder screen; relaunch after a prior successful
  login → placeholder screen without re-prompting for login (validates the
  Keychain-backed `hasStoredToken()` path).
- This remains a bootstrap only. Real Phase 5 work (multi-window `UIScene`,
  Stage Manager, external display, privacy screen on background,
  clipboard/file bridges, settings, icon/launch) still needs to be
  decomposed into further tasks now that there is a baseline app to attach
  them to.
