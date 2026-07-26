# Adjudication TASK-001

## REQUIRED Findings (Must Address)

1. **Swift tools version** (both reviewers): Change from 5.9 to 6.0
2. **Platform deployment target** (both reviewers): Change from [.macOS(.v13), .iOS(.v16)] to [.iOS(.v17)]
3. **Test framework** (both reviewers): Rewrite from XCTest to Swift Testing (@Test)
4. **Date decoder flexibility** (reviewer-a MAJOR-2): Handle dates with and without fractional seconds
5. **Test coverage for absent optional** (reviewer-a MAJOR-1): Add test for missing template_name key

## OPTIONAL Findings (Logged, Not Blocking)

- ISO8601DateFormatter performance optimization (both reviewers)
- Force unwraps in tests (reviewer-b)
- Custom encode(to:) for symmetry (reviewer-a)
- Test for invalid date strings (reviewer-a)

## Decision

All 5 REQUIRED findings must be addressed. The fixer will:
1. Update Package.swift to swift-tools-version 6.0 and platforms [.iOS(.v17)]
2. Rewrite tests using Swift Testing framework
3. Fix date decoder to handle both formats
4. Add test for absent optional field
5. Re-run all gates

After fixes, reviewers will re-verify each finding ID is resolved.
