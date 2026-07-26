# TASK-007 Review B - Security & Architecture

**Verdict:** APPROVE

## OPTIONAL Findings

### B1 (minor)
**Location:** PTYClient.swift:45
**Evidence:** `private var webSocketTask: URLSessionWebSocketTask?`
**Rule:** Resource management
**Required Change:** Add explicit cleanup in deinit to ensure WebSocket is cancelled

### B2 (minor)
**Location:** PTYReconnectPolicy.swift:28
**Evidence:** `private var currentAttempt: Int = 0`
**Rule:** State management
**Required Change:** Consider making attempt counter actor-isolated if accessed concurrently

### B3 (nit)
**Location:** PTYClient.swift:120
**Evidence:** WebSocket message parsing
**Rule:** Input validation
**Required Change:** Add size limit check on incoming messages to prevent memory exhaustion

### B4 (nit)
**Location:** PTYTransport.swift:25
**Evidence:** Protocol doesn't specify timeout behavior
**Rule:** Protocol clarity
**Required Change:** Document timeout expectations in protocol contract
