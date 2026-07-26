#if canImport(WebKit)
import SwiftUI
import WebKit
#if canImport(os)
import os
#endif

/// A SwiftUI view that wraps WKWebView for displaying a VNC session (noVNC/KasmVNC).
///
/// Loads the provided URL in a WKWebView and handles navigation failures
/// by displaying an error message. Cleans up the WKWebView on disappearance.
public struct VNCWebView: View {
    @State private var viewModel: VNCWebViewModel

    /// Creates a VNC web view for the given URL.
    /// - Parameters:
    ///   - url: The VNC subdomain app URL to load.
    ///   - token: Optional session token for cookie injection.
    public init(url: URL, token: String? = nil) {
        _viewModel = State(initialValue: VNCWebViewModel(url: url, token: token))
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                ErrorView(message: errorMessage) {
                    viewModel.clearError()
                    viewModel.navigationDidStart()
                }
            } else {
                WebViewRepresentable(viewModel: viewModel)
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

/// UIViewRepresentable wrapping WKWebView with navigation delegate support.
private struct WebViewRepresentable: UIViewRepresentable {
    let viewModel: VNCWebViewModel

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        viewModel.webView = webView

        viewModel.navigationDidStart()

        if let token = viewModel.token {
            Task { @MainActor in
                #if canImport(os)
                os_log(.info, "Starting cookie injection for VNC")
                #else
                print("[VNCWebView] Starting cookie injection")
                #endif
                
                await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
                
                #if canImport(os)
                os_log(.info, "Cookie injection complete, loading VNC session")
                #else
                print("[VNCWebView] Cookie injection complete, loading VNC session")
                #endif
                
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
        let viewModel: VNCWebViewModel
        weak var webView: WKWebView?

        init(viewModel: VNCWebViewModel) {
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
