---
id: TASK-016
title: AppShell bootstrap — @main entry point, Info.plist, and login/post-login root composition
phase: 5
module: AppShell
depends_on: []
blocks: []
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-016-appshell-bootstrap
---

> **Orchestrator: confirm the dependency-graph frontmatter.** `depends_on: []`,
> `blocks: []`, `parallel_safe_with: []`, and the worktree name are proposed
> defaults from the spec-writer, not authoritative. `depends_on: []` is proposed
> because this task only *reads* from already-COMPLETE modules (CoderAuth,
> CoderUI) and creates a brand-new directory. `blocks: []` is a placeholder:
> in practice every remaining Phase 5 task (multi-window/`UIScene`, Stage
> Manager, external display, privacy screen, clipboard/file bridges, settings,
> icon/launch) depends on this one, because none of them have an app to attach
> to until it lands. Populate `blocks` once those tasks are numbered.

## Goal
Create the missing iOS app target sources at `Sources/AppShell/` so the
`CoderApp` target declared in `project.yml` can actually build and launch:
a `@main` SwiftUI `App` with one `WindowGroup` that checks the Keychain for an
existing session token at launch and shows either `LoginView` or a minimal
placeholder "signed in" screen. This is a **bootstrap prerequisite** for Phase 5,
not Phase 5 itself.

## Background the implementer needs (read this, do not redesign it)

### 1. The missing-AppShell discovery
`PROGRESS.md` lists Phase 0 ("Scaffolding") as `TASK-001 ✅ COMPLETE`, but no
`tasks/TASK-001.md` spec file exists and, more importantly, **the app it was
supposed to scaffold does not exist**. Verified facts as of this spec:

- `/persistent/workspaces/coder/project.yml` is a valid XcodeGen config
  declaring an application target `CoderApp` with
  `sources: [{ path: Sources/AppShell }]` and
  `INFOPLIST_FILE: Sources/AppShell/Info.plist`.
- There is **no `Sources/` directory at the repo root at all.** A glob for
  `Sources/**` returns nothing. Both the source directory and the `Info.plist`
  that `project.yml` points at are absent.
- A repo-wide grep for `@main`, `WindowGroup`, `UIApplicationDelegate`, and
  `UISceneDelegate` finds **zero hits in first-party source**. Every hit is
  either inside a `.build/` checkout of a third-party dependency (SwiftTerm's
  own demo `AppDelegate.swift`, swift-argument-parser samples), a `.build/`
  derived test runner, `PROGRESS.md` prose, or unrelated `site/` TypeScript.
- Phases 0-4 produced five isolated SPM library packages under `Modules/`
  (CoderKit, CoderAuth, TerminalFeature, WebAppFeature, CoderUI), each with its
  own `Package.swift` and tests. **Nothing composes them.** There is no DI
  wiring, no entry point, no scene.

So: `xcodegen generate` against the current tree would produce a target whose
source path does not exist. This task creates exactly the missing pieces.

### 2. Why this is a bootstrap, not Phase 5
`PLAN.md`'s Phase 5 scope is "Multi-window UIScene, Stage Manager, external
display; privacy screen on background; clipboard/file bridges; error/offline
states; settings; icon/launch." Every one of those is a *modification to an
existing app*. None can be specified or implemented against a repo with no app.
This task's job is only to get a minimal, buildable, launchable app on screen.
Resist scope creep hard: each Phase 5 bullet becomes its own follow-on task,
and this task's diff should be small enough that those tasks can be written
against a known-good baseline.

### 3. The LoginViewModel navigation gap, and the decision made for you
`Modules/CoderUI/Sources/LoginViewModel.swift` currently ends its success path
with:

```swift
_ = try await authService.authenticate(serverURL: url)
isLoading = false
// Note: Navigation or success callback would be handled by the view
```

That comment is aspirational. The view model **discards** the token returned by
`authenticate` (note the `_ =`) and exposes no way for any caller to learn that
login succeeded. Its entire public surface today is `serverURL` (read/write),
`isLoading` (private setter), `errorMessage` (private setter), and
`login() async`. A root view observing this type cannot distinguish "never
attempted" from "succeeded" — both are `isLoading == false, errorMessage == nil`.
This gap must be closed or the app cannot navigate past the login screen.

