import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import CoderKit

// MARK: - Mock URLSession

private func dummyURLResponse() -> URLResponse {
    URLResponse(
        url: URL(string: "https://coder.example.com")!,
        mimeType: nil,
        expectedContentLength: 0,
        textEncodingName: nil
    )
}

/// A mock URLSession that returns preconfigured responses.
private struct MockURLSession: URLSessionProtocol, Sendable {
    let mockData: Data?
    let mockResponse: URLResponse?
    let mockError: Error?

    init(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil) {
        self.mockData = data
        self.mockResponse = response
        self.mockError = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let mockError {
            throw mockError
        }
        return (mockData ?? Data(), mockResponse ?? dummyURLResponse())
    }
}

/// Captures the URLRequest for assertion in tests.
private actor CapturingSession: URLSessionProtocol {
    private let mockData: Data?
    private let mockResponse: URLResponse?
    private let mockError: Error?
    private var _capturedRequest: URLRequest?

    nonisolated func capturedRequest() async -> URLRequest? {
        await _capturedRequest
    }

    init(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil) {
        self.mockData = data
        self.mockResponse = response
        self.mockError = error
        self._capturedRequest = nil
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        _capturedRequest = request
        if let mockError {
            throw mockError
        }
        return (mockData ?? Data(), mockResponse ?? dummyURLResponse())
    }
}

// MARK: - Test helpers

private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://coder.example.com/api/v2/workspaces")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private let testBaseURL = URL(string: "https://coder.example.com")!

// MARK: - Sample JSON

private let sampleWorkspaceListJSON = """
{
    "count": 2,
    "workspaces": [
        {
            "id": "550e8400-e29b-41d4-a716-446655440001",
            "name": "workspace-1",
            "owner_name": "alice",
            "template_name": "kubernetes",
            "status": "running",
            "created_at": "2024-01-15T10:30:45.123Z",
            "updated_at": "2024-01-15T11:45:30.456Z"
        },
        {
            "id": "550e8400-e29b-41d4-a716-446655440002",
            "name": "workspace-2",
            "owner_name": "bob",
            "template_name": "docker",
            "status": "stopped",
            "created_at": "2024-01-14T08:00:00Z",
            "updated_at": "2024-01-14T09:00:00Z"
        }
    ]
}
"""

private let emptyWorkspaceListJSON = """
{
    "count": 0,
    "workspaces": []
}
"""

// MARK: - Tests

@Test func testListWorkspacesDefaultPagination() async throws {
    let responseData = try #require(sampleWorkspaceListJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let result = try await client.listWorkspaces()

    #expect(result.count == 2)
    #expect(result.workspaces.count == 2)
    #expect(result.workspaces[0].name == "workspace-1")
    #expect(result.workspaces[0].ownerName == "alice")
    #expect(result.workspaces[0].status == .running)
    #expect(result.workspaces[1].name == "workspace-2")
    #expect(result.workspaces[1].ownerName == "bob")
    #expect(result.workspaces[1].status == .stopped)

    // Verify default query parameters
    let request = try #require(await session.capturedRequest())
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

    #expect(components.path == "/api/v2/workspaces")

    let queryItems = components.queryItems ?? []
    #expect(queryItems.contains(where: { $0.name == "offset" && $0.value == "0" }))
    #expect(queryItems.contains(where: { $0.name == "limit" && $0.value == "25" }))
}

@Test func testListWorkspacesCustomPagination() async throws {
    let responseData = try #require(sampleWorkspaceListJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let result = try await client.listWorkspaces(offset: 10, limit: 5)

    #expect(result.count == 2)

    // Verify custom query parameters
    let request = try #require(await session.capturedRequest())
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

    let queryItems = components.queryItems ?? []
    #expect(queryItems.contains(where: { $0.name == "offset" && $0.value == "10" }))
    #expect(queryItems.contains(where: { $0.name == "limit" && $0.value == "5" }))
}

@Test func testListWorkspacesEmptyResult() async throws {
    let responseData = try #require(emptyWorkspaceListJSON.data(using: .utf8))

    let session = MockURLSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let result = try await client.listWorkspaces()

    #expect(result.count == 0)
    #expect(result.workspaces.isEmpty)
}

