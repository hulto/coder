# TASK-004 Review A - Spec Compliance

**Verdict:** REQUEST_CHANGES

## REQUIRED Findings

### A1 (major)
**Location:** Workspace.swift:57-75
**Evidence:** `private static let iso8601WithFractionalSeconds: ISO8601DateFormatter` and `private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter`
**Rule:** RUBRIC-A/concurrency-compliance
**Required Change:** ISO8601DateFormatter is not Sendable. Mark these static properties with `nonisolated(unsafe)` to indicate they are thread-safe for read-only access after initialization.

### A2 (minor)
**Location:** WorkspaceListTests.swift:40-71
**Evidence:** `private final class CapturingSession: @unchecked Sendable, URLSessionProtocol` with `NSLock` usage in async context
**Rule:** RUBRIC-A/concurrency-safety
**Required Change:** Replace NSLock with actor-based synchronization. Convert CapturingSession to an actor and make capturedRequest an async method to avoid using NSLock in async contexts.

## OPTIONAL Findings

### A3 (nit)
**Location:** CoderAPIClient.swift:104
**Evidence:** `var queryItems = [`
**Rule:** RUBRIC-A/immutability
**Required Change:** Change `var queryItems` to `let queryItems` since the variable is never mutated after initialization.

## Summary
The implementation correctly addresses the workspace list API requirements with proper models, pagination support, and comprehensive test coverage. However, there are two concurrency-related issues that need to be fixed to comply with Swift 6 strict concurrency checking.