**Decision: option (b). Add a single public, observable, private-setter
`isAuthenticated: Bool` property to `LoginViewModel`, set to `true` on the
success path.** Fold this into TASK-016 rather than splitting it into a
separate task.

Rationale, and why the alternatives lost:

- **Why not (a), a completion closure** on `init` or `login()`? `LoginViewModel`
  is `@Observable @MainActor final class ... Sendable`. Storing an escaping
  closure as a property forces it to be `@Sendable` and makes the type's
  `Sendable` conformance meaningfully harder to reason about under strict
  concurrency. It also changes an existing initializer signature that eight
  existing tests in `Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift`
  construct directly, and it pushes navigation state into a callback that
  SwiftUI cannot observe declaratively. A closure is the wrong shape for a type
  that already exists specifically to be observed.
- **Why (b) wins.** The type is already `@Observable`. Adding one more
  `public private(set) var` is the smallest possible additive change: it breaks
  no existing initializer, breaks no existing test (all eight existing tests
  construct the view model and assert on other properties; none enumerate the
  property list), needs no `Sendable` re-reasoning, and is directly consumable
  from SwiftUI via the `@Bindable`/observation the root view already uses. It is
  purely additive to the public surface.
- **Why fold it in rather than split it out.** The change is roughly three lines
  plus tests. Splitting it would create a task whose entire content is one
  property, and would force TASK-016 to serialize behind it for no benefit.
  Critically, the property is only *meaningful* in combination with the root
  view that observes it — specifying them apart would mean specifying an
  unobserved property with no consumer, which is exactly the kind of
  "built in isolation, never assembled" failure that produced this whole
  situation. The two ship together.

Constraints on the change: it is **additive only**. Do not change `login()`'s
signature, do not change `init`'s signature, do not change the existing error
strings or `isLoading` semantics, do not remove or repurpose `errorMessage`,
and do not start storing the token in the view model (the token is already
persisted to the Keychain by `AuthService.authenticate`; duplicating it into a
UI-layer object would put a secret somewhere it does not belong). Set
`isAuthenticated = true` only on the success path, and reset it to `false` at
the top of `login()` alongside the existing `errorMessage = nil` clear, so a
retry after a prior success cannot leave a stale `true`.

### 4. What CoderAuth already gives you (do not reinvent it)
`Modules/CoderAuth/Sources/AuthService.swift` is an `actor` and already exposes
everything the launch-state check needs. **Use these; do not touch the Keychain
directly from AppShell.**

- `public func hasStoredToken() async -> Bool` — non-throwing, returns `false` on
  any keychain error. This is exactly the launch-time check. Use it.
- `public func authenticate(serverURL: URL) async throws -> String` — returns the
  session token and has already written it to the Keychain under
  `KeychainKeys.sessionToken` before returning.
- `public func getStoredToken() async throws -> String` and
  `public func signOut() async throws` also exist. You do not need them for this
  task's minimal scope; do not add a sign-out button (that is settings work).

`AuthService`'s initializer is `#if`-split. On Apple platforms
(`canImport(Security) && canImport(AuthenticationServices)`) there is an
`@available(iOS 17.0, macOS 14.0, *)` init where **every parameter has a
default** (`ASWebAuthSessionProvider()`, `SystemKeychainStore()`,
`BiometricAuthenticator()`, `enableBiometrics: false`). So AppShell constructs
it as plain `AuthService()`. On non-Apple platforms (this Linux sandbox) that
zero-argument init **does not exist** — the `#else` branch requires
`webAuthSession:` and `keychainStore:` explicitly. This matters for what can be
compiled here; see the acceptance criteria.

`Modules/CoderAuth/Sources/KeychainManager.swift` provides the `KeychainStoring`
protocol, `KeychainKeys.sessionToken`, `SystemKeychainStore` (Apple-only, behind
`#if canImport(Security)`), and `InMemoryKeychainStore` (all platforms, for
tests).

