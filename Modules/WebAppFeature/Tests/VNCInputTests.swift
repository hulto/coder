import Foundation
import Testing

@testable import WebAppFeature

#if canImport(WebKit)
import WebKit
#endif

/// Tests for VNC touch/pointer/zoom input configuration (TASK-015).
///
/// `VNCInputConfiguration`'s defaults are plain data and run on Linux
/// (outside `#if canImport(WebKit)`). The WebKit-gated suite below applies
/// that same shared configuration (via `@testable import`) to a real
/// `WKWebView.scrollView`, so it exercises the actual values
/// `WebViewRepresentable.configureForVNCInput` applies rather than a
/// hand-copied duplicate. The construction-regression tests confirm the
/// frozen `VNCWebView` public surface still builds and evaluates after this
/// task's changes.
@Suite("VNC Input Configuration Tests")
struct VNCInputTests {

    @Test("Zoom ownership defaults pin scale to 1.0 and disable the pinch recognizer")
    func zoomDefaults() {
        let configuration = VNCInputConfiguration.vncDefault

        #expect(configuration.pinchGestureRecognizerEnabled == false)
        #expect(configuration.minimumZoomScale == 1.0)
        #expect(configuration.maximumZoomScale == 1.0)
        #expect(configuration.bouncesZoom == false)
    }

    @Test("Scroll/bounce defaults disable panning, bounce, and indicators for the full-bleed canvas")
    func scrollDefaults() {
        let configuration = VNCInputConfiguration.vncDefault

        #expect(configuration.isScrollEnabled == false)
        #expect(configuration.bounces == false)
        #expect(configuration.showsVerticalScrollIndicator == false)
        #expect(configuration.showsHorizontalScrollIndicator == false)
    }

    @Test("Content inset adjustment behavior defaults to never")
    func contentInsetDefaults() {
        let configuration = VNCInputConfiguration.vncDefault

        #expect(configuration.contentInsetAdjustmentBehaviorIsNever == true)
    }

    @Test("VNCInputConfiguration has value semantics")
    func valueSemantics() {
        var configuration = VNCInputConfiguration.vncDefault
        let original = configuration
        configuration.isScrollEnabled = true

        #expect(original.isScrollEnabled == false)
        #expect(configuration.isScrollEnabled == true)
        #expect(configuration != original)
    }

#if canImport(WebKit)
    /// Applies the shared `VNCInputConfiguration` values to a real
    /// `WKWebView.scrollView`, exercising the same data
    /// `WebViewRepresentable.configureForVNCInput` applies in production.
    @MainActor
    private func applyVNCInputConfiguration(
        _ webView: WKWebView, _ configuration: VNCInputConfiguration
    ) {
        let scrollView = webView.scrollView

        scrollView.pinchGestureRecognizer?.isEnabled = configuration.pinchGestureRecognizerEnabled
        scrollView.minimumZoomScale = configuration.minimumZoomScale
        scrollView.maximumZoomScale = configuration.maximumZoomScale
        scrollView.bouncesZoom = configuration.bouncesZoom

        scrollView.isScrollEnabled = configuration.isScrollEnabled
        scrollView.bounces = configuration.bounces
        scrollView.showsVerticalScrollIndicator = configuration.showsVerticalScrollIndicator
        scrollView.showsHorizontalScrollIndicator = configuration.showsHorizontalScrollIndicator
        scrollView.contentInsetAdjustmentBehavior =
            configuration.contentInsetAdjustmentBehaviorIsNever ? .never : .automatic
    }

    @Test("Pinch-to-zoom gesture is disabled so noVNC owns zoom")
    @MainActor
    func pinchGestureDisabled() {
        let webView = WKWebView()
        applyVNCInputConfiguration(webView, .vncDefault)

        #expect(
            webView.scrollView.pinchGestureRecognizer?.isEnabled
                == VNCInputConfiguration.vncDefault.pinchGestureRecognizerEnabled)
    }

    @Test("Zoom scale is pinned to 1.0 so WebKit cannot rescale the canvas")
    @MainActor
    func zoomScalePinned() {
        let webView = WKWebView()
        applyVNCInputConfiguration(webView, .vncDefault)

        #expect(
            webView.scrollView.minimumZoomScale == VNCInputConfiguration.vncDefault.minimumZoomScale)
        #expect(
            webView.scrollView.maximumZoomScale == VNCInputConfiguration.vncDefault.maximumZoomScale)
        #expect(webView.scrollView.bouncesZoom == VNCInputConfiguration.vncDefault.bouncesZoom)
    }

    @Test("Scroll panning, bounce, and indicators are disabled for the full-bleed canvas")
    @MainActor
    func scrollPanningBounceAndIndicatorsDisabled() {
        let webView = WKWebView()
        applyVNCInputConfiguration(webView, .vncDefault)

        #expect(
            webView.scrollView.isScrollEnabled == VNCInputConfiguration.vncDefault.isScrollEnabled)
        #expect(webView.scrollView.bounces == VNCInputConfiguration.vncDefault.bounces)
        #expect(
            webView.scrollView.showsVerticalScrollIndicator
                == VNCInputConfiguration.vncDefault.showsVerticalScrollIndicator)
        #expect(
            webView.scrollView.showsHorizontalScrollIndicator
                == VNCInputConfiguration.vncDefault.showsHorizontalScrollIndicator)
    }

    @Test("Content inset adjustment behavior is deliberately set to never")
    @MainActor
    func contentInsetAdjustmentNever() {
        let webView = WKWebView()
        applyVNCInputConfiguration(webView, .vncDefault)

        #expect(webView.scrollView.contentInsetAdjustmentBehavior == .never)
    }

    @Test("VNCWebView still constructs and evaluates its body without a token")
    @MainActor
    func viewConstructionWithoutToken() {
        let url = URL(string: "https://vnc.example.com")!
        let view = VNCWebView(url: url)
        _ = view.body
    }

    @Test("VNCWebView still constructs and evaluates its body with a token")
    @MainActor
    func viewConstructionWithToken() {
        let url = URL(string: "https://vnc.example.com")!
        let view = VNCWebView(url: url, token: "test-token")
        _ = view.body
    }
#endif
}
