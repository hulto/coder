---
id: TASK-015
title: VNC touch/pointer, zoom, and trackpad tuning (WebAppFeature)
phase: 4
module: WebAppFeature
depends_on: [TASK-013]
blocks: []
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-015-vnc-pointer
---

## Goal
Configure the `WKWebView` that hosts the KasmVNC/noVNC web client so native
iPadOS input (touch, trackpad pointer, external keyboard) reaches the embedded
remote-desktop canvas cleanly, instead of being consumed by WebKit's own
scroll/zoom/pointer behavior. This closes the "touch/pointer handling
optimizations" item deferred by TASK-013 and completes Phase 4.

## Background the implementer needs (read this, do not redesign it)
This task is **not** a VNC input implementation. Per the project's architecture
decision, the app embeds Coder's served KasmVNC/noVNC **web client** inside a
`WKWebView` (there is no reachable raw RFB TCP port; KasmVNC's noVNC fork
deviates from the RFB spec, so a native RFB client is off the table). The
noVNC JavaScript running inside the page already owns **all** mouse, touch, and
keyboard to RFB translation, including its own canvas zoom/pan and its own
touch gesture recognizers.

Therefore the only thing this task changes is **how much of the native input
WebKit swallows before the page's JavaScript sees it**. Three concrete problems:

1. **Zoom ownership conflict.** `WKWebView`'s `scrollView` ships with its own
   pinch-to-zoom (page zoom). A VNC session is a single full-bleed `<canvas>`;
   OS-level page zoom scales the canvas as a blurry bitmap and simultaneously
   steals the pinch gesture that noVNC would otherwise use for its own
   scaling/`clip` mode. Exactly one layer must own zoom. Pick one, implement
   it, and document the reason in a code comment.
2. **Scroll/bounce conflict.** The page is not a scrolling document. Native
   scrolling, rubber-band bounce, and scroll indicators over a remote desktop
   cause the viewport to drift when the user means to drag inside the guest OS.
3. **Trackpad pointer behavior.** `WKWebView` gets `UIPointerInteraction`
   support largely for free, so a Magic Keyboard / trackpad pointer already
   hovers and clicks over web content. What is needed is a deliberate check
   that nothing this task does breaks it, plus any explicit configuration
   required so the pointer behaves as a precise cursor over the canvas rather
   than as a generic link-snapping web pointer.

Everything here lives in `WKWebView`/`UIScrollView`/`WKWebViewConfiguration`
setup. No JavaScript injection into the noVNC client is required or wanted.

## In scope (files this task MAY create/modify)
- `Modules/WebAppFeature/Sources/VNCWebView.swift` (modify) — the
  `WebViewRepresentable.makeUIView` / `updateUIView` path only.
- `Modules/WebAppFeature/Sources/VNCInputConfiguration.swift` (new, optional) —
  create **only if** the gesture/pointer settings warrant a separate helper;
  a plain value type plus a pure `apply`-style function keeps the settings
  unit-testable without a live `WKWebView`. Do not create this file just to
  hold two lines.
- `Modules/WebAppFeature/Tests/VNCInputTests.swift` (new) — tests for this task.

Note the real on-disk layout is flat: sources live in
`Modules/WebAppFeature/Sources/`, tests in `Modules/WebAppFeature/Tests/`
(there is no nested `Sources/WebAppFeature/` directory, despite what earlier
task specs wrote).

## Explicitly OUT of scope (do NOT touch)
- Any `.xcodeproj` / `project.yml` / `Package.swift` target wiring.
- Native RFB/VNC protocol implementation. The embedded web client owns this.
- Any JavaScript injection, `WKUserScript`, or `evaluateJavaScript` call aimed
  at reconfiguring noVNC's own settings. If you believe the noVNC client needs
  a query parameter or JS setting, stop and report it rather than adding it.
- `Modules/WebAppFeature/Sources/VNCWebViewModel.swift` — specifically its
  `token`, `injectionTask`, `cleanup()`, and navigation-state logic from
  TASK-013/TASK-014. Leave this file untouched.
- `Modules/WebAppFeature/Sources/CookieInjector.swift` and all cookie /
  session-token injection behavior (TASK-014).
- `Modules/WebAppFeature/Sources/VSCodeWebView.swift`,
  `VSCodeWebViewModel.swift`, and their tests.
- `KeyboardShortcutHandler.swift` and the keyboard accessory bar. Hardware
  keyboard shortcut capture is a separate concern already implemented for
  VS Code; do not extend it to VNC here.
- `CoderKit` and `CoderAuth` modules.
- Clipboard sync between native and web (Phase 5 polish).

## Contracts / interfaces it MUST honor
- The frozen public surface is unchanged. It MUST remain exactly:
  ```swift
  public struct VNCWebView: View {
      public init(url: URL, token: String? = nil)
  }
  ```
  No new parameters, no new overloads, no changed defaults.
- **This task MUST NOT add any new public API** unless it creates
  `VNCInputConfiguration.swift`, in which case that type may be `internal`
  only. Nothing new becomes `public` from this task. Existing behavior of
  `VNCWebViewModel` (error/loading state, cleanup, cookie injection ordering)
  MUST be preserved bit-for-bit.
- All configuration MUST be applied inside `WebViewRepresentable.makeUIView`
  (and `updateUIView` if it must be re-asserted), before or independently of
  the existing load/injection sequencing. The existing ordering contract from
  TASK-014 stands: when a token is present, cookie injection completes before
  `webView.load(request)` is issued. Do not reorder or duplicate that load.
- Any new type introduced MUST be `Sendable`. UIKit/WebKit-touching code stays
  `@MainActor`.