### 5. What CoderUI gives you
The **only** SwiftUI screen that exists in the entire repo is
`Modules/CoderUI/Sources/LoginView.swift`:

```swift
@available(iOS 17.0, macOS 14.0, *)
public struct LoginView: View {
    public init(viewModel: LoginViewModel)
}
```

The whole file is wrapped in `#if canImport(SwiftUI)`. There is no workspace
list view, no workspace detail view, no navigation container, no tab bar, no
theme. `Modules/CoderKit/Tests/WorkspaceListTests.swift` tests *data* logic
only; grep confirms no `: View` type exists anywhere in `Modules/CoderKit/Sources`.
**This is why the post-login destination in this task is an explicit
placeholder** — there is nothing to route to yet, and building a workspace list
here would be unscoped feature work.

## In scope (files this task MAY create/modify)

New app-target sources at the repo root (**not** under `Modules/`):

- `Sources/AppShell/CoderApp.swift` (new) — the `@main` `App` struct and its
  single `WindowGroup`.
- `Sources/AppShell/RootView.swift` (new) — the root view that owns launch-state
  resolution and switches between login and the placeholder.
- `Sources/AppShell/SignedInPlaceholderView.swift` (new) — the minimal
  post-login screen. May instead live inside `RootView.swift` if it stays
  trivial; do not create a file to hold four lines.
- `Sources/AppShell/Info.plist` (new) — minimal plist satisfying
  `project.yml`'s `INFOPLIST_FILE`.

Minimal additive change to existing CoderUI files:

- `Modules/CoderUI/Sources/LoginViewModel.swift` (modify) — add
  `public private(set) var isAuthenticated: Bool = false`, set it on the success
  path, reset it at the top of `login()`. Nothing else.
- `Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift` (modify) — add
  test cases for the new property. **Do not edit or delete the eight existing
  tests.** Note the real on-disk test path is
  `Tests/CoderUITests/`, matching `Package.swift`'s
  `path: "Tests/CoderUITests"` for the test target — *not* the flat `Tests/`
  layout some other modules use.

Optional, only if warranted:

- `Modules/CoderUI/Sources/LoginView.swift` (modify) — **only** if the chosen
  root-view composition genuinely requires it. It should not: `LoginView` takes
  a `LoginViewModel` and the root view can observe that same instance directly.
  If you find yourself editing `LoginView.swift`, stop and justify it in the
  summary.

## Explicitly OUT of scope (do NOT touch)

- Multi-window `UIScene` support, `UISceneDelegate`, Stage Manager, external
  display handling. One plain `WindowGroup` only.
- Privacy screen on backgrounding (blur/obscure on resign-active).
- Clipboard bridges and file bridges.
- A settings screen (and therefore: no sign-out button, no biometrics toggle).
- App icon and launch screen visual design. A default/absent icon is fine; do
  not commission or generate icon art, and do not add an asset catalog full of
  placeholder images.
- Any workspace-list UI, workspace-detail UI, or terminal/VS Code/VNC screen
  wiring. `TerminalFeature` and `WebAppFeature` are complete modules but this
  task does **not** route to them. `project.yml` already lists them as target
  dependencies; leave that alone and simply do not import them from AppShell.
- Any change to `Modules/CoderAuth/**` — `AuthService.swift`,
  `KeychainManager.swift`, `WebAuthSession.swift`, `BiometricAuth.swift`,
  `AuthError.swift` are **read-only dependencies** for this task.
- Any change to `Modules/CoderKit/**`, `Modules/TerminalFeature/**`, or
  `Modules/WebAppFeature/**`.
- Any change to `project.yml`, any `.xcodeproj`/`.pbxproj`, or any
  `Package.swift`. **If, after reading `project.yml`, you conclude it is wrong
  or incomplete for what this task needs to build, do NOT silently fix it.**
  Report it in your summary and stop. `project.yml` changes are cross-cutting
  and affect every parallel worktree, so they are orchestrator-owned. (For
  reference, the spec-writer read `project.yml` and believes it is already
  correct and sufficient for this task: it declares the app target, the iOS 17
  deployment target, `SWIFT_VERSION: 6.0`,
  `SWIFT_STRICT_CONCURRENCY: complete`, the bundle id `com.coder.ios`, all five
  package dependencies, and the two paths this task creates. The one thing
  worth a second look is that all five packages are declared as target
  dependencies while this task only needs CoderAuth and CoderUI — that is
  harmless over-declaration, not an error, and must not be "cleaned up" here.)
