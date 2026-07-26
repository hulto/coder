import Foundation

/// A reconnecting PTY client that communicates over WebSocket.
///
/// This client implements Coder's reconnecting-PTY protocol, providing:
/// - Automatic reconnection with exponential backoff and jitter
/// - Session resumption using reconnect tokens
/// - Bidirectional terminal I/O via AsyncStream
/// - Terminal resize support
///
/// The client uses dependency injection for the WebSocket transport,
/// making it testable with mock implementations.
///
/// - Important: Secrets (tokens, credentials) are never logged.
public actor PTYClient: PTYSession {
    /// The WebSocket endpoint URL.
    private let baseURL: URL

    /// The transport layer for WebSocket connections.
    private let transport: any PTYTransport

    /// Reconnect policy for managing reconnection attempts.
    private var reconnectPolicy: PTYReconnectPolicy

    /// Reconnect token for session resumption.
    private let reconnectToken: String

    /// Initial terminal dimensions.
    private var cols: Int
    private var rows: Int

    /// Optional command to execute in the terminal.
    private let command: String?

    /// Current WebSocket connection.
    private var webSocket: (any PTYWebSocket)?

    /// Task that manages the WebSocket connection and message handling.
    private var connectionTask: Task<Void, Never>?

    /// Whether the client is currently connected.
    private var isConnected: Bool = false

    /// Continuation for yielding output data.
    private let outputContinuation: AsyncStream<Data>.Continuation

    /// Asynchronous stream of terminal output data.
    public let output: AsyncStream<Data>

    /// Logger for diagnostic messages. Never logs secrets.
    private let logger: PTYLogging

    /// Creates a new PTY client.
    ///
    /// - Parameters:
    ///   - url: The WebSocket endpoint URL.
    ///   - transport: The transport layer for WebSocket connections.
    ///   - reconnectToken: Token for session resumption.
    ///   - cols: Initial number of columns.
    ///   - rows: Initial number of rows.
    ///   - command: Optional command to execute in the terminal.
    ///   - reconnectPolicy: Policy for managing reconnection attempts.
    ///   - logger: Logger for diagnostic messages. Defaults to a no-op logger.
    public init(
        url: URL,
        transport: any PTYTransport,
        reconnectToken: String,
        cols: Int = 80,
        rows: Int = 24,
        command: String? = nil,
        reconnectPolicy: PTYReconnectPolicy = PTYReconnectPolicy(),
        logger: PTYLogging = NoOpPTYLogger()
    ) {
        self.baseURL = url
        self.transport = transport
        self.reconnectToken = reconnectToken
        self.cols = cols
        self.rows = rows
        self.command = command
        self.reconnectPolicy = reconnectPolicy
        self.logger = logger

        var continuation: AsyncStream<Data>.Continuation!
        self.output = AsyncStream(bufferingPolicy: .unbounded) { continuation = $0 }
        self.outputContinuation = continuation
    }

    /// Starts the PTY session and begins receiving output.
    ///
    /// This method establishes the WebSocket connection and starts
    /// the reconnection loop if the connection is lost.
    public func start() {
        guard connectionTask == nil else {
            return
        }

        connectionTask = Task { [weak self] in
            guard let self else { return }
            await self.connectionLoop()
        }
    }

    /// Stops the PTY session and closes all connections.
    public func stop() async {
        connectionTask?.cancel()
        connectionTask = nil

        if let ws = webSocket {
            try? await ws.close(code: .normalClosure, reason: nil)
        }
        webSocket = nil
        isConnected = false
        outputContinuation.finish()
    }

    /// Sends input data to the terminal.
    ///
    /// The data is encoded as a JSON `ReconnectingPTYRequest` and sent
    /// through the WebSocket connection.
    ///
    /// - Parameter data: The data to send to the terminal.
    /// - Throws: ``PTYClientError/notConnected`` if not connected.
    /// - Throws: ``PTYClientError/encodingFailed`` if the data cannot be encoded.
    public func send(_ data: Data) async throws {
        guard let ws = webSocket, isConnected else {
            throw PTYClientError.notConnected
        }

        // Convert binary data to string for JSON encoding.
        // Terminal input is typically UTF-8 text.
        guard let inputString = String(data: data, encoding: .utf8) else {
            throw PTYClientError.encodingFailed
        }

        let request = ReconnectingPTYRequest(data: inputString, height: 0, width: 0)
        try await sendRequest(request, via: ws)
    }

    /// Resizes the terminal.
    ///
    /// Sends a resize request through the WebSocket connection.
    ///
    /// - Parameters:
    ///   - cols: Number of columns.
    ///   - rows: Number of rows.
    /// - Throws: ``PTYClientError/notConnected`` if not connected.
    public func resize(cols: Int, rows: Int) async throws {
        self.cols = cols
        self.rows = rows

        guard let ws = webSocket, isConnected else {
            throw PTYClientError.notConnected
        }

        let request = ReconnectingPTYRequest(data: "", height: UInt16(rows), width: UInt16(cols))
        try await sendRequest(request, via: ws)
    }

    // MARK: - Internal (for testing)

    /// Returns whether the client is currently connected.
    var connected: Bool {
        isConnected
    }

    /// Returns the current attempt number from the reconnect policy.
    var reconnectAttempt: Int {
        reconnectPolicy.currentAttempt
    }

    // MARK: - Private Methods

    /// Sends a PTY request through the WebSocket.
    private func sendRequest(_ request: ReconnectingPTYRequest, via ws: any PTYWebSocket) async throws {
        let jsonData = try JSONEncoder().encode(request)

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw PTYClientError.encodingFailed
        }

        try await ws.send(text: jsonString)
    }

    /// Main connection loop that handles reconnection.
    private func connectionLoop() async {
        while !Task.isCancelled {
            do {
                try await connect()
                try await receiveMessages()
            } catch is CancellationError {
                break
            } catch {
                // Log error without sensitive information
                logger.log("Connection error occurred, attempting reconnect")

                // Calculate backoff delay
                let delay = reconnectPolicy.nextDelay()
                let delayString = String(format: "%.1f", delay)
                let attempt = reconnectPolicy.currentAttempt
                logger.log("Reconnecting in \(delayString)s (attempt \(attempt))")

                // Sleep with cancellation support
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
            }
        }
    }

    /// Establishes a WebSocket connection.
    private func connect() async throws {
        // Build the WebSocket URL with query parameters
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PTYClientError.invalidURL
        }

        var queryItems = components.queryItems ?? []

        // Add reconnect token for session resumption
        queryItems.append(URLQueryItem(name: "reconnect", value: reconnectToken))

        // Add terminal dimensions
        queryItems.append(URLQueryItem(name: "height", value: "\(rows)"))
        queryItems.append(URLQueryItem(name: "width", value: "\(cols)"))

        // Add command if specified
        if let command = command {
            queryItems.append(URLQueryItem(name: "command", value: command))
        }

        components.queryItems = queryItems

        guard let wsURL = components.url else {
            throw PTYClientError.invalidURL
        }

        // Connect via transport with authentication headers
        let headers: [String: String] = [:]
        let ws = try await transport.connect(url: wsURL, headers: headers)
        webSocket = ws
        isConnected = true

        // Reset reconnect policy on successful connection
        reconnectPolicy.reset()

        logger.log("Connected to PTY session")
    }

    /// Receives and processes messages from the WebSocket.
    private func receiveMessages() async throws {
        guard let ws = webSocket else {
            throw PTYClientError.notConnected
        }

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()

                switch message {
                case .text:
                    // Text messages are not expected in the PTY protocol;
                    // raw terminal output arrives as binary data.
                    break

                case .data(let data):
                    // Binary messages contain terminal output
                    outputContinuation.yield(data)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Connection lost; throw to trigger reconnection
                isConnected = false
                throw error
            }
        }
    }
}

