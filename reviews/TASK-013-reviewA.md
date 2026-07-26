# Review TASK-013 - Reviewer A

**Verdict:** APPROVE

## OPTIONAL Findings

### A1 (minor)
**Location:** Sources/VNCWebViewModel.swift:59-61
**Evidence:**
```swift
public func stopLoading() {
    isLoading = false
}
```
**Rule:** RUBRIC-A/naming-accuracy
**Required Change:** Either also call `webView?.stopLoading()` inside this method (mirroring cleanup()), or rename to `markNotLoading()` to avoid implying the WKWebView load is cancelled.

### A2 (nit)
**Location:** Sources/VNCWebView.swift:22-23
**Evidence:**
```swift
viewModel.clearError()
viewModel.navigationDidStart()
```
**Rule:** RUBRIC-A/no-redundant-calls
**Required Change:** Remove the `viewModel.navigationDidStart()` call here; `makeUIView` already calls it on the fresh WebViewRepresentable. The duplicate call is harmless but misleading.

### A3 (nit)
**Location:** Sources/VNCWebView.swift:70-74
**Evidence:**
```swift
deinit {
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView = nil
}
```
**Rule:** RUBRIC-A/mainactor-safety
**Required Change:** Coordinator is @MainActor but deinit may execute off-main in edge cases. Wrap WKWebView mutations in `Task { @MainActor in ... }` or accept the theoretical risk since in practice the Coordinator is always main-thread-retained. No action strictly required.

### A4 (nit)
**Location:** Tests/VNCWebViewTests.swift:116-133
**Evidence:**
```swift
#expect(!errorMsg.contains("password"))
#expect(!errorMsg.contains("token"))...
```
**Rule:** RUBRIC-A/test-meaningfulness
**Required Change:** The 'no secrets' test asserts the localizedDescription of a hand-crafted NSError doesn't contain magic words — it cannot catch a real secret leak. Replace with a test that feeds an error whose userInfo contains a token-bearing URL and asserts the token is absent from `errorMessage`, or remove the test as a false sense of coverage.
