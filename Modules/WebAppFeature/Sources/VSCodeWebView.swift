#if canImport(WebKit)
import SwiftUI
import WebKit

/// A SwiftUI view that wraps WKWebView for displaying VS Code Web.
///
/// Loads the provided URL in a WKWebView and handles navigation failures
/// by displaying an error message. Cleans up the WKWebView on disappearance.
public struct VSCodeWebView: View {
    @State private var viewModel: VSCodeWebViewModel
    private let onShortcut: (@Sendable (KeyboardShortcut) -> Void)?

    /// Creates a VS Code Web view for the given URL.
    /// - Parameters:
    ///   - url: The VS Code Web subdomain app URL to load.
    ///   - token: Optional session token for cookie injection.
    ///   - onShortcut: Optional callback for hardware keyboard shortcuts.
    public init(url: URL, token: String? = nil, onShortcut: (@Sendable (KeyboardShortcut) -> Void)? = nil) {
        _viewModel = State(initialValue: VSCodeWebViewModel(url: url, token: token))
        self.onShortcut = onShortcut
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                ErrorView(message: errorMessage) {
                    viewModel.clearError()
                    viewModel.navigationDidStart()
                }
            } else {
                WebViewRepresentable(viewModel: viewModel, onShortcut: onShortcut)
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

/// UIViewRepresentable wrapping WKWebView with navigation delegate support.
private struct WebViewRepresentable: UIViewRepresentable {
    let viewModel: VSCodeWebViewModel
    let onShortcut: (@Sendable (KeyboardShortcut) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let webView = ShortcutCapturingWebView()
        webView.onShortcut = onShortcut
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        viewModel.webView = webView

        viewModel.navigationDidStart()

        if let token = viewModel.token {
            Task { @MainActor in
                do {
                    try await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
                } catch {
                    viewModel.handleNavigationError(error)
                    return
                }
                let request = URLRequest(url: viewModel.url)
                webView.load(request)
            }
        } else {
            let request = URLRequest(url: viewModel.url)
            webView.load(request)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // State is driven by the view model; no imperative updates needed.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, @unchecked Sendable {
        let viewModel: VSCodeWebViewModel
        weak var webView: WKWebView?

        init(viewModel: VSCodeWebViewModel) {
            self.viewModel = viewModel
        }

        deinit {
            webView?.stopLoading()
            webView?.navigationDelegate = nil
            webView = nil
        }

        func webView(
            _ webView: WKWebView,
            didFail _: WKNavigation!,
            withError error: Error
        ) {
            viewModel.handleNavigationError(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation _: WKNavigation!,
            withError error: Error
        ) {
            viewModel.handleNavigationError(error)
        }

        func webView(
            _ webView: WKWebView,
            didFinish _: WKNavigation!
        ) {
            viewModel.navigationDidFinish()
        }
    }
}

/// Displays a navigation error with a retry option.
private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Failed to load")
                .font(.headline)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
#endif