- Repo hygiene debt: the tracked `.build/` directories and the missing
  `.swiftlint.yml`. See `PROGRESS.md`'s "Known Repo Hygiene Debt"; that is its
  own task.
- Backfilling a `tasks/TASK-001.md` for whatever Phase 0 was supposed to be.

## Contracts / interfaces it MUST honor

**How AppShell may touch each module:**

| Module | Allowed from AppShell |
|---|---|
| `CoderAuth` | Import and consume read-only: construct one `AuthService()`, call `hasStoredToken()`. No source changes. |
| `CoderUI` | Import and consume `LoginView` / `LoginViewModel`. May add the one additive property described above. |
| `CoderKit` | Do not import. No workspace UI in this task. |
| `TerminalFeature` | Do not import. |
| `WebAppFeature` | Do not import. |

**New public API this task may add.** Exactly one symbol, in CoderUI:

```swift
// Modules/CoderUI/Sources/LoginViewModel.swift
public private(set) var isAuthenticated: Bool = false
```

No other new public API in CoderUI. Everything in `Sources/AppShell/` belongs to
an application target, not a library, so its types should be `internal` (the
default). The only exception is the `@main` `App` struct, which is `internal`
too — do not mark AppShell types `public`.

**Frozen surface that must not change:**

```swift
public struct LoginView: View {
    public init(viewModel: LoginViewModel)
}

@Observable @MainActor public final class LoginViewModel: Sendable {
    public var serverURL: String
    public private(set) var isLoading: Bool
    public private(set) var errorMessage: String?
    public init(authService: AuthService)
    public func login() async
}
```

`git diff` must show no change to any of those declarations — only the addition
of the new property and its two assignments.

**Concurrency and platform contracts:**

- Swift 6, strict concurrency complete, zero warnings.
- The `App` struct and all views are `@MainActor` (SwiftUI's `App` and `View`
  conformances already imply this; do not add redundant annotations that
  produce warnings).
- `AuthService` is an `actor`. Calls into it are `async` and must be `await`ed
  from a `Task`/`.task` modifier, not blocked on.
- Exactly **one** `AuthService` instance is constructed, at the app root, and
  passed down. Do not construct a second one inside a view body (view bodies
  re-run; constructing an actor there is a bug). Hold it in a `let` on the `App`
  struct or in an `@State`-held object created once.
- iOS 17 floor. Do not add `if #available(...)` gates for APIs already satisfied
  by iOS 17 — unnecessary availability checks are a review finding (this was
  called out in TASK-015 review).
- The `LoginViewModel` change must keep the file compiling on Linux. That file
  has no `#if canImport(SwiftUI)` guard today (it imports `Foundation`,
  `Observation`, `CoderAuth`) and must not gain one.

**Launch-state contract for `RootView`:**

Model the root state as a small three-case enum, e.g.

```swift
private enum LaunchState {
    case checking
    case signedOut
    case signedIn
}
```

- Start in `.checking` and render a neutral placeholder (a `ProgressView` is
  fine). Do **not** flash `LoginView` before the Keychain check resolves.
- Resolve once, in a `.task { }` on the root view, by awaiting
  `authService.hasStoredToken()`. `true` → `.signedIn`, `false` → `.signedOut`.
- When `.signedOut`, render `LoginView(viewModel:)` with the single long-lived
  `LoginViewModel`, and transition to `.signedIn` when that view model's
  `isAuthenticated` becomes `true`.
- When `.signedIn`, render the placeholder signed-in screen.
- Do not re-run the Keychain check on every appearance; once is enough for this
  task.

**Secrets contract:** the session token must never be logged, never rendered on
screen, and never stored in a view or view model. The signed-in placeholder
shows only that the user is signed in — for example the text "Signed in" and,
at most, the non-secret server URL the user typed. **Never display or log the
token or any prefix/suffix of it.**

