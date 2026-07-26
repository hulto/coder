---
id: TASK-004
title: Workspace list API and models
phase: 1
module: CoderKit
depends_on: [TASK-002]
blocks: [TASK-005]
parallel_safe_with: []
worktree: main
---

## Goal
Implement workspace list retrieval with proper models and API integration.

## In Scope
- Workspace list API endpoint integration
- Workspace model with all required fields
- Workspace status enum
- Pagination support
- Error handling for API responses

## Out of Scope
- UI components (TASK-005)
- Workspace detail view
- Workspace start/stop functionality

## Requirements
- Fetch workspace list from `/api/v2/workspaces` endpoint
- Parse workspace objects with id, name, status, template, created_at, updated_at
- Handle pagination with offset/limit parameters
- Map API errors to appropriate Swift errors
- All types must be Sendable and Codable

## Acceptance Criteria
- [ ] Workspace model includes all required fields
- [ ] WorkspaceStatus enum covers all possible states
- [ ] API client method fetches workspace list successfully
- [ ] Pagination parameters work correctly
- [ ] Error responses are properly mapped
- [ ] Unit tests cover happy path and error cases
- [ ] Build passes with strict concurrency
- [ ] All tests pass

## Definition of Done
- [ ] Code implemented in CoderKit module
- [ ] Unit tests written and passing
- [ ] swift build passes with strict concurrency
- [ ] swift test passes
- [ ] Code reviewed by dual reviewers
- [ ] All REQUIRED findings addressed
- [ ] PROGRESS.md updated
