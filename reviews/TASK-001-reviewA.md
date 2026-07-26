# Review TASK-001 — Reviewer A

**Verdict:** REJECT

## REQUIRED Findings

### BLOCKER-1: Wrong Swift tools version
- **Location:** `Modules/CoderKit/Package.swift:1`
- **Evidence:** `// swift-tools-version: 5.9`
- **Rule:** Spec requires swift-tools-version 6.0
- **Required change:** Change to `// swift-tools-version: 6.0`

### BLOCKER-2: Wrong platform deployment target
- **Location:** `Modules/CoderKit/Package.swift:7-8`
- **Evidence:** `.macOS(.v13), .iOS(.v16)`
- **Rule:** Spec requires `platforms: [.iOS(.v17)]` only
- **Required change:** Replace with `platforms: [.iOS(.v17)]`

### BLOCKER-3: Tests use XCTest instead of Swift Testing
- **Location:** `Modules/CoderKit/Tests/WorkspaceTests.swift:1-4`
- **Evidence:** `import XCTest` / `final class WorkspaceTests: XCTestCase`
- **Rule:** Spec requires Swift Testing framework with @Test macro
- **Required change:** Rewrite using `import Testing` and `@Test` functions

### MAJOR-1: Missing test for absent optional field
- **Location:** `Modules/CoderKit/Tests/WorkspaceTests.swift`
- **Evidence:** Test covers `null` but not absent key
- **Rule:** Spec requires coverage of null optional fields (both null and absent)
- **Required change:** Add test case where `template_name` key is omitted entirely

### MAJOR-2: Date decoder overly strict
- **Location:** `Modules/CoderKit/Sources/Models/Workspace.swift:65-66`
- **Evidence:** ISO8601DateFormatter requires fractional seconds
- **Rule:** Real-world APIs return dates with and without fractional seconds
- **Required change:** Handle both formats gracefully

## OPTIONAL Findings

### MINOR-1: No custom encode(to:)
- **Location:** `Modules/CoderKit/Sources/Models/Workspace.swift`
- **Evidence:** Asymmetric encode/decode round-trip
- **Required change:** Add matching encode(to:) or document behavior

### MINOR-2: ISO8601DateFormatter allocated per decode
- **Location:** `Modules/CoderKit/Sources/Models/Workspace.swift:65-66`
- **Evidence:** New formatter created on every decode
- **Required change:** Use static let cached formatter

### MINOR-3: No test for invalid date strings
- **Location:** `Modules/CoderKit/Tests/WorkspaceTests.swift`
- **Evidence:** No test for malformed date error path
- **Required change:** Add test using #expect(throws:)
