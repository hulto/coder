# Re-verification TASK-015 — Reviewer B (remediation iteration 1)

Files read in full (current working-tree state):
- Modules/WebAppFeature/Sources/VNCWebView.swift
- Modules/WebAppFeature/Sources/VNCInputConfiguration.swift (new)
- Modules/WebAppFeature/Tests/VNCInputTests.swift

No shell available this session; gate results below are from the
orchestrator's independent run (build clean, 29/29 tests, swiftlint 0
violations on touched files), not re-run by this reviewer. Reasoning about
compile-correctness and guard logic is done by direct source reading.

## B4 deep-dive (the highest-risk finding to re-verify)

The pinch guard is the load-bearing case:

```swift
if scrollView.pinchGestureRecognizer?.isEnabled != wantsPinchEnabled {
    scrollView.pinchGestureRecognizer?.isEnabled = wantsPinchEnabled
}
```

`scrollView.pinchGestureRecognizer?.isEnabled` is `Bool?`; `wantsPinchEnabled`
is `Bool`. Swift promotes the RHS to `Bool?` via `Optional.==`. When the
recognizer exists (the normal case), after the first application
`Optional(false) != false` evaluates `false`, so no write occurs on any
subsequent re-render. This suppresses exactly the regression B4 identified:
writing `isEnabled` on a recognizer mid-recognition forces `.cancelled`, and
that write is now skipped once the value is already correct.

All 9 property writes checked individually for the same pattern: pinch
(137-140), minZoom (141-144), maxZoom (145-148), bouncesZoom (149-152),
isScrollEnabled (161-164), bounces (165-168), showsVertical (169-172),
showsHorizontal (173-176), contentInsetAdjustment (177-181). All 9 are
guarded. The `contentInsetAdjustmentBehavior` guard
(`hasNeverInsetAdjustment != wantsNeverInsetAdjustment`) is also correct:
after the first write both sides are `true`, suppressing further writes.

Float equality on zoom scale is safe in this specific case: `1.0` is exactly
representable and is compared against a value this same code wrote. A
hypothetical WebKit-internal rewrite of `minimumZoomScale` would cause a
redundant zoom-scale write, not a gesture cancellation, since zoom-scale
writes don't touch the pan/pinch recognizers carrying an active drag.

## B3 re-check

The comment at VNCWebView.swift:127-136 no longer claims disabling the
pinch recognizer "hands" the gesture to noVNC's JS. It now correctly states
pinning `minimumZoomScale == maximumZoomScale == 1.0` is "the authoritative
setting," and that disabling the pinch recognizer / `bouncesZoom` are
"defensive/redundant... but do not themselves route anything to the page."
This is the exact correction B3 demanded.

## Finding-by-finding disposition

```yaml
- id: B1
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Tests/VNCInputTests.swift:23-59
  evidence: |
    @Test("Zoom ownership defaults pin scale to 1.0 and disable the pinch recognizer")
    func zoomDefaults() {
        let configuration = VNCInputConfiguration.vncDefault
        #expect(configuration.pinchGestureRecognizerEnabled == false)
    ...
    @Test("VNCInputConfiguration has value semantics")
  rule: RUBRIC-B/sendable-compliance
  required_change: "RESOLVED. Four @Test functions (zoomDefaults, scrollDefaults, contentInsetDefaults, valueSemantics) sit above the #if canImport(WebKit) guard and reference only VNCInputConfiguration, which lives in a file with no WebKit/UIKit import. They compile and run on Linux. 25 -> 29 tests is exactly +4, matching. Criterion 8 met."

- id: B2
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Tests/VNCInputTests.swift:66-82 and Modules/WebAppFeature/Sources/VNCWebView.swift:125
  evidence: |
    // production
    let configuration = VNCInputConfiguration.vncDefault
    // test
    scrollView.isScrollEnabled = configuration.isScrollEnabled
  rule: RUBRIC-B/error-propagation
  required_change: "RESOLVED, residual gap logged as B11. The original defect (flipping a production value would not fail any test) is closed: both production and test read the same VNCInputConfiguration.vncDefault, so changing a field's default value fails the corresponding Linux test immediately. What remains duplicated is the application mechanism (which scrollView property each field maps to), which the spec explicitly accepts as untestable without a live WKWebView."

- id: B3
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:127-136
  evidence: |
    // The authoritative setting is pinning minimumZoomScale == maximumZoomScale == 1.0...
    // Disabling the pinch gesture recognizer and bouncesZoom are defensive/redundant...
    // do not themselves route anything to the page.
  rule: RUBRIC-B/wkwebview-config
  required_change: "RESOLVED. False causal claim removed. Comment now correctly names the authoritative setting and demotes the others to defensive/redundant, explicitly stating they do not route anything to the page."

- id: B4
  severity: major
  class: REQUIRED
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:137-181
  evidence: |
    let wantsPinchEnabled = configuration.pinchGestureRecognizerEnabled
    if scrollView.pinchGestureRecognizer?.isEnabled != wantsPinchEnabled {
        scrollView.pinchGestureRecognizer?.isEnabled = wantsPinchEnabled
    }
  rule: RUBRIC-B/lifecycle-aware
  required_change: "RESOLVED for the gesture-cancellation mechanism. All 9 property writes individually verified guarded; the load-bearing case (isEnabled written on a live recognizer mid-recognition) is suppressed after first application. See B9 for one residual non-latching branch (nil recognizer), which is cosmetic, not a correctness bug."

- id: B6
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:161-164, VNCInputConfiguration.swift:40,65
  evidence: "var isScrollEnabled: Bool ... isScrollEnabled: false"
  rule: RUBRIC-B/lifecycle-aware
  required_change: "RESOLVED (this is A1/B6). isScrollEnabled now defaults false, applied in production, asserted on Linux and against a real WKWebView."
```

