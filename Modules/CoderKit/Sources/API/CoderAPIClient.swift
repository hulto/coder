import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Protocol abstracting URLSession data loading for testability.
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Wrapper around URLSession that conforms to URLSessionProtocol.
public struct URLSessionWrapper: URLSessionProtocol, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// A URLSession-based implementation of the Coder API client.
public final class CoderAPIClient: CoderAPIClientProtocol, Sendable {
    public let baseURL: URL
    private let sessionToken: String
    private let session: URLSessionProtocol
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        sessionToken: String,
        session: URLSessionProtocol = URLSessionWrapper()
    ) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.session = session

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        // Build URL
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        urlComponents?.path = endpoint.path
        if let queryItems = endpoint.queryItems {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionToken, forHTTPHeaderField: "Coder-Session-Token")

        // Perform request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.httpError(statusCode: 0, data: data)
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Success - decode response
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Workspace Endpoints

    /// Fetches a paginated list of workspaces.
    /// - Parameters:
    ///   - offset: The number of workspaces to skip (for pagination).
    ///   - limit: The maximum number of workspaces to return.
    /// - Returns: A `WorkspaceList` containing the workspaces and total count.
    public func listWorkspaces(offset: Int = 0, limit: Int = 25) async throws -> WorkspaceList {
        let queryItems = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        let endpoint = APIEndpoint(
            path: "/api/v2/workspaces",
            method: .get,
            queryItems: queryItems
        )
        return try await request(endpoint)
    }

    // MARK: - Workspace Build Endpoints

    /// Starts a workspace by creating a new build with transition "start".
    /// - Parameter id: The UUID of the workspace to start.
    /// - Returns: The created `WorkspaceBuild` representing the start operation.
    public func startWorkspace(id: UUID) async throws -> WorkspaceBuild {
        let body = try JSONEncoder().encode(["transition": "start"])
        let endpoint = APIEndpoint(
            path: "/api/v2/workspaces/\(id.uuidString)/builds",
            method: .post,
            body: body
        )
        return try await request(endpoint)
    }

    /// Stops a workspace by creating a new build with transition "stop".
    /// - Parameter id: The UUID of the workspace to stop.
    /// - Returns: The created `WorkspaceBuild` representing the stop operation.
    public func stopWorkspace(id: UUID) async throws -> WorkspaceBuild {
        let body = try JSONEncoder().encode(["transition": "stop"])
        let endpoint = APIEndpoint(
            path: "/api/v2/workspaces/\(id.uuidString)/builds",
            method: .post,
            body: body
        )
        return try await request(endpoint)
    }
}