## Acceptance criteria (each must be machine- or reviewer-verifiable)

1. `Sources/AppShell/` exists at the **repo root** (not under `Modules/`) and
   contains, at minimum, one Swift file declaring `@main` and an `Info.plist`.
   Verifiable: `ls Sources/AppShell/` and `grep -r '@main' Sources/AppShell/`.
2. The paths match `project.yml` exactly: sources at `Sources/AppShell` and the
   plist at `Sources/AppShell/Info.plist`. A reviewer can diff the two path
   strings against `project.yml` lines 20 and 29.
3. Exactly one `@main` type exists in first-party source. Verifiable:
   `grep -rn '@main' Sources/ Modules/*/Sources/` returns exactly one hit.
4. Exactly one `WindowGroup` is declared. No `UISceneDelegate`,
   `UIApplicationDelegate`, `UIApplicationSceneManifest` multi-scene config, or
   `supportsMultipleScenes` anywhere in the diff. Verifiable by grep.
5. `RootView` implements the three-state launch contract above: a reviewer can
   point at the `.checking` initial state, the single `.task`-driven
   `await authService.hasStoredToken()` call, and both destination branches.
   Rendering `LoginView` unconditionally before the check resolves fails this.
6. Exactly one `AuthService` is constructed in `Sources/AppShell/`. Verifiable:
   `grep -rn 'AuthService(' Sources/AppShell/` returns exactly one hit, and it
   is not inside a `var body` / `some View` computed property.
7. `LoginViewModel` gains exactly one new public member,
   `public private(set) var isAuthenticated: Bool`, defaulting to `false`. The
   `git diff` for `LoginViewModel.swift` shows only: the property declaration,
   an `isAuthenticated = false` reset near the existing `errorMessage = nil`
   clear at the top of `login()`, an `isAuthenticated = true` on the success
   path, and doc comments. No signature changes to `init` or `login()`.
8. The `// Note: Navigation or success callback would be handled by the view`
   comment is replaced or removed, since it no longer describes the code. Its
   replacement (if any) describes behavior, not change history.
9. The token is still discarded by `LoginViewModel` — the success path does not
   begin storing the returned `String` on the view model. Verifiable by reading
   the diff.
10. All eight existing tests in `LoginViewModelTests.swift` are unmodified.
    Verifiable: the diff for that file is additive only (new `@Test` cases
    appended), with zero deletions inside the existing test bodies.
11. `swift build --package-path Modules/CoderUI -Xswiftc -strict-concurrency=complete`
    is clean and `swift test --package-path Modules/CoderUI` is green, including
    the new `isAuthenticated` tests. **This is the primary machine gate for this
    task's logic change** (see the environment caveat below).
12. The four untouched modules still build: `swift build --package-path
    Modules/<M> -Xswiftc -strict-concurrency=complete` for CoderKit, CoderAuth,
    TerminalFeature, WebAppFeature. Since this task must not change them, this is
    a regression check that the diff leaked nothing.
13. `git diff --stat` shows changes confined to `Sources/AppShell/**`,
    `Modules/CoderUI/Sources/LoginViewModel.swift`, and
    `Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift` (plus
    `LoginView.swift` only with the written justification required above). Zero
    changes to `project.yml`, any `Package.swift`, any `.xcodeproj`/`.pbxproj`,
    or any file under `Modules/CoderAuth/`, `Modules/CoderKit/`,
    `Modules/TerminalFeature/`, `Modules/WebAppFeature/`.
14. `Info.plist` is minimal and valid: it declares at least
    `CFBundleDevelopmentRegion`, `CFBundleExecutable`
    (`$(EXECUTABLE_NAME)`), `CFBundleIdentifier`
    (`$(PRODUCT_BUNDLE_IDENTIFIER)`), `CFBundleName` (`$(PRODUCT_NAME)`),
    `CFBundlePackageType` (`$(PRODUCT_BUNDLE_PACKAGE_TYPE)`),
    `CFBundleShortVersionString`, `CFBundleVersion`,
    `UILaunchScreen` (an empty dict is acceptable and is what makes a
    storyboard-free SwiftUI app launch full-screen on iOS 17), and
    `UISupportedInterfaceOrientations`. It declares **no entitlements-requiring
    keys and no privacy-usage strings**, because nothing in Phases 0-4 requested
    any capability that needs one. It is well-formed XML (verifiable with
    `python3 -c "import plistlib,sys; plistlib.load(open(sys.argv[1],'rb'))" Sources/AppShell/Info.plist`,
    which needs no Apple tooling).
