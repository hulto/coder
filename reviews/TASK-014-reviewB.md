# Review TASK-014 — Reviewer B (security / concurrency / iOS architecture)

Files reviewed in full: `Modules/WebAppFeature/Sources/VNCWebView.swift`,
`Modules/WebAppFeature/Sources/VNCWebViewModel.swift`,
`Modules/WebAppFeature/Sources/CookieInjector.swift`,
`Modules/WebAppFeature/Tests/VNCCookieInjectionTests.swift`.
Cross-referenced `reviews/TASK-012-reviewB.md` (B1/B3/B4 treated as settled),
`Modules/WebAppFeature/Sources/VSCodeWebView.swift`,
`Modules/WebAppFeature/Tests/CookieInjectorTests.swift`,
`Modules/WebAppFeature/Package.swift`.

## Gate verification — NOT CONFIRMED

Reviewer had no shell in this session and could not run the build gate
directly. Every build artifact under
`Modules/WebAppFeature/.build/x86_64-unknown-linux-gnu/` is Linux. On Linux
`canImport(WebKit)` is false, and both `VNCWebView.swift` and
`CookieInjector.swift` are wrapped top-to-bottom in `#if canImport(WebKit)`.
Any previously reported green gate compiled these as empty translation
units. See B1.

## REQUIRED findings

```yaml
- id: B1
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:1 (and CookieInjector.swift:1); evidence from .build/x86_64-unknown-linux-gnu/
  evidence: "#if canImport(WebKit)   // wraps 100% of VNCWebView.swift and CookieInjector.swift"
  rule: RUBRIC-B/sendable-compliance
  required_change: "Re-run DoD gates against an Apple SDK (xcodebuild, or swift build with -Xswiftc -sdk $(xcrun --sdk iphoneos --show-sdk-path) -Xswiftc -target -Xswiftc arm64-apple-ios17.0) and attach that output. A green Linux strict-concurrency build is vacuous: canImport(WebKit) is false there, so the entire deliverable and all its WebKit tests compile away, leaving acceptance criterion 1 unproven."

- id: B2
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:52-74
  evidence: |
    if let token = viewModel.token {
        Task { @MainActor in
            await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
            let request = URLRequest(url: viewModel.url)
            webView.load(request)
        }
    }
  rule: RUBRIC-B/task-cancellation
  required_change: "Store the Task handle on VNCWebViewModel (var injectionTask: Task<Void, Never>?), cancel it in cleanup(), and check Task.isCancelled after the await before webView.load(request). onDisappear -> cleanup() nils viewModel.webView and sets navigationDelegate = nil, but this Task holds a STRONG capture of webView, so a dismissed view still gets the session token written into its cookie store and a network load started, with its navigation delegate already detached so any failure is silently swallowed. TASK-012 B2 rated the VS Code twin as minor/wasteful; combined with the delegate teardown it is a real lifecycle defect."

- id: B3
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/CookieInjector.swift:75-83
  evidence: |
    public static func injectCookies(into webView: WKWebView, for url: URL, token: String) async {
        guard let cookie = makeCookie(for: url, token: token) else {
            print("[CookieInjector] Failed to create cookie, invalid URL")
            return
        }
  rule: RUBRIC-B/error-propagation
  required_change: "Make injectCookies throwing (or return Bool/Result) and have VNCWebView.swift:60 skip webView.load(request) on failure, surfacing it via viewModel.handleNavigationError(...). Today injection silently no-ops and the code loads the VNC URL unauthenticated, so the user hits an opaque login page or 401 inside the web view with no signal that SSO failed. Criterion 5 requires logging the error; it does not license proceeding as if injection succeeded."

- id: B4
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/CookieInjector.swift:39-53
  evidence: |
    guard let host = domain(from: url) else { return nil }
    return [.name: cookieName, .value: token, .domain: host, .path: "/", .secure: true,
            HTTPCookiePropertyKey("HttpOnly"): true, HTTPCookiePropertyKey("SameSite"): "None"]
  rule: RUBRIC-B/cookie-security
  required_change: "Add `guard url.scheme?.lowercased() == \"https\" else { return nil }` before building properties. `.secure: true` marks the cookie Secure but nothing validates the target is HTTPS. VNCWebView.init(url:token:) accepts any URL and no caller validates, so an http:// VNC subdomain (dev deployment, misconfigured wildcard access URL) yields a cookie WebKit refuses to send -> silent auth failure, and SameSite=None without enforced Secure is a plaintext-exposure footgun."
```

## OPTIONAL findings

```yaml
- id: B5
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebViewModel.swift:13
  evidence: "final class VNCWebViewModel: @unchecked Sendable {   // preceded by @MainActor @Observable"
  rule: RUBRIC-B/sendable-compliance
  required_change: "Drop @unchecked Sendable. The type is @MainActor-isolated and therefore already implicitly Sendable with compiler-checked guarantees; @unchecked only disables that checking and would mask a future nonisolated mutable member. Currently safe (all members are let, private(set) under MainActor, or the MainActor-isolated weak webView), so hardening rather than a live race. Same at VSCodeWebViewModel.swift:13."

