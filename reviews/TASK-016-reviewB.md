# Review TASK-016 — Reviewer B (security / concurrency / iOS architecture)

Scope: `Sources/AppShell/CoderApp.swift`, `Sources/AppShell/RootView.swift`,
`Sources/AppShell/Info.plist`, `Modules/CoderUI/Sources/LoginViewModel.swift`,
`Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift`. Cross-checked
against `Modules/CoderAuth/Sources/AuthService.swift`,
`Modules/CoderAuth/Sources/WebAuthSession.swift`, and confirmed
`Modules/CoderUI/Sources/LoginView.swift` was not modified.

No shell in this session (reviewer-b has no Bash tool); `Sources/AppShell/`
cannot be compiled in this Linux sandbox regardless (no Package.swift by
design, no XcodeGen, no Apple SDK, `AuthService()`'s zero-arg init doesn't
exist as a symbol here). Assessment of those files is manual reasoning
only, per the spec's own instructions.

A sign-out button/flow is correctly absent — explicitly out of scope per
the spec ("do not add a sign-out button; that is settings work"). Not a
finding.

## Findings

```yaml
- id: B1
  severity: minor
  class: OPTIONAL
  location: Sources/AppShell/RootView.swift:21
  evidence: "_loginViewModel = State(initialValue: LoginViewModel(authService: authService))"
  rule: RUBRIC-B/memory-management
  required_change: "No change required for correctness; optionally note in a comment that the allocation on re-init is discarded. SwiftUI re-runs RootView.init on every parent re-render, so a fresh LoginViewModel is constructed and immediately thrown away each time, but SwiftUI keeps the first-stored box for a given view identity, so in-progress login state (isLoading/errorMessage/isAuthenticated) is NOT discarded. LoginViewModel.init only stores a reference, so the wasted allocation is benign. This is the documented State(initialValue:) seeding pattern and is correct here."

- id: B2
  severity: minor
  class: OPTIONAL
  location: Sources/AppShell/RootView.swift:31-35
  evidence: |
    .onChange(of: loginViewModel.isAuthenticated) { _, authenticated in
        if authenticated {
            launchState = .signedIn
        }
    }
  rule: RUBRIC-B/lifecycle-aware
  required_change: "No change strictly required. The onChange is attached inside the .signedOut branch, so it is installed only while LoginView is on screen and torn down on transition to .signedIn. That is sufficient for the one-way transition this task specifies, because isAuthenticated can only flip false->true while LoginView is presented. If a future task adds sign-out (returning to .signedOut with a stale isAuthenticated == true), this modifier will not re-fire on re-entry because onChange ignores the initial value; that future task must reset the view model or pass initial: true. Flagging so the follow-on task does not inherit a silent trap."

- id: B3
  severity: nit
  class: OPTIONAL
  location: Sources/AppShell/RootView.swift:37
  evidence: "SignedInPlaceholderView(serverURL: loginViewModel.serverURL)"
  rule: RUBRIC-B/input-validation
  required_change: "Optionally pass the trimmed value (serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) for display consistency with what login() actually validated and used. Not a security issue: SwiftUI Text(String) with a non-literal String does not parse markdown or markup, so there is no injection vector, and the value is non-secret user input. Purely cosmetic."

- id: B4
  severity: nit
  class: OPTIONAL
  location: Sources/AppShell/RootView.swift:40-46
  evidence: |
    .task {
        guard launchState == .checking else { return }
        let hasToken = await authService.hasStoredToken()
        launchState = hasToken ? .signedIn : .signedOut
    }
  rule: RUBRIC-B/task-cancellation
  required_change: "Optionally add a Task.isCancelled check (or guard !Task.isCancelled) after the await before assigning launchState. hasStoredToken() is a fast, non-throwing Keychain read that swallows errors and returns false, so a cancelled-then-resumed write is harmless in practice and cannot produce a wrong terminal state. Listed for completeness against the task-cancellation rule only."
```

## Verified clean (no findings)

- **Exactly one `AuthService`.** `private let authService = AuthService()` is
  a stored `let` on the `App` struct, not inside `var body`/a computed
  `some View`. SwiftUI instantiates the `@main` `App` struct once per
  process; `body` re-evaluation cannot re-run a stored-property
  initializer. Grep confirms one `AuthService(` hit in `Sources/AppShell/`.
  Satisfies criterion 6 and the "not constructed inside a view body"
  contract.
- **Actor isolation.** `AuthService` is a `public actor` (therefore
  `Sendable`), so passing it from `CoderApp` into `RootView.init` and
  storing it as a `let` crosses no unsafe boundary. `App` and `View`
  conformances are `@MainActor`, so `AuthService()` is constructed on the
  MainActor and `hasStoredToken()` is properly `await`ed from `.task`
  (which inherits MainActor isolation), never blocked on. `launchState` is
  written back on the MainActor after the `await`. No data race, no
  `@unchecked`, no redundant `@MainActor` annotations that would warn.
