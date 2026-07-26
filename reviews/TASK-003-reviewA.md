# TASK-003 Review A - Spec Compliance

**Verdict:** REQUEST_CHANGES

## REQUIRED Findings

### A1 (blocker)
**Location:** WebAuthSession.swift:65,71
**Evidence:** `AuthError.sessionError(error.localizedDescription)`
**Rule:** RUBRIC-A/compilation
**Required Change:** Add `case sessionError(String)` to `AuthError` enum in AuthError.swift and a matching arm in the `CustomStringConvertible` extension. Alternatively, map to the existing `.unexpected(String)` case.

### A2 (major)
**Location:** WebAuthSession.swift:55-85
**Evidence:** `Task { @MainActor in let session = ASWebAuthenticationSession(...) { ... }; session.start() }`
**Rule:** RUBRIC-A/correctness
**Required Change:** ASWebAuthenticationSession does not retain itself; the local `session` variable is deallocated when the Task body completes after `start()`, so the callback never fires and the continuation hangs. Store the session in a property (e.g. an `@MainActor` class-level `var currentSession: ASWebAuthenticationSession?`) and nil it out in the callback.

### A3 (minor)
**Location:** AuthService.swift:91-95
**Evidence:** `try validateToken(token)  // validates trimmed` then `let tokenData = Data(token.utf8)  // stores original, untrimmed`
**Rule:** RUBRIC-A/correctness
**Required Change:** Store `token.trimmingCharacters(in: .whitespacesAndNewlines)` so the persisted value matches what was validated, or remove the trim from validation and validate the raw token directly.

## OPTIONAL Findings

### A4 (nit)
**Location:** WebAuthSession.swift:15
**Evidence:** `/// - Throws: ``AuthError/sessionError(_:)`` for other session failures.`
**Rule:** RUBRIC-A/documentation
**Required Change:** Update doc comment to reference the actual error case once A1 is resolved.

### A5 (nit)
**Location:** WebAuthSession.swift:65,71
**Evidence:** `AuthError.sessionError(error.localizedDescription)`
**Rule:** RUBRIC-A/no-secrets-in-errors
**Required Change:** Consider passing a static/generic message (e.g. "Web authentication session failed") instead of `error.localizedDescription`, which is an uncontrolled system string. Aligns with spec constraint: 'No secrets in logs or error messages.'
