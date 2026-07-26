---
id: TASK-007
title: PTY WebSocket client with reconnect (TerminalFeature)
phase: 2
module: TerminalFeature
depends_on: [TASK-002]
blocks: [TASK-008]
parallel_safe_with: [TASK-009, TASK-010]
context_budget_tokens: 60000
worktree: wt/task-007-pty
---

## Goal
Implement a reconnecting PTY client over URLSessionWebSocketTask that speaks Coder's
reconnecting-PTY protocol, exposing an AsyncStream<Data> of terminal output and an
async send(_:) for input. Reconnect with exponential backoff, resuming the session
by reconnect token.

## In scope (files this task MAY create/modify)
- Sources/TerminalFeature/PTYClient.swift            (new)
- Sources/TerminalFeature/PTYReconnectPolicy.swift   (new)
- Tests/TerminalFeatureTests/PTYClientTests.swift    (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring (orchestrator does this)
- SwiftTerm UIViewRepresentable (TASK-008)
- CoderKit public API (consume only; do not modify)

## Contracts / interfaces it MUST honor
- Consumes `CoderKit.WorkspaceAgent` and `CoderKit.SessionToken` (see @Sources/CoderKit/Models).
- Public surface MUST be:
      public protocol PTYSession: Sendable {
          var output: AsyncStream<Data> { get }
          func send(_ data: Data) async throws
          func resize(cols: Int, rows: Int) async throws
      }
- All public types Sendable; the client is an `actor`. No @MainActor on the client.

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Reconnects after a simulated socket drop within backoff schedule (unit test with a
   mock WebSocket transport injected via protocol).
3. Backoff is capped and jittered; no busy-loop on repeated failure (test asserts call
   spacing).
4. No secrets (session tokens) written to os_log/print (reviewer-B checks).

## Test requirements
- Swift Testing (`@Test`), transport injected via a `PTYTransport` protocol + fake.
- Cover: happy path, single drop+resume, N consecutive failures → gives up with typed error.

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/TerminalFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/TerminalFeature` green
- [ ] `swiftlint lint --strict Modules/TerminalFeature` clean
- [ ] `swift-format lint -r Modules/TerminalFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
