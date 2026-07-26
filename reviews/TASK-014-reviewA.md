# Review TASK-014 — Reviewer A

## Scope note
Bulk of the implementation (VNCWebView.swift cookie-injection wiring,
VNCWebViewModel.swift token plumbing, Tests/VNCCookieInjectionTests.swift)
predates this session and had not been previously reviewed. This session
only added two style/gate fixes (trailing whitespace in VNCWebView.swift,
trailing comma + en-dash removal in CookieInjector.swift). Review covers
the full current state of all four files against the TASK-014 spec.

## Gate results (run in this session)
- `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` — PASS, zero warnings.
- `swift test --package-path Modules/WebAppFeature` — PASS, 25/25 tests green.
- `swiftlint lint --strict Modules/WebAppFeature` — FAILS (exit 2), but all 34
  violations are in pre-existing files untouched by this task
  (`KeyboardShortcutHandlerTests.swift`, `Package.swift`, `.build/` derived
  sources). Confirmed via `git stash` that this gate also failed identically
  before this session's changes — not a regression introduced by TASK-014.
  Zero violations in `VNCWebView.swift`, `VNCWebViewModel.swift`,
  `CookieInjector.swift`, or `VNCCookieInjectionTests.swift`.
- `swift-format lint -r Modules/WebAppFeature` — exits 0 (warnings only, no
  errors); warnings are indentation-style mismatches (2-space vs 4-space)
  present across the whole module, not specific to this task's files.
- Note: this sandbox is Linux; `#if canImport(WebKit)` / `#if canImport(os)`
  blocks (all of VNCWebView.swift's UIKit/WebKit code and the os_log calls)
  are never compiled or exercised here. Only macOS/iOS CI can validate that
  code path compiles and the tests inside `#if canImport(WebKit)` in
  VNCCookieInjectionTests.swift actually run.

## REQUIRED Findings

```yaml
- id: A1
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Tests/VNCCookieInjectionTests.swift (whole file)
  evidence: |
    #if canImport(WebKit)
        @Test("CookieInjector creates valid cookie for VNC URL")
        func cookieInjectorCreatesCookie() { ... CookieInjector.makeCookie(...) ... }
    #endif
  rule: RUBRIC-A/tests-meaningful (spec: "Test requirements: Mock WKHTTPCookieStore for testing")
  required_change: >
    The task spec explicitly requires a "Mock WKHTTPCookieStore for testing"
    and coverage of "cookie injection before navigation." The test file never
    calls CookieInjector.injectCookies(into:for:token:) (the actual async
    entry point wired into VNCWebView) against any cookie store, mock or
    real — it only tests the pure helpers makeCookie/domain, which were
    already covered by CookieInjectorTests.swift from TASK-012. Add a test
    that reuses the existing MockHTTPCookieStore (or a WKWebView with a real
    WKHTTPCookieStore) and asserts injectCookies() actually stores the
    coder_session_token cookie for a VNC URL, matching the pattern already
    established in CookieInjectorTests.swift:143-158.

- id: A2
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Tests/VNCCookieInjectionTests.swift and Modules/WebAppFeature/Tests/VNCWebViewTests.swift
  evidence: |
    // VNCWebViewTests.swift:143
    let view = VNCWebView(url: url)
    // no test anywhere constructs VNCWebView(url:token:) or exercises
    // WebViewRepresentable.makeUIView's `if let token = viewModel.token { Task { ... } }` branch
  rule: RUBRIC-A/acceptance-criteria (AC2 "Integrates cookie injection into VNCWebView initialization", AC6 "Unit tests verify cookie injection integration")
  required_change: >
    Add at least a construction-level test for VNCWebView(url:token:) (mirroring
    CookieInjectorTests.swift:196-202's "View can be created with a URL and
    token" for VSCodeWebView) so the token-carrying initializer path that
    TASK-014 actually modifies is exercised at all, not just VNCWebViewModel
    in isolation. Better: since UIViewRepresentable.makeUIView cannot easily
    be invoked outside of SwiftUI rendering, at minimum add the construction
    test; ideally note in a comment why deeper integration coverage isn't
    feasible (matching the honest limitation already accepted for TASK-012 in
    reviews/TASK-012-adjudication.md A2/B4).
```

## OPTIONAL Findings

```yaml
- id: A3
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:52-70
  evidence: |
    if let token = viewModel.token {
        Task { @MainActor in
            ...
            await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
            ...
            webView.load(request)
        }
    }
  rule: RUBRIC-A/race-conditions
  required_change: >
    The unstructured Task is never stored or cancelled. If the view
    disappears (triggering viewModel.cleanup(), which nils out
    navigationDelegate and calls stopLoading()) while injection is still
    in-flight, the task will still call webView.load(request) afterward on a
    torn-down web view. This mirrors an already-accepted OPTIONAL finding
    (B2) from TASK-012's adjudication for the identical pattern in
    VSCodeWebView.swift, so not blocking here either, but flagging for
    consistency since it was copied verbatim into new code.

- id: A4
  severity: nit
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:55,63
  evidence: |
    os_log(.info, "Starting cookie injection for VNC")
    os_log(.info, "Cookie injection complete, loading VNC session")
  rule: RUBRIC-A/documentation
  required_change: >
    No functional issue (matches existing os_log usage precedent in
    TerminalFeature). Consider using a single shared logger category, since
    both VSCodeWebView.swift and VNCWebView.swift now duplicate an
    ad-hoc "canImport(os)/print fallback" logging block. Not blocking.
```

## Acceptance criteria checklist
1. Compiles under Swift 6 strict concurrency, zero warnings — PASS (verified).
2. Integrates cookie injection into VNCWebView initialization — PASS (code present, but see A2 for test gap).
3. Injects session token as `coder_session_token` cookie before navigation — PASS; `webView.load(request)` is only called after `await CookieInjector.injectCookies(...)` completes.
4. Handles cookie injection asynchronously — PASS (`async`/`await`, unstructured `Task`).
5. Logs errors if injection fails without exposing token — PASS; `CookieInjector.injectCookies` logs `"Failed to create cookie, invalid URL"` with no token value; VNCWebView-level logs also omit token.
6. Unit tests verify cookie injection integration — PARTIAL / FAIL, see A1/A2: no test actually invokes `injectCookies()` for VNC, nor constructs `VNCWebView(url:token:)`.
7. No secrets logged or exposed in error messages — PASS; explicit tests assert token absence from error messages (`tokenNotExposedInErrors`, `noSecretsExposed`).

## Contract check (CookieInjector reuse, TASK-012 contract)
`CookieInjector.injectCookies(into:for:token:)` signature and behavior are
used identically to VSCodeWebView.swift's integration — no re-litigation of
TASK-012's design needed. Usage in VNCWebView.swift is contract-conformant.

## Summary
Core implementation (cookie injection wiring, async ordering, non-exposure
of secrets) is correct and matches TASK-012's established CookieInjector
contract. Build and full test suite are green. However, the test file
required by this task's own spec ("Mock WKHTTPCookieStore for testing...
Cover: cookie injection before navigation") does not actually test cookie
injection — it re-tests `CookieInjector.makeCookie`/`domain`, which were
already tested in TASK-012's `CookieInjectorTests.swift`. No test exercises
`injectCookies()` against a cookie store (mock or real) in a VNC context, and
no test constructs `VNCWebView(url:token:)`, meaning the actual new
integration surface introduced by this task has no direct test coverage.
This is a real acceptance-criterion gap (AC6), not just a style nit.

VERDICT: REQUEST_CHANGES