- All WebKit/UIKit code MUST remain inside `#if canImport(WebKit)` (and
  `#if canImport(UIKit)` where UIKit-only symbols are used), matching the
  existing file structure so the package still builds on Linux.
- Package minimum is iOS 17 / macOS 14. Any API newer than that MUST be
  `@available`-gated with a documented fallback. Do not add an
  `if #available(iOS 13.4, *)` style gate for APIs already satisfied by the
  iOS 17 floor; unnecessary availability checks are a review finding.

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. `VNCWebView`'s public signature is byte-identical to the contract above;
   `git diff` shows no change to the `public init` line or the type's
   declaration.
3. `git diff --stat` shows no changes to `VNCWebViewModel.swift`,
   `CookieInjector.swift`, `VSCodeWebView.swift`, `VSCodeWebViewModel.swift`,
   or `KeyboardShortcutHandler.swift`.
4. Zoom ownership is decided and implemented exactly once. Reviewer can point
   at the specific call(s) that set it, e.g. the `scrollView` pinch/zoom
   properties (`scrollView.pinchGestureRecognizer?.isEnabled`,
   `scrollView.minimumZoomScale` / `maximumZoomScale`, and/or
   `scrollView.bouncesZoom`), or the WebKit configuration flag that disables
   page-level zoom. Setting several overlapping knobs that contradict each
   other fails this criterion.
5. A code comment adjacent to the zoom configuration explains **why** that
   layer owns zoom, in one to three sentences, naming the other layer it is
   deliberately disabling. The comment describes behavior, not the change
   history.
6. Scroll behavior appropriate to a full-bleed canvas is configured on
   `webView.scrollView`: at minimum bounce and scroll indicators are addressed,
   and `contentInsetAdjustmentBehavior` is set deliberately rather than left at
   the default. Each such setting is either used or absent; no dead assignments.
7. Trackpad/pointer behavior is explicitly addressed: either the implementation
   documents in a comment that `WKWebView`'s built-in `UIPointerInteraction`
   support is sufficient and that this task's changes do not disable it, **or**
   it adds explicit pointer configuration. A silent no-op fails this criterion.
8. If any configuration is expressed as data (e.g. a `VNCInputConfiguration`
   value type), its defaults are asserted by unit tests that run on Linux
   (outside `#if canImport(WebKit)`).
9. No behavior change to navigation, error display, retry, cleanup, or cookie
   injection. Existing tests in `VNCWebViewTests.swift` and
   `VNCCookieInjectionTests.swift` pass unmodified; the diff does not edit them.
10. No secrets logged or exposed. No new logging of URLs or tokens.
11. **Device-only, NOT part of the automated gate:** actual touch latency,
    pinch feel, gesture responsiveness, trackpad pointer appearance over the
    remote desktop, and pointer precision cannot be verified by any agent in
    this sandbox. Per the project's own "Agents cannot verify these" list, VNC
    touch input and gesture mapping is a human device checklist item. The
    implementer MUST list, in the returned summary, the specific gestures a
    human should test on a real iPad (at minimum: one-finger drag inside the
    guest desktop, two-finger pinch, two-finger pan/scroll inside a guest app,
    trackpad hover, trackpad left-click and right-click).

Standing environment caveat: like TASK-013 and TASK-014, this task can only be
gate-verified (build / test / lint / format) because this dev sandbox is Linux,
where `canImport(WebKit)` is false and every WebKit-gated body compiles to an
empty stub. The real touch, pointer, and gesture behavior needs a real-device
or Apple-SDK CI run before shipping, per the caveat recorded in
`reviews/TASK-014-adjudication.md` and `PROGRESS.md`.

## Test requirements
- Swift Testing (`@Test` / `#expect`), matching the existing suites' style.
- Tests live in `Modules/WebAppFeature/Tests/VNCInputTests.swift`. Do not modify
  `VNCWebViewTests.swift` or `VNCCookieInjectionTests.swift`.
- Mock strategy: there is no meaningful mock for `WKWebView.scrollView` on
  Linux, and `UIViewRepresentable.makeUIView` cannot be invoked outside SwiftUI
  rendering. So split testable logic out as pure values/functions and test
  those, following the precedent already set by
  `VNCCookieInjectionTests.injectionPrecedesLoad`, which tests the *sequencing
  contract* at the call site rather than the representable itself.
- Cover:
  - Default values of any introduced configuration type (Linux-runnable, i.e.
    outside `#if canImport(WebKit)`).
  - `Sendable` / value-semantics of any introduced type.
  - Under `#if canImport(WebKit)`: applying the configuration to a real
    `WKWebView` yields the expected `scrollView` property values. Guard this
    suite so it compiles away on Linux.
  - Regression: `VNCWebView(url:)` and `VNCWebView(url:token:)` still
    construct and their `body` still evaluates.
- If the implementation ends up being a handful of direct property assignments
  with no extractable logic, say so explicitly in the summary and still ship
  the WebKit-gated property-assertion tests plus the construction regression
  tests. Do not invent an abstraction solely to have something to unit test.

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/WebAppFeature` green
- [ ] `swiftlint lint --strict Modules/WebAppFeature` clean on the files this task touches (a pre-existing, module-wide swiftlint debt unrelated to this task is tracked separately in `PROGRESS.md`'s "Known Repo Hygiene Debt" section: `Package.swift`, `KeyboardShortcutHandlerTests.swift`, and untracked `.build/` derived sources already fail `--strict` before this task starts; do not attempt to fix those files here, confirm via `git stash`/targeted-path linting that your diff introduces zero new violations)
- [ ] `swift-format lint -r Modules/WebAppFeature` clean (warnings-only exit is the established baseline; do not introduce new errors)
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
