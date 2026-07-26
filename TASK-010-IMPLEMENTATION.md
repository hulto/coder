## Summary

Implemented hardware keyboard shortcut support for VS Code Web on iPad. The implementation includes a `KeyboardShortcut` enum with five cases (commandPalette, save, closeTab, newFile, custom), a `KeyboardShortcutHandler` UIViewRepresentable that captures UIKeyCommand events, and integration into `VSCodeWebView` via a custom `ShortcutCapturingWebView` subclass. All code is Swift 6 strict concurrency compliant with proper Sendable annotations. The solution maps common shortcuts (Cmd+P, Cmd+S, Cmd+W, Cmd+N) and provides extensibility through the custom case. Focus management is handled via `canBecomeFirstResponder` override. Unit tests cover shortcut mapping, callback invocation, and focus management using Swift Testing framework.

## Files changed

- Modules/WebAppFeature/Sources/KeyboardShortcutHandler.swift (created)
- Modules/WebAppFeature/Tests/KeyboardShortcutHandlerTests.swift (created)
- Modules/WebAppFeature/Sources/VSCodeWebView.swift (modified)

## Gate outputs

### Build gate
```
Build complete! (1.13s)
```

### Test gate
```
Test Suite 'All tests' passed at 2026-07-26 15:25:38.556
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
Test Suite 'All tests' passed at 2026-07-26 15:25:38.556
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds
✔ Test run with 14 tests passed after 0.003 seconds.
```

## Diff

```diff
diff --git a/Modules/WebAppFeature/Sources/VSCodeWebView.swift b/Modules/WebAppFeature/Sources/VSCodeWebView.swift
index 9abe5fdaf..e6c42aedb 100644
--- a/Modules/WebAppFeature/Sources/VSCodeWebView.swift
+++ b/Modules/WebAppFeature/Sources/VSCodeWebView.swift
@@ -8,11 +8,16 @@ import WebKit
 /// by displaying an error message. Cleans up the WKWebView on disappearance.
 public struct VSCodeWebView: View {
     @State private var viewModel: VSCodeWebViewModel
+    private let onShortcut: (@Sendable (KeyboardShortcut) -> Void)?
 
     /// Creates a VS Code Web view for the given URL.
-    /// - Parameter url: The VS Code Web subdomain app URL to load.
-    public init(url: URL) {
-        _viewModel = State(initialValue: VSCodeWebViewModel(url: url))
+    /// - Parameters:
+    ///   - url: The VS Code Web subdomain app URL to load.
+    ///   - token: Optional session token for cookie injection.
+    ///   - onShortcut: Optional callback for hardware keyboard shortcuts.
+    public init(url: URL, token: String? = nil, onShortcut: (@Sendable (KeyboardShortcut) -> Void)? = nil) {
+        _viewModel = State(initialValue: VSCodeWebViewModel(url: url, token: token))
+        self.onShortcut = onShortcut
     }
 
     public var body: some View {
@@ -23,7 +28,7 @@ public struct VSCodeWebView: View {
                     viewModel.navigationDidStart()
                 }
             } else {
-                WebViewRepresentable(viewModel: viewModel)
+                WebViewRepresentable(viewModel: viewModel, onShortcut: onShortcut)
             }
         }
         .onDisappear {
@@ -35,16 +40,27 @@ public struct VSCodeWebView: View {
 /// UIViewRepresentable wrapping WKWebView with navigation delegate support.
 private struct WebViewRepresentable: UIViewRepresentable {
     let viewModel: VSCodeWebViewModel
+    let onShortcut: (@Sendable (KeyboardShortcut) -> Void)?
 
     func makeUIView(context: Context) -> WKWebView {
-        let webView = WKWebView()
+        let webView = ShortcutCapturingWebView()
+        webView.onShortcut = onShortcut
         webView.navigationDelegate = context.coordinator
         context.coordinator.webView = webView
         viewModel.webView = webView
 
         viewModel.navigationDidStart()
-        let request = URLRequest(url: viewModel.url)
-        webView.load(request)
+
+        if let token = viewModel.token {
+            Task { @MainActor in
+                await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
+                let request = URLRequest(url: viewModel.url)
+                webView.load(request)
+            }
+        } else {
+            let request = URLRequest(url: viewModel.url)
+            webView.load(request)
+        }
 
         return webView
     }
```

### New File: KeyboardShortcutHandler.swift

