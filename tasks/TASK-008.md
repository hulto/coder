---
id: TASK-008
title: SwiftTerm UIViewRepresentable wrapper (TerminalFeature)
phase: 2
module: TerminalFeature
depends_on: [TASK-007]
blocks: []
parallel_safe_with: [TASK-009, TASK-010]
context_budget_tokens: 60000
worktree: wt/task-008-swiftterm
---

## Goal
Create a SwiftUI-compatible terminal view using SwiftTerm that connects to the PTY client from TASK-007. The view should handle keyboard input, display terminal output, and support terminal resize.

## In scope (files this task MAY create/modify)
- Sources/TerminalFeature/TerminalView.swift (new)
- Sources/TerminalFeature/TerminalViewModel.swift (new)
- Tests/TerminalFeatureTests/TerminalViewTests.swift (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring
- PTY client implementation (TASK-007)
- Keyboard accessory bar (TASK-011)
- CoderKit or CoderAuth modules

## Contracts / interfaces it MUST honor
- Consumes `TerminalFeature.PTYSession` protocol from TASK-007
- Public surface MUST be:
  ```swift
  public struct TerminalView: View {
      public init(session: PTYSession)
  }
  ```
- View must be Sendable
- Must integrate with SwiftTerm library (add to Package.swift dependencies)

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Displays terminal output from PTYSession.output stream.
3. Captures keyboard input and sends via PTYSession.send().
4. Handles terminal resize events and calls PTYSession.resize().
5. Properly cleans up resources on view disappearance.
6. Unit tests verify view creation and basic functionality.

## Test requirements
- Swift Testing (`@Test`)
- Mock PTYSession for testing
- Cover: view creation, output display, input capture, resize handling

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/TerminalFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/TerminalFeature` green
- [ ] `swiftlint lint --strict Modules/TerminalFeature` clean
- [ ] `swift-format lint -r Modules/TerminalFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