- **`.onChange` API form.** The two-parameter `{ _, newValue in }` closure
  is the iOS 17 `onChange(of:initial:_:)` signature, correct, non-deprecated
  for the iOS 17 floor. Observing the specific `Bool` property on an
  `@Observable` class is correct: the read is registered by observation
  tracking during body evaluation, so the change propagates. Observing the
  whole object is not needed and would be worse.
- **"Resolve exactly once" launch check.** `.task` is attached to the outer
  `Group`, whose identity is stable across `launchState` transitions (the
  `switch` changes content, not `Group` identity, and no `id:` is
  supplied). It will not re-run on `.checking` -> `.signedOut`/`.signedIn`.
  The `guard launchState == .checking else { return }` makes it idempotent
  even if it did. `LaunchState` is a payload-free enum, so `Equatable`/`==`
  is synthesized and the guard compiles. No flash of `LoginView` before
  resolution, satisfying criterion 5.
- **Secrets contract.** Zero `print`/`os_log`/`Logger`/`NSLog` anywhere in
  `Sources/AppShell/`. No token is stored on `CoderApp`, `RootView`, or
  `SignedInPlaceholderView`, the only value crossing from `AuthService` is
  a `Bool` (`hasToken`). `SignedInPlaceholderView` receives only the
  non-secret `serverURL` String. `LoginViewModel` still discards the token
  via `_ = try await authService.authenticate(...)` and stores no token
  property. Criteria 9 and 15 satisfied.
- **No force unwraps / force casts.** Grep for `!`, `as!`, `try!` in
  `Sources/AppShell/` returns nothing. Criterion 16 satisfied. (The `!`
  occurrences in `LoginViewModelTests.swift` are pre-existing test-only
  `URL(string:)!` matching the established suite style, which the spec
  permits.)
- **No retain cycles.** No closure in `Sources/AppShell/` captures `self`,
  `RootView` is a struct, and the `.task`/`.onChange` closures capture the
  struct's stored `let` and `@State` projections, not a class instance. No
  delegates.
- **`LoginViewModel` diff is additive-only and honors the frozen surface.**
  One new member `public private(set) var isAuthenticated: Bool = false`;
  reset next to the existing `errorMessage = nil`; set `true` only on the
  success path after `authenticate` returns without throwing. `init` and
  `login()` signatures unchanged, `isLoading` semantics unchanged, error
  strings unchanged. The stale "Note: Navigation..." comment is gone,
  replaced by behavior-describing text. No `#if canImport(SwiftUI)` guard
  added, so the file still compiles on Linux. Criteria 7, 8, 9 satisfied.
- **Tests.** The eight existing tests are byte-identical and unmodified;
  six new `@Test` cases are appended in the existing Swift Testing
  `@Suite`/`@MainActor struct` style, using only CoderAuth's shipped mocks
  and the Linux-compilable `AuthService(webAuthSession:keychainStore:)`
  initializer. Coverage matches all five required cases including reset
  semantics. `MockWebAuthSessionProvider` is `Sendable` with
  `NSLock`-guarded state, so mutating it from the `@MainActor` test body is
  race-free. Criterion 10 satisfied.
- **`LoginView.swift` untouched.** File content matches the frozen contract
  exactly; no changes, so the spec's "stop and justify" clause is not
  triggered.
- **Availability.** Neither `CoderApp` nor `RootView` carries a redundant
  `@available(iOS 17.0, *)`. Correct given the project's iOS 17 floor.
  Avoids the TASK-015 unnecessary-availability-gate finding pattern.
- **Structure/scope.** `Sources/AppShell/` at repo root contains exactly
  `CoderApp.swift`, `RootView.swift`, `Info.plist`, matching `project.yml`.
  Exactly one `@main` and one `WindowGroup`; no `UISceneDelegate`,
  `UIApplicationDelegate`, or multi-scene keys. `SignedInPlaceholderView`
  correctly lives inside `RootView.swift`. All AppShell types are
  `internal`. No import of CoderKit/TerminalFeature/WebAppFeature.
  `project.yml` unmodified.
- **`Info.plist`.** Well-formed XML with all nine required keys including
  `UILaunchScreen` as an empty dict and the three orientations. No
  entitlements-requiring keys, no privacy-usage strings. Criterion 14
  satisfied.

## Note on unverifiability

Consistent with the spec's environment section, `Sources/AppShell/` was
never compiled: no `Package.swift` (correctly not invented), no XcodeGen,
no Apple SDK, and `AuthService()`'s zero-arg init does not exist as a
symbol on Linux. This assessment of those three files is manual reasoning
only. Before merge, an Apple-toolchain run must execute
`xcodegen generate`, then
`xcodebuild -scheme CoderApp -destination 'platform=iOS Simulator,name=iPhone 15' build`,
then the three-branch launch smoke test (fresh install -> LoginView;
successful login -> placeholder; relaunch -> placeholder without
re-login).

All four findings are OPTIONAL (minor/nit). None is a security
vulnerability, data race, actor-isolation violation, or architectural
defect. No blockers, no majors.

VERDICT: APPROVE
