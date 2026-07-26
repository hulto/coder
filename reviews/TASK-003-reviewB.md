# TASK-003 Review B - Security & Architecture

**Verdict:** REQUEST_CHANGES

## REQUIRED Findings

### B1 (blocker)
**Location:** WebAuthSession.swift:56-84
**Evidence:** `let session = ASWebAuthenticationSession(...)\nsession.start()`
**Rule:** RUBRIC-B/ios-lifecycle
**Required Change:** Store ASWebAuthenticationSession as a property on ASWebAuthSessionProvider to prevent immediate deallocation. The session must be retained until the callback fires.

## OPTIONAL Findings

### B2 (minor)
**Location:** KeychainManager.swift:58
**Evidence:** `try? delete(forKey: key)`
**Rule:** RUBRIC-B/error-propagation
**Required Change:** Either propagate the delete error or handle errSecItemNotFound explicitly. Silent failure may mask keychain corruption or permission issues.
