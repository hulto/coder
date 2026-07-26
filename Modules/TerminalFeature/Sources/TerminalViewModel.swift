#if canImport(SwiftUI) && canImport(UIKit)
import Foundation
import SwiftTerm
import Observation
import os.log

/// View model that manages the terminal session lifecycle and coordinates between
/// SwiftUI and SwiftTerm.
///
/// This class:
/// - Manages the PTYSession lifecycle
/// - Handles terminal dimensions and resize events
/// - Coordinates input/output between SwiftUI and SwiftTerm
@available(iOS 17.0, *)
@Observable
@MainActor
final class TerminalViewModel {
    private let session: any PTYSession
    private weak var terminalView: SwiftTerm.TerminalView?
    private var outputTask: Task<Void, Never>?
    private var isRunning = false
    
    /// Current terminal dimensions in characters
    private(set) var cols: Int = 80
    private(set) var rows: Int = 24
    
    init(session: any PTYSession) {
        self.session = session
    }
    
    /// Attaches a SwiftTerm TerminalView to this view model.
    func attachTerminal(_ terminalView: SwiftTerm.TerminalView) {
        self.terminalView = terminalView
    }
    
    /// Starts the terminal session and begins processing output.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        outputTask = Task { [weak self] in
            guard let self = self else { return }
            
            for await data in self.session.output {
                await MainActor.run {
                    self.terminalView?.feed(data: data)
                }
            }
        }
    }
    
    /// Stops the terminal session and cleans up resources.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        
        outputTask?.cancel()
        outputTask = nil
        terminalView = nil
    }
    
    /// Sends input data to the terminal session.
    func sendInput(_ data: Data) {
        Task {
            do {
                try await session.send(data)
            } catch {
                os_log(.error, "Failed to send data: %{public}@", error.localizedDescription)
            }
        }
    }
    
    /// Handles container size changes and updates terminal dimensions.
    func handleResize(containerSize: CGSize) {
        // Estimate character dimensions based on container size
        // Typical terminal character is ~7x14 pixels
        let charWidth = 7.0
        let charHeight = 14.0
        
        let newCols = max(1, Int(containerSize.width / charWidth))
        let newRows = max(1, Int(containerSize.height / charHeight))
        
        guard newCols != cols || newRows != rows else { return }
        
        cols = newCols
        rows = newRows
        
        Task {
            do {
                try await session.resize(cols: cols, rows: rows)
            } catch {
                os_log(.error, "Failed to resize session: %{public}@", error.localizedDescription)
            }
        }
    }
    
    /// Handles terminal resize events from SwiftTerm.
    func handleTerminalResize(cols: Int, rows: Int) {
        guard cols != self.cols || rows != self.rows else { return }
        
        self.cols = cols
        self.rows = rows
        
        Task {
            do {
                try await session.resize(cols: cols, rows: rows)
            } catch {
                os_log(.error, "Failed to resize terminal: %{public}@", error.localizedDescription)
            }
        }
    }
}
#endif
