# TASK-011 Review B - Security & Architecture

**Verdict:** REQUEST_CHANGES

## REQUIRED Findings

### B1 (blocker)
**Location:** Sources/VSCodeWebView.swift:30
**Evidence:** `viewModel.isLoading = false`
**Rule:** RUBRIC-B/access-control
**Required Change:** `isLoading` is declared `private(set)` in VSCodeWebViewModel. Either make it `public(set)` or add a public method like `stopLoading()` to the view model and call that instead.

### B2 (major)
**Location:** Sources/VSCodeWebView.swift:59
**Evidence:** `final class Coordinator: NSObject, WKNavigationDelegate, @unchecked Sendable`
**Rule:** RUBRIC-B/concurrency-isolation
**Required Change:** Coordinator accesses @MainActor-isolated viewModel but is not itself @MainActor. Add @MainActor annotation: `final class Coordinator: NSObject, WKNavigationDelegate, @unchecked Sendable, @MainActor`

### B3 (major)
**Location:** Sources/VSCodeWebView.swift:29-31
**Evidence:** `.onDisappear { viewModel.isLoading = false }`
**Rule:** RUBRIC-B/webview-cleanup
**Required Change:** Task spec requires proper WKWebView cleanup on disappearance. Add a cleanup method to view model that stops loading and nils the navigation delegate: `viewModel.cleanup()` which calls `webView?.stopLoading()` and `webView?.navigationDelegate = nil`

## OPTIONAL Findings

### B4 (minor)
**Location:** Sources/VSCodeWebView.swift:39-48
**Evidence:** `func makeUIView(context: Context) -> WKWebView { let webView = WKWebView(); webView.navigationDelegate = context.coordinator; context.coordinator.webView = webView; viewModel.navigationDidStart(); let request = URLRequest(url: viewModel.url); webView.load(request); return webView }`
**Rule:** RUBRIC-B/error-handling
**Required Change:** `navigationDidStart()` is called before `load()` but `load()` could fail synchronously. Consider wrapping in a do-catch or checking the return value of `load()`

### B5 (nit)
**Location:** Sources/VSCodeWebViewModel.swift:15
**Evidence:** `public private(set) var isLoading: Bool = false`
**Rule:** RUBRIC-B/api-design
**Required Change:** If external mutation is needed (as in VSCodeWebView.swift:30), change to `public var`. Otherwise, provide explicit state transition methods.