- id: B6
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:87-100
  evidence: |
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, @unchecked Sendable {
        deinit {
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView = nil
        }
  rule: RUBRIC-B/lifecycle-aware
  required_change: "deinit on a @MainActor class is nonisolated and can run on any thread, yet it touches the MainActor-isolated webView property and calls stopLoading()/mutates navigationDelegate, both main-thread-only UIKit APIs. This compiles only because @unchecked Sendable suppresses the isolation check, i.e. the annotation is hiding an unsafe deinit. Empty the deinit (a weak ref needs no manual nil-ing; WKWebView stops on dealloc) and rely on cleanup() from onDisappear for deterministic teardown. Also drop the redundant @unchecked Sendable per B5."

- id: B7
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:54-66; CookieInjector.swift:77
  evidence: |
    os_log(.info, "Starting cookie injection for VNC")
    os_log(.info, "Cookie injection complete, loading VNC session")
    print("[CookieInjector] Failed to create cookie, invalid URL")
  rule: RUBRIC-B/no-secrets-in-logs
  required_change: "No token leak: every log site was traced, the token value never reaches a format string, and error.localizedDescription (VNCWebViewModel.swift:50) carries only WebKit's message. Criteria 5 and 7 met. Hygiene only: (a) use a Logger(subsystem:category:) instance rather than top-level os_log / bare print so messages are level-filterable and do not ship to stdout in release (TASK-012 B1 recurring in new code); (b) the two .info calls bracketing injection add no diagnostic value beyond confirming the code ran, collapse to a single failure-path log."

- id: B8
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Tests/VNCCookieInjectionTests.swift:47-82
  evidence: "cookieInjectorCreatesCookie / cookieInjectorInvalidURL / cookieInjectorDomainExtraction"
  rule: RUBRIC-B/wkwebview-config
  required_change: "No test asserts TASK-014's actual contract, 'must inject cookies before WKWebView loads URL'. These three WebKit tests duplicate CookieInjectorTests.swift coverage with the host string changed from vscode. to vnc.; the ordering guarantee in VNCWebView.makeUIView is untested. Extract a testable seam (e.g. an async prepareAndLoad(webView:url:token:) on the view model) and assert injection precedes load using the existing MockHTTPCookieStore. Note these also compile away on the Linux CI (B1)."

- id: B9
  severity: nit
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:41-125 vs Sources/VSCodeWebView.swift:41-114
  evidence: "Coordinator, makeUIView cookie-injection block, and ErrorView are byte-for-byte duplicated across the two files."
  rule: RUBRIC-B/memory-management
  required_change: "Follow-up task: factor the shared WKWebView + cookie-injection + navigation-delegate scaffolding into one generic representable. B2/B3/B5/B6 each must be fixed twice today, and TASK-014 forbids touching the VS Code implementation, so the duplicated defects will drift apart. Out of scope here."
```

## Checked and clean

- Token never appears in any log, error message, or `debugDescription`. Criteria 5 and 7 hold.
- Cookie ordering is structurally correct in the happy path: `await injectCookies(...)` completes before `webView.load(request)` on the same MainActor Task, and no `load` is issued on the token path outside that Task. **There is no injection/load race.** The exposures are cancellation (B2) and injection failure (B3), not ordering.
- `viewModel.webView` and `Coordinator.webView` are both correctly `weak`.
- No Keychain access in scope (token arrives pre-fetched via `init(url:token:)`), so `kSecAttrAccessible*` is N/A, worth confirming separately that the caller sources it from `CoderAuth`.
- No force unwraps in production code (only `URL(string:)!` in tests, acceptable). No `as!`, no `unsafeBitCast`, no custom `URLSessionDelegate`/TLS override, no WebSocket code.
- No hardcoded credentials or URLs; `example.com` hosts are test-only.
- The two style fixes applied this session (trailing whitespace, trailing comma, en-dash removal) are correct and carry no logic change.

## Summary

The feature does what the spec asks: session token injected as
`coder_session_token` with Secure + HttpOnly + SameSite=None,
asynchronously, before navigation, never logged. Blocking concerns are
elsewhere: the DoD gate was almost certainly run on Linux where the whole
feature is `#if`'d out (B1); the injection Task is uncancellable and
outlives `cleanup()` while strongly capturing `webView`, so a dismissed
view still gets a token injected and a load started with its delegate
detached (B2); injection failure is swallowed and the URL loads
unauthenticated anyway (B3); and nothing validates HTTPS before minting a
Secure/SameSite=None cookie (B4).

```
VERDICT: REQUEST_CHANGES
```
