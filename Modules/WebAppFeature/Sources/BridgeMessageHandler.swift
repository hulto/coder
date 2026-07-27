#if canImport(WebKit) && canImport(UIKit)
import Foundation
import WebKit
import UIKit
import SafariServices
import OSLog

private let logger = Logger(subsystem: "com.coder.ios", category: "BridgeMessageHandler")

/// Haptic feedback intensity surfaced to JavaScript.
public enum HapticStyle: String, Sendable {
    case light
    case medium
    case heavy
}

/// Receives structured messages from the JavaScript bridge and dispatches native actions.
///
/// Register as the handler for the `"coderNative"` message name. JavaScript sends
/// messages via `window.CoderNative.send({ action: "...", ... })`, which is
/// injected at document start by ``bridgeScript``.
@MainActor
public final class BridgeMessageHandler: NSObject, WKScriptMessageHandler, @unchecked Sendable {
    /// Called when JavaScript invokes `window.CoderNative.notifyStateChange(state)`.
    public var onStateChange: ((String) -> Void)?

    public override init() {}

    // MARK: - WKScriptMessageHandler

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "coderNative",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            logger.debug("Ignored malformed bridge message")
            return
        }

        switch action {
        case "hapticFeedback":
            let rawStyle = body["style"] as? String ?? "medium"
            triggerHaptic(style: HapticStyle(rawValue: rawStyle) ?? .medium)

        case "copyToClipboard":
            guard let text = body["text"] as? String else { return }
            UIPasteboard.general.string = text

        case "openExternal":
            guard let urlString = body["url"] as? String,
                  let url = URL(string: urlString) else { return }
            openExternal(url: url)

        case "notifyStateChange":
            guard let state = body["state"] as? String else { return }
            onStateChange?(state)

        default:
            logger.debug("Unknown bridge action: \(action)")
        }
    }

    // MARK: - Private Handlers

    private func triggerHaptic(style: HapticStyle) {
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light:  uiStyle = .light
        case .medium: uiStyle = .medium
        case .heavy:  uiStyle = .heavy
        }
        UIImpactFeedbackGenerator(style: uiStyle).impactOccurred()
    }

    private func openExternal(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(SFSafariViewController(url: url), animated: true)
    }

    // MARK: - JS Bridge Script

    /// JavaScript injected at document start that exposes `window.CoderNative`.
    ///
    /// Call `window.CoderNative.send({ action: "...", ... })` directly or use the
    /// convenience methods (`hapticFeedback`, `copyToClipboard`, `openExternal`,
    /// `notifyStateChange`). Messages are silently dropped in non-native environments.
    public static let bridgeScript: String = """
    (function() {
        if (window.CoderNative) return;
        window.CoderNative = {
            send: function(payload) {
                var handlers = window.webkit &&
                               window.webkit.messageHandlers &&
                               window.webkit.messageHandlers.coderNative;
                if (handlers) { handlers.postMessage(payload); }
            },
            hapticFeedback: function(style) {
                this.send({ action: 'hapticFeedback', style: style || 'medium' });
            },
            copyToClipboard: function(text) {
                this.send({ action: 'copyToClipboard', text: text });
            },
            openExternal: function(url) {
                this.send({ action: 'openExternal', url: url });
            },
            notifyStateChange: function(state) {
                this.send({ action: 'notifyStateChange', state: state });
            }
        };
        Object.freeze(window.CoderNative);
    })();
    """
}
#endif
