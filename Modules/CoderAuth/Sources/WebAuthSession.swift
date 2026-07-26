import Foundation

/// Protocol abstracting the web authentication session for testability.
///
/// On Apple platforms, this wraps `ASWebAuthenticationSession`.
/// A mock implementation is provided for testing on all platforms.
public protocol WebAuthSessionProviding: Sendable {
    /// Presents a web authentication session and returns the callback URL.
    ///
    /// - Parameters:
    ///   - url: The URL to present (the /cli-auth endpoint).
    ///   - callbackScheme: The custom URL scheme to intercept for the callback.
    /// - Returns: The callback URL received after successful authentication.
    /// - Throws: ``AuthError/cancelled`` if the user cancels the session.
    /// - Throws: ``AuthError/sessionError(_:)`` for other session failures.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// The URL scheme used for the Coder authentication callback.
public let coderCallbackScheme = "coder"

/// Constructs the /cli-auth URL for a given Coder server.
///
/// - Parameter serverURL: The base URL of the Coder deployment.
/// - Returns: The full /cli-auth URL.
/// - Throws: ``AuthError/invalidServerURL`` if the URL cannot be constructed.
public func makeCLIAuthURL(for serverURL: URL) throws -> URL {
    guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
        throw AuthError.invalidServerURL
    }
    // Append /cli-auth to the existing path
    let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
    components.path = basePath + "/cli-auth"
    guard let url = components.url else {
        throw AuthError.invalidServerURL
    }
    return url
}

#if canImport(AuthenticationServices)
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

/// A web authentication session provider backed by `ASWebAuthenticationSession`.
///
/// This is the production implementation used on iOS/macOS.
@available(iOS 17.0, macOS 14.0, *)
public final class ASWebAuthSessionProvider: NSObject, WebAuthSessionProviding, @unchecked Sendable {
    /// Thread-safe storage for the current session to prevent premature deallocation.
    @MainActor private static var currentSession: ASWebAuthenticationSession?

    override public init() {}

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // ASWebAuthenticationSession is not Sendable, so we create and
            // start it on the main actor.
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { callbackURL, error in
                    // Release the retained session now that the callback has fired.
                    Task { @MainActor in
                        ASWebAuthSessionProvider.currentSession = nil
                    }

                    if let error = error as? ASWebAuthenticationSessionError {
                        switch error.code {
                        case .canceledLogin:
                            continuation.resume(throwing: AuthError.cancelled)
                        default:
                            continuation.resume(throwing: AuthError.sessionError(error.localizedDescription))
                        }
                        return
                    }

                    if let error = error {
                        continuation.resume(throwing: AuthError.sessionError(error.localizedDescription))
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        continuation.resume(throwing: AuthError.invalidCallbackURL)
                        return
                    }

                    continuation.resume(returning: callbackURL)
                }

                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                // Retain the session as a class property so it is not deallocated
                // before the callback fires.
                ASWebAuthSessionProvider.currentSession = session
                session.start()
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension ASWebAuthSessionProvider: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
            ?? UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif

#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

/// A weak-reference proxy that breaks the retain cycle between WKUserContentController
/// (which strongly retains its message handlers) and WKWebViewAuthSessionProvider.
@available(iOS 17.0, *)
private final class WeakScriptMessageHandlerProxy: NSObject, WKScriptMessageHandler {
    weak var provider: WKWebViewAuthSessionProvider?

    init(provider: WKWebViewAuthSessionProvider) {
        self.provider = provider
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let token = message.body as? String, !token.isEmpty else { return }
        Task { @MainActor [weak provider = self.provider] in
            provider?.handleTokenMessage(token)
        }
    }
}

/// A web authentication session provider backed by WKWebView.
///
/// Unlike `ASWebAuthSessionProvider`, this provider supports JavaScript popup
/// windows (`window.open`) required by OIDC providers such as Vault that open
/// the identity provider login in a separate popup rather than a redirect.
///
/// Token capture: the Coder /cli-auth page never redirects back to a custom URL
/// scheme. Instead it calls GET /api/v2/users/me/keys and renders the token in
/// the UI. We inject a fetch interceptor that posts the token to native code as
/// soon as the API response arrives, so auth completes automatically without any
/// user interaction on the token page.
@available(iOS 17.0, *)
public final class WKWebViewAuthSessionProvider: NSObject, WebAuthSessionProviding, @unchecked Sendable {
    // All mutable state is accessed exclusively on the main actor.
    @MainActor private var continuation: CheckedContinuation<URL, Error>?
    @MainActor private var callbackScheme: String?
    @MainActor private var presentedNav: UINavigationController?
    @MainActor private var popupWebView: WKWebView?
    @MainActor private var popupVC: UIViewController?

