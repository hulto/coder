import Foundation

/// Errors that can occur when making API requests.
public enum APIError: Error, Sendable {
    /// The URL could not be constructed.
    case invalidURL
    /// A network error occurred.
    case networkError(Error)
    /// The server returned an HTTP error status code.
    case httpError(statusCode: Int, data: Data?)
    /// The response could not be decoded.
    case decodingError(Error)
    /// The request was unauthorized (401).
    case unauthorized
    /// The request was forbidden (403).
    case forbidden
    /// The resource was not found (404).
    case notFound
    /// The request conflicts with the current state (409).
    case conflict
}

extension APIError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, _):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized"
        case .forbidden:
            return "Forbidden"
        case .notFound:
            return "Not found"
        case .conflict:
            return "Conflict"
        }
    }
}
