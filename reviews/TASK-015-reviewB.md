# Review TASK-015 — Reviewer B (security / concurrency / iOS architecture)

Scope reviewed in full: `Modules/WebAppFeature/Sources/VNCWebView.swift` (new
`configureForVNCInput(_:)` at :112-144, call sites :50 and :94) and
`Modules/WebAppFeature/Tests/VNCInputTests.swift`. Cross-referenced but not
re-reviewed (settled): `VNCWebViewModel.swift`, `CookieInjector.swift`,
`VSCodeWebView.swift`, `VNCCookieInjectionTests.swift`.

## Passing checks

- **Diff scope**: `configureForVNCInput` and every `scrollView.*` assignment
  exist only in `VNCWebView.swift`. No such symbol in `VNCWebViewModel.swift`,
  `CookieInjector.swift`, `VSCodeWebView.swift`, `VSCodeWebViewModel.swift`,
  `KeyboardShortcutHandler.swift`. Criterion 3 holds.
- **Public API**: `public init(url: URL, token: String? = nil)`
  byte-identical. `configureForVNCInput` is `private` on a `private struct`.
  No new public symbol. Criterion 2 holds.
- **Secrets**: nothing new logged; pre-existing `os_log` calls interpolate no
  URL or token.
- **MainActor**: `UIViewRepresentable`'s requirements are `@MainActor`, so
  `configureForVNCInput` is inferred `@MainActor` as an instance method of
  the conformer; both call sites are already MainActor-isolated. No new
  `Task`, closure capture, shared mutable state, or retain-cycle surface.
- **Criterion 9**: `configureForVNCInput(webView)` is inserted at :50, before
  `navigationDidStart()` and before any `load(request)`; the TASK-014
  injection-precedes-load ordering at :52-84 is untouched.

## Gate verification — NOT CONFIRMED

Reviewer had no shell in this session. Independently: all of
`VNCWebView.swift` is inside `#if canImport(WebKit)` (:1/:210), false on this
Linux sandbox, and **all six** tests in `VNCInputTests.swift` are inside
`#if canImport(WebKit)` (:22/:99). A green Linux gate compiles this task's
entire deliverable and its entire test file to nothing. See B1.

## REQUIRED findings

```yaml
- id: B1
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Tests/VNCInputTests.swift:22-99
  evidence: |
    @Suite("VNC Input Configuration Tests")
    struct VNCInputTests {
    #if canImport(WebKit)
        ... all six @Test functions ...
    #endif
    }
  rule: RUBRIC-B/sendable-compliance
  required_change: "This task's test file has ZERO Linux-runnable assertions: every @Test is inside `#if canImport(WebKit)`, so on the only platform the gate actually runs, VNCInputTests is an empty struct and `swift test` green-lights nothing this task wrote. Spec criterion 8 explicitly requires Linux-runnable coverage ('outside #if canImport(WebKit)'). Either (a) extract the eight settings into an internal Sendable `VNCInputConfiguration` declared outside the WebKit guard, assert its defaults on Linux, and have configureForVNCInput apply it, or (b) attach real Apple-SDK build/test output proving these six tests compile and pass. Do not ship a green Linux gate as evidence for this task."

- id: B2
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Tests/VNCInputTests.swift:30-42
  evidence: |
    /// Mirrors the scroll/zoom/pointer configuration applied by
    /// `WebViewRepresentable.configureForVNCInput`.
    private func applyVNCInputConfiguration(_ webView: WKWebView) {
        let scrollView = webView.scrollView
        scrollView.pinchGestureRecognizer?.isEnabled = false
        scrollView.minimumZoomScale = 1.0
        ...
    }
  rule: RUBRIC-B/error-propagation
  required_change: "These tests are tautological. applyVNCInputConfiguration is a hand-copied duplicate of the production body; each test sets a property then asserts that same property has the value it just set. They exercise UIScrollView, not configureForVNCInput. Delete the configureForVNCInput call from updateUIView, or change contentInsetAdjustmentBehavior to .always in production, and all six still pass. Make the production code reachable: hoist the settings into an internal Sendable VNCInputConfiguration with an internal @MainActor WebKit-gated apply(to:) called by BOTH configureForVNCInput and the tests. `@testable import WebAppFeature` is already present, so internal visibility suffices."

- id: B3
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:115-121
  evidence: |
    // ... so the gesture reaches noVNC's own canvas zoom/`clip` mode
    // handling instead.
    scrollView.pinchGestureRecognizer?.isEnabled = false
  rule: RUBRIC-B/wkwebview-config
  required_change: "The comment asserts a causal mechanism that is not how UIKit gesture recognizers work, and that assertion is load-bearing for criteria 4 and 5. Setting isEnabled = false cancels in-progress recognition and stops the recognizer receiving touches; it does NOT forward or hand the gesture to WebKit's touch-event pipeline. Whether the pinch reaches noVNC's JS touchstart/touchmove depends on WKWebView's internal touch-event delivery (largely independent of the scrollView's pinch recognizer) and on whether noVNC calls preventDefault(). The setting that actually prevents visible page rescaling is pinning minimumZoomScale == maximumZoomScale == 1.0, and it is sufficient alone. Either correct the comment to claim only what is verifiable ('WebKit page zoom is pinned to 1.0 so the canvas is never bitmap-rescaled; noVNC's own JS touch handlers continue to receive touch events') and drop the 'so the gesture reaches noVNC' claim, or cite the specific WebKit behavior that justifies it. As written, criterion 5 is satisfied by a possibly-false claim, and criterion 4's 'exactly once' is arguably violated: three overlapping knobs are set for one decision without stating which is authoritative."

