# TASK-015 Review A

Scope: `Modules/WebAppFeature/Sources/VNCWebView.swift`'s new
`configureForVNCInput(_:)` and its call sites in `makeUIView`/`updateUIView`,
plus `Modules/WebAppFeature/Tests/VNCInputTests.swift`. TASK-014's
already-adjudicated changes to `CookieInjector.swift`, `VNCWebViewModel.swift`,
`VSCodeWebView.swift`, and `VNCCookieInjectionTests.swift` are out of scope and
not re-reviewed here.

## Gate results

- `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete`: clean, no warnings.
- `swift test --package-path Modules/WebAppFeature`: green, 25 tests pass (the WebKit-gated `VNC Input Configuration Tests` suite executes 0 tests on Linux since `canImport(WebKit)` is false there, per the spec's standing caveat).
- `swiftlint lint --strict Modules/WebAppFeature/Sources/VNCWebView.swift Modules/WebAppFeature/Tests/VNCInputTests.swift`: 0 violations.
- `swift-format lint`: only `[Indentation]`/`[OrderedImports]` warnings, confirmed to be pre-existing module-wide baseline noise (identical warning class/volume found in untouched `VNCWebViewModel.swift`). No new violations introduced by this diff.

## Acceptance criteria check

- AC1 (strict concurrency, zero warnings): pass.
- AC2 (frozen public signature): pass — `git diff` shows `public init(url:token:)` and the `VNCWebView` struct declaration untouched.
- AC3 (`VNCWebViewModel.swift`, `CookieInjector.swift`, `VSCodeWebView.swift`, `KeyboardShortcutHandler.swift` untouched by *this* diff): pass, restricting to TASK-015-attributable changes (TASK-014's changes to the first three are a separate, already-settled diff per the task framing).
- AC4 (zoom ownership decided once, non-contradictory): pass — `pinchGestureRecognizer?.isEnabled = false`, `minimumZoomScale`/`maximumZoomScale` pinned to 1.0, `bouncesZoom = false`. Consistent, not overlapping/contradictory (gesture recognition vs. zoom-scale API are distinct surfaces).
- AC5 (comment explains why): pass — comment names WebKit's page-zoom layer as the disabled layer and noVNC's canvas zoom/`clip` mode as the owner.
- AC6 (scroll/bounce addressed, `contentInsetAdjustmentBehavior` deliberate, no dead assignments): partially — see A1 below on `isScrollEnabled`.
- AC7 (trackpad/pointer explicitly addressed): pass — explicit comment states built-in `UIPointerInteraction` is left alone and why, satisfying the "no silent no-op" requirement.
- AC8 (Linux-runnable default-value tests for any data type): N/A — no `VNCInputConfiguration` type was introduced, consistent with the spec's "don't invent an abstraction" guidance for a handful of direct property assignments.
- AC9 (no behavior change to nav/error/cleanup/cookie injection; `VNCWebViewTests.swift`/`VNCCookieInjectionTests.swift` unedited): pass — `VNCWebViewTests.swift` shows no diff at all; `VNCCookieInjectionTests.swift`'s diff is TASK-014's addition, not an edit by this task.
- AC10 (no secrets logged): pass — no new logging added by this task's diff.
- AC11 (device-checklist reminder): not evaluated here (summary-only requirement for the implementer, not gate-verifiable); reviewer note: confirm the returned task summary actually lists the required gesture checklist before merge.

## Findings

```yaml
- id: A1
  severity: major
  class: REQUIRED
  location: "Modules/WebAppFeature/Sources/VNCWebView.swift:112-136"
  evidence: |
    scrollView.bounces = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .never
  rule: RUBRIC-A/acceptance-criteria (AC6), RUBRIC-A/edge-cases
  required_change: >
    scrollView.isScrollEnabled is left at its default (true) and is never
    addressed, despite the spec's background section explicitly calling out
    "viewport drift when the user means to drag inside the guest OS" as the
    problem to solve (background item 2) and AC6 requiring bounce AND scroll
    behavior to be "addressed... deliberately rather than left at the
    default." Bounce, indicators, and content-inset are handled, but the more
    fundamental scroll-panning toggle is not, so a one-finger drag over the
    canvas could still pan the WKWebView's scrollable content region (if it
    is ever taller/wider than the viewport, e.g. due to viewport-meta
    mismatches in the served page) instead of reaching noVNC's own touch
    handling untouched. Add an explicit
    `scrollView.isScrollEnabled = false` (or a comment explaining why leaving
    it `true` is deliberate and safe given the canvas is always exactly
    viewport-sized) and cover it with a test alongside the other scroll
    assertions in VNCInputTests.swift.

- id: A2
  severity: minor
  class: OPTIONAL
  location: "Modules/WebAppFeature/Tests/VNCInputTests.swift:30-42"
  evidence: |
    private func applyVNCInputConfiguration(_ webView: WKWebView) {
        let scrollView = webView.scrollView
        scrollView.pinchGestureRecognizer?.isEnabled = false
        ...
    }
  rule: RUBRIC-A/tests-meaningful, RUBRIC-A/mock-strategy
  required_change: >
    The test suite exercises a hand-duplicated copy of the property
    assignments rather than the real `configureForVNCInput` in
    VNCWebView.swift. If a future edit changes the real method (e.g. flips
    `bouncesZoom` or removes the `contentInsetAdjustmentBehavior` line) without
    updating this private mirror, these tests keep passing while asserting
    stale behavior, i.e. they cannot catch that regression. This exact
    duplication strategy is explicitly sanctioned by the task spec (mirrors
    the project's own precedent, `VNCCookieInjectionTests.injectionPrecedesLoad`),
    and the real obstacle is stronger than "the method is private": the
    containing type `WebViewRepresentable` is itself `private` to the file,
    so no visibility bump to `configureForVNCInput` alone (even via
    `@testable import`, already used here) would make it reachable from the
    test target. A closeable gap does exist, though: hoist
    `configureForVNCInput` out of `WebViewRepresentable` into a file-scope
    `internal static func` (or free function) in VNCWebView.swift, taking a
    `WKWebView` parameter. That requires no change to `WebViewRepresentable`'s
    privacy and would let VNCInputTests.swift call the real implementation via
    `@testable import` instead of maintaining a duplicate. Not a blocker since
    the spec explicitly permits and precedents the mirroring approach, but
    worth doing in a follow-up to close the drift risk.
```

## Verdict

VERDICT: REQUEST_CHANGES
