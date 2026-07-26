# Review TASK-010 - Reviewer B

**Verdict:** REQUEST_CHANGES

## REQUIRED Findings

### B1 (major)
**Location:** KeyboardShortcutHandler.swift:74-78
**Evidence:**
```swift
public func makeUIView(context: Context) -> KeyCaptureView {
    let view = KeyCaptureView()
    view.onShortcut = onShortcut
    return view
}
```
**Rule:** RUBRIC-B/focus-management
**Required Change:** KeyCaptureView overrides canBecomeFirstResponder to return true but never calls becomeFirstResponder(). Without this the view will never receive pressesBegan events, breaking the standalone KeyboardShortcutHandler overlay entirely. Add `DispatchQueue.main.async { view.becomeFirstResponder() }` in makeUIView after creating the view (deferred to avoid calling before the view is in the hierarchy).

## OPTIONAL Findings

### B2 (minor)
**Location:** KeyboardShortcutHandler.swift:123-132
**Evidence:**
```swift
static func map(input: String?) -> KeyboardShortcut? {
    switch input {
    case "p": return .commandPalette
    case "s": return .save
    ...
```
**Rule:** RUBRIC-B/correctness
**Required Change:** Input matching is case-sensitive. Cmd+Shift+P produces input "P" (uppercase) which falls through to .custom("P") instead of .commandPalette. Normalize input with `input?.lowercased()` before the switch, or add uppercase cases.

### B3 (minor)
**Location:** KeyboardShortcutHandler.swift:98-112,146-160
**Evidence:** pressesBegan logic is duplicated verbatim in KeyCaptureView and ShortcutCapturingWebView
**Rule:** RUBRIC-B/code-quality
**Required Change:** Extract the shared pressesBegan logic into a single helper (e.g. a protocol extension or a free function taking the presses set and callback) to eliminate duplication and ensure future fixes apply to both paths.

### B4 (minor)
**Location:** KeyboardShortcutHandlerTests.swift:114-207
**Evidence:** Tests only invoke callbacks directly; no test constructs UIKeyCommand or verifies pressesBegan mapping end-to-end.
**Rule:** RUBRIC-B/test-coverage
**Required Change:** Task spec requires "Mock keyboard input for testing". Add at least one test that exercises pressesBegan with a mock UIPress/UIKeyCommand to verify the full path from key event → mapper → callback, not just the callback in isolation.

## Summary
- **No secrets exposure** — no `os_log`, `print`, or any logging of tokens/cookies anywhere.
- **No Keychain misuse** — no Keychain access in this task's code.
- **Concurrency is sound** — `KeyboardShortcutHandler` is `Sendable` with `@Sendable` closure; `KeyCaptureView`/`ShortcutCapturingWebView` are UIView subclasses (implicitly `@MainActor`); `Coordinator` is `@MainActor @unchecked Sendable` with weak webView ref. No data races.
- **No retain cycles** — `navigationDelegate` is weak, `viewModel.webView` is weak, `onShortcut` closures are held by the view (not the reverse).
- **No force unwraps or unsafe bit casts** — clean.
- **No hardcoded URLs/credentials/magic numbers** — clean.
- **Error handling is complete** — navigation errors propagate through `handleNavigationError` to `ErrorView`.

The **blocker-level concern** is B1: the `KeyCaptureView` never becomes first responder, so the standalone `KeyboardShortcutHandler` overlay cannot receive key events. This fails acceptance criterion 5 ("Handles focus management"). The `VSCodeWebView` path works because `WKWebView` naturally becomes first responder on tap, but the standalone API is broken.
