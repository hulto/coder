# Review TASK-013 - Reviewer B

**Verdict:** APPROVE

## REQUIRED Findings

### B1 (minor)
**Location:** VNCWebViewModel.swift:13
**Evidence:**
```swift
public final class VNCWebViewModel: @unchecked Sendable
```
**Rule:** RUBRIC-B/api-surface
**Required Change:** Mark VNCWebViewModel as `internal` (remove `public` from the class and all its members). The task spec mandates the public surface MUST be only `VNCWebView { init(url: URL) }`. State-management methods (`navigationDidStart`, `handleNavigationError`, `clearError`, `cleanup`, etc.) are implementation details consumed only by VNCWebView/Coordinator and must not be public API.

## OPTIONAL Findings

### B2 (nit)
**Location:** VNCWebView.swift:19-27
**Evidence:**
```swift
if let errorMessage = viewModel.errorMessage { ErrorView(...) } else { WebViewRepresentable(...) }
```
**Rule:** RUBRIC-B/unused-state
**Required Change:** `isLoading` is set in the view model but never read in the view body — no loading indicator is rendered. Either add a `ProgressView` overlay gated on `viewModel.isLoading`, or remove the property if a future task will consume it.

### B3 (nit)
**Location:** VNCWebView.swift:70-74
**Evidence:**
```swift
deinit { webView?.stopLoading(); webView?.navigationDelegate = nil; webView = nil }
```
**Rule:** RUBRIC-B/redundant-cleanup
**Required Change:** Coordinator.deinit duplicates the cleanup already performed by `viewModel.cleanup()` in `onDisappear`. Remove the deinit body or add a comment explaining why both paths are needed (e.g. if the Coordinator can outlive the onDisappear call).
