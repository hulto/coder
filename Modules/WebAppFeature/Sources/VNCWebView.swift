#if canImport(UIKit)
import SwiftUI
import UIKit
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

        configureForVNCInput(webView)

        viewModel.navigationDidStart()

        if let token = viewModel.token {
            viewModel.injectionTask = Task { @MainActor [viewModel] in
                #if canImport(os)
                os_log(.info, "Starting cookie injection for VNC")
                #else
                print("[VNCWebView] Starting cookie injection")
                #endif

                do {
                    try await CookieInjector.injectCookies(into: webView, for: viewModel.url, token: token)
                } catch {
                    guard !Task.isCancelled else { return }
                    viewModel.handleNavigationError(error)
                    return
                }

                guard !Task.isCancelled else { return }

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
        // Re-assert scroll/zoom configuration on every SwiftUI update.
        // `configureForVNCInput` writes each property idempotently (only
        // when the current value differs), so calling it here is a true
        // no-op once the configuration is already applied and cannot
        // cancel an in-flight gesture: a recognizer's `isEnabled` is only
        // ever written when it is already the target value, so a drag or
        // pinch mid-recognition on the guest desktop is never interrupted
        // by an unrelated SwiftUI re-render (e.g. `viewModel.isLoading`
        // toggling while the user's fingers are still down).
        configureForVNCInput(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    /// Configures the web view's scroll view so native gestures don't
    /// compete with the noVNC JavaScript client's own input handling.
    ///
    /// The embedded KasmVNC/noVNC web client renders a single full-bleed
    /// `<canvas>` and owns all touch, pointer, and keyboard translation to
    /// RFB itself, including its own pinch-to-zoom/pan handling. Without
    /// this configuration, `WKWebView`'s default `UIScrollView` would
    /// compete with the page for the same gestures: native page-zoom would
    /// blur-scale the canvas as a bitmap while stealing the pinch gesture
    /// noVNC needs, and native scrolling/bounce would drift the viewport
    /// whenever the user drags inside the guest desktop.
    ///
    /// Every property write below is idempotent (checked before written) so
    /// this method is safe to call from `updateUIView` on every SwiftUI
    /// re-render: writing `pinchGestureRecognizer?.isEnabled` on a
    /// recognizer that is mid-recognition forces it to `.cancelled`, so
    /// re-asserting an already-correct value must never happen.
    private func configureForVNCInput(_ webView: WKWebView) {
        let scrollView = webView.scrollView
        let configuration = VNCInputConfiguration.vncDefault

        // Zoom ownership: the noVNC JavaScript client owns zoom, not
        // WKWebView's page-zoom layer. The authoritative setting is pinning
        // `minimumZoomScale == maximumZoomScale == 1.0`, which prevents
        // WebKit from ever bitmap-rescaling the page; noVNC's own JS touch
        // handlers continue to receive the underlying touch events
        // independently of this scroll view's gesture recognizers.
        // Disabling the pinch gesture recognizer and `bouncesZoom` are
        // defensive/redundant: they stop this scroll view's own recognizer
        // from consuming the gesture, but do not themselves route anything
        // to the page.
        let wantsPinchEnabled = configuration.pinchGestureRecognizerEnabled
        if scrollView.pinchGestureRecognizer?.isEnabled != wantsPinchEnabled {
            scrollView.pinchGestureRecognizer?.isEnabled = wantsPinchEnabled
        }
        let wantsMinZoom = configuration.minimumZoomScale
        if scrollView.minimumZoomScale != wantsMinZoom {
            scrollView.minimumZoomScale = wantsMinZoom
        }
        let wantsMaxZoom = configuration.maximumZoomScale
        if scrollView.maximumZoomScale != wantsMaxZoom {
            scrollView.maximumZoomScale = wantsMaxZoom
        }
        let wantsBouncesZoom = configuration.bouncesZoom
        if scrollView.bouncesZoom != wantsBouncesZoom {
            scrollView.bouncesZoom = wantsBouncesZoom
        }

        // Scroll/bounce: the page is a single full-bleed canvas, not a
        // scrolling document, so native panning, scroll indicators, and
        // rubber-band bounce would visually drift the viewport whenever the
        // user drags inside the guest OS. `contentInsetAdjustmentBehavior`
        // is pinned to `.never` rather than left at `.automatic` so
        // safe-area insets never shift the canvas's coordinate space out
        // from under the pointer/touch input noVNC is tracking.
        let wantsScrollEnabled = configuration.isScrollEnabled
        if scrollView.isScrollEnabled != wantsScrollEnabled {
            scrollView.isScrollEnabled = wantsScrollEnabled
        }
        let wantsBounces = configuration.bounces
        if scrollView.bounces != wantsBounces {
            scrollView.bounces = wantsBounces
        }
        let wantsVerticalIndicator = configuration.showsVerticalScrollIndicator
        if scrollView.showsVerticalScrollIndicator != wantsVerticalIndicator {
            scrollView.showsVerticalScrollIndicator = wantsVerticalIndicator
        }
        let wantsHorizontalIndicator = configuration.showsHorizontalScrollIndicator
        if scrollView.showsHorizontalScrollIndicator != wantsHorizontalIndicator {
            scrollView.showsHorizontalScrollIndicator = wantsHorizontalIndicator
        }
        let wantsNeverInsetAdjustment = configuration.contentInsetAdjustmentBehaviorIsNever
        let hasNeverInsetAdjustment = scrollView.contentInsetAdjustmentBehavior == .never
        if hasNeverInsetAdjustment != wantsNeverInsetAdjustment {
            scrollView.contentInsetAdjustmentBehavior = wantsNeverInsetAdjustment ? .never : .automatic
        }

        // Trackpad/pointer: WKWebView already provides `UIPointerInteraction`
        // support over web content for free (Magic Keyboard / trackpad hover
        // and click), and nothing above touches pointer interactions or
        // gesture recognizers other than the scroll view's own pinch
        // recognizer. No explicit pointer configuration is added here; the
        // built-in behavior is sufficient and is left untouched.
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, @unchecked Sendable {
        let viewModel: VNCWebViewModel
        weak var webView: WKWebView?

        init(viewModel: VNCWebViewModel) {
            self.viewModel = viewModel
        }

        // Deliberately empty: `webView` is a weak reference, so it needs no
        // manual nil-out, and WKWebView stops loading on dealloc. Actual
        // teardown (stopLoading, clearing navigationDelegate) happens
        // deterministically in VNCWebViewModel.cleanup(), called from
        // onDisappear. A nonisolated deinit must not touch MainActor-only
        // UIKit APIs.
        deinit {}

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
#endif // canImport(UIKit)
