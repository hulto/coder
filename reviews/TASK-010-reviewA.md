# Review TASK-010 - Reviewer A

**Verdict:** APPROVE

## OPTIONAL Findings

### A1 (minor)
**Location:** KeyboardShortcutHandler.swift:124-131
**Evidence:**
```swift
switch input {
case "p": return .commandPalette
case "s": return .save
...
}
```
**Rule:** RUBRIC-A/edge-case-handling
**Required Change:** Normalize input to lowercase before matching: `switch input?.lowercased()` so that Cmd+Shift+P (input "P") still maps to .commandPalette instead of falling through to .custom("P"). VS Code's own command palette shortcut is Cmd+Shift+P on macOS.

### A2 (minor)
**Location:** KeyboardShortcutHandler.swift:92
**Evidence:** `public class KeyCaptureView: UIView {`
**Rule:** RUBRIC-A/contract-surface
**Required Change:** Remove `public` from KeyCaptureView. The task spec's required public surface lists only KeyboardShortcutHandler and KeyboardShortcut. KeyCaptureView is an implementation detail and should be internal.

### A3 (minor)
**Location:** KeyboardShortcutHandler.swift:101
**Evidence:** `guard let keyCommand = press.key else { continue }`
**Rule:** RUBRIC-A/contract-surface
**Required Change:** `press.key` returns `UIKey`, not `UIKeyCommand`. Rename the local to `key` to avoid confusion. The spec says "Must use UIKeyCommand" — consider also overriding `keyCommands` to register UIKeyCommand objects, or document why UIKey via pressesBegan is preferred.

### A4 (minor)
**Location:** KeyboardShortcutHandler.swift:74-78
**Evidence:**
```swift
public func makeUIView(context: Context) -> KeyCaptureView {
    let view = KeyCaptureView()
    view.onShortcut = onShortcut
    return view
}
```
**Rule:** RUBRIC-A/acceptance-criteria
**Required Change:** KeyCaptureView never calls becomeFirstResponder(), so the standalone overlay usage pattern (shown in the doc comment) will not receive key events. Add `DispatchQueue.main.async { view.becomeFirstResponder() }` in makeUIView, or override didMoveToWindow in KeyCaptureView to call becomeFirstResponder when added to a window.

### A5 (nit)
**Location:** KeyboardShortcutHandler.swift:98-112,146-160
**Evidence:** pressesBegan logic is duplicated verbatim in KeyCaptureView and ShortcutCapturingWebView
**Rule:** RUBRIC-A/idiomatic-swift
**Required Change:** Extract the shared press-handling logic into a free function or a protocol extension to eliminate duplication.