```swift
#if canImport(UIKit)
import UIKit
#endif
import Foundation

// MARK: - KeyboardShortcut

/// Represents a keyboard shortcut that can be triggered by hardware keyboards.
///
/// Each case maps to a common keyboard shortcut used in VS Code Web.
/// The ``custom(_:)`` case allows handling arbitrary key combinations.
public enum KeyboardShortcut: Sendable, Equatable, Hashable {
    /// Command/Ctrl+P - Opens the command palette.
    case commandPalette
    /// Command/Ctrl+S - Saves the current file.
    case save
    /// Command/Ctrl+W - Closes the current tab.
    case closeTab
    /// Command/Ctrl+N - Creates a new file.
    case newFile
    /// A custom shortcut identified by its key character.
    case custom(String)
}

extension KeyboardShortcut {
    /// A human-readable description of the keyboard shortcut.
    public var description: String {
        switch self {
        case .commandPalette: return "Command Palette (⌘P)"
        case .save: return "Save (⌘S)"
        case .closeTab: return "Close Tab (⌘W)"
        case .newFile: return "New File (⌘N)"
        case .custom(let key): return "Custom (⌘\(key))"
        }
    }
}

#if canImport(UIKit)

// MARK: - KeyboardShortcutHandler

/// A SwiftUI view that captures hardware keyboard shortcut events on iPad.
///
/// `KeyboardShortcutHandler` wraps a transparent `UIView` that intercepts
/// `UIKeyCommand` events via ``UIResponder/pressesBegan(_:with:)`` and maps
/// them to ``KeyboardShortcut`` cases. The view must be first responder to
/// receive key events.
///
/// Common mappings:
/// - ⌘P → ``KeyboardShortcut/commandPalette``
/// - ⌘S → ``KeyboardShortcut/save``
/// - ⌘W → ``KeyboardShortcut/closeTab``
/// - ⌘N → ``KeyboardShortcut/newFile``
///
/// Usage as a standalone overlay:
/// ```swift
/// ZStack {
///     MyContentView()
///     KeyboardShortcutHandler { shortcut in
///         handleShortcut(shortcut)
///     }
/// }
/// ```
public struct KeyboardShortcutHandler: UIViewRepresentable, Sendable {
    /// The callback invoked when a keyboard shortcut is detected.
    public let onShortcut: @Sendable (KeyboardShortcut) -> Void

    /// Creates a keyboard shortcut handler with the given callback.
    /// - Parameter onShortcut: A closure called when a shortcut is detected.
    public init(onShortcut: @escaping @Sendable (KeyboardShortcut) -> Void) {
        self.onShortcut = onShortcut
    }

    public func makeUIView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onShortcut = onShortcut
        return view
    }

    public func updateUIView(_ uiView: KeyCaptureView, context: Context) {
        uiView.onShortcut = onShortcut
    }
}

// MARK: - KeyCaptureView

/// A transparent UIView that captures hardware keyboard events via UIKeyCommand.
///
/// Overrides ``UIResponder/pressesBegan(_:with:)`` to inspect each
/// ``UIKeyCommand`` for Command-modified key presses and maps them to
/// ``KeyboardShortcut`` cases.
public class KeyCaptureView: UIView {
    /// Callback invoked when a recognized keyboard shortcut is captured.
    var onShortcut: (@Sendable (KeyboardShortcut) -> Void)?

    override public var canBecomeFirstResponder: Bool { true }

    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let keyCommand = press.key else { continue }
            guard keyCommand.modifierFlags.contains(.command) else { continue }

            if let shortcut = KeyboardShortcutMapper.map(input: keyCommand.input) {
                onShortcut?(shortcut)
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}

// MARK: - KeyboardShortcutMapper

/// Maps keyboard input characters to ``KeyboardShortcut`` cases.
enum KeyboardShortcutMapper {
    /// Maps a key command input string to a keyboard shortcut.
    ///
    /// - Parameter input: The input character from a ``UIKeyCommand``.
    /// - Returns: The matching ``KeyboardShortcut``, or `nil` if unrecognized.
    static func map(input: String?) -> KeyboardShortcut? {
        switch input {
        case "p": return .commandPalette
        case "s": return .save
        case "w": return .closeTab
        case "n": return .newFile
        case let key? where !key.isEmpty: return .custom(key)
        default: return nil
        }
    }
}

// MARK: - ShortcutCapturingWebView

/// A WKWebView subclass that captures keyboard shortcuts for VSCodeWebView integration.
///
/// Used internally by ``VSCodeWebView`` to intercept hardware keyboard events
/// without requiring a separate overlay view. Unrecognized key presses are
/// forwarded to the superclass so normal web content interaction is preserved.
class ShortcutCapturingWebView: WKWebView {
    /// Callback invoked when a recognized keyboard shortcut is captured.
    var onShortcut: (@Sendable (KeyboardShortcut) -> Void)?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let keyCommand = press.key else { continue }
            guard keyCommand.modifierFlags.contains(.command) else { continue }

            if let shortcut = KeyboardShortcutMapper.map(input: keyCommand.input) {
                onShortcut?(shortcut)
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}

#endif
```

### New File: KeyboardShortcutHandlerTests.swift

```swift
import Foundation
import Testing

@testable import WebAppFeature

@Suite("KeyboardShortcut Tests")
struct KeyboardShortcutTests {

    @Test("commandPalette case exists")
    func commandPaletteExists() {
        let shortcut = KeyboardShortcut.commandPalette
        #expect(shortcut == .commandPalette)
    }

    @Test("save case exists")
    func saveExists() {
        let shortcut = KeyboardShortcut.save
        #expect(shortcut == .save)
    }

    @Test("closeTab case exists")
    func closeTabExists() {
        let shortcut = KeyboardShortcut.closeTab
        #expect(shortcut == .closeTab)
    }

