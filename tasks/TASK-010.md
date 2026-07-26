---
id: TASK-010
title: Keyboard shortcuts for VS Code Web (WebAppFeature)
phase: 3
module: WebAppFeature
depends_on: [TASK-012]
blocks: []
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-010-keyboard
---

## Goal
Implement keyboard shortcut handling for VS Code Web to improve iPad keyboard experience. This includes focus management and common shortcuts like Cmd/Ctrl+P for command palette, Cmd/Ctrl+S for save, etc.

## In scope (files this task MAY create/modify)
- Sources/WebAppFeature/KeyboardShortcutHandler.swift (new)
- Sources/WebAppFeature/VSCodeWebView.swift (modified)
- Tests/WebAppFeatureTests/KeyboardShortcutHandlerTests.swift (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring
- Cookie injection (TASK-012)
- Terminal keyboard handling (TASK-009)
- CoderKit or CoderAuth modules

## Contracts / interfaces it MUST honor
- Public surface MUST be:
  ```swift
  public struct KeyboardShortcutHandler: UIViewRepresentable {
      public init(onShortcut: @escaping (KeyboardShortcut) -> Void)
  }
  
  public enum KeyboardShortcut: Sendable {
      case commandPalette
      case save
      case closeTab
      case newFile
      case custom(String)
  }
  ```
- Must use UIKeyCommand for hardware keyboard support
- Must be Sendable

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Captures hardware keyboard input via UIKeyCommand.
3. Maps common shortcuts to KeyboardShortcut enum cases.
4. Sends shortcuts to parent via callback.
5. Handles focus management (first responder).
6. Unit tests verify shortcut mapping.
7. No secrets logged or exposed.

## Test requirements
- Swift Testing (`@Test`)
- Mock keyboard input for testing
- Cover: shortcut mapping, callback invocation, focus management

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/WebAppFeature -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/WebAppFeature` green
- [ ] `swiftlint lint --strict Modules/WebAppFeature` clean
- [ ] `swift-format lint -r Modules/WebAppFeature` clean
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