- id: B4
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:89-95
  evidence: |
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Re-assert scroll/zoom configuration on every SwiftUI update. UIKit
        // does not guarantee these `scrollView` properties survive internal
        // WKWebView relayout, so the safest contract is "always correct"
        // rather than "correct once at creation".
        configureForVNCInput(uiView)
    }
  rule: RUBRIC-B/lifecycle-aware
  required_change: "Unconditionally re-asserting pinchGestureRecognizer?.isEnabled = false on every re-render is not inert. Writing isEnabled on a recognizer that is mid-recognition forces a transition to .cancelled and re-delivers touchesCancelled(_:with:) to its view. SwiftUI calls updateUIView on any ancestor state change, which will land mid-gesture (e.g. viewModel.isLoading flipping while fingers are down), so this can cancel an in-flight drag inside the guest desktop, exactly the bug this task exists to prevent. contentInsetAdjustmentBehavior and min/maximumZoomScale writes additionally invalidate scroll-view layout each render. Guard each assignment for idempotence (`if pinch.isEnabled { pinch.isEnabled = false }`, `if scrollView.bounces { scrollView.bounces = false }`, etc.), or drop the updateUIView call. The comment's justification is asserted without evidence: UIScrollView does not reset caller-set bounces/zoomScale/contentInsetAdjustmentBehavior on relayout. If a concrete WebKit reset case exists, name it; otherwise the call is unjustified cost plus gesture-cancellation risk."
```

## OPTIONAL findings

```yaml
- id: B5
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:136
  evidence: "scrollView.contentInsetAdjustmentBehavior = .never"
  rule: RUBRIC-B/lifecycle-aware
  required_change: "`.never` lays the canvas out under the home indicator and notch, and on iPad in Stage Manager / Split View under the window's rounded corners and drag handle. The comment's justification (stable coordinate space for noVNC pointer tracking) is defensible for a remote desktop, but the bottom rows of the guest desktop become occluded and the bottom ~20pt becomes a home-indicator swipe zone that will steal drags. Consider pairing `.never` with a deliberate `.ignoresSafeArea()` at the SwiftUI layer or contentInset compensation, and add Stage Manager occlusion to the human device checklist."

- id: B6
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:126-136
  evidence: |
    scrollView.bounces = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
  rule: RUBRIC-B/lifecycle-aware
  required_change: "isScrollEnabled is left at its default true. With bounces = false and zoom pinned, the scroll view still pans whenever content exceeds the viewport (transiently during noVNC load, on rotation, when the software keyboard resizes the viewport), reintroducing the exact 'viewport drift' the comment claims to eliminate. Either set scrollView.isScrollEnabled = false or document why panning is deliberately retained. As written the stated intent and the code disagree."

- id: B7
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Tests/VNCInputTests.swift:87,93
  evidence: 'let url = URL(string: "https://vnc.example.com")!'
  rule: RUBRIC-B/no-force-unwraps
  required_change: "Force unwraps in test code. Matches existing precedent in VNCWebViewTests.swift, so not blocking, but `try #require(URL(string:))` avoids a crash-on-typo that reports as a signal rather than a test failure."

- id: B8
  severity: nit
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:138-143
  evidence: |
    // Trackpad/pointer: WKWebView already provides `UIPointerInteraction`
    // support over web content for free ... No explicit pointer
    // configuration is added here.
  rule: RUBRIC-B/wkwebview-config
  required_change: "Satisfies criterion 7 as a documented no-op, which the spec permits. But the criterion asked for a check that this task's changes do not break pointer support; disabling pinchGestureRecognizer does alter the scroll view's recognizer set. Trackpad two-finger scroll on iPadOS is delivered via the pan recognizer, not the pinch one, so the claim is probably right but unverified here. Add trackpad two-finger scroll explicitly to the human device checklist."
```

## Summary of the crux question (does disabling pinchGestureRecognizer hand the gesture to noVNC's JS?)

Disabling `pinchGestureRecognizer` is **not** a mechanism for handing the
pinch to the page's JS. It removes one consumer; it does not route
anything. The property doing the real work is the pinned
`minimumZoomScale`/`maximumZoomScale`. Whether noVNC's JS actually receives
the touch stream is a WebKit touch-delivery question this sandbox cannot
answer, and the comment states it as settled fact. That overclaim is B3.

The `updateUIView` re-assertion (B4) is the more concrete risk: `isEnabled`
writes cancel in-flight recognition, and SwiftUI re-renders are not
synchronized with user gestures.

VERDICT: REQUEST_CHANGES