15. No secrets exposed: `grep -rin 'token' Sources/AppShell/` shows no print,
    log, or UI-text rendering of a token value. The signed-in placeholder
    displays no token material.
16. No force unwraps (`!`) in `Sources/AppShell/` production code, per the
    project's anti-patterns list. (Force-unwrapped *types* like `String!` are
    likewise out.)
17. `swiftlint lint --strict` and `swift-format lint` are clean **on the files
    this task touches** (see the DoD note about pre-existing module-wide debt).

### What is NOT verifiable in this sandbox — read this before writing gates

This is important and the implementer must not fake it. The established gates in
every prior task (`swift build --package-path Modules/<M>`, `swift test
--package-path Modules/<M>`) target **individual SPM packages under `Modules/`**.
`Sources/AppShell/` is a **new location outside `Modules/` with no
`Package.swift` of its own** — by design, because `project.yml` builds it as an
Xcode *application target*, not an SPM package. Consequences:

- **`Sources/AppShell/` cannot be compiled by `swift build` at all.** There is
  no package manifest that includes it, and this task must not add one (that
  would be `Package.swift` wiring, which is explicitly out of scope and
  orchestrator-owned). Do not invent a throwaway `Package.swift` to make a gate
  go green.
- Building it requires `xcodegen generate` followed by `xcodebuild`. **XcodeGen
  and the Apple SDK are not available in this Linux dev sandbox.** `xcodebuild`
  does not exist on Linux, and the iOS SDK, SwiftUI's `App`/`WindowGroup`,
  `Security`/`SecItem*`, and `AuthenticationServices` are all unavailable here.
- Concretely, `AuthService()` (the zero-argument form AppShell uses) **does not
  even exist as a symbol on Linux** — it lives behind
  `#if canImport(Security) && canImport(AuthenticationServices)`. So AppShell's
  code is not merely untested here, it is *uncompilable* here.

**Therefore:**

- **CAN be gate-verified in this sandbox:** the `LoginViewModel.isAuthenticated`
  change and its tests (pure logic, no SwiftUI, Linux-runnable via
  `swift test --package-path Modules/CoderUI`); the continued clean build of all
  five modules; lint/format on touched files; the `Info.plist` XML being
  well-formed; and every structural/grep-based criterion above (file paths,
  single `@main`, single `WindowGroup`, single `AuthService(`, no force
  unwraps, no token logging, diff scope).
- **CANNOT be gate-verified here and MUST NOT be demanded by any acceptance
  criterion:** `xcodegen generate` succeeding, `xcodebuild` compiling the
  `CoderApp` target, the app launching in a simulator or on device, the
  Keychain check returning anything real, the login web-auth sheet presenting,
  or any visual/interaction behavior. The AppShell Swift files in this task are
  **written but never compiled** in this environment. Treat every line of them
  as unverified until an Apple-SDK CI or macOS run happens.

The implementer MUST state plainly in the returned summary that
`Sources/AppShell/` was not compiled, and MUST list what a human/CI on an Apple
toolchain needs to run first: `xcodegen generate`, then
`xcodebuild -scheme CoderApp -destination 'platform=iOS Simulator,name=iPhone 15' build`,
then a launch smoke test of both branches (fresh install → LoginView; after a
successful login → placeholder; relaunch → placeholder without re-login).

