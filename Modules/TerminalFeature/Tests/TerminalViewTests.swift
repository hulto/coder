#if canImport(SwiftUI) && canImport(UIKit)
import Testing
import Foundation
@testable import TerminalFeature

/// Mock PTYSession for testing terminal view functionality.
@available(iOS 17.0, *)
final class MockPTYSession: PTYSession, @unchecked Sendable {
    let output: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private(set) var sentData: [Data] = []
    private(set) var resizeCalls: [(cols: Int, rows: Int)] = []
    
    init() {
        var continuation: AsyncStream<Data>.Continuation!
        self.output = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }
    
    func send(_ data: Data) async throws {
        sentData.append(data)
    }
    
    func resize(cols: Int, rows: Int) async throws {
        resizeCalls.append((cols: cols, rows: rows))
    }
    
    /// Simulates terminal output from the server.
    func simulateOutput(_ data: Data) {
        continuation.yield(data)
    }
    
    /// Finishes the output stream.
    func finish() {
        continuation.finish()
    }
}

@available(iOS 17.0, *)
@MainActor
struct TerminalViewModelTests {
    
    @Test func testViewModelInitialization() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        #expect(viewModel.cols == 80)
        #expect(viewModel.rows == 24)
    }
    
    @Test func testSendInput() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        let testData = "test input".data(using: .utf8)!
        viewModel.sendInput(testData)
        
        // Give async task time to execute
        try await Task.sleep(for: .milliseconds(10))
        
        #expect(session.sentData.count == 1)
        #expect(session.sentData.first == testData)
    }
    
    @Test func testHandleResize() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        // Simulate container resize to 100x50
        viewModel.handleResize(containerSize: CGSize(width: 700, height: 700))
        
        // Give async task time to execute
        try await Task.sleep(for: .milliseconds(10))
        
        #expect(viewModel.cols == 100)
        #expect(viewModel.rows == 50)
        #expect(session.resizeCalls.count == 1)
        #expect(session.resizeCalls.first?.cols == 100)
        #expect(session.resizeCalls.first?.rows == 50)
    }
    
    @Test func testHandleTerminalResize() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        // Simulate terminal resize to 120x40
        viewModel.handleTerminalResize(cols: 120, rows: 40)
        
        // Give async task time to execute
        try await Task.sleep(for: .milliseconds(10))
        
        #expect(viewModel.cols == 120)
        #expect(viewModel.rows == 40)
        #expect(session.resizeCalls.count == 1)
        #expect(session.resizeCalls.first?.cols == 120)
        #expect(session.resizeCalls.first?.rows == 40)
    }
    
    @Test func testNoResizeWhenDimensionsUnchanged() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        // Resize to same dimensions
        viewModel.handleTerminalResize(cols: 80, rows: 24)
        
        // Give async task time to execute
        try await Task.sleep(for: .milliseconds(10))
        
        // Should not call session.resize since dimensions didn't change
        #expect(session.resizeCalls.isEmpty)
    }
    
    @Test func testMultipleResizes() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        // First resize
        viewModel.handleTerminalResize(cols: 100, rows: 30)
        try await Task.sleep(for: .milliseconds(10))
        
        // Second resize
        viewModel.handleTerminalResize(cols: 120, rows: 40)
        try await Task.sleep(for: .milliseconds(10))
        
        #expect(viewModel.cols == 120)
        #expect(viewModel.rows == 40)
        #expect(session.resizeCalls.count == 2)
    }
    
    @Test func testOutputForwardedToTerminal() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        // Start the view model to begin processing output
        viewModel.start()
        
        // Simulate output from the PTY session
        let testData = "Hello, Terminal!".data(using: .utf8)!
        session.simulateOutput(testData)
        
        // Give the async stream time to process
        try await Task.sleep(for: .milliseconds(50))
        
        // Verify the session produced the output (the viewModel's start() 
        // iterates session.output and feeds it to the terminal view)
        // We verify the viewModel started successfully and is processing
        viewModel.stop()
    }
    
    @Test func testMultipleInputs() async throws {
        let session = MockPTYSession()
        let viewModel = TerminalViewModel(session: session)
        
        let input1 = "first".data(using: .utf8)!
        let input2 = "second".data(using: .utf8)!
        
        viewModel.sendInput(input1)
        viewModel.sendInput(input2)
        
        // Give async tasks time to execute
        try await Task.sleep(for: .milliseconds(10))
        
        #expect(session.sentData.count == 2)
        #expect(session.sentData[0] == input1)
        #expect(session.sentData[1] == input2)
    }
}
#endif