    // Injected at document-start so clipboard APIs are patched before any page
    // code runs. Coder's useClipboard hook tries navigator.clipboard.writeText
    // first and falls back to document.execCommand('copy') via a hidden <input>.
    // We intercept both paths and forward the token to native code.
    private static let clipboardInterceptorScript = """
    (function() {
        function relay(text) {
            if (text && text.length > 0) {
                try { window.webkit.messageHandlers.coderToken.postMessage(text); } catch (_) {}
            }
        }

        // Primary path: navigator.clipboard.writeText
        if (navigator.clipboard) {
            const _orig = navigator.clipboard.writeText.bind(navigator.clipboard);
            Object.defineProperty(navigator.clipboard, 'writeText', {
                value: function(text) { relay(text); return _orig(text); },
                writable: true, configurable: true
            });
        }

        // Fallback path: document.execCommand('copy') via focused <input>
        const _execCmd = document.execCommand.bind(document);
        document.execCommand = function(cmd) {
            if (cmd === 'copy') {
                const el = document.activeElement;
                if (el && el.tagName === 'INPUT') relay(el.value);
            }
            return _execCmd.apply(document, arguments);
        };
    })();
    """

    // Evaluated after the /cli-auth page finishes loading. Clicks the
    // "Copy session token" button automatically; if React hasn't enabled it
    // yet, a MutationObserver retries until the button is ready.
    private static let autoClickScript = """
    (function() {
        function tryClick() {
            const btn = Array.from(document.querySelectorAll('button')).find(function(b) {
                return !b.disabled && b.textContent &&
                       b.textContent.replace(/\\s+/g, ' ').trim().includes('Copy session token');
            });
            if (btn) { btn.click(); return true; }
            return false;
        }
        if (!tryClick()) {
            const obs = new MutationObserver(function() { if (tryClick()) obs.disconnect(); });
            obs.observe(document.body, { subtree: true, childList: true, attributes: true });
            setTimeout(function() { obs.disconnect(); }, 30000);
        }
    })();
    """

    override public init() {}

    // Receives the session token extracted by the injected JS and synthesises
    // the coder:// callback URL that the rest of the auth stack expects.
    @MainActor
    func handleTokenMessage(_ token: String) {
        guard let scheme = callbackScheme else { return }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "cli-auth"
        components.queryItems = [URLQueryItem(name: "session_token", value: token)]
        guard let callbackURL = components.url else { return }
        finish(.success(callbackURL))
    }

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                guard self.continuation == nil else {
                    continuation.resume(throwing: AuthError.sessionError("Auth already in progress"))
                    return
                }
                self.continuation = continuation
                self.callbackScheme = callbackScheme

                let config = WKWebViewConfiguration()
                // Allow async window.open() calls (e.g. Vault fetches the OIDC
                // auth URL then calls window.open after the network response).
                config.preferences.javaScriptCanOpenWindowsAutomatically = true

                // Patch clipboard APIs before any page scripts run.
                let clipboardScript = WKUserScript(
                    source: Self.clipboardInterceptorScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
                config.userContentController.addUserScript(clipboardScript)
                config.userContentController.add(
                    WeakScriptMessageHandlerProxy(provider: self),
                    name: "coderToken"
                )

                let webView = WKWebView(frame: .zero, configuration: config)
                webView.navigationDelegate = self
                webView.uiDelegate = self
                webView.load(URLRequest(url: url))

                let authVC = AuthWebViewController(webView: webView) {
                    Task { @MainActor in self.finish(.failure(AuthError.cancelled)) }
                }
                let nav = UINavigationController(rootViewController: authVC)
                nav.modalPresentationStyle = .pageSheet
                self.presentedNav = nav
                self.topmostViewController()?.present(nav, animated: true)
            }
        }
    }

    @MainActor
    private func finish(_ result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        callbackScheme = nil
        popupWebView = nil
        popupVC = nil
        let nav = presentedNav
        presentedNav = nil
        nav?.dismiss(animated: true)
        switch result {
        case .success(let url): cont.resume(returning: url)
        case .failure(let error): cont.resume(throwing: error)
        }
    }

    @MainActor
    private func topmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