@Test func testListWorkspacesUnauthorized() async throws {
    let session = MockURLSession(
        data: Data(),
        response: makeHTTPResponse(statusCode: 401)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "bad-token",
        session: session
    )

    do {
        _ = try await client.listWorkspaces()
        Issue.record("Expected APIError.unauthorized to be thrown")
    } catch let error as APIError {
        if case .unauthorized = error {
            // Expected
        } else {
            Issue.record("Expected .unauthorized, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testListWorkspacesForbidden() async throws {
    let session = MockURLSession(
        data: Data(),
        response: makeHTTPResponse(statusCode: 403)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    do {
        _ = try await client.listWorkspaces()
        Issue.record("Expected APIError.forbidden to be thrown")
    } catch let error as APIError {
        if case .forbidden = error {
            // Expected
        } else {
            Issue.record("Expected .forbidden, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testListWorkspacesNotFound() async throws {
    let session = MockURLSession(
        data: Data(),
        response: makeHTTPResponse(statusCode: 404)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    do {
        _ = try await client.listWorkspaces()
        Issue.record("Expected APIError.notFound to be thrown")
    } catch let error as APIError {
        if case .notFound = error {
            // Expected
        } else {
            Issue.record("Expected .notFound, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testListWorkspacesServerError() async throws {
    let session = MockURLSession(
        data: Data("Internal Server Error".utf8),
        response: makeHTTPResponse(statusCode: 500)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    do {
        _ = try await client.listWorkspaces()
        Issue.record("Expected APIError.httpError to be thrown")
    } catch let error as APIError {
        if case .httpError(let statusCode, _) = error {
            #expect(statusCode == 500)
        } else {
            Issue.record("Expected .httpError, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testListWorkspacesNetworkError() async throws {
    struct MockNetworkError: Error, Sendable {}

    let session = MockURLSession(error: MockNetworkError())

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    do {
        _ = try await client.listWorkspaces()
        Issue.record("Expected APIError.networkError to be thrown")
    } catch let error as APIError {
        if case .networkError = error {
            // Expected
        } else {
            Issue.record("Expected .networkError, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testListWorkspacesDecodingError() async throws {
    let invalidJSON = #"{"bad json"#
    let responseData = try #require(invalidJSON.data(using: .utf8))

    let session = MockURLSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    do {
        _ = try await client.listWorkspaces()
        Issue.record("Expected APIError.decodingError to be thrown")
    } catch let error as APIError {
        if case .decodingError = error {
            // Expected
        } else {
            Issue.record("Expected .decodingError, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testListWorkspacesSessionTokenHeader() async throws {
    let responseData = try #require(emptyWorkspaceListJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "my-secret-token",
        session: session
    )

    _ = try await client.listWorkspaces()

    let request = try #require(await session.capturedRequest())
    let tokenHeader = request.value(forHTTPHeaderField: "Coder-Session-Token")
    #expect(tokenHeader == "my-secret-token")
}

@Test func testListWorkspacesHTTPMethod() async throws {
    let responseData = try #require(emptyWorkspaceListJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    _ = try await client.listWorkspaces()

    let request = try #require(await session.capturedRequest())
    #expect(request.httpMethod == "GET")
}

@Test func testWorkspaceListDecoding() throws {
    let jsonData = try #require(sampleWorkspaceListJSON.data(using: .utf8))
    let workspaceList = try JSONDecoder().decode(WorkspaceList.self, from: jsonData)

    #expect(workspaceList.count == 2)
    #expect(workspaceList.workspaces.count == 2)
    #expect(workspaceList.workspaces[0].id == UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001"))
    #expect(workspaceList.workspaces[1].id == UUID(uuidString: "550e8400-e29b-41d4-a716-446655440002"))
}

@Test func testWorkspaceListEncoding() throws {
    let workspaceList = WorkspaceList(
        count: 1,
        workspaces: [
            Workspace(
                id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001")!,
                name: "test",
                ownerName: "alice",
                templateName: "kubernetes",
                status: .running,
                createdAt: Date(timeIntervalSince1970: 1705312245),
                updatedAt: Date(timeIntervalSince1970: 1705316730)
            )
        ]
    )

    let data = try JSONEncoder().encode(workspaceList)
    let decoded = try JSONDecoder().decode(WorkspaceList.self, from: data)

    #expect(decoded.count == 1)
    #expect(decoded.workspaces.count == 1)
    #expect(decoded.workspaces[0].name == "test")
}
