---
id: TASK-012
title: Cookie injection for VS Code Web (WebAppFeature)
phase: 3
module: WebAppFeature
depends_on: [TASK-011]
blocks: []
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-012-cookie-injection
---

## Goal
Implement cookie injection for VS Code Web to authenticate the WKWebView using the session token from CoderAuth. This enables seamless SSO for VS Code Web without requiring users to re-authenticate.

## In scope (files this task MAY create/modify)
- Sources/WebAppFeature/VSCodeWebView.swift (modified)
- Sources/WebAppFeature/VSCodeWebViewModel.swift (modified)
- Sources/WebAppFeature/CookieInjector.swift (new)
- Tests/WebAppFeatureTests/CookieInjectorTests.swift (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring
- VS Code Web UI or functionality
- VNC implementation (TASK-013)
- CoderKit or CoderAuth modules

## Contracts / interfaces it MUST honor
- Consumes `CoderAuth.SessionTokenStore` to retrieve session token
- Public surface MUST be:
  ```swift
  public struct CookieInjector {
      public static func injectCookies(into webView: WKWebView, for url: URL, token: String) async
  }
  ```
- Must use `WKHTTPCookieStore` to inject cookies
- Must handle cookie domain correctly (extract from URL)
- Must set cookie with proper attributes (HttpOnly, Secure, SameSite)

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Extracts domain from URL correctly.
3. Injects session token as `coder_session_token` cookie.
4. Sets cookie attributes correctly (HttpOnly=true, Secure=true, SameSite=None).
5. Handles cookie injection asynchronously.
6. Logs errors if injection fails (but doesn't expose token).
7. Unit tests verify cookie injection logic.
8. No secrets logged or exposed in error messages.

## Test requirements
- Swift Testing (`@Test`)
- Mock WKHTTPCookieStore for testing
- Cover: cookie injection, domain extraction, error handling

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/WebAppFeature` green
- [ ] `swiftlint lint --strict Modules/WebAppFeature` clean
- [ ] `swift-format lint -r Modules/WebAppFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
