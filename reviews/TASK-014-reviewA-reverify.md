# Re-verification TASK-014 — Reviewer A (remediation iteration 1)

Files read in full (current working-tree state):
- Modules/WebAppFeature/Sources/VNCWebView.swift
- Modules/WebAppFeature/Sources/VNCWebViewModel.swift
- Modules/WebAppFeature/Sources/CookieInjector.swift
- Modules/WebAppFeature/Sources/VSCodeWebView.swift
- Modules/WebAppFeature/Tests/VNCCookieInjectionTests.swift

Diff inspected via `git diff HEAD` (working tree vs last commit) to isolate
exactly what the fixer changed in this remediation pass.

## Gate results (this session)

- `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` — PASS, zero warnings.
- `swift test --package-path Modules/WebAppFeature` — PASS, 25/25 (same count
  as before remediation; expected on Linux per the task framing, since
  `#if canImport(WebKit)` bodies including the five new WebKit-gated tests
  compile away here — see standing B1 caveat, not re-litigated below).
- `swiftlint lint --strict` on the five target files — 0 violations.
- `swift-format lint -r` on the five target files — exits 0 (indentation
  warnings only, identical class of pre-existing module-wide style mismatch
  noted in the original adjudication, not a regression).

## Finding-by-finding disposition

### B2: uncancelled cookie-injection Task outliving cleanup() — RESOLVED

`VNCWebViewModel` gained `var injectionTask: Task<Void, Never>?`
(VNCWebViewModel.swift:35). `VNCWebView.swift:53` now assigns
`viewModel.injectionTask = Task { @MainActor [viewModel] in ... }`, and
`cleanup()` (VNCWebViewModel.swift:76-85) does
`injectionTask?.cancel(); injectionTask = nil` before tearing down the web
view. Inside the task body, both the failure path (line 63) and the
success path (line 68) now `guard !Task.isCancelled else { return }` before
calling `handleNavigationError` or `webView.load(request)`. A dismissed view
can no longer have a cookie-injection task silently complete and start a
network load after `cleanup()` runs. This directly matches the required
change ("Store the Task handle..., cancel it in cleanup(), and check
Task.isCancelled after the await before webView.load(request)").

Residual note (not a new blocker): the local `webView` variable is still
strongly captured by the closure, so a cancelled-but-still-in-flight
`await CookieInjector.injectCookies` call can keep the WKWebView alive
slightly longer and still write the cookie into its store before the
cancellation check is reached. This is a materially smaller issue than the
original defect (no unauthenticated load fires, no misleading UI state) and
was not what B2's required_change asked for verbatim (it asked for the
Task handle + cancellation guard before `load`, which is exactly what was
delivered). Not re-opening as REQUIRED; logging as OPTIONAL below.

### B6: unsafe Coordinator.deinit touching MainActor state — RESOLVED

`Coordinator.deinit` (VNCWebView.swift:110) is now an empty body with a
comment explaining that weak-ref cleanup is unnecessary and that real
teardown happens in `cleanup()`. The nonisolated deinit no longer touches
`webView?.stopLoading()` / `webView?.navigationDelegate = nil`, which were
the MainActor-only UIKit calls flagged as unsound. Matches the required
change exactly.

### B3: swallowed cookie-injection failure (unauthenticated load on failure) — RESOLVED

`CookieInjector.injectCookies` (CookieInjector.swift:88-96) is now
`async throws`, throwing `CookieInjectionError.invalidURL` (new enum,
CookieInjector.swift:6-9) instead of silently returning on a bad URL.
`VNCWebView.swift:60-66` wraps the call in `do/catch`, calling
`viewModel.handleNavigationError(error)` and `return`-ing before reaching
`webView.load(request)` on failure. The VNC URL is no longer loaded
unauthenticated when injection fails. Matches the required change.

### B4: no HTTPS scheme validation before minting a Secure cookie — RESOLVED

