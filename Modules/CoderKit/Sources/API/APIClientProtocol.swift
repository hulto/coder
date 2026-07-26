import Foundation

/// Protocol defining the interface for a Coder API client.
public protocol CoderAPIClientProtocol: Sendable {
    /// The base URL for the API (e.g. "https://coder.example.com").
    var baseURL: URL { get }

    /// Performs an API request and decodes the response.
    /// - Parameter endpoint: The API endpoint to request.
    /// - Returns: The decoded response of type T.
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
}
