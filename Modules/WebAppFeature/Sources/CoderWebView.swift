#if canImport(WebKit) && canImport(UIKit)
import SwiftUI
import UIKit
import WebKit

/// The primary hybrid web container for the Coder iOS app.
///
/// Loads the user's Coder deployment in a persistent `WKWebView` session with
/// session-cookie injection, a JS-to-native bridge, and route interception hooks.
/// All navigation passes through ``NavigationManager``, which logs interceptable
/// routes (VS Code, terminal, VNC) and can redirect them to native views once
/// ``AppSettings/enableNativeInterception`` is enabled.
public struct CoderWebView: View {
    private let url: URL
    private let token: String?

    /// Creates the Coder web shell.
    ///
    /// - Parameters:
    ///   - url: Base URL of the user's Coder deployment.
    ///   - token: Session token for `coder_session_token` cookie injection.
    ///            Pass `nil` to skip injection (web app will redirect to login).
    public init(url: URL, token: String? = nil) {
        self.url = url
        self.token = token
    }

    public var body: some View {
        CoderWebViewRepresentable(url: url, token: token)
            .background(
                Color(red: 30/255, green: 30/255, blue: 30/255)
                    .ignoresSafeArea()
            )
    }
}

// MARK: - UIViewRepresentable

private struct CoderWebViewRepresentable: UIViewRepresentable {
    let url: URL
    let token: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            baseURL: url,
            enableNativeInterception: AppSettings.shared.enableNativeInterception
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Persistent data store so cookies, local storage, and auth tokens survive restarts.
        config.websiteDataStore = .default()

        // Append "CoderIOSNative/1.0" to the UA so the server can identify native clients.
        config.applicationNameForUserAgent = "CoderIOSNative/1.0"

        // Register the JS bridge and inject its client-side API before any page script runs.
        let userContent = config.userContentController
        userContent.add(context.coordinator.bridge, name: "coderNative")
        userContent.addUserScript(
            WKUserScript(
                source: BridgeMessageHandler.bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        // Seed html/body with VS Code Dark background before the page paints so there
        // is no white flash in the safe-area padding regions that VS Code leaves unfilled.
        userContent.addUserScript(
            WKUserScript(
                source: "document.documentElement.style.backgroundColor='#1e1e1e';" +
                        "document.documentElement.style.webkitTextSizeAdjust='100%';",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        // After VS Code's theme loads, sync html background to the actual theme color so
        // light-theme users also get a matching background in the safe-area padding regions.
        userContent.addUserScript(
            WKUserScript(
                source: """
                    (function() {
                        var apply = function() {
                            var bg = getComputedStyle(document.documentElement)
                                .getPropertyValue('--vscode-editor-background').trim();
                            if (bg) { document.documentElement.style.backgroundColor = bg; }
                        };
                        apply();
                        new MutationObserver(apply).observe(document.documentElement,
                            { attributes: true, attributeFilter: ['class', 'style'] });
                    })();
                    """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator.navigationManager
        webView.uiDelegate = context.coordinator.navigationManager
        webView.allowsBackForwardNavigationGestures = true

        // Disable automatic safe-area inset adjustment so the scrollView doesn't add a
        // content inset. The WKWebView frame is already positioned below the status bar
        // (top safe area) by SwiftUI, and the bottom edge extends under the home indicator
        // so VS Code and terminal can render edge-to-edge without a gap.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // VS Code Web pads its own layout using env(safe-area-inset-*). The JS injections
        // above set html.backgroundColor to match the loaded theme, but also cover the
        // WKWebView scrollView and underPage layers with the same dark default so nothing
        // appears white while the page is loading or over-scrolled.
        let vscDark = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)
        webView.underPageBackgroundColor = vscDark
        webView.scrollView.backgroundColor = vscDark

        // Disable rubber-banding so the view feels like a native app pane.
        webView.scrollView.bounces = false

        // Fix the zoom scale so pinch-to-zoom doesn't disrupt terminal or IDE views.
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0

        // Disable auto-correction on any native text inputs wired through this web view.
        webView.scrollView.keyboardDismissMode = .interactive

        context.coordinator.loadInitialPage(in: webView, token: token)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // State is driven by NavigationManager; no imperative updates on re-renders.
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "coderNative")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }
}

// MARK: - Coordinator

@MainActor
final class Coordinator: @unchecked Sendable {
    let navigationManager: NavigationManager
    let bridge: BridgeMessageHandler
    private let baseURL: URL
    private let token: String?

    init(baseURL: URL, enableNativeInterception: Bool) {
        self.baseURL = baseURL
        self.token = nil
        self.navigationManager = NavigationManager(
            baseURL: baseURL,
            enableNativeInterception: enableNativeInterception
        )
        self.bridge = BridgeMessageHandler()
    }

    /// Injects the session cookie (if available) then loads the base URL.
    func loadInitialPage(in webView: WKWebView, token: String?) {
        guard let token, !token.isEmpty,
              let cookie = CookieInjector.makeCookie(for: baseURL, token: token) else {
            webView.load(URLRequest(url: baseURL))
            return
        }

        Task { @MainActor in
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            webView.load(URLRequest(url: baseURL))
        }
    }
}
#endif