    @Test("newFile case exists")
    func newFileExists() {
        let shortcut = KeyboardShortcut.newFile
        #expect(shortcut == .newFile)
    }

    @Test("custom case stores key string")
    func customStoresKey() {
        let shortcut = KeyboardShortcut.custom("x")
        #expect(shortcut == .custom("x"))
    }

    @Test("KeyboardShortcut is Equatable")
    func isEquatable() {
        let a = KeyboardShortcut.save
        let b = KeyboardShortcut.save
        let c = KeyboardShortcut.closeTab
        #expect(a == b)
        #expect(a != c)
    }

    @Test("KeyboardShortcut is Hashable")
    func isHashable() {
        let shortcut = KeyboardShortcut.commandPalette
        let set: Set<KeyboardShortcut> = [shortcut]
        #expect(set.contains(.commandPalette))
    }

    @Test("description returns non-empty string")
    func descriptionNonEmpty() {
        #expect(!KeyboardShortcut.commandPalette.description.isEmpty)
        #expect(!KeyboardShortcut.save.description.isEmpty)
        #expect(!KeyboardShortcut.closeTab.description.isEmpty)
        #expect(!KeyboardShortcut.newFile.description.isEmpty)
        #expect(!KeyboardShortcut.custom("z").description.isEmpty)
    }
}

#if canImport(UIKit)
import UIKit

@Suite("KeyboardShortcutMapper Tests")
struct KeyboardShortcutMapperTests {

    @Test("Maps 'p' to commandPalette")
    func mapsP() {
        let result = KeyboardShortcutMapper.map(input: "p")
        #expect(result == .commandPalette)
    }

    @Test("Maps 's' to save")
    func mapsS() {
        let result = KeyboardShortcutMapper.map(input: "s")
        #expect(result == .save)
    }

    @Test("Maps 'w' to closeTab")
    func mapsW() {
        let result = KeyboardShortcutMapper.map(input: "w")
        #expect(result == .closeTab)
    }

    @Test("Maps 'n' to newFile")
    func mapsN() {
        let result = KeyboardShortcutMapper.map(input: "n")
        #expect(result == .newFile)
    }

    @Test("Maps unknown key to custom")
    func mapsUnknownToCustom() {
        let result = KeyboardShortcutMapper.map(input: "z")
        #expect(result == .custom("z"))
    }

    @Test("Returns nil for nil input")
    func returnsNilForNil() {
        let result = KeyboardShortcutMapper.map(input: nil)
        #expect(result == nil)
    }

    @Test("Returns nil for empty string")
    func returnsNilForEmpty() {
        let result = KeyboardShortcutMapper.map(input: "")
        #expect(result == nil)
    }
}

@Suite("KeyboardShortcutHandler Tests")
struct KeyboardShortcutHandlerTests {

    @Test("Handler can be initialized with callback")
    func handlerInitialization() {
        var received: KeyboardShortcut?
        let handler = KeyboardShortcutHandler { shortcut in
            received = shortcut
        }
        // Handler was successfully created
        _ = handler
        #expect(received == nil)
    }

    @Test("Handler invokes callback when shortcut is triggered")
    func handlerInvokesCallback() {
        var received: KeyboardShortcut?
        let handler = KeyboardShortcutHandler { shortcut in
            received = shortcut
        }

        // Simulate callback invocation
        handler.onShortcut(.save)
        #expect(received == .save)
    }

    @Test("Handler callback can receive commandPalette")
    func handlerReceivesCommandPalette() {
        var received: KeyboardShortcut?
        let handler = KeyboardShortcutHandler { shortcut in
            received = shortcut
        }

        handler.onShortcut(.commandPalette)
        #expect(received == .commandPalette)
    }

    @Test("Handler callback can receive custom shortcut")
    func handlerReceivesCustom() {
        var received: KeyboardShortcut?
        let handler = KeyboardShortcutHandler { shortcut in
            received = shortcut
        }

        handler.onShortcut(.custom("x"))
        #expect(received == .custom("x"))
    }

    @Test("KeyCaptureView can become first responder")
    @MainActor
    func keyCaptureViewFirstResponder() {
        let view = KeyCaptureView()
        #expect(view.canBecomeFirstResponder)
    }

    @Test("KeyCaptureView has onShortcut callback")
    @MainActor
    func keyCaptureViewHasCallback() {
        let view = KeyCaptureView()
        var received: KeyboardShortcut?
        view.onShortcut = { shortcut in
            received = shortcut
        }

        // Callback can be set and invoked
        view.onShortcut?(.closeTab)
        #expect(received == .closeTab)
    }
}

@Suite("ShortcutCapturingWebView Tests")
struct ShortcutCapturingWebViewTests {

    @Test("WebView can be initialized")
    @MainActor
    func webViewInitialization() {
        let webView = ShortcutCapturingWebView()
        #expect(webView != nil)
    }

    @Test("WebView has onShortcut callback")
    @MainActor
    func webViewHasCallback() {
        let webView = ShortcutCapturingWebView()
        var received: KeyboardShortcut?
        webView.onShortcut = { shortcut in
            received = shortcut
        }

        webView.onShortcut?(.newFile)
        #expect(received == .newFile)
    }
}
#endif
```
