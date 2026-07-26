# TASK-015 Reviewer A — Remediation Re-verification (iteration 1)

Scope: `Modules/WebAppFeature/Sources/VNCWebView.swift`,
`Modules/WebAppFeature/Sources/VNCInputConfiguration.swift` (new),
`Modules/WebAppFeature/Tests/VNCInputTests.swift`, re-checked against the five
REQUIRED findings the adjudication routed to remediation.

## Gate results (re-run)

- `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete`: clean, zero warnings.
- `swift test --package-path Modules/WebAppFeature`: green, **29/29** (up from
  25 before this task). "VNC Input Configuration Tests" suite executed
  4 tests on this Linux sandbox (`zoomDefaults`, `scrollDefaults`,
  `contentInsetDefaults`, `valueSemantics`) plus the pre-existing 6
  WebKit-gated tests compiled to nothing on Linux as expected (standing
  caveat, unchanged). Net +4 Linux-runnable tests confirmed exactly as
  claimed.
- `swiftlint lint --strict` on the three touched files: 0 violations.
- `swift-format lint -r` on the three touched files: exit 0, only
  `[Indentation]`/`[LineLength]` warnings (pre-existing module-wide
  baseline, no new violation category introduced).
- Diff scope: confirmed zero diff on `VNCWebViewTests.swift`,
  `KeyboardShortcutHandler.swift`; `Package.swift` untouched (no explicit
  file list, directory-based source discovery, new file needs no wiring).
  `VNCWebViewModel.swift`/`CookieInjector.swift`/`VSCodeWebView.swift`/
  `VNCCookieInjectionTests.swift` diffs remain attributable to TASK-014's
  already-adjudicated, still-uncommitted changes in the shared working
  tree, not this remediation.

## Per-finding verification

### A1/B6 — `scrollView.isScrollEnabled` never addressed
**RESOLVED.** `VNCInputConfiguration.vncDefault.isScrollEnabled = false`
(VNCInputConfiguration.swift:65), applied with an idempotence guard in
`configureForVNCInput` (VNCWebView.swift:161-164), and asserted both by the
Linux-runnable `scrollDefaults` test (VNCInputTests.swift:37) and the
WebKit-gated `scrollPanningBounceAndIndicatorsDisabled` test
(VNCInputTests.swift:115). Panning is now explicitly disabled, matching the
stated "viewport drift" intent from the spec's background section.

### B1 — zero Linux-runnable coverage
**RESOLVED.** `VNCInputConfiguration.swift` contains no `canImport(WebKit)`
guard at all (confirmed by grep; the file's only mention of the phrase is
inside a doc comment, not a compilation guard). Its `Sendable`/`Equatable`
conformance and `.vncDefault` static value are plain data, and the test run
confirms exactly 4 new tests execute on this Linux sandbox:
`zoomDefaults`, `scrollDefaults`, `contentInsetDefaults`, `valueSemantics`.
Test count went from the pre-remediation 25 to 29, verified by direct
`swift test` run, not by trusting the summary. This is genuine, non-trivial
Linux-runnable coverage of real production defaults, not a placeholder.

### B2/A2 — tautological tests
**RESOLVED, with a residual noted as a new OPTIONAL finding (see below).**
The test file's WebKit-gated `applyVNCInputConfiguration(_:_:)` helper now
takes `configuration: VNCInputConfiguration` as a parameter and applies
*its* fields (`configuration.pinchGestureRecognizerEnabled`,
`configuration.isScrollEnabled`, etc.) rather than hardcoded literals, and
every `@Test` in the WebKit-gated suite calls it with `.vncDefault` and
asserts against `VNCInputConfiguration.vncDefault.<field>` — the same
shared source of truth `configureForVNCInput` reads in production
(VNCWebView.swift:125, `let configuration = VNCInputConfiguration.vncDefault`).
I traced through the original adjudication's concrete demonstration ("flip
`contentInsetAdjustmentBehavior` to `.always` in production... all six
still pass"): that exact scenario is now impossible without also changing
`vncDefault`, since production and tests both read the same static value.
This closes the *data-drift* risk that was the demonstrated failure mode.