`CookieInjector.cookieProperties` (CookieInjector.swift:51) now has
`guard url.scheme?.lowercased() == "https" else { return nil }` before
building the cookie properties dictionary, so `makeCookie`/`injectCookies`
fail closed (and now throw, per B3's fix) for non-HTTPS targets. Doc
comment updated to explain the rationale. Matches the required change.

### A1: missing test coverage for CookieInjector.injectCookies against a cookie store for VNC — RESOLVED

New test `injectCookiesStoresSessionCookie` (VNCCookieInjectionTests.swift:95-110)
constructs a real `WKWebView`, calls
`try await CookieInjector.injectCookies(into: webView, for: url, token: token)`
against `https://vnc.example.com/path`, then reads back
`webView.configuration.websiteDataStore.httpCookieStore.allCookies()` and
asserts the `coder_session_token` cookie exists with the correct value and
domain. This exercises the actual async entry point wired into
`VNCWebView`, not just the pure `makeCookie`/`domain` helpers, closing the
gap identified in A1. A companion test,
`injectCookiesThrowsForInvalidURL` (lines 112-124), asserts the throwing
failure path stores no cookie (`#expect(throws: CookieInjectionError.self)`
+ empty `allCookies()`), which is sound Swift Testing usage matching the
API used elsewhere in the same file and in `CookieInjectorTests.swift`.
Both would compile and pass against the current `CookieInjector` signature
(`async throws`) on a real Apple SDK.

### A2: missing test coverage for VNCWebView(url:token:) construction — RESOLVED

New test `viewCreationWithToken` (VNCCookieInjectionTests.swift:149-156)
constructs `VNCWebView(url: url, token: "test-token")` and forces
`_ = view.body` to materialize the view, matching the
`VNCWebView.init(url:token:)` signature
(`public init(url: URL, token: String? = nil)`), so it compiles against
the current initializer. This exercises the actual token-carrying
initializer/integration surface the task modifies, which previously had
zero direct construction test.

Also present (folds in optional B8 as noted in the adjudication): a new
test `injectionPrecedesLoad` (lines 126-147) asserts the cookie is visible
in the store immediately after `injectCookies` completes and before any
load would be issued, with an honest comment explaining that
`UIViewRepresentable.makeUIView` itself cannot be invoked outside SwiftUI
rendering, so this is an approximation of the real ordering contract
rather than a true end-to-end test of `makeUIView`. Reasonable given the
constraint; does not block A1/A2 closure.

## VSCodeWebView.swift change-scope check

`git diff HEAD -- Modules/WebAppFeature/Sources/VSCodeWebView.swift` shows
exactly one hunk: the call site adapts to `injectCookies`'s new `async
throws` signature with a `do/catch` that forwards the error to
`viewModel.handleNavigationError(error)` and returns, mirroring
VNCWebView's fix at the source level (not applying VNCWebView's Task-handle
storage/cancellation logic, since VSCodeWebViewModel has no
`injectionTask` property and TASK-014 does not license touching VS Code
Web beyond the forced signature change). No other changes to this file.
This is the minimal forced change and stays in scope.

## New findings introduced by remediation

```yaml
- id: A5
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:53,61,77
  evidence: |
    viewModel.injectionTask = Task { @MainActor [viewModel] in
        ...
        try await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
        ...
        guard !Task.isCancelled else { return }
        ...
        webView.load(request)
    }
  rule: RUBRIC-A/race-conditions
  required_change: >
    The closure still strongly captures the local `webView` (only `viewModel`
    is added to the capture list). If cleanup() cancels the task while the
    `await CookieInjector.injectCookies(...)` call is already in flight, the
    cancellation is not observed until the next `guard !Task.isCancelled`
    check, so the cookie write itself is not interrupted (WKHTTPCookieStore.
    setCookie has no cancellation-aware overload). This no longer causes an
    unauthenticated/misleading load (the real defect B2 targeted, now fixed),
    but a torn-down webView can still receive a late cookie write. Consider
    also weakly capturing webView or checking Task.isCancelled immediately
    before calling injectCookies, purely as defense in depth. Not blocking;
    does not reopen B2 since B2's required_change is fully satisfied.
```

No other new REQUIRED or OPTIONAL issues found. Nothing in the diff
reintroduces logging of the token, reintroduces force-unwraps in production
code, or regresses concurrency-checked build cleanliness.

## Standing caveat (unchanged, not re-litigated)

B1 (Linux sandbox gate validity for `#if canImport(WebKit)` code) remains
an environment limitation outside the fixer's control, per the
adjudication. The new WebKit-gated tests are logically sound Swift that
would compile and pass on a real Apple SDK given the current
`CookieInjector`/`VNCWebView` implementations (verified by reading the
signatures and API usage directly), but this reviewer cannot execute them
in this sandbox. This does not block this re-verification's disposition
of A1/A2, which is about whether the tests are meaningful and correct, not
whether they ran here.

## Overall disposition

All six assigned REQUIRED findings (B2, B6, B3, B4, A1, A2) are RESOLVED
with code-level evidence, and the fix is properly scoped (VSCodeWebView.swift
touched only for the forced signature adaptation). One new OPTIONAL/minor
finding (A5) logged, not blocking.

VERDICT: APPROVE
