# TASK-008 Review B - Security & Architecture

**Verdict:** APPROVE (after fixes)

## REQUIRED Findings (All Addressed)

### B1 (blocker) - FIXED
**Location:** Tests/TerminalViewTests.swift:69
**Evidence:** `viewModel.handleResize(width: 700, height: 700)`
**Rule:** RUBRIC-B/compilation
**Required Change:** Align test method signature with implementation
**Status:** ✅ Fixed - test now calls `handleResize(containerSize:)`

### B2 (major) - FIXED
**Location:** Sources/TerminalViewModel.swift:63-65
**Evidence:** `try? await session.send(data)`
**Rule:** RUBRIC-B/error-handling
**Required Change:** Log errors instead of silently discarding
**Status:** ✅ Fixed - errors now logged with os_log

### B3 (major) - FIXED
**Location:** Sources/TerminalViewModel.swift:83-85, 95-97
**Evidence:** `try? await session.resize(...)`
**Rule:** RUBRIC-B/error-handling
**Required Change:** Log errors instead of silently discarding
**Status:** ✅ Fixed - errors now logged with os_log

### B4 (major) - FIXED
**Location:** Tests/TerminalViewTests.swift:40
**Evidence:** `struct TerminalViewModelTests`
**Rule:** RUBRIC-B/concurrency
**Required Change:** Add @MainActor annotation
**Status:** ✅ Fixed - @MainActor added to test struct

## OPTIONAL Findings (Not Blocking)

### B5 (minor)
**Location:** Sources/TerminalViewModel.swift:72-73
**Evidence:** `let charWidth = 7.0; let charHeight = 14.0`
**Rule:** RUBRIC-B/magic-numbers
**Required Change:** Extract to named constants or query from SwiftTerm
**Status:** Not addressed - acceptable for initial implementation

### B6 (minor)
**Location:** Sources/TerminalViewModel.swift:69-86 + Sources/TerminalView.swift:64-66
**Evidence:** Dual resize paths can ping-pong
**Rule:** RUBRIC-B/correctness
**Required Change:** Pick one authoritative source or add guard
**Status:** Not addressed - acceptable for initial implementation

### B7 (nit)
**Location:** Tests/TerminalViewTests.swift:8
**Evidence:** `final class MockPTYSession: PTYSession, @unchecked Sendable`
**Rule:** RUBRIC-B/concurrency
**Required Change:** Use lock or actor for sentData/resizeCalls
**Status:** Not addressed - acceptable for test code
