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
        DispatchQueue.main.async { view.becomeFirstResponder() }
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
