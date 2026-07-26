import Foundation

/// Describes a single API request to the Coder REST API.
public struct APIEndpoint: Sendable {
    /// The URL path component (e.g. "/api/v1/workspaces").
    public let path: String
    /// The HTTP method to use.
    public let method: HTTPMethod
    /// Optional URL query items to append to the URL.
    public let queryItems: [URLQueryItem]?
    /// Optional HTTP body data (typically JSON-encoded).
    public let body: Data?

    public init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
    }
}

/// HTTP methods supported by the API client.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
