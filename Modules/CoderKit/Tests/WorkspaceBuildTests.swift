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
private final class CapturingSession: @unchecked Sendable, URLSessionProtocol {
    private let lock = NSLock()
    private let mockData: Data?
    private let mockResponse: URLResponse?
    private let mockError: Error?
    private var _capturedRequest: URLRequest?

    var capturedRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _capturedRequest
    }

    init(data: Data? = nil, response: URLResponse? = nil, error: Error? = nil) {
        self.mockData = data
        self.mockResponse = response
        self.mockError = error
        lock.lock()
        _capturedRequest = nil
        lock.unlock()
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        captureRequest(request)
        if let mockError {
            throw mockError
        }
        return (mockData ?? Data(), mockResponse ?? dummyURLResponse())
    }

    private func captureRequest(_ request: URLRequest) {
        lock.lock()
        _capturedRequest = request
        lock.unlock()
    }
}

// MARK: - Test helpers

private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://coder.example.com/api/v2/workspaces/test/builds")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private let testBaseURL = URL(string: "https://coder.example.com")!
private let testWorkspaceID = UUID()

// MARK: - WorkspaceBuild Model Tests

@Test func testWorkspaceBuildDecoding() async throws {
    let json = """
    {
        "id": "12345678-1234-1234-1234-123456789abc",
        "workspace_id": "87654321-4321-4321-4321-cba987654321",
        "transition": "start",
        "status": "pending",
        "created_at": "2024-01-15T10:30:00Z",
        "updated_at": "2024-01-15T10:30:00Z"
    }
    """
    let data = try #require(json.data(using: .utf8))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let build = try decoder.decode(WorkspaceBuild.self, from: data)

    #expect(build.id.uuidString == "12345678-1234-1234-1234-123456789ABC")
    #expect(build.workspaceID.uuidString == "87654321-4321-4321-4321-CBA987654321")
    #expect(build.transition == .start)
    #expect(build.status == .pending)
}

@Test func testWorkspaceBuildDecodingWithFractionalSeconds() async throws {
    let json = """
    {
        "id": "12345678-1234-1234-1234-123456789abc",
        "workspace_id": "87654321-4321-4321-4321-cba987654321",
        "transition": "stop",
        "status": "running",
        "created_at": "2024-01-15T10:30:00.123456Z",
        "updated_at": "2024-01-15T10:30:01.654321Z"
    }
    """
    let data = try #require(json.data(using: .utf8))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let build = try decoder.decode(WorkspaceBuild.self, from: data)

    #expect(build.transition == .stop)
    #expect(build.status == .running)
}

