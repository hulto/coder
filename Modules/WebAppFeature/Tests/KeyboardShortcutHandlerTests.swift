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
