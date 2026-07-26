import Foundation

/// Protocol for WebSocket transport abstraction.
///
/// This protocol allows for dependency injection of the WebSocket implementation,
/// making the PTYClient testable with mock transports.
public protocol PTYTransport: Sendable {
    /// Connects to the WebSocket endpoint.
    ///
    /// - Parameters:
    ///   - url: The WebSocket URL to connect to.
    ///   - headers: HTTP headers to include in the connection request.
    /// - Returns: A WebSocket connection.
    /// - Throws: Error if the connection cannot be established.
    func connect(url: URL, headers: [String: String]) async throws -> any PTYWebSocket
}

/// Protocol for WebSocket connection abstraction.
///
/// This protocol provides a minimal interface for WebSocket operations,
/// allowing for easy mocking in tests.
public protocol PTYWebSocket: Sendable {
    /// Sends a text message through the WebSocket.
    ///
    /// - Parameter message: The text message to send.
    /// - Throws: Error if the message cannot be sent.
    func send(text: String) async throws

    /// Receives the next message from the WebSocket.
    ///
    /// - Returns: The received WebSocket message.
    /// - Throws: Error if the message cannot be received.
    func receive() async throws -> PTYWebSocketMessage

    /// Closes the WebSocket connection.
    ///
    /// - Parameters:
    ///   - code: The close code.
    ///   - reason: Optional close reason.
    /// - Throws: Error if the connection cannot be closed.
    func close(code: PTYWebSocketCloseCode, reason: String?) async throws
}

/// Represents a WebSocket message.
public enum PTYWebSocketMessage: Sendable {
    case text(String)
    case data(Data)
}

/// WebSocket close codes.
public enum PTYWebSocketCloseCode: Sendable {
    case normalClosure
    case goingAway
    case protocolError
    case unsupportedData
    case abnormalClosure

    var rawValue: UInt16 {
        switch self {
        case .normalClosure: return 1000
        case .goingAway: return 1001
        case .protocolError: return 1002
        case .unsupportedData: return 1003
        case .abnormalClosure: return 1006
        }
    }
}

/// Errors that can occur during PTY transport operations.
public enum PTYTransportError: Error, Sendable {
    case invalidURL
    case connectionFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case connectionClosed
}

#if canImport(Darwin)
import Foundation

/// Apple-platform implementation using URLSessionWebSocketTask.
///
/// This transport is only available on Apple platforms where
/// `URLSessionWebSocketTask` is natively supported.
public actor URLSessionPTYTransport: PTYTransport {
    private let session: URLSession
    private let sessionToken: String?

    /// Creates a new URLSession-based transport.
    ///
    /// - Parameters:
    ///   - session: The URLSession to use for connections.
    ///   - sessionToken: Optional session token for authentication.
    public init(session: URLSession = .shared, sessionToken: String? = nil) {
        self.session = session
        self.sessionToken = sessionToken
    }

    public func connect(url: URL, headers: [String: String]) async throws -> any PTYWebSocket {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let token = sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionWebSocketAdapter(task: task)
    }
}

/// Adapter that wraps URLSessionWebSocketTask to conform to PTYWebSocket.
private actor URLSessionWebSocketAdapter: PTYWebSocket {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> PTYWebSocketMessage {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return .text(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            throw PTYTransportError.receiveFailed("Unknown message type")
        }
    }

    func close(code: PTYWebSocketCloseCode, reason: String?) async throws {
        let nsCode = URLSessionWebSocketTask.CloseCode(rawValue: Int(code.rawValue)) ?? .normalClosure
        task.cancel(with: nsCode, reason: reason.map { Data($0.utf8) })
    }
}
#endif
