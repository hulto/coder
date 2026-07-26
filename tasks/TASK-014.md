---
id: TASK-014
title: Cookie injection for VNC (WebAppFeature)
phase: 4
module: WebAppFeature
depends_on: [TASK-013]
blocks: []
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-014-vnc-cookie
---

## Goal
Implement cookie injection for VNC to authenticate the WKWebView using the session token from CoderAuth. This enables seamless SSO for VNC without requiring users to re-authenticate.

## In scope (files this task MAY create/modify)
- Sources/WebAppFeature/VNCWebView.swift (modified)
- Sources/WebAppFeature/VNCWebViewModel.swift (modified)
- Tests/WebAppFeatureTests/VNCCookieInjectionTests.swift (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring
- VNC UI or functionality
- VS Code Web implementation (TASK-012)
- CoderKit or CoderAuth modules

## Contracts / interfaces it MUST honor
- Reuses `CookieInjector` from TASK-012
- Must inject cookies before WKWebView loads URL
- Must handle cookie injection asynchronously
- Must log errors if injection fails (but don't expose token)

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Integrates cookie injection into VNCWebView initialization.
3. Injects session token as `coder_session_token` cookie before navigation.
4. Handles cookie injection asynchronously.
5. Logs errors if injection fails (but doesn't expose token).
6. Unit tests verify cookie injection integration.
7. No secrets logged or exposed in error messages.

## Test requirements
- Swift Testing (`@Test`)
- Mock WKHTTPCookieStore for testing
- Cover: cookie injection before navigation, error handling

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/WebAppFeature` green
- [ ] `swiftlint lint --strict Modules/WebAppFeature` clean
- [ ] `swift-format lint -r Modules/WebAppFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
