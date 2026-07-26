---
id: TASK-009
title: Keyboard accessory bar for terminal (TerminalFeature)
phase: 2
module: TerminalFeature
depends_on: [TASK-008]
blocks: []
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-009-keyboard-bar
---

## Goal
Create a keyboard accessory bar that provides quick access to common terminal keys (Esc, Ctrl, Tab, arrows) that are difficult or impossible to type on iPad keyboards. This solves the notorious iPad Esc/Ctrl problem mentioned in the engineering plan.

## In scope (files this task MAY create/modify)
- Sources/TerminalFeature/KeyboardAccessoryBar.swift (new)
- Sources/TerminalFeature/KeyboardAccessoryViewModel.swift (new)
- Tests/TerminalFeatureTests/KeyboardAccessoryBarTests.swift (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring
- TerminalView or TerminalViewModel (TASK-008)
- Hardware keyboard handling (future task)
- CoderKit or CoderAuth modules

## Contracts / interfaces it MUST honor
- Consumes `TerminalFeature.PTYSession` protocol from TASK-007
- Public surface MUST be:
  ```swift
  public struct KeyboardAccessoryBar: View {
      public init(session: PTYSession)
  }
  ```
- View must be Sendable
- Must integrate with TerminalView from TASK-008

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Displays accessory bar with Esc, Ctrl, Tab, Up, Down, Left, Right buttons.
3. Tapping Esc sends Escape sequence (0x1B) via PTYSession.send().
4. Tapping Ctrl activates control key mode (next key sent as Ctrl+key).
5. Tapping Tab sends Tab character (0x09) via PTYSession.send().
6. Tapping arrow keys sends appropriate ANSI escape sequences.
7. Unit tests verify key sequences are sent correctly.
8. Properly cleans up resources on view disappearance.

## Test requirements
- Swift Testing (`@Test`)
- Mock PTYSession for testing
- Cover: view creation, each button sends correct sequence, Ctrl mode toggle

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/TerminalFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/TerminalFeature` green
- [ ] `swiftlint lint --strict Modules/TerminalFeature` clean
- [ ] `swift-format lint -r Modules/TerminalFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
