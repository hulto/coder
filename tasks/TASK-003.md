---
id: TASK-003
title: CoderAuth authentication flow with /cli-auth
phase: 1
module: CoderAuth
depends_on: [TASK-002]
blocks: [TASK-005]
parallel_safe_with: []
---

## Goal
Implement the authentication flow using ASWebAuthenticationSession to authenticate users via Coder's /cli-auth endpoint. Store session tokens securely in Keychain with biometric protection.

## In Scope
- CoderAuth/Sources/AuthService.swift - Main authentication service
- CoderAuth/Sources/KeychainManager.swift - Secure token storage
- CoderAuth/Sources/BiometricAuth.swift - Face ID/Touch ID integration
- CoderAuth/Tests/AuthServiceTests.swift - Authentication flow tests
- CoderAuth/Tests/KeychainManagerTests.swift - Keychain operation tests

## Out of Scope
- UI components for login screen (TASK-005)
- Token refresh logic (future task)
- Multi-account support (future task)

## Requirements
1. Use ASWebAuthenticationSession to open https://<coder-host>/cli-auth
2. Extract session token from redirect URL
3. Store token in Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
4. Optional biometric protection (Face ID/Touch ID) for token access
5. Provide async/await interface for authentication flow
6. Handle authentication cancellation and errors gracefully
7. Validate token format before storage

## Acceptance Criteria
- [ ] ASWebAuthenticationSession successfully opens /cli-auth URL
- [ ] Session token extracted from redirect callback
- [ ] Token stored in Keychain with proper accessibility
- [ ] Biometric authentication gates token retrieval when enabled
- [ ] Authentication can be cancelled by user
- [ ] Invalid tokens are rejected before storage
- [ ] All operations are async/await compatible
- [ ] Unit tests cover happy path, cancellation, and error cases

## Technical Constraints
- iOS 17.0+ deployment target
- Swift 6 strict concurrency
- No secrets in logs or error messages
- Keychain operations must be thread-safe
- Biometric auth uses LocalAuthentication framework

## Definition of Done
- [ ] swift build passes with strict concurrency
- [ ] swift test passes (all tests green)
- [ ] Code reviewed by 2 reviewers (1 security-focused)
- [ ] No REQUIRED findings from reviewers
- [ ] Documentation comments on public APIs
