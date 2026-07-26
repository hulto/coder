import Testing
import Foundation
@testable import TerminalFeature

// MARK: - Mock Types

/// Mock WebSocket for testing
actor MockWebSocket: PTYWebSocket {
    var sentMessages: [String] = []
    var messagesToReceive: [PTYWebSocketMessage] = []
    var closeCode: PTYWebSocketCloseCode?
    var closeReason: String?
    var shouldFailOnReceive = false
    var receiveError: Error?
    var receiveDelay: Duration?

    nonisolated func send(text: String) async throws {
        await addSentMessage(text)
    }

    private func addSentMessage(_ text: String) {
        sentMessages.append(text)
    }

    nonisolated func receive() async throws -> PTYWebSocketMessage {
        if let delay = await receiveDelay {
            try await Task.sleep(for: delay)
        }
        let state = await getState()
        if state.shouldFailOnReceive {
            throw state.receiveError ?? PTYTransportError.receiveFailed("Test error")
        }
        guard !state.messagesToReceive.isEmpty else {
            // Block until cancelled (simulates a live connection with no data)
            try await Task.sleep(for: .seconds(3600))
            throw PTYTransportError.connectionClosed
        }
        return await popMessage()
    }

    private func getState() -> (messagesToReceive: [PTYWebSocketMessage], shouldFailOnReceive: Bool, receiveError: Error?) {
        (messagesToReceive, shouldFailOnReceive, receiveError)
    }

    private func popMessage() async -> PTYWebSocketMessage {
        let message = messagesToReceive.removeFirst()
        return message
    }

    nonisolated func close(code: PTYWebSocketCloseCode, reason: String?) async throws {
        await setCloseInfo(code: code, reason: reason)
    }

    private func setCloseInfo(code: PTYWebSocketCloseCode, reason: String?) {
        closeCode = code
        closeReason = reason
    }

    func addMessageToReceive(_ message: PTYWebSocketMessage) {
        messagesToReceive.append(message)
    }

    func setReceiveFailure(error: Error? = nil) {
        shouldFailOnReceive = true
        receiveError = error
    }
}

/// Mock transport for testing
actor MockTransport: PTYTransport {
    var webSocket: MockWebSocket?
    var connectCallCount = 0
    var shouldFailConnect = false
    var connectError: Error?
    var lastConnectedURL: URL?
    var lastConnectedHeaders: [String: String]?

    nonisolated func connect(url: URL, headers: [String: String]) async throws -> any PTYWebSocket {
        await recordConnect(url: url, headers: headers)
        if await shouldFailConnect {
            throw await connectError ?? PTYTransportError.connectionFailed("Test error")
        }
        guard let ws = await webSocket else {
            throw PTYTransportError.connectionFailed("No mock websocket configured")
        }
        return ws
    }

    private func recordConnect(url: URL, headers: [String: String]) {
        connectCallCount += 1
        lastConnectedURL = url
        lastConnectedHeaders = headers
    }

    func setWebSocket(_ ws: MockWebSocket) {
        webSocket = ws
    }

    func setConnectFailure(error: Error? = nil) {
        shouldFailConnect = true
        connectError = error
    }
}

// MARK: - PTYClient Tests

@Suite("PTYClient Tests")
struct PTYClientTests {
    private let testURL = URL(string: "wss://coder.example.com/api/v2/workspaceagents/test-agent/pty")!
    private let testReconnectToken = "test-reconnect-token-12345"

