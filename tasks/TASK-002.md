---
id: TASK-002
title: CoderKit API client with URLSession
phase: 1
module: CoderKit
depends_on: [TASK-001]
blocks: [TASK-003, TASK-004]
parallel_safe_with: []
context_budget_tokens: 60000
worktree: wt/task-002-api-client
---

## Goal
Implement a generic HTTP client for the Coder REST API using URLSession with async/await. The client should handle authentication headers, JSON encoding/decoding, error mapping, and provide a foundation for all API endpoints.

## In scope (files this task MAY create/modify)
- Sources/CoderKit/API/CoderAPIClient.swift (new)
- Sources/CoderKit/API/APIError.swift (new)
- Sources/CoderKit/API/APIClientProtocol.swift (new)
- Tests/CoderKitTests/APIClientTests.swift (new)

## Explicitly OUT of scope (do NOT touch)
- Any .xcodeproj / project.yml / Package.swift target wiring
- Authentication flow (TASK-003)
- Specific endpoint methods beyond the generic client (TASK-003+)
- CoderAuth module

## Contracts / interfaces it MUST honor
- Consumes `CoderKit.Workspace` and other models from TASK-001
- Public surface MUST be:
  ```swift
  public protocol CoderAPIClientProtocol: Sendable {
      var baseURL: URL { get }
      func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
  }
  
  public struct APIEndpoint: Sendable {
      public let path: String
      public let method: HTTPMethod
      public let queryItems: [URLQueryItem]?
      public let body: Data?
  }
  
  public enum HTTPMethod: String, Sendable {
      case get = "GET"
      case post = "POST"
      case put = "PUT"
      case delete = "DELETE"
  }
  
  public enum APIError: Error, Sendable {
      case invalidURL
      case networkError(Error)
      case httpError(statusCode: Int, data: Data?)
      case decodingError(Error)
      case unauthorized
      case notFound
  }
  ```
- All public types Sendable; the client is an `actor` or uses `@MainActor` appropriately
- Session token passed via `Coder-Session-Token` header

## Acceptance criteria (each must be machine- or reviewer-verifiable)
1. Compiles under Swift 6 strict concurrency (complete) with zero warnings.
2. Can make GET/POST/PUT/DELETE requests with proper headers.
3. Decodes JSON responses into Codable types.
4. Maps HTTP status codes to typed errors (401 → unauthorized, 404 → notFound, etc.).
5. Handles network errors gracefully.
6. Unit tests with mock URLSession transport (inject via protocol).
7. No secrets logged or exposed in error messages.

## Test requirements
- Swift Testing (`@Test`) with a mock URLSession transport injected via protocol.
- Cover: successful GET, POST with body, 401 error, 404 error, network failure, invalid JSON response.
- Verify session token is sent in headers.
- Verify error mapping for various HTTP status codes.

## Definition of Done (all must be TRUE)
- [ ] `swift build --package-path Modules/CoderKit -Xswiftc -strict-concurrency=complete` clean
- [ ] `swift test --package-path Modules/CoderKit` green
- [ ] `swiftlint lint --strict Modules/CoderKit` clean (if available)
- [ ] `swift-format lint -r Modules/CoderKit` clean (if available)
- [ ] Diff touches only in-scope files
- [ ] Returns: summary (≤300 words) + full diff + gate command outputs
