# TASK-011 Review A - Spec Compliance

**Verdict:** REQUEST_CHANGES

## REQUIRED Findings

### A1 (blocker)
**Location:** Sources/VSCodeWebView.swift:30
**Evidence:** `viewModel.isLoading = false`
**Rule:** RUBRIC-A/compilation
**Required Change:** `isLoading` is `public private(set)` in VSCodeWebViewModel. Writing it from a different file is a compile error. Either change the setter to `internal`/`package`, or add a dedicated `func resetLoadingState()` method on the view model and call that instead.

### A2 (blocker)
**Location:** Sources/VSCodeWebView.swift:59-88
**Evidence:** `final class Coordinator: NSObject, WKNavigationDelegate, @unchecked Sendable`
**Rule:** RUBRIC-A/strict-concurrency
**Required Change:** Coordinator is nonisolated but calls @MainActor methods on viewModel synchronously from ObjC delegate callbacks (lines 72, 80, 87). Under Swift 6 strict-concurrency=complete this is a compile error: you cannot call @MainActor-isolated methods from a nonisolated synchronous context. Mark Coordinator `@MainActor` (it is always used on the main thread by WebKit) and drop `@unchecked Sendable`.

### A3 (blocker)
**Location:** Tests/VSCodeWebViewTests.swift:119
**Evidence:** `#expect(view.body != nil)`
**Rule:** RUBRIC-A/compilation
**Required Change:** `View.body` returns `some View` (opaque, non-optional). Comparing it to `nil` is a type error. Replace with a trivial structural check, e.g. just construct the view and assert the stored URL via the view model, or remove this test since compilation of the view itself is already proven by the target building.

### A4 (major)
**Location:** Sources/VSCodeWebView.swift:29-31
**Evidence:** `.onDisappear { viewModel.isLoading = false }`
**Rule:** RUBRIC-A/acceptance-criterion-4
**Required Change:** Acceptance criterion 4 requires "Properly cleans up WKWebView on view disappearance." Setting isLoading=false is not cleanup. Add a `func cleanUp()` on the view model that the representable's `dismantleUIView` or onDisappear calls to: stopLoading, set navigationDelegate = nil, and nil out the coordinator's webView reference.

## OPTIONAL Findings

### A5 (minor)
**Location:** Tests/VSCodeWebViewTests.swift:110-122
**Evidence:** `VSCodeWebViewCreationTests`
**Rule:** RUBRIC-A/test-meaningfulness
**Required Change:** The only view-level test verifies `view.body != nil` (which doesn't compile). The task spec requires tests for "view creation, URL loading, navigation failure handling." URL loading and navigation failure are only tested via the view model. Add at least one test that verifies the Coordinator delegates errors to the view model (e.g. by injecting a mock or by testing through the representable's coordinator directly).

### A6 (minor)
**Location:** Sources/VSCodeWebView.swift:36
**Evidence:** `private struct WebViewRepresentable: UIViewRepresentable`
**Rule:** RUBRIC-A/acceptance-criterion-1
**Required Change:** UIViewRepresentable is iOS-only. The `#if canImport(WebKit)` guard wraps the entire file, which is correct, but the package declares macOS(.v14) as a supported platform. On macOS the entire module is empty. Consider also providing an NSViewRepresentable fallback for macOS, or restrict the package platform to iOS only.