@Test func testWorkspaceBuildEncoding() async throws {
    let build = WorkspaceBuild(
        id: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
        workspaceID: UUID(uuidString: "87654321-4321-4321-4321-CBA987654321")!,
        transition: .start,
        status: .pending,
        createdAt: Date(timeIntervalSince1970: 1705315800),
        updatedAt: Date(timeIntervalSince1970: 1705315800)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(build)
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(json.contains("\"transition\":\"start\""))
    #expect(json.contains("\"status\":\"pending\""))
    #expect(json.contains("\"workspace_id\""))
}

@Test func testWorkspaceBuildStatusAllCases() async throws {
    let statuses: [WorkspaceBuildStatus] = [.pending, .starting, .running, .stopping, .stopped, .failed, .canceling, .deleted]

    for status in statuses {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789abc",
            "workspace_id": "87654321-4321-4321-4321-cba987654321",
            "transition": "start",
            "status": "\(status.rawValue)",
            "created_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T10:30:00Z"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let build = try decoder.decode(WorkspaceBuild.self, from: data)
        #expect(build.status == status)
    }
}

@Test func testWorkspaceTransitionAllCases() async throws {
    let transitions: [WorkspaceTransition] = [.start, .stop, .delete]

    for transition in transitions {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789abc",
            "workspace_id": "87654321-4321-4321-4321-cba987654321",
            "transition": "\(transition.rawValue)",
            "status": "pending",
            "created_at": "2024-01-15T10:30:00Z",
            "updated_at": "2024-01-15T10:30:00Z"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let build = try decoder.decode(WorkspaceBuild.self, from: data)
        #expect(build.transition == transition)
    }
}

// MARK: - startWorkspace API Tests

@Test func testStartWorkspaceSuccess() async throws {
    let responseJSON = """
    {
        "id": "12345678-1234-1234-1234-123456789abc",
        "workspace_id": "\(testWorkspaceID.uuidString.lowercased())",
        "transition": "start",
        "status": "pending",
        "created_at": "2024-01-15T10:30:00Z",
        "updated_at": "2024-01-15T10:30:00Z"
    }
    """
    let responseData = try #require(responseJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 201)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let build = try await client.startWorkspace(id: testWorkspaceID)

    #expect(build.id.uuidString == "12345678-1234-1234-1234-123456789ABC")
    #expect(build.workspaceID == testWorkspaceID)
    #expect(build.transition == .start)
    #expect(build.status == .pending)

    let request = try #require(session.capturedRequest)
    #expect(request.httpMethod == "POST")
    let url = try #require(request.url)
    #expect(url.path == "/api/v2/workspaces/\(testWorkspaceID.uuidString)/builds")

    let bodyData = try #require(request.httpBody)
    let bodyJSON = try #require(String(data: bodyData, encoding: .utf8))
    #expect(bodyJSON.contains("\"transition\":\"start\""))
}

@Test func testStartWorkspaceConflict() async throws {
    let session = MockURLSession(
        data: Data("workspace is already running".utf8),
        response: makeHTTPResponse(statusCode: 409)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    do {
        _ = try await client.startWorkspace(id: testWorkspaceID)
        Issue.record("Expected APIError.conflict to be thrown")
    } catch let error as APIError {
        if case .conflict = error {
            // Expected
        } else {
            Issue.record("Expected .conflict, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testStartWorkspaceNotFound() async throws {
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
        _ = try await client.startWorkspace(id: testWorkspaceID)
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

@Test func testStartWorkspaceUnauthorized() async throws {
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
        _ = try await client.startWorkspace(id: testWorkspaceID)
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

// MARK: - stopWorkspace API Tests

@Test func testStopWorkspaceSuccess() async throws {
    let responseJSON = """
    {
        "id": "12345678-1234-1234-1234-123456789abc",
        "workspace_id": "\(testWorkspaceID.uuidString.lowercased())",
        "transition": "stop",
        "status": "pending",
        "created_at": "2024-01-15T10:30:00Z",
        "updated_at": "2024-01-15T10:30:00Z"
    }
    """
    let responseData = try #require(responseJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 201)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let build = try await client.stopWorkspace(id: testWorkspaceID)

    #expect(build.id.uuidString == "12345678-1234-1234-1234-123456789ABC")
    #expect(build.workspaceID == testWorkspaceID)
    #expect(build.transition == .stop)
    #expect(build.status == .pending)

    let request = try #require(session.capturedRequest)
    #expect(request.httpMethod == "POST")
    let url = try #require(request.url)
    #expect(url.path == "/api/v2/workspaces/\(testWorkspaceID.uuidString)/builds")

    let bodyData = try #require(request.httpBody)
    let bodyJSON = try #require(String(data: bodyData, encoding: .utf8))
    #expect(bodyJSON.contains("\"transition\":\"stop\""))
}

@Test func testStopWorkspaceConflict() async throws {
    let session = MockURLSession(
        data: Data("workspace is already stopped".utf8),
        response: makeHTTPResponse(statusCode: 409)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    do {
        _ = try await client.stopWorkspace(id: testWorkspaceID)
        Issue.record("Expected APIError.conflict to be thrown")
    } catch let error as APIError {
        if case .conflict = error {
            // Expected
        } else {
            Issue.record("Expected .conflict, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}

@Test func testStopWorkspaceNotFound() async throws {
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
        _ = try await client.stopWorkspace(id: testWorkspaceID)
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

@Test func testStopWorkspaceUnauthorized() async throws {
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
        _ = try await client.stopWorkspace(id: testWorkspaceID)
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

// MARK: - APIError Tests

@Test func testAPIErrorConflictDescription() async throws {
    let error = APIError.conflict
    #expect(error.description == "Conflict")
}

@Test func testConflictErrorMapping() async throws {
    let session = MockURLSession(
        data: Data(),
        response: makeHTTPResponse(statusCode: 409)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let endpoint = APIEndpoint(path: "/api/v2/test")

    do {
        let _: WorkspaceBuild = try await client.request(endpoint)
        Issue.record("Expected APIError.conflict to be thrown")
    } catch let error as APIError {
        if case .conflict = error {
            // Expected
        } else {
            Issue.record("Expected .conflict, got \(error)")
        }
    } catch {
        Issue.record("Expected APIError, got \(error)")
    }
}