    @Test("Client initializes with correct parameters")
    func initialization() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken,
            cols: 100,
            rows: 50,
            command: "bash"
        )

        #expect(await client.connected == false)
        #expect(await client.reconnectAttempt == 0)
    }

    @Test("Client connects successfully")
    func connect() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken
        )

        await client.start()

        // Wait for connection to establish
        try await Task.sleep(for: .milliseconds(100))

        #expect(await client.connected == true)
        #expect(await transport.connectCallCount == 1)

        await client.stop()
    }

    @Test("Client sends data correctly")
    func sendData() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken
        )

        await client.start()
        try await Task.sleep(for: .milliseconds(100))

        let testData = "ls -la\n".data(using: .utf8)!
        try await client.send(testData)

        let sentMessages = await webSocket.sentMessages
        #expect(sentMessages.count == 1)

        // Verify the message is valid JSON with correct structure
        let sentJSON = sentMessages[0]
        let jsonData = sentJSON.data(using: .utf8)!
        let request = try JSONDecoder().decode(ReconnectingPTYRequest.self, from: jsonData)

        #expect(request.data == "ls -la\n")
        #expect(request.height == 0)
        #expect(request.width == 0)

        await client.stop()
    }

    @Test("Client resizes terminal correctly")
    func resize() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken,
            cols: 80,
            rows: 24
        )

        await client.start()
        try await Task.sleep(for: .milliseconds(100))

        try await client.resize(cols: 120, rows: 40)

        let sentMessages = await webSocket.sentMessages
        #expect(sentMessages.count == 1)

        // Verify the resize message
        let sentJSON = sentMessages[0]
        let jsonData = sentJSON.data(using: .utf8)!
        let request = try JSONDecoder().decode(ReconnectingPTYRequest.self, from: jsonData)

        #expect(request.data == "")
        #expect(request.height == 40)
        #expect(request.width == 120)

        await client.stop()
    }

    @Test("Client receives output data")
    func receiveOutput() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        // Prepare messages to receive
        let outputData1 = "Welcome to Coder!\n".data(using: .utf8)!
        let outputData2 = "$ ".data(using: .utf8)!
        await webSocket.addMessageToReceive(.data(outputData1))
        await webSocket.addMessageToReceive(.data(outputData2))

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken
        )

        await client.start()

        // Collect output
        var receivedOutput: [Data] = []
        let stream = await client.output
        let outputTask = Task {
            for await data in stream {
                receivedOutput.append(data)
                if receivedOutput.count == 2 {
                    break
                }
            }
        }

        await outputTask.value

        #expect(receivedOutput.count == 2)
        #expect(String(data: receivedOutput[0], encoding: .utf8) == "Welcome to Coder!\n")
        #expect(String(data: receivedOutput[1], encoding: .utf8) == "$ ")

        await client.stop()
    }

    @Test("Client throws error when sending without connection")
    func sendWithoutConnection() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken
        )

        // Don't start the client, so it's not connected
        let testData = "test\n".data(using: .utf8)!

        await #expect(throws: PTYClientError.self) {
            try await client.send(testData)
        }
    }

    @Test("Client throws error when resizing without connection")
    func resizeWithoutConnection() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken
        )

        // Don't start the client, so it's not connected
        await #expect(throws: PTYClientError.self) {
            try await client.resize(cols: 100, rows: 50)
        }
    }

    @Test("Client stops cleanly")
    func stop() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken
        )

        await client.start()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await client.connected == true)

        await client.stop()
        try await Task.sleep(for: .milliseconds(100))

        #expect(await client.connected == false)
        #expect(await webSocket.closeCode == .normalClosure)
    }

    @Test("Client includes reconnect token in URL")
    func reconnectTokenInURL() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken
        )

        await client.start()
        try await Task.sleep(for: .milliseconds(100))

        let connectedURL = await transport.lastConnectedURL
        #expect(connectedURL != nil)

        let components = URLComponents(url: connectedURL!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        let reconnectItem = queryItems.first(where: { $0.name == "reconnect" })
        #expect(reconnectItem?.value == testReconnectToken)

        await client.stop()
    }

    @Test("Client includes terminal dimensions in URL")
    func terminalDimensionsInURL() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken,
            cols: 132,
            rows: 43
        )

        await client.start()
        try await Task.sleep(for: .milliseconds(100))

        let connectedURL = await transport.lastConnectedURL
        #expect(connectedURL != nil)

        let components = URLComponents(url: connectedURL!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        let heightItem = queryItems.first(where: { $0.name == "height" })
        let widthItem = queryItems.first(where: { $0.name == "width" })

        #expect(heightItem?.value == "43")
        #expect(widthItem?.value == "132")

        await client.stop()
    }

    @Test("Client includes command in URL when provided")
    func commandInURL() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken,
            command: "bash"
        )

        await client.start()
        try await Task.sleep(for: .milliseconds(100))

        let connectedURL = await transport.lastConnectedURL
        #expect(connectedURL != nil)

        let components = URLComponents(url: connectedURL!, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        let commandItem = queryItems.first(where: { $0.name == "command" })
        #expect(commandItem?.value == "bash")

        await client.stop()
    }

    @Test("Reconnect policy resets on successful connection")
    func reconnectPolicyResetsOnConnect() async throws {
        let transport = MockTransport()
        let webSocket = MockWebSocket()
        await transport.setWebSocket(webSocket)

        let policy = PTYReconnectPolicy(
            baseDelay: 0.01,
            maxDelay: 0.1,
            multiplier: 2.0,
            jitter: 0.0
        )

        let client = PTYClient(
            url: testURL,
            transport: transport,
            reconnectToken: testReconnectToken,
            reconnectPolicy: policy
        )

        await client.start()
        try await Task.sleep(for: .milliseconds(100))

        // After successful connection, attempt counter should be reset
        #expect(await client.reconnectAttempt == 0)

        await client.stop()
    }
}

