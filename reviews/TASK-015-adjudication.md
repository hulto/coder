# Adjudication TASK-015

**Gate Status:** ⚠️ PASSED ON LINUX, VALIDITY QUESTIONED (same standing
caveat as TASK-014, see B1 below)
- `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` — PASS
- `swift test --package-path Modules/WebAppFeature` — PASS, 25/25 (unchanged
  from before this task: all 6 new tests in `VNCInputTests.swift` are inside
  `#if canImport(WebKit)`, which is false on this Linux sandbox, so none of
  them actually ran. See B1.)
- `swiftlint lint --strict` on touched files (`VNCWebView.swift`,
  `VNCInputTests.swift`) — 0 violations.
- `swift-format lint -r` — exits 0 (pre-existing indentation-style baseline
  only, confirmed identical class/volume in an untouched file).
- Diff scope confirmed by both reviewers and independently by the
  orchestrator: only `VNCWebView.swift` (new `configureForVNCInput` method
  and its two call sites) and new `VNCInputTests.swift` were touched by
  this task. `VNCWebViewModel.swift`, `CookieInjector.swift`,
  `VSCodeWebView.swift`, `VNCCookieInjectionTests.swift` show diffs only
  because TASK-014's already-integrated changes remain uncommitted in the
  shared working tree; this task did not edit them.

## Reviewer Verdicts
- Reviewer A: REQUEST_CHANGES
- Reviewer B: REQUEST_CHANGES

## REQUIRED Findings (Union)

1. **A1 / B6: `scrollView.isScrollEnabled` never addressed.** Both
   reviewers independently flagged this. The spec's own background section
   names "viewport drift when the user means to drag inside the guest OS"
   as problem #2 this task exists to solve, and acceptance criterion 6
   requires scroll behavior to be addressed deliberately; leaving the
   scroll-panning toggle at its default directly contradicts the stated
   goal. Reviewer A classified this REQUIRED (A1, major); reviewer B's B6
   raised the identical property gap as OPTIONAL but with the same
   "stated intent and code disagree" framing. Per adjudication rule 4
   (union of REQUIRED findings; either reviewer's REQUIRED classification
   stands), this is REQUIRED. **Must fix.**

2. **B1: Test file has zero Linux-runnable assertions.** All six tests in
   `VNCInputTests.swift` are inside `#if canImport(WebKit)`. Spec
   criterion 8 explicitly requires coverage "that runs on Linux (outside
   `#if canImport(WebKit)`)" for any introduced configuration data. No
   `VNCInputConfiguration` type was introduced (spec permitted this,
   correctly, since a handful of property assignments doesn't warrant an
   abstraction on its own), but that choice is exactly what makes
   criterion 8 unmet: with no non-WebKit-gated data type, there is
   nothing this task's tests assert outside the WebKit guard, so the gate
   as it stands proves nothing for this task on this sandbox. **Must
   fix** by extracting an internal, `Sendable`, non-WebKit-gated
   configuration type (or equivalent pure data/logic) with Linux-runnable
   default-value assertions, per the fix approach both reviewers
   converged on independently.

3. **B2 (union with A2, REQUIRED wins): Tests are tautological.**
   `VNCInputTests.swift`'s `applyVNCInputConfiguration` is a hand-copied
   duplicate of the real `configureForVNCInput`, so the tests assert that
   `UIScrollView` correctly stores values just written to it, not that
   `VNCWebView.swift`'s actual implementation does the right thing.
   Reviewer A rated this OPTIONAL (A2), citing the spec's explicit
   permission for a "mirroring" approach and correctly noting the
   containing type is itself `private`. Reviewer B rated the same
   underlying issue REQUIRED (B2), with a concrete demonstration that
   deleting the real `configureForVNCInput` call from `updateUIView`
   entirely, or flipping a production value, would not fail any of these
   tests, i.e. they provide no regression protection at all for the
   method they claim to test. Per adjudication rule 4, REQUIRED
   classification governs; this is not a genuine A-vs-B conflict, B's
   demonstration is a strict escalation of the same finding with concrete
   proof of the gap's severity. **Must fix.** Both reviewers independently
   converged on the same fix: hoist the settings into a file-scope
   internal function/type reachable via the existing `@testable import`,
   so tests exercise the real implementation rather than a copy.

