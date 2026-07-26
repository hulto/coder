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

private struct TestResponse: Codable, Equatable, Sendable {
    let message: String
}

private struct TestPostBody: Codable, Sendable {
    let name: String
}

private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://coder.example.com/api/v1/test")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private let testBaseURL = URL(string: "https://coder.example.com")!

// MARK: - Tests

@Test func testSuccessfulGetRequest() async throws {
    let responseJSON = #"{"message":"hello"}"#
    let responseData = try #require(responseJSON.data(using: .utf8))

    let session = MockURLSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let endpoint = APIEndpoint(path: "/api/v1/test")
    let result: TestResponse = try await client.request(endpoint)

    #expect(result.message == "hello")
}

@Test func testPostWithJSONBody() async throws {
    let responseJSON = #"{"message":"created"}"#
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

    let body = try JSONEncoder().encode(TestPostBody(name: "workspace-1"))
    let endpoint = APIEndpoint(
        path: "/api/v1/workspaces",
        method: .post,
        body: body
    )

    let result: TestResponse = try await client.request(endpoint)
    #expect(result.message == "created")

    let request = try #require(session.capturedRequest)
    #expect(request.httpMethod == "POST")
    #expect(request.httpBody == body)
}

@Test func testUnauthorizedMapping() async throws {
    let session = MockURLSession(
        data: Data(),
        response: makeHTTPResponse(statusCode: 401)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "bad-token",
        session: session
    )

    let endpoint = APIEndpoint(path: "/api/v1/test")

    do {
        let _: TestResponse = try await client.request(endpoint)
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

@Test func testNotFoundMapping() async throws {
    let session = MockURLSession(
        data: Data(),
        response: makeHTTPResponse(statusCode: 404)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let endpoint = APIEndpoint(path: "/api/v1/nonexistent")

    do {
        let _: TestResponse = try await client.request(endpoint)
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

@Test func testNetworkFailureHandling() async throws {
    struct MockNetworkError: Error, Sendable {}

    let session = MockURLSession(
        error: MockNetworkError()
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let endpoint = APIEndpoint(path: "/api/v1/test")

    do {
        let _: TestResponse = try await client.request(endpoint)
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

@Test func testInvalidJSONResponse() async throws {
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

    let endpoint = APIEndpoint(path: "/api/v1/test")

    do {
        let _: TestResponse = try await client.request(endpoint)
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

@Test func testSessionTokenSentInHeaders() async throws {
    let responseJSON = #"{"message":"ok"}"#
    let responseData = try #require(responseJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "my-secret-token",
        session: session
    )

    let endpoint = APIEndpoint(path: "/api/v1/test")
    let _: TestResponse = try await client.request(endpoint)

    let request = try #require(session.capturedRequest)
    let tokenHeader = request.value(forHTTPHeaderField: "Coder-Session-Token")
    #expect(tokenHeader == "my-secret-token")
}

@Test func testHTTPErrorMapping() async throws {
    let session = MockURLSession(
        data: Data("server error".utf8),
        response: makeHTTPResponse(statusCode: 500)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let endpoint = APIEndpoint(path: "/api/v1/test")

    do {
        let _: TestResponse = try await client.request(endpoint)
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

@Test func testQueryItems() async throws {
    let responseJSON = #"{"message":"ok"}"#
    let responseData = try #require(responseJSON.data(using: .utf8))

    let session = CapturingSession(
        data: responseData,
        response: makeHTTPResponse(statusCode: 200)
    )

    let client = CoderAPIClient(
        baseURL: testBaseURL,
        sessionToken: "test-token",
        session: session
    )

    let endpoint = APIEndpoint(
        path: "/api/v1/workspaces",
        method: .get,
        queryItems: [URLQueryItem(name: "owner", value: "alice")]
    )

    let _: TestResponse = try await client.request(endpoint)

    let request = try #require(session.capturedRequest)
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let queryItems = components.queryItems
    #expect(queryItems?.contains(where: { $0.name == "owner" && $0.value == "alice" }) == true)
}