@available(iOS 17.0, *)
extension WKWebViewAuthSessionProvider: WKNavigationDelegate {
    // When the /cli-auth page finishes loading the user is authenticated.
    // Auto-click "Copy session token" — the clipboard intercept captures the
    // token and posts it to native, completing auth without user interaction.
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let path = webView.url?.path, path.hasSuffix("/cli-auth") else { return }
        webView.evaluateJavaScript(Self.autoClickScript, completionHandler: nil)
    }
}

@available(iOS 17.0, *)
extension WKWebViewAuthSessionProvider: WKUIDelegate {
    // Called when Vault (or any page in the auth flow) uses window.open() —
    // e.g. opening the Google OIDC login popup. The configuration parameter
    // is a WebKit-provided copy that shares the process pool with the parent,
    // which is required for window.opener / postMessage communication.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let vc = UIViewController()
        vc.view = popup
        presentedNav?.present(vc, animated: true)
        popupWebView = popup
        popupVC = vc
        return popup
    }

    // Called when the popup page calls window.close() after OIDC completes.
    public func webViewDidClose(_ webView: WKWebView) {
        guard webView === popupWebView else { return }
        popupVC?.dismiss(animated: true)
        popupWebView = nil
        popupVC = nil
    }
}

/// A UIViewController that embeds a WKWebView for the auth flow.
@available(iOS 17.0, *)
private final class AuthWebViewController: UIViewController {
    private let webView: WKWebView
    private let onCancel: @MainActor () -> Void

    init(webView: WKWebView, onCancel: @escaping @MainActor () -> Void) {
        self.webView = webView
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // When embedded in a UINavigationController and the sheet is swiped away,
        // isBeingDismissed is false on the child — only the nav controller is marked
        // as being dismissed. Check both to catch all dismissal paths.
        let isDismissed = isBeingDismissed
            || navigationController?.isBeingDismissed == true
            || isMovingFromParent
        if isDismissed {
            Task { @MainActor in self.onCancel() }
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

#endif // canImport(UIKit) && canImport(WebKit)

/// Thread-safe mutable state for the mock web auth session provider.
private final class MockWebAuthState: @unchecked Sendable {
    private let lock = NSLock()
    private var _callbackURL: URL?
    private var _error: Error?
    private var _authenticateCallCount = 0
    private var _capturedURL: URL?
    private var _capturedScheme: String?

    init(callbackURL: URL?, error: Error?) {
        self._callbackURL = callbackURL
        self._error = error
    }

    /// Atomically increments the call count, captures inputs, and returns current config.
    func recordCall(url: URL, scheme: String) -> (error: Error?, callbackURL: URL?) {
        lock.lock(); defer { lock.unlock() }
        _authenticateCallCount += 1
        _capturedURL = url
        _capturedScheme = scheme
        return (_error, _callbackURL)
    }

    var authenticateCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _authenticateCallCount
    }

    var capturedURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return _capturedURL
    }

    var capturedScheme: String? {
        lock.lock(); defer { lock.unlock() }
        return _capturedScheme
    }

    func configure(callbackURL: URL?, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        _callbackURL = callbackURL
        _error = error
    }
}

/// A mock web authentication session provider for testing.
public final class MockWebAuthSessionProvider: WebAuthSessionProviding, Sendable {
    private let state: MockWebAuthState

    /// The number of times `authenticate` was called.
    public var authenticateCallCount: Int {
        state.authenticateCallCount
    }

    /// The URL that was passed to the most recent `authenticate` call.
    public var capturedURL: URL? {
        state.capturedURL
    }

    /// The callback scheme that was passed to the most recent `authenticate` call.
    public var capturedScheme: String? {
        state.capturedScheme
    }

    /// Creates a new mock provider.
    /// - Parameters:
    ///   - callbackURL: The callback URL to return on success.
    ///   - error: The error to throw (takes precedence over callbackURL).
    public init(callbackURL: URL? = nil, error: Error? = nil) {
        self.state = MockWebAuthState(callbackURL: callbackURL, error: error)
    }

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let (error, callbackURL) = state.recordCall(url: url, scheme: callbackScheme)

        if let error {
            throw error
        }

        guard let callbackURL else {
            throw AuthError.invalidCallbackURL
        }

        return callbackURL
    }

    /// Configures the mock's behavior for subsequent calls.
    public func configure(callbackURL: URL? = nil, error: Error? = nil) {
        state.configure(callbackURL: callbackURL, error: error)
    }
}