// MARK: - PTYReconnectPolicy Tests

@Suite("PTYReconnectPolicy Tests")
struct PTYReconnectPolicyTests {
    @Test("Policy starts with attempt 0")
    func initialAttempt() {
        let policy = PTYReconnectPolicy()
        #expect(policy.currentAttempt == 0)
    }

    @Test("Policy increments attempt counter")
    func incrementAttempt() {
        var policy = PTYReconnectPolicy()

        _ = policy.nextDelay()
        #expect(policy.currentAttempt == 1)

        _ = policy.nextDelay()
        #expect(policy.currentAttempt == 2)

        _ = policy.nextDelay()
        #expect(policy.currentAttempt == 3)
    }

    @Test("Policy resets attempt counter")
    func resetAttempt() {
        var policy = PTYReconnectPolicy()

        _ = policy.nextDelay()
        _ = policy.nextDelay()
        _ = policy.nextDelay()

        policy.reset()
        #expect(policy.currentAttempt == 0)
    }

    @Test("Policy returns increasing delays")
    func increasingDelays() {
        var policy = PTYReconnectPolicy(
            baseDelay: 1.0,
            maxDelay: 60.0,
            multiplier: 2.0,
            jitter: 0.0
        )

        let delay1 = policy.nextDelay()
        let delay2 = policy.nextDelay()
        let delay3 = policy.nextDelay()

        // With no jitter, delays should be exactly: 1.0, 2.0, 4.0
        #expect(delay1 == 1.0)
        #expect(delay2 == 2.0)
        #expect(delay3 == 4.0)
    }

    @Test("Policy caps delay at maximum")
    func maxDelayCap() {
        var policy = PTYReconnectPolicy(
            baseDelay: 1.0,
            maxDelay: 5.0,
            multiplier: 2.0,
            jitter: 0.0
        )

        // Generate several delays
        var delays: [TimeInterval] = []
        for _ in 0..<10 {
            delays.append(policy.nextDelay())
        }

        // All delays should be <= maxDelay
        for delay in delays {
            #expect(delay <= 5.0)
        }

        // Later delays should be capped at maxDelay
        #expect(delays[3] == 5.0) // 1.0 * 2^3 = 8.0, capped to 5.0
        #expect(delays[4] == 5.0)
    }

    @Test("Policy applies jitter correctly")
    func jitterApplication() {
        // Use a fresh policy per call so we always check attempt-0 jitter
        for _ in 0..<20 {
            var policy = PTYReconnectPolicy(
                baseDelay: 1.0,
                maxDelay: 60.0,
                multiplier: 2.0,
                jitter: 0.3
            )
            let delay = policy.nextDelay()
            // For attempt 0, base is 1.0, so range is [0.7, 1.3]
            #expect(delay >= 0.7)
            #expect(delay <= 1.3)
        }
    }

    @Test("Policy handles zero jitter")
    func zeroJitter() {
        var policy = PTYReconnectPolicy(
            baseDelay: 2.0,
            maxDelay: 60.0,
            multiplier: 2.0,
            jitter: 0.0
        )

        let delay1 = policy.nextDelay()
        let delay2 = policy.nextDelay()

        // With zero jitter, delays should be exact
        #expect(delay1 == 2.0)
        #expect(delay2 == 4.0)
    }

    @Test("Policy validates parameters")
    func parameterValidation() {
        // Negative base delay should be clamped to 0
        let policy1 = PTYReconnectPolicy(baseDelay: -1.0)
        #expect(policy1.baseDelay == 0.0)

        // Max delay less than base should be clamped to base
        let policy2 = PTYReconnectPolicy(baseDelay: 5.0, maxDelay: 2.0)
        #expect(policy2.maxDelay == 5.0)

        // Multiplier less than 1 should be clamped to 1
        let policy3 = PTYReconnectPolicy(multiplier: 0.5)
        #expect(policy3.multiplier == 1.0)

        // Jitter less than 0 should be clamped to 0
        let policy4 = PTYReconnectPolicy(jitter: -0.5)
        #expect(policy4.jitter == 0.0)

        // Jitter greater than 1 should be clamped to 1
        let policy5 = PTYReconnectPolicy(jitter: 1.5)
        #expect(policy5.jitter == 1.0)
    }
}