4. **B3: Misleading comment overclaims a causal mechanism.** The comment
   at `VNCWebView.swift:115-121` states that disabling
   `scrollView.pinchGestureRecognizer?.isEnabled` is what makes "the
   gesture reach noVNC's own canvas zoom." Reviewer B's analysis is
   correct: disabling a gesture recognizer stops it from recognizing
   touches, it does not "hand" or "forward" the gesture to anything;
   whether noVNC's JS receives the touch stream is a WebKit
   touch-delivery question independent of this recognizer, and the
   property actually doing the load-bearing work is the pinned
   `minimumZoomScale == maximumZoomScale == 1.0`. This directly
   undermines acceptance criteria 4 ("point at the specific call(s) that
   set it... contradicting knobs fails this criterion") and 5 (comment
   must correctly explain why). **Must fix**: correct the comment to
   claim only what's verifiable, and clarify which single setting is
   authoritative for zoom ownership per criterion 4's "exactly once"
   requirement.

5. **B4: `updateUIView` reassignment can cancel an in-flight gesture.**
   Calling `configureForVNCInput` unconditionally from `updateUIView`
   means `pinchGestureRecognizer?.isEnabled = false` is reassigned on
   every SwiftUI re-render, and reviewer B's technical claim is sound:
   writing `isEnabled` on a recognizer mid-recognition forces a
   transition to `.cancelled`. SwiftUI can call `updateUIView` from an
   unrelated ancestor state change (e.g. `viewModel.isLoading` toggling)
   while the user's fingers are still down, which would cancel exactly
   the drag-inside-guest-desktop interaction this task exists to protect.
   This is a real, plausible regression path, not a hypothetical. **Must
   fix**: either make each property assignment idempotent (check before
   write) or provide concrete evidence that these `scrollView` properties
   are reset by WebKit internals between renders (justifying the
   unconditional re-assertion); the current comment asserts the latter
   without evidence.

## OPTIONAL Findings (Logged, Not Blocking)

### From Reviewer A
- (A2 escalated to REQUIRED as B2 above; no separate OPTIONAL A findings
  remain.)

### From Reviewer B
- B5: `contentInsetAdjustmentBehavior = .never` may occlude content under
  the home indicator/Stage Manager window chrome; consider pairing with
  `.ignoresSafeArea()` or documented inset compensation. Add to human
  device checklist.
- B7: Force-unwrapped `URL(string:)!` in new tests; matches existing
  precedent in `VNCWebViewTests.swift`, not blocking.
- B8: Trackpad two-finger scroll behavior (delivered via pan recognizer,
  not pinch) is probably unaffected by this diff but unverified in this
  sandbox; add explicitly to the human device checklist.

## Decision (initial)
**REQUEST_CHANGES.** Union of REQUIRED findings (A1/B6 merged, B1, B2/A2
merged, B3, B4) sent this to REMEDIATE. This is a more substantial set of
findings than TASK-014's first pass, reflecting that this task's subject
matter (gesture/zoom tuning) is inherently harder to get right without
device verification, and the implementer's test strategy (duplicate
mirroring) papered over a real coverage gap that both reviewers caught
independently from different angles.

Routed to `fixer` with all five REQUIRED findings. B5, B7, B8 left logged
as OPTIONAL, not assigned; folded into the human device-testing checklist
this task already owes per acceptance criterion 11.

Iteration count: 1 of 3 (MAX_REMEDIATION_ITERATIONS).

## Re-verification (after remediation iteration 1)

Both reviewers independently re-reviewed the fixer's changes against all
five assigned REQUIRED findings (see
`reviews/TASK-015-reviewA-reverify.md` and
`reviews/TASK-015-reviewB-reverify.md`):

- A1/B6 (`isScrollEnabled`): RESOLVED. Now `false` in
  `VNCInputConfiguration.vncDefault`, applied with an idempotence guard,
  asserted on Linux and against a real `WKWebView`.
- B1 (zero Linux-runnable coverage): RESOLVED. New
  `VNCInputConfiguration.swift` has no `canImport(WebKit)` guard; test
  count independently confirmed to rise from 25 to 29 (exactly 4 new
  Linux-runnable tests) by both reviewers running `swift test` themselves
  or reading the orchestrator's run.
