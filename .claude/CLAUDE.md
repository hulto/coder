# Coder iOS — Agent Operating Rules

## Core Principles
- Swift 6, strict concurrency = complete. New code MUST compile with zero concurrency warnings.
- Min iOS/iPadOS 17. SwiftUI + UIKit interop. Local SPM packages under Modules/.
- NEVER edit *.xcodeproj / *.pbxproj. Structure changes go through project.yml (XcodeGen) — humans/orchestrator only.
- One writer per task. Reviewers and orchestrator never edit source.
- Secrets (tokens, cookies) NEVER logged. Keychain via CoderAuth only.
- New tests use Swift Testing (@Test/#expect). Every task ships tests for its acceptance criteria.
- Definition of Done = all gates in the task's DoD block are green AND diff is in-scope.

## Architecture
- Module boundaries: CoderKit (API/models), CoderAuth (auth/Keychain), TerminalFeature (PTY/SwiftTerm), WebAppFeature (WKWebView), CoderUI (SwiftUI screens), AppShell (DI/scene wiring).
- Public contracts frozen before fan-out to consumers. Check docs/adr/ for decisions.
- All public types Sendable. Actors for mutable shared state. @MainActor for UI.

## Workflow
- Full plan: @docs/plan/
- Current state: @PROGRESS.md
- Task specs: tasks/TASK-###.md
- Review outputs: reviews/TASK-###-reviewA.md, reviews/TASK-###-reviewB.md
- Architecture decisions: docs/adr/

## Gates (enforced by hooks)
```bash
swift build --package-path Modules/<M> -Xswiftc -strict-concurrency=complete
swift test --package-path Modules/<M>
swiftlint lint --strict Modules/<M>
swift-format lint -r Modules/<M>
```

## Anti-patterns (do NOT)
- Edit .pbxproj or .xcodeproj files
- Log tokens, cookies, or credentials
- Use force unwraps (!) in production code
- Share mutable state across isolation boundaries
- Swallow errors with empty catch blocks
- Write tests as a separate task (they ship with implementation)