// MARK: - Supporting Types

/// Errors that can occur during PTY client operations.
public enum PTYClientError: Error, Sendable, CustomStringConvertible {
    /// The URL could not be constructed.
    case invalidURL
    /// The client is not connected to a PTY session.
    case notConnected
    /// The data could not be encoded as UTF-8.
    case encodingFailed
    /// The connection failed.
    case connectionFailed(String)

    public var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .notConnected:
            return "Not connected to PTY session"
        case .encodingFailed:
            return "Failed to encode data"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        }
    }
}

/// Internal representation of a Coder ReconnectingPTYRequest.
///
/// This matches the server-side `ReconnectingPTYRequest` struct:
/// ```go
/// type ReconnectingPTYRequest struct {
///     Data   string `json:"data,omitempty"`
///     Height uint16 `json:"height,omitempty"`
///     Width  uint16 `json:"width,omitempty"`
/// }
/// ```
struct ReconnectingPTYRequest: Codable, Sendable {
    let data: String
    let height: UInt16
    let width: UInt16
}

// MARK: - Logging

/// Protocol for PTY client logging.
///
/// Implementations must ensure that no secrets (tokens, credentials,
/// session data) are included in log output.
public protocol PTYLogging: Sendable {
    func log(_ message: String)
}

/// A no-op logger that discards all messages.
public struct NoOpPTYLogger: PTYLogging {
    public init() {}
    public func log(_ message: String) {}
}

/// A logger that prints to standard output. For debugging only.
///
/// - Warning: Do not use in production. Ensure no sensitive data is logged.
public struct PrintPTYLogger: PTYLogging {
    private let prefix: String

    public init(prefix: String = "[PTYClient]") {
        self.prefix = prefix
    }

    public func log(_ message: String) {
        print("\(prefix) \(message)")
    }
}
