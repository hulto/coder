---
id: TASK-005
title: Workspace start/stop API methods
phase: 1
module: CoderKit
depends_on: [TASK-002, TASK-004]
blocks: []
parallel_safe_with: []
---

## Goal
Implement API methods to start and stop workspaces, including workspace build status tracking.

## In Scope
- `startWorkspace(id:)` method in CoderAPIClient
- `stopWorkspace(id:)` method in CoderAPIClient
- `WorkspaceBuild` model to track build status
- `WorkspaceBuildStatus` enum (pending, starting, running, stopping, stopped, failed, canceling, deleted)
- Error handling for invalid workspace states
- Unit tests for all new functionality

## Out of Scope
- UI components for start/stop buttons
- Automatic workspace lifecycle management
- Build log streaming (future task)
- Workspace deletion

## Requirements
- POST to `/api/v2/workspaces/{id}/builds` with appropriate transition
- Handle 409 Conflict when workspace is in invalid state
- Return updated workspace with new status
- All types must be Sendable and Codable
- Strict concurrency compliance

## Acceptance Criteria
- [ ] `startWorkspace(id:)` method implemented and tested
- [ ] `stopWorkspace(id:)` method implemented and tested
- [ ] `WorkspaceBuild` model with proper fields
- [ ] `WorkspaceBuildStatus` enum with all states
- [ ] Error handling for conflict scenarios
- [ ] All tests pass with strict concurrency
- [ ] Code reviewed and approved

## Technical Notes
- Start transition: POST with `{"transition": "start"}`
- Stop transition: POST with `{"transition": "stop"}`
- Build status transitions are asynchronous - client polls workspace status
- 409 Conflict indicates workspace cannot transition (e.g., starting a running workspace)
