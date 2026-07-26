# TASK-016 Review A

Reviewed: Sources/AppShell/CoderApp.swift, Sources/AppShell/RootView.swift,
Sources/AppShell/Info.plist, Modules/CoderUI/Sources/LoginViewModel.swift,
Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift, plus read-only
verification against Modules/CoderAuth/Sources/AuthService.swift,
Modules/CoderAuth/Sources/KeychainManager.swift,
Modules/CoderAuth/Sources/WebAuthSession.swift, and
Modules/CoderUI/Sources/LoginView.swift.

## Gate results (runnable in this sandbox)

- `swift build --package-path Modules/CoderUI -Xswiftc -strict-concurrency=complete`: clean.
- `swift test --package-path Modules/CoderUI`: 14/14 tests pass (8 pre-existing + 6 new).
- `swift build --package-path Modules/CoderKit -Xswiftc -strict-concurrency=complete`: clean (regression, unchanged).
- `swift build --package-path Modules/CoderAuth -Xswiftc -strict-concurrency=complete`: clean (regression, unchanged).
- `swift build --package-path Modules/TerminalFeature -Xswiftc -strict-concurrency=complete`: clean (regression, unchanged).
- `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete`: clean (regression, unchanged).
- `python3 -c "import plistlib,sys; plistlib.load(...)" Sources/AppShell/Info.plist`: parses, all 9 required keys present, no extras, no entitlement/privacy keys.
- `swiftlint lint --strict` on `Sources/AppShell/CoderApp.swift` + `RootView.swift` + the new test file: 0 violations.
- `swiftlint lint --strict` on `LoginViewModel.swift`: 10 violations (trailing whitespace + `redundant_sendable` on `class LoginViewModel: Sendable`). Verified against `git show HEAD:...LoginViewModel.swift`: 13 violations pre-exist before this task's diff, same categories. This task's diff does not introduce a new violation category and net-reduces the trailing-whitespace count. Matches DoD note "introduce no new violations" and PROGRESS.md's documented hygiene debt.
- `swift-format lint -r` on touched files: warnings only (indentation/import-order/line-length), exit 0. Matches documented "warnings-only exit is the established baseline."
- `grep -rn '@main' Sources/ Modules/*/Sources/`: exactly one hit (`Sources/AppShell/CoderApp.swift:9`).
- Exactly one `WindowGroup`, zero `UISceneDelegate`/`UIApplicationDelegate`/`UIApplicationSceneManifest`/`supportsMultipleScenes` hits.
- Exactly one `AuthService(` construction in `Sources/AppShell/`, at `CoderApp`'s stored-property level, not inside `var body`.
- No force unwraps in `Sources/AppShell/` (the one `!` found is logical negation `!serverURL.isEmpty`).
- No token logging/rendering; `SignedInPlaceholderView` shows only "Signed in" text and the non-secret `serverURL`.
- `git diff` confirms `Modules/CoderUI/Sources/LoginView.swift` has zero changes (untouched, as required — no unauthorized edit to the frozen surface).
- `git diff --stat` confirms non-`.build/` changes confined to `Sources/AppShell/**` (new, untracked), `Modules/CoderUI/Sources/LoginViewModel.swift`, and `Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift`. `project.yml`, `Modules/CoderAuth/**`, `Modules/CoderKit/**` non-`.build` files untouched. (WebAppFeature source changes present in the working tree are pre-existing, uncommitted work from TASK-014/015 per the parent agent's explicit instruction; out of scope for this review.)
- `LoginViewModel.swift` diff is exactly the documented additive shape: new property, reset at top of `login()`, set-true on success path, stale comment replaced with behavior-describing text, token still discarded (`_ = try await authService.authenticate(...)`).
- `LoginViewModelTests.swift` diff is purely additive (zero deleted lines); all 8 original tests unmodified; 6 new tests cover all 5 required scenarios (initial-false, success-true, failure-false-with-errorMessage, both early-return paths, reset-after-success-then-failure via `mockWebAuth.configure(error:)`).
- Manually verified `AuthService(webAuthSession:keychainStore:)` and `MockWebAuthSessionProvider(callbackURL:)/(error:)/.configure(callbackURL:error:)` signatures used in tests match `Modules/CoderAuth/Sources/AuthService.swift` and `WebAuthSession.swift` exactly.
- Manually verified `RootView`'s `LoginView(viewModel:)` call matches `LoginView`'s real `public init(viewModel: LoginViewModel)`.
- Verified plain Swift enums without associated values or raw types auto-synthesize `Equatable`, so `guard launchState == .checking` in `RootView.body`'s `.task` compiles without an explicit `Equatable` conformance — not a bug.
- `RootView`'s `.onChange(of: loginViewModel.isAuthenticated)` is scoped to the `.signedOut` case only and transitions to `.signedIn`, matching the launch-state contract precisely. The `.task` guard is a reasonable defensive re-entrancy check even though SwiftUI's `.task` fires once per view identity here.
- All `Sources/AppShell/` types (`CoderApp`, `RootView`, `LaunchState`, `SignedInPlaceholderView`) are `internal`, none `public`, per contract.

No findings rise to blocker or major severity. Two minor/nit observations below, both optional.

```yaml
- id: A1
  severity: minor
  class: OPTIONAL
  location: "Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift:172-188"
  evidence: |
    @Test("isAuthenticated stays false after a failed login")
    func isAuthenticatedFalseAfterFailure() async {
        ...
        #expect(viewModel.isAuthenticated == false)
        #expect(viewModel.errorMessage == "Authentication was cancelled by the user.")
    }
  rule: RUBRIC-A/edge-case-coverage
  required_change: "No change required to pass review; optional improvement: add a case where a login fails after isLoading was already true from a slow-resolving mock, to additionally assert isLoading transitions false->true->false around the failure path. Current coverage already exercises this indirectly via loadingStateTransitions (pre-existing) and is adequate as-is."

- id: A2
  severity: nit
  class: OPTIONAL
  location: "Sources/AppShell/RootView.swift:31"
  evidence: |
    LoginView(viewModel: loginViewModel)
        .onChange(of: loginViewModel.isAuthenticated) { _, authenticated in
  rule: RUBRIC-A/documentation
  required_change: "Optional: add a one-line comment above the .onChange noting that it only observes the isAuthenticated flag while signedOut is rendered, and that isAuthenticated intentionally never resets back to false once the view transitions to .signedIn (no consumer needs it to). Purely a clarity nit; behavior is already correct and matches the spec's launch-state contract."
```

## Summary

All 17 acceptance criteria verified as satisfied. The `AuthService()`, `hasStoredToken()`, and `LoginView(viewModel:)` usages in `Sources/AppShell/` are manually verified against the real CoderAuth/CoderUI public signatures and match exactly (this file cannot be gate-verified in this Linux sandbox per the spec's explicit, correct claim, and no fake Package.swift was invented to work around that). The `LoginViewModel.isAuthenticated` addition is the single frozen-surface-compliant additive change specified, is fully gate-verified (build clean, all 14 tests green), and the diff shape matches the spec's line-by-line description exactly. `LoginView.swift` is confirmed untouched. Diff scope is confined to the 5 in-scope files; no out-of-scope files (project.yml, Package.swift, CoderAuth, CoderKit) were modified. Pre-existing swiftlint debt on `LoginViewModel.swift` (redundant_sendable + trailing whitespace) predates this diff and is not worsened, consistent with the spec's documented hygiene-debt carve-out.

VERDICT: APPROVE