This is a different mechanism than literally invoking the private
`configureForVNCInput` (which the containing `private struct
WebViewRepresentable` still does not expose, correctly noted as a real
obstacle in the original A2), but it is a reasonable and adjudication-
sanctioned alternative that eliminates the specific drift scenario both
reviewers demonstrated. It does not eliminate a narrower residual: the
test's property-to-property *mapping* (`scrollView.bounces =
configuration.bounces`, etc.) is still independently hand-copied from
production's mapping, so a transposition bug in `configureForVNCInput`
itself (e.g. assigning `configuration.bounces` to `scrollView.bouncesZoom`
by mistake) would not be caught, since the test never calls the real
method. This is a materially smaller and lower-severity gap than the
original tautology (which caught nothing about production at all), so I am
not re-opening B2/A2 as REQUIRED; logging it as new OPTIONAL finding
A3 below.

### B3 — misleading comment overclaiming a causal mechanism
**RESOLVED.** The comment at VNCWebView.swift:127-136 no longer claims
disabling the pinch recognizer "hands" or routes the gesture to noVNC's JS.
It now states: "The authoritative setting is pinning `minimumZoomScale ==
maximumZoomScale == 1.0`, which prevents WebKit from ever bitmap-rescaling
the page; noVNC's own JS touch handlers continue to receive the underlying
touch events independently of this scroll view's gesture recognizers.
Disabling the pinch gesture recognizer and `bouncesZoom` are
defensive/redundant: they stop this scroll view's own recognizer from
consuming the gesture, but do not themselves route anything to the page."
This matches the corrected language both reviewers converged on, correctly
identifies the single authoritative setting (satisfying AC4's "exactly
once" requirement), and no longer asserts an unverifiable WebKit
touch-delivery mechanism as settled fact.

### B4 — `updateUIView` reassignment can cancel an in-flight gesture
**RESOLVED.** Verified all 9 property writes in `configureForVNCInput` are
individually gated by an `if current != wanted` check before writing:
`pinchGestureRecognizer?.isEnabled` (:137-140), `minimumZoomScale`
(:141-144), `maximumZoomScale` (:145-148), `bouncesZoom` (:149-152),
`isScrollEnabled` (:161-164), `bounces` (:165-168),
`showsVerticalScrollIndicator` (:169-172),
`showsHorizontalScrollIndicator` (:173-176), and
`contentInsetAdjustmentBehavior` (:177-181, using a derived
`hasNeverInsetAdjustment` boolean comparison since the guard needs to
compare against the config's `Bool` representation). None of the 9 writes
is unconditional. On a webview already in the desired configuration
(the steady-state case for `updateUIView`, which is where the SwiftUI
re-render risk lives), calling `configureForVNCInput` again performs zero
writes, so `pinchGestureRecognizer?.isEnabled` cannot be reassigned
mid-recognition by an unrelated ancestor state change. The updated comment
at :90-98 accurately describes this behavior rather than asserting an
unproven WebKit-internals claim.

## New findings introduced by this remediation

```yaml
- id: A3
  severity: minor
  class: OPTIONAL
  location: "Modules/WebAppFeature/Tests/VNCInputTests.swift:66-82"
  evidence: |
    private func applyVNCInputConfiguration(
        _ webView: WKWebView, _ configuration: VNCInputConfiguration
    ) {
        let scrollView = webView.scrollView
        scrollView.pinchGestureRecognizer?.isEnabled = configuration.pinchGestureRecognizerEnabled
        scrollView.minimumZoomScale = configuration.minimumZoomScale
        ...
    }
  rule: RUBRIC-A/tests-meaningful
  required_change: >
    This helper closes the data-drift risk B2 demonstrated (production and
    tests now both read VNCInputConfiguration.vncDefault as the single
    source of truth for values), but the field-to-scrollView-property
    *mapping* itself is still independently hand-copied here versus
    configureForVNCInput's mapping in VNCWebView.swift. A transposition bug
    in production (e.g. assigning configuration.bounces to
    scrollView.bouncesZoom instead of scrollView.bounces) would not be
    caught by these tests, since they never invoke the real
    configureForVNCInput. Not blocking: this is a narrower and
    lower-severity residual than the original tautology, and the spec
    permits a mirroring strategy. Optional follow-up: hoist the mapping
    itself into a shared internal function/static method (e.g.
    `VNCInputConfiguration.apply(to: UIScrollView)`) called by both
    configureForVNCInput and the tests, eliminating the second
    hand-maintained mapping entirely.
```

No other new REQUIRED or OPTIONAL issues found. `VNCInputConfiguration` is
correctly `internal` (no `public` modifier), `Sendable`, `Equatable`, and
the public `VNCWebView` surface remains byte-identical
(`git log` shows no change to files outside this task's scope beyond the
already-settled TASK-014 diffs).

## Verdict

All five REQUIRED findings (A1/B6, B1, B2/A2, B3, B4) are confirmed
resolved with direct evidence, not just the fixer's self-report. Gates are
green with no regressions. One new OPTIONAL finding (A3) logged, not
blocking.

VERDICT: APPROVE