**Standing environment caveat** (same one recorded for TASK-013/014/015): this
dev sandbox runs Linux, where `canImport(WebKit)`, `canImport(Security)`, and
`canImport(AuthenticationServices)` are all false. See `PROGRESS.md`'s
"Standing Environment Caveat" section and
`reviews/TASK-014-adjudication.md` finding B1. Also see `PROGRESS.md`'s
"Known Repo Hygiene Debt" section for why `swiftlint --strict` has never been
cleanly runnable repo-wide (tracked `.build/` directories, no `.swiftlint.yml`)
and must be scoped to this task's touched paths.

## Test requirements

- Swift Testing (`@Test` / `#expect`), matching the existing suite style in
  `Modules/CoderUI/Tests/CoderUITests/LoginViewModelTests.swift` (which uses
  `@Suite("LoginViewModel Tests") @MainActor struct`).
- New tests are **appended** to that existing file. Do not create a parallel
  file, and do not modify the eight existing test cases.
- Mock strategy: reuse the mocks CoderAuth already ships, exactly as the
  existing tests do. `AuthService(webAuthSession: MockWebAuthSessionProvider(...),
  keychainStore: InMemoryKeychainStore())` is the Linux-compilable initializer.
  `MockWebAuthSessionProvider(callbackURL:)` drives success;
  `MockWebAuthSessionProvider(error:)` drives failure. A valid success callback
  looks like `URL(string: "coder://cli-auth?session_token=test_token_12345678")`
  (the token must be ≥8 characters or `AuthService.validateToken` rejects it).
  Do not write new mocks.
- Cover, at minimum:
  1. `isAuthenticated` is `false` on a freshly constructed `LoginViewModel`.
  2. `isAuthenticated` becomes `true` after a successful `login()`.
  3. `isAuthenticated` stays `false` after a failed `login()` (use
     `MockWebAuthSessionProvider(error: AuthError.cancelled)`), and
     `errorMessage` is still populated as before.
  4. `isAuthenticated` stays `false` for the empty-URL and invalid-URL
     early-return paths (these return before `authService` is ever called).
  5. Reset semantics: after a successful `login()` sets `isAuthenticated == true`,
     a subsequent `login()` against a now-failing mock ends with
     `isAuthenticated == false`. Use `MockWebAuthSessionProvider.configure(...)`
     to flip the mock's behavior between calls.
- Do **not** write tests for anything in `Sources/AppShell/` — there is no test
  target that can compile it, and adding one would require `Package.swift` or
  `project.yml` changes that are out of scope. Say so in the summary rather than
  inventing a target.

## Definition of Done (all must be TRUE)

- [ ] `swift build --package-path Modules/CoderUI -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/CoderUI` green (existing 8 tests + new `isAuthenticated` tests)
- [ ] `swift build --package-path Modules/CoderAuth -Xswiftc -strict-concurrency=complete` clean (regression: unchanged)
- [ ] `swift build --package-path Modules/CoderKit -Xswiftc -strict-concurrency=complete` clean (regression: unchanged)
- [ ] `swift build --package-path Modules/TerminalFeature -Xswiftc -strict-concurrency=complete` clean (regression: unchanged)
- [ ] `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` clean (regression: unchanged)
- [ ] `swiftlint lint --strict Modules/CoderUI Sources/AppShell` clean **on the files this task touches**. A pre-existing, module-wide swiftlint debt unrelated to this task is tracked in `PROGRESS.md`'s "Known Repo Hygiene Debt" (tracked `.build/` derived sources and the absent `.swiftlint.yml` already fail `--strict` before this task starts). Do not fix those here; confirm via targeted-path linting that your diff introduces zero new violations.
- [ ] `swift-format lint -r Modules/CoderUI Sources/AppShell` clean (warnings-only exit is the established baseline; introduce no new errors)
- [ ] `Sources/AppShell/Info.plist` parses as valid plist XML (`python3 -c "import plistlib,sys; plistlib.load(open(sys.argv[1],'rb'))" Sources/AppShell/Info.plist`)
- [ ] `grep -rn '@main' Sources/ Modules/*/Sources/` returns exactly one hit
- [ ] Diff touches only in-scope files (verified with `git diff --stat`)
- [ ] Summary explicitly states that `Sources/AppShell/` was **never compiled** in this sandbox, and lists the Apple-toolchain commands + launch smoke test a human/CI must run
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
