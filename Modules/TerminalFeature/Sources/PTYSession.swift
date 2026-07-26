import Foundation

/// Protocol defining a PTY session interface.
///
/// Conforming types provide a bidirectional terminal session with:
/// - Asynchronous output stream
/// - Input sending capability
/// - Terminal resize support
public protocol PTYSession: Sendable {
    /// Asynchronous stream of terminal output data.
    var output: AsyncStream<Data> { get }
    
    /// Sends input data to the terminal.
    ///
    /// - Parameter data: The data to send to the terminal.
    /// - Throws: Error if the data cannot be sent.
    func send(_ data: Data) async throws
    
    /// Resizes the terminal.
    ///
    /// - Parameters:
    ///   - cols: Number of columns.
    ///   - rows: Number of rows.
    /// - Throws: Error if the resize cannot be performed.
    func resize(cols: Int, rows: Int) async throws
}
