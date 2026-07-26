# TASK-002 Review B

**Verdict:** APPROVE

## OPTIONAL Findings

### B1 (minor)
**Location:** CoderAPIClient.swift:74
**Evidence:** `throw APIError.httpError(statusCode: 0, data: data)`
**Rule:** RUBRIC-B/error-clarity
**Required Change:** Status code 0 for non-HTTPURLResponse is confusing. Consider a dedicated error case like .invalidResponse or document that 0 indicates non-HTTP response.

### B2 (nit)
**Location:** CoderAPIClient.swift:60
**Evidence:** `request.setValue("application/json", forHTTPHeaderField: "Content-Type")`
**Rule:** RUBRIC-B/http-standards
**Required Change:** Add Accept: application/json header for proper HTTP semantics. Content-Type describes the request body; Accept describes expected response format.

### B3 (nit)
**Location:** CoderAPIClient.swift:57-61
**Evidence:** `var request = URLRequest(url: url)`
**Rule:** RUBRIC-B/network-config
**Required Change:** Consider making timeout configurable or explicit. URLSession.shared defaults to 60s timeout, but explicit configuration improves clarity and control.
