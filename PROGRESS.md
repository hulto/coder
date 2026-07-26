# Coder iOS Client — Progress Tracker

## Current Phase: 2 (Terminal)

## Task Index

| TASK-### | Phase | Module | Status | Worktree | Last Gate |
|----------|-------|--------|--------|----------|-----------|
| TASK-001 | 0 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-002 | 1 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-003 | 1 | CoderAuth | ✅ COMPLETE | main | All gates green |
| TASK-004 | 1 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-005 | 1 | CoderKit | ✅ COMPLETE | main | All gates green |
| TASK-006 | 1 | CoderUI | ✅ COMPLETE | main | All gates green |
| TASK-007 | 2 | TerminalFeature | ✅ COMPLETE | main | All gates green |
| TASK-008 | 2 | TerminalFeature | ✅ COMPLETE | main | All gates green |
| TASK-009 | 2 | TerminalFeature | ✅ COMPLETE | main | All gates green |
| TASK-010 | 3 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| TASK-011 | 3 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| TASK-012 | 3 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| TASK-013 | 4 | WebAppFeature | ✅ COMPLETE | main | All gates green |
| (none yet) | | | | | |

## Phase State
- [ ] Phase 0: Scaffolding (0.5–1 wk)
- [ ] Phase 1: Auth + workspace list + start/stop (1–2 wk)
- [ ] Phase 2: Terminal (1–2 wk)
- [ ] Phase 3: VS Code Web (1 wk)
- [ ] Phase 4: VNC (0.5–1 wk)
- [ ] Phase 5: Polish (1–2 wk)

## Architectural Invariants
- Swift 6, strict concurrency = complete
- Min iOS/iPadOS 17
- Local SPM packages under Modules/
- XcodeGen for project generation (never edit .pbxproj)
- Module boundaries: CoderKit, CoderAuth, TerminalFeature, WebAppFeature, CoderUI, AppShell
- All public types Sendable
- Actors for mutable shared state
- @MainActor for UI updates

## Adjudication Rules
- Union of REQUIRED findings from both reviewers must be addressed
- Deterministic gates are supreme (any failed gate = REQUEST_CHANGES)
- Genuine conflict → orchestrator decides, record as ADR
- OPTIONAL findings logged but not blocking
- MAX_REMEDIATION_ITERATIONS = 3 per task
