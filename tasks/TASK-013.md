---
id: TASK-013
title: VNC WKWebView host (WebAppFeature)
phase: 4
module: WebAppFeature
depends_on: [TASK-012]
blocks: [TASK-014]
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-013-vnc-webview
---

## Goal
Create a WKWebView-based host for VNC (noVNC/KasmVNC) that loads the VNC subdomain app URL and handles basic navigation. This is the foundation for embedding VNC in the iOS app.

## In scope (files this task MAY create/modify)
- Sources/WebAppFeature/VNCWebView.swift (new)
- Sources/WebAppFeature/VNCWebViewModel.swift (new)
- Tests/WebAppFeatureTests/VNCWebViewTests.swift (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring
- Cookie injection (TASK-014)
- Touch/pointer handling optimizations (future task)
- CoderKit or CoderAuth modules

## Contracts / interfaces it MUST honor
- Public surface MUST be:
  ```swift
  public struct VNCWebView: View {
      public init(url: URL)
  }
  ```
- View must be Sendable
- Must use WKWebView via UIViewRepresentable
- Must handle basic navigation (load URL, handle navigation failures)

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Displays WKWebView loading the provided URL.
3. Handles navigation failures gracefully (shows error message).
4. Properly cleans up WKWebView on view disappearance.
5. Unit tests verify view creation and basic functionality.
6. No secrets logged or exposed.

## Test requirements
- Swift Testing (`@Test`)
- Mock WKWebView navigation for testing
- Cover: view creation, URL loading, navigation failure handling

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/WebAppFeature` green
- [ ] `swiftlint lint --strict Modules/WebAppFeature` clean
- [ ] `swift-format lint -r Modules/WebAppFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
