#if canImport(WebKit)
import Foundation
import UIKit
import WebKit
import OSLog

private let logger = Logger(subsystem: "com.coder.ios", category: "NavigationManager")

/// Classifies a navigation URL to determine whether it targets a native view.
public enum RouteInterceptor: Sendable {
    /// Standard Coder web UI — pass through to WKWebView.
    case passThrough
    /// VS Code Web session path (`/code` prefix or `/@owner/workspace` pattern).
    case vscodeWeb(URL)
    /// Web terminal path.
    case terminal(URL)
    /// VNC remote-desktop path.
    case vnc(URL)
}

extension RouteInterceptor {
    /// Classifies `url` against known native route patterns.
    ///
    /// Only URLs whose host matches `baseURL` are eligible for interception;
    /// external navigations always return `.passThrough`.
    public static func classify(_ url: URL, baseURL: URL?) -> RouteInterceptor {
        guard let host = url.host, host == baseURL?.host else { return .passThrough }
        let path = url.path
        if path.hasPrefix("/code") ||
            path.range(of: #"^/@[^/]+/[^/]+"#, options: .regularExpression) != nil {
            return .vscodeWeb(url)
        }
        if path.contains("/terminal") {
            return .terminal(url)
        }
        if path.contains("/vnc") {
            return .vnc(url)
        }
        return .passThrough
    }
}

/// Full-screen view controller that hosts a popup WKWebView with a dismiss button.
private final class PopupViewController: UIViewController {
    private let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        // Semi-transparent backing so the button is visible over both dark and light content.
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        closeButton.layer.cornerRadius = 16
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc private func handleClose() {
        dismiss(animated: true)
    }
}

/// Handles WKWebView navigation decisions and route interception for the Coder shell.
///
/// Set this as the `navigationDelegate` on the primary WKWebView. When
/// `enableNativeInterception` is false (the default), all classified routes still
/// pass through to the web view so the feature flag is safe to ship before native
/// views are ready.
@MainActor
public final class NavigationManager: NSObject, WKNavigationDelegate, WKUIDelegate, @unchecked Sendable {
    /// The Coder deployment base URL used for same-host validation.
    public let baseURL: URL?

    /// When true, intercepted routes cancel web navigation and invoke native stubs.
    public let enableNativeInterception: Bool

    /// Called when navigation fails with an error.
    public var onNavigationError: ((Error) -> Void)?

    /// Called when navigation completes successfully.
    public var onNavigationFinished: (() -> Void)?

    // Retained so the popup WKWebView isn't deallocated before it is dismissed.
    private var popupWebView: WKWebView?

    public init(baseURL: URL?, enableNativeInterception: Bool = false) {
        self.baseURL = baseURL
        self.enableNativeInterception = enableNativeInterception
    }

    // MARK: - WKNavigationDelegate

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = navigationAction.request.url else {
            return (.allow, preferences)
        }

        switch RouteInterceptor.classify(url, baseURL: baseURL) {
        case .passThrough:
            return (.allow, preferences)

        case .vscodeWeb(let target):
            logger.debug("Route: vscodeWeb \(target.absoluteString)")
            if enableNativeInterception {
                handleNativeVSCode(url: target)
                return (.cancel, preferences)
            }
            return (.allow, preferences)

        case .terminal(let target):
            logger.debug("Route: terminal \(target.absoluteString)")
            if enableNativeInterception {
                handleNativeTerminal(url: target)
                return (.cancel, preferences)
            }
            return (.allow, preferences)

        case .vnc(let target):
            logger.debug("Route: vnc \(target.absoluteString)")
            if enableNativeInterception {
                handleNativeVNC(url: target)
                return (.cancel, preferences)
            }
            return (.allow, preferences)
        }
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        onNavigationError?(error)
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        onNavigationError?(error)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onNavigationFinished?()
    }

    // MARK: - WKUIDelegate

    /// Handles `window.open()` and `target="_blank"` popup requests from the web UI.
    ///
    /// WKWebView blocks popups unless a `WKUIDelegate` is set. Coder's terminal and
    /// other app routes open in new windows, which would show a "Popup blocked" error
    /// without this. When native interception is on, known routes are handed to their
    /// native handlers. Otherwise the popup is presented in a modal sheet so the main
    /// web view stays on the workspace page and `window.opener` semantics work correctly.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        if enableNativeInterception {
            switch RouteInterceptor.classify(url, baseURL: baseURL) {
            case .terminal(let target):
                logger.debug("Popup native: terminal \(target.absoluteString)")
                handleNativeTerminal(url: target)
                return nil
            case .vscodeWeb(let target):
                logger.debug("Popup native: vscodeWeb \(target.absoluteString)")
                handleNativeVSCode(url: target)
                return nil
            case .vnc(let target):
                logger.debug("Popup native: vnc \(target.absoluteString)")
                handleNativeVNC(url: target)
                return nil
            case .passThrough:
                break
            }
        }

        logger.debug("Popup: presenting fullscreen for \(url.absoluteString)")
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        let vc = PopupViewController(webView: popup)
        topmostViewController()?.present(vc, animated: true)
        popupWebView = popup
        return popup
    }

    /// Dismisses the fullscreen popup when the page calls `window.close()`.
    public func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        topmostViewController()?.dismiss(animated: true)
        popupWebView = nil
    }

    private func topmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: - Native Route Stubs
    //
    // To add a native view for a route:
    // 1. Add a matching pattern in RouteInterceptor.classify(_:baseURL:).
    // 2. Add a case to RouteInterceptor.
    // 3. Handle it in decidePolicyFor.
    // 4. Replace the stub below with a call that presents the native view.
    // See NATIVE_ROUTES.md for a complete walkthrough.

    private func handleNativeVSCode(url: URL) {
        logger.info("Native VS Code stub triggered for \(url.absoluteString)")
    }

    private func handleNativeTerminal(url: URL) {
        logger.info("Native terminal stub triggered for \(url.absoluteString)")
    }

    private func handleNativeVNC(url: URL) {
        logger.info("Native VNC stub triggered for \(url.absoluteString)")
    }
}
#endif