## New findings introduced by this remediation

```yaml
- id: B9
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Sources/VNCWebView.swift:138
  evidence: "if scrollView.pinchGestureRecognizer?.isEnabled != wantsPinchEnabled {"
  rule: RUBRIC-B/lifecycle-aware
  required_change: "When pinchGestureRecognizer is nil, the comparison Optional<Bool>.none != Optional(false) is true, so the branch is entered every render; the body is then a no-op via optional chaining, so no correctness bug, but the guard silently fails to latch in that case, contradicting the file comment claiming every write is idempotent. UIScrollView always vends a pinch recognizer in practice, so cosmetic. Tightening available: `if let pinch = scrollView.pinchGestureRecognizer, pinch.isEnabled != wantsPinchEnabled { pinch.isEnabled = wantsPinchEnabled }`."

- id: B10
  severity: minor
  class: OPTIONAL
  location: VNCInputConfiguration.swift:20,24 applied at VNCWebView.swift:141-148
  evidence: |
    var minimumZoomScale: Double   // config field
    scrollView.minimumZoomScale != wantsMinZoom   // CGFloat != Double
  rule: RUBRIC-B/wkwebview-config
  required_change: "UIScrollView.minimumZoomScale is CGFloat; the config field is Double. Both the != and the assignment rely on implicit CGFloat<->Double conversion (SE-0307, Swift 5.5+), which compiles on Apple platforms but cannot be proven by the Linux gate since this path is entirely inside #if canImport(WebKit). Could also emit warnings in some diagnostic modes, risking acceptance criterion 1's zero-warnings requirement on a real Apple SDK build. Minimal fix: explicit `CGFloat(configuration.minimumZoomScale)` at the application site. Flagged as the highest-value item for an Apple-SDK CI run to confirm; the Linux gate structurally cannot verify this."

- id: B11
  severity: minor
  class: OPTIONAL
  location: Modules/WebAppFeature/Tests/VNCInputTests.swift:66-82 vs Sources/VNCWebView.swift:123-189
  evidence: |
    // test applies unconditionally: scrollView.bounces = configuration.bounces
    // production applies conditionally: if scrollView.bounces != wantsBounces { ... }
  rule: RUBRIC-B/error-propagation
  required_change: "The test's applyVNCInputConfiguration writes unconditionally while production writes conditionally, so the WebKit-gated tests provide zero coverage for the idempotence guards themselves, the newly-introduced risk surface in this remediation. An inverted guard in production would not be caught by any test. Not blocking. Cheapest close: hoist the guarded application into a file-scope internal @MainActor function both production and tests call, closing this and the residual half of B2 in one move."

- id: B12
  severity: nit
  class: OPTIONAL
  location: VNCInputConfiguration.swift:50-55
  evidence: "var contentInsetAdjustmentBehaviorIsNever: Bool"
  rule: RUBRIC-B/hardcoded-values
  required_change: "Encoding a 4-case enum as Bool is lossy (.scrollableAxes/.always unrepresentable). Rationale (platform-agnostic, no UIKit import) is sound and harmless while vncDefault is the only instance. Logged for awareness if a future config option is added."

- id: B13
  severity: nit
  class: OPTIONAL
  location: Modules/WebAppFeature/Tests/VNCInputTests.swift:137,145
  evidence: 'let url = URL(string: "https://vnc.example.com")!'
  rule: RUBRIC-B/no-force-unwraps
  required_change: "Carried forward unchanged from prior B7. Matches existing precedent, WebKit-gated so never runs on Linux gate. Not blocking."
```

## Rubric sweep on new/changed code (no findings)

No secrets logged. No Keychain access. `VNCInputConfiguration` is a
`Sendable` value type of `Bool`/`Double`; `static let vncDefault` is valid
under Swift 6 strict concurrency without `nonisolated(unsafe)`.
`configureForVNCInput` remains `@MainActor`-inferred via
`UIViewRepresentable`. No new closures, captures, or retain-cycle surface.
No force unwraps in production. No new public API (`VNCInputConfiguration`
is `internal`; `VNCWebView`'s `public init(url:token:)` untouched). Test
count 25 -> 29 arithmetically consistent with exactly four new
non-gated tests.

## Summary

All five REQUIRED findings from the adjudication (A1/B6, B1, B2, B3, B4)
are genuinely resolved, verified by direct reading rather than trusting the
fixer's self-report. The B4 fix is correct at the mechanism level: the
pinch-recognizer write is actually suppressed on re-render. Residual items
are all OPTIONAL; B10 (Double/CGFloat conversion) is the one item this
reviewer would most want an Apple-SDK build to confirm, but it does not
change the verdict, since it's a structural limitation of this whole task
already recorded as a standing caveat, not something this remediation
introduced.

29/29 green on Linux still exercises none of the WebKit-gated code,
including every line of `configureForVNCInput`; the four new tests prove
the config data is right, not that it's applied correctly on a real device.

VERDICT: APPROVE
