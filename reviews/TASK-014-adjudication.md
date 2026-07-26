# Adjudication TASK-014

**Gate Status:** ⚠️ PASSED ON LINUX, VALIDITY QUESTIONED (see B1)
- `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` — PASS
- `swift test --package-path Modules/WebAppFeature` — PASS, 25/25
- `swiftlint lint --strict Modules/WebAppFeature` — fails, but only on
  pre-existing violations outside TASK-014's file scope
  (`KeyboardShortcutHandlerTests.swift`, `Package.swift`, untracked `.build/`
  derived sources with no `.swiftlint.yml` to exclude them). Confirmed via
  `git stash` (reviewer A) that this predates this session. Zero violations
  in TASK-014-owned files.
- `swift-format lint -r Modules/WebAppFeature` — exits 0 (warnings only).
- Both reviewers independently flagged that this sandbox is Linux, so
  `#if canImport(WebKit)` bodies (all of `VNCWebView.swift`,
  `CookieInjector.swift`, and the WebKit-gated tests in
  `VNCCookieInjectionTests.swift`) compile to empty stubs here. The green
  build/test gate does not prove the actual deliverable compiles or runs.
  This is an environment limitation affecting every WebAppFeature/
  TerminalFeature task done in this session, not specific to TASK-014's
  code, but it means gate greenness on this box is necessary, not
  sufficient. Recorded as B1; tracked as a follow-up (see Decision).

## Reviewer Verdicts
- Reviewer A: REQUEST_CHANGES
- Reviewer B: REQUEST_CHANGES

## REQUIRED Findings (Union)

1. **B1: Gate validity on Linux sandbox** — environment limitation, not a
   code defect. No code fix possible in this task; requires CI/device
   validation on an Apple SDK before this task can be considered truly
   verified. Tracked as a standing caveat on every task in this repo run
   under this sandbox, not unique to TASK-014. Not remediable by the fixer.
   Action: note prominently in PROGRESS.md that this and prior WebAppFeature/
   TerminalFeature tasks need a real macOS/iOS gate run before shipping.

2. **B2: Uncancelled injection Task outlives `cleanup()`, strong-captures
   `webView`** (VNCWebView.swift:52-74) — REQUIRED per reviewer B, with
   reviewer A flagging the same code as OPTIONAL (A3) citing TASK-012
   precedent. Per adjudication rule 4 (union of REQUIRED findings), B's
   classification governs: this is not a genuine A-vs-B conflict, B's
   reasoning (interaction with `cleanup()`'s delegate teardown, meaning a
   dismissed view still gets a token silently injected and a load started)
   is a strict superset of A's observation and stands as REQUIRED.
   **Must fix.**

3. **B3: Cookie-injection failure is swallowed; code proceeds to load the
   VNC URL unauthenticated** (CookieInjector.swift:75-83 /
   VNCWebView.swift:52-70). **Must fix.**

4. **B4: No HTTPS scheme validation before minting a Secure/SameSite=None
   cookie** (CookieInjector.swift:39-53). **Must fix.** Note: this method
   is shared with TASK-012 (VS Code Web); fixing it here also benefits that
   call site, which is in scope since `CookieInjector.swift` is a dependency
   this task legitimately touches for its DoD, not new scope creep.

