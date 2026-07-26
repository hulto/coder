---
id: TASK-006
title: Login UI with SwiftUI
phase: 1
module: CoderUI
depends_on: [TASK-003]
blocks: []
parallel_safe_with: []
---

## Goal
Implement SwiftUI login screen that integrates with AuthService for /cli-auth flow.

## In Scope
- LoginView with server URL input
- Login button that triggers authentication
- Loading state during authentication
- Error display for authentication failures
- Success callback/navigation
- Unit tests for view model

## Out of Scope
- Navigation integration (AppShell task)
- Biometric prompt UI (handled by AuthService)
- Token storage UI (handled by AuthService)
- Multi-account support

## Requirements
- SwiftUI view with TextField for server URL
- Button to initiate login
- @Observable view model for state management
- Async/await integration with AuthService
- Error handling with user-friendly messages
- Accessibility support
- All types Sendable

## Acceptance Criteria
- [ ] LoginView displays server URL input
- [ ] Login button triggers authentication
- [ ] Loading state shown during auth
- [ ] Errors displayed to user
- [ ] Success callback invoked on completion
- [ ] View model is @Observable and Sendable
- [ ] All tests pass with strict concurrency
- [ ] Code reviewed and approved

## Technical Notes
- Use @Observable macro for view model (Swift 5.9+)
- AuthService.authenticate() is async throws
- Error messages should be user-friendly, no technical details
- View should be previewable in Xcode
