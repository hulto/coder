# Review TASK-012 - Reviewer B

## Verdict: APPROVE

## OPTIONAL Findings

### B1 (minor)
**Location:** `CookieInjector.swift:74`
**Evidence:** `print("[CookieInjector] Failed to create cookie – invalid URL")`
**Rule:** "Acceptance criterion 6: Logs errors if injection fails"
**Required Change:** Use os_log or Logger instead of print() for proper log-level control and privacy redaction in production. Token is correctly excluded.

### B2 (minor)
**Location:** `VSCodeWebView.swift:50-54`
**Evidence:**
```swift
Task { @MainActor in
    await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
    let request = URLRequest(url: viewModel.url)
    webView.load(request)
}
```
**Rule:** "Resource cleanup on view disappearance"
**Required Change:** Store the Task reference in the view model and cancel it in cleanup(). Currently if the view disappears before the Task executes, cookies are still injected and a request is loaded into an orphaned webView. Low risk but wasteful.

### B3 (nit)
**Location:** `CookieInjector.swift:47-48`
**Evidence:**
```swift
HTTPCookiePropertyKey("HttpOnly"): true,
HTTPCookiePropertyKey("SameSite"): "None",
```
**Rule:** "Cookie attributes set correctly"
**Required Change:** Consider using HTTPCookiePropertyKey.sameSitePolicy (iOS 17+) instead of raw string keys for SameSite, with a fallback for earlier OS versions. HttpOnly string key is correct and verified by tests. Current approach works but is fragile across OS versions.

### B4 (nit)
**Location:** `CookieInjectorTests.swift:143-158`
**Evidence:** `mockStoreRecordsCookies` test exercises MockHTTPCookieStore directly, not CookieInjector.injectCookies()
**Rule:** "Acceptance criterion 7: Unit tests verify cookie injection logic"
**Required Change:** No test exercises injectCookies() end-to-end with a mock cookie store. The current tests verify cookie construction and properties but not the actual injection path through WKHTTPCookieStore.setCookie. Consider adding an integration-style test or document this as a known limitation of WKHTTPCookieStore mocking.

## Summary
- **Security**: Token never logged or exposed. Cookie attributes (HttpOnly, Secure, SameSite=None) correctly set.
- **Concurrency**: Proper async/await usage with `withCheckedContinuation`. Sendable compliance correct.
- **Architecture**: Clean separation of concerns. Error handling complete.
- **iOS Idioms**: Proper use of WKHTTPCookieStore. Cookie attributes set correctly. Async/await used correctly.
