# TASK-006 Review B - Security & Architecture

**Verdict:** APPROVE

## OPTIONAL Findings

### B1 (minor)
**Location:** LoginViewModel.swift
**Evidence:** No test for concurrent login attempts
**Rule:** RUBRIC-B/concurrency-testing
**Required Change:** Add test verifying behavior when login() is called multiple times concurrently

### B2 (minor)
**Location:** LoginViewModel.swift
**Evidence:** Error messages are hardcoded strings
**Rule:** RUBRIC-B/localization-readiness
**Required Change:** Consider using NSLocalizedString or String Catalog for error messages

### B3 (nit)
**Location:** LoginView.swift
**Evidence:** No test for keyboard return key behavior
**Rule:** RUBRIC-B/ux-testing
**Required Change:** Consider adding UI test for keyboard return key triggering login

### B4 (nit)
**Location:** LoginViewModel.swift
**Evidence:** No test for URL normalization
**Rule:** RUBRIC-B/input-validation
**Required Change:** Consider adding test for URL normalization (e.g., trailing slashes, protocol handling)
