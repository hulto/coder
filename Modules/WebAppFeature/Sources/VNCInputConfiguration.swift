import Foundation

/// The native `UIScrollView` input settings applied to the `WKWebView` that
/// hosts the KasmVNC/noVNC web client.
///
/// This type exists so the settings governing zoom ownership, scroll/bounce
/// behavior, and content inset handling are data, not inline literals,
/// letting their defaults be asserted by tests that run on Linux (there is
/// no `WKWebView`/`UIScrollView` available outside an Apple platform).
/// `VNCWebView.swift` applies this same configuration to the real
/// `WKWebView.scrollView` under `#if canImport(WebKit)`.
struct VNCInputConfiguration: Sendable, Equatable {
    /// Whether the scroll view's built-in pinch gesture recognizer is
    /// enabled. `false` so WebKit's page-zoom layer never competes with
    /// noVNC's own canvas zoom for the pinch gesture.
    var pinchGestureRecognizerEnabled: Bool

    /// Minimum page-zoom scale. Pinned equal to `maximumZoomScale` so
    /// WebKit never bitmap-rescales the canvas.
    var minimumZoomScale: Double

    /// Maximum page-zoom scale. Pinned equal to `minimumZoomScale` so
    /// WebKit never bitmap-rescales the canvas.
    var maximumZoomScale: Double

    /// Whether the scroll view rubber-bands past the zoom limits.
    /// `false` since zoom is pinned to a single scale; there is nothing to
    /// bounce past.
    var bouncesZoom: Bool

    /// Whether the scroll view rubber-bands at scroll boundaries. `false`
    /// because the canvas is a single full-bleed surface, not a scrolling
    /// document.
    var bounces: Bool

    /// Whether native panning is enabled on the scroll view. `false`
    /// because the canvas is a single full-bleed surface, not a scrolling
    /// document; native panning would drift the viewport instead of
    /// reaching noVNC's own drag handling.
    var isScrollEnabled: Bool

    /// Whether the vertical scroll indicator is shown. `false`; there is no
    /// scrollable document to indicate a position within.
    var showsVerticalScrollIndicator: Bool

    /// Whether the horizontal scroll indicator is shown. `false`; there is
    /// no scrollable document to indicate a position within.
    var showsHorizontalScrollIndicator: Bool

    /// Content inset adjustment behavior. `true` maps to `.never`
    /// (represented here as a `Bool` so this type stays platform-agnostic
    /// and does not need to import `UIKit`) so safe-area insets never
    /// shift the canvas's coordinate space out from under the
    /// pointer/touch input noVNC is tracking.
    var contentInsetAdjustmentBehaviorIsNever: Bool

    /// The configuration this task applies to every VNC session's
    /// `WKWebView.scrollView`.
    static let vncDefault = VNCInputConfiguration(
        pinchGestureRecognizerEnabled: false,
        minimumZoomScale: 1.0,
        maximumZoomScale: 1.0,
        bouncesZoom: false,
        bounces: false,
        isScrollEnabled: false,
        showsVerticalScrollIndicator: false,
        showsHorizontalScrollIndicator: false,
        contentInsetAdjustmentBehaviorIsNever: true
    )
}