- B2/A2 (tautological tests): RESOLVED. Production `configureForVNCInput`
  and the test suite now both read the same `VNCInputConfiguration
  .vncDefault` as their single source of truth for values, closing the
  exact drift scenario originally demonstrated (flipping a production
  default without updating a hand-typed test literal). Both reviewers
  independently identified the same narrower residual (test still
  hand-duplicates the field-to-`scrollView`-property *mapping*, not just
  the values) and both classified it OPTIONAL (A3 / B11), not blocking,
  since it is materially smaller than the original defect and the spec
  permits a mirroring strategy.
- B3 (misleading comment): RESOLVED. Comment corrected to name
  `minimumZoomScale == maximumZoomScale == 1.0` as the sole authoritative
  setting and explicitly states the pinch-recognizer/`bouncesZoom` toggles
  "do not themselves route anything to the page."
- B4 (gesture cancellation on re-render): RESOLVED. Both reviewers
  independently verified, property-by-property, that all 9 `scrollView`
  writes in `configureForVNCInput` are now idempotence-guarded
  (`if current != wanted`), so a steady-state `updateUIView` call (the
  risk case) performs zero writes and cannot cancel an in-flight gesture.
  Reviewer B additionally verified the guard logic itself is sound
  (including the `Bool?`/`Bool` optional-promotion edge case for the
  pinch recognizer, and the derived-boolean comparison for
  `contentInsetAdjustmentBehavior`).

Gates independently re-run/re-confirmed: build clean, 29/29 tests pass,
swiftlint 0 violations on all 3 touched files (`VNCWebView.swift`,
`VNCInputConfiguration.swift`, `VNCInputTests.swift`), swift-format
warnings-only (pre-existing baseline class, no new violations). Diff
scope confirmed clean: only this task's 3 files changed; TASK-014's
already-adjudicated changes remain uncommitted in the shared working tree
but were not touched by this remediation.

New OPTIONAL findings from re-verification (not blocking):
- A3/B11 (converged independently): the test's mapping from
  `VNCInputConfiguration` fields to `scrollView` properties is still
  hand-duplicated separately from production's mapping, so a
  transposition bug in production (e.g. assigning `bounces` to
  `bouncesZoom`) would not be caught. Both reviewers suggest the same
  follow-up: hoist the guarded mapping itself into a shared internal
  function/method both production and tests call. Logged for a future
  polish pass, not blocking integration.
- B9: `pinchGestureRecognizer` nil-case guard doesn't latch (cosmetic,
  recognizer is always non-nil in practice).
- B10: `Double`/`CGFloat` implicit conversion for zoom-scale fields
  compiles on Apple platforms but is unverifiable on this Linux sandbox;
  flagged as the highest-value item for a real Apple-SDK CI run to
  confirm.
- B12: `contentInsetAdjustmentBehavior` lossily encoded as `Bool`;
  harmless while `vncDefault` is the only configuration instance.
- B13: force-unwrapped `URL(string:)!` in new tests, matches existing
  precedent, not blocking.

## Final Decision
**APPROVED.** All REQUIRED findings from both reviewers are resolved with
code-level verification from two independent re-reviews, not just fixer
self-report. Gates green, diff scope clean. Ready for INTEGRATE.

Standing caveats carried forward (not blocking, but visible for whoever
runs this on a real Apple SDK / device / CI):
- B1 (from TASK-014, still applies): this task's `WKWebView`-gated code
  (all of `configureForVNCInput`'s actual application to a live
  `scrollView`) has only ever been syntax-checked on this Linux sandbox,
  never executed. The 29 passing tests prove the new
  `VNCInputConfiguration` data is correct; they do not prove the
  production mapping from that data to `scrollView` properties is
  correct on a real device.
- B10: confirm the `Double`→`CGFloat` zoom-scale conversion compiles
  without warning on a real Apple SDK.
- Acceptance criterion 11's human device-testing checklist (one-finger
  drag inside guest desktop, two-finger pinch, two-finger pan/scroll,
  trackpad hover/left-click/right-click) plus the reviewer-logged
  additions (Stage Manager/home-indicator occlusion from
  `contentInsetAdjustmentBehavior = .never`, trackpad two-finger scroll)
  remain outstanding, device-only, not gate-verifiable.
- A3/B11, B9, B12, B13: OPTIONAL, left for a future polish pass.