5. **A1: No test exercises `CookieInjector.injectCookies` against a cookie
   store for a VNC URL** — only pure `makeCookie`/`domain` helpers are
   retested (already covered by TASK-012's `CookieInjectorTests.swift`).
   **Must fix.**

6. **A2: No test constructs `VNCWebView(url:token:)`** — the actual
   token-carrying initializer and integration surface this task modifies
   has zero direct test coverage. **Must fix.**

## OPTIONAL Findings (Logged, Not Blocking)

### From Reviewer A
- A3: Uncancelled Task (superseded by B2 above, now REQUIRED)
- A4: Duplicate logging scaffolding between VSCodeWebView.swift and
  VNCWebView.swift; consider a shared logger category. Not blocking.

### From Reviewer B
- B5: Drop redundant `@unchecked Sendable` on `VNCWebViewModel` (and
  `VSCodeWebViewModel`); type is already safely `Sendable` via `@MainActor`.
  Not blocking.
- B6: `Coordinator.deinit` is `nonisolated` but touches MainActor-isolated
  state; only compiles due to `@unchecked Sendable`. Empty the deinit body
  and rely on `cleanup()` for teardown. Not blocking, but related to B2's
  fix, so the fixer should address both together if straightforward.
- B7: Logging hygiene, no token leak confirmed. Not blocking.
- B8: WebKit tests should assert injection precedes load, not just
  re-derive cookie properties. Related to A1/A2 remediation; fixer should
  fold this into the new test coverage.
- B9: Duplicated WKWebView scaffolding between VNC and VS Code web views;
  flagged as a follow-up task, explicitly out of scope for TASK-014 (spec
  forbids touching VS Code Web implementation).

## Decision (initial)
**REQUEST_CHANGES.** Union of REQUIRED findings (B2, B3, B4, A1, A2) sent
this to REMEDIATE. B1 (gate validity on Linux) recorded as a standing
environment caveat, not a fixer task, since there is no code change that
resolves it in this sandbox.

Routed to `fixer` with the five REQUIRED findings (B2, B3, B4, A1, A2) and
folded in B6 (mechanically related to B2) and B8 (mechanically related to
A1/A2 test remediation) since addressing the REQUIRED finding properly
required touching the same code/tests anyway. B5, A4, B7, B9 left logged
as OPTIONAL, not assigned.

Iteration count: 1 of 3 (MAX_REMEDIATION_ITERATIONS).

## Re-verification (after remediation iteration 1)

Reviewer A re-reviewed the fixer's changes against all six assigned
REQUIRED findings (see `reviews/TASK-014-reviewA-reverify.md`):

- B2 (uncancelled Task): RESOLVED — `injectionTask` stored on
  `VNCWebViewModel`, cancelled in `cleanup()`, `Task.isCancelled` checked
  before both the failure and success continuations.
- B6 (unsafe deinit): RESOLVED — `Coordinator.deinit` emptied; teardown
  fully owned by `cleanup()`.
- B3 (swallowed injection failure): RESOLVED — `injectCookies` is now
  `async throws` (`CookieInjectionError.invalidURL`); caller surfaces the
  error via `handleNavigationError` and skips the load.
- B4 (no HTTPS validation): RESOLVED — scheme guard added in
  `cookieProperties` before the host check.
- A1 (missing injectCookies test coverage): RESOLVED — new test exercises
  the real async entry point against a live `WKWebView`/cookie store for a
  VNC URL, plus a failure-path companion test.
- A2 (missing VNCWebView(url:token:) test): RESOLVED — new construction
  test added.

Gates independently re-run by both the orchestrator and reviewer-A:
build clean, 25/25 tests pass (WebKit-gated tests compile away on this
Linux sandbox per standing caveat B1, not a regression), swiftlint 0
violations on all 5 touched files, swift-format warnings-only (pre-existing
class, not new).

`VSCodeWebView.swift`'s one-hunk change (forced `do/catch` adaptation to
`injectCookies`'s new throwing signature) confirmed as the minimal
compile-compatible fix, no scope creep into VS Code Web's own logic.

One new OPTIONAL finding logged (A5: injection closure still strongly
captures `webView`, so a cancelled-but-in-flight cookie write isn't
interrupted mid-await; does not reopen B2, whose required_change is fully
satisfied). Not blocking.

## Final Decision
**APPROVED.** All REQUIRED findings from both reviewers are resolved with
code-level verification, not just fixer self-report. Gates green. Ready
for INTEGRATE.

Standing caveats carried forward (not blocking, but should be visible to
whoever runs this on a real Apple SDK / device / CI):
- B1: this entire task (and the WebAppFeature/TerminalFeature work before
  it) was gated and tested on a Linux sandbox where `canImport(WebKit)` is
  false. All WebKit-gated code and tests are syntactically reviewed and
  believed correct but have never actually executed. A real macOS/iOS CI
  or device run is required before this can be considered fully verified.
- A5, B5 (partially addressed by removing `@unchecked Sendable`), B7, B9:
  logged OPTIONAL, left for a future polish pass.
- Repo-wide tooling debt found in this task (not introduced by it, not
  fixed): `Modules/WebAppFeature/.build/` is tracked in git from a prior
  commit ("first agent") with no `.gitignore` entry for `.build/`; no
  `.swiftlint.yml` exists anywhere to exclude derived/build files from
  `swiftlint lint --strict`, so the literal gate command as written in
  every task spec's DoD has never been clean for this module. Both are
  infrastructure issues for a separate cleanup task, not this one.
