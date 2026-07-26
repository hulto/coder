#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import SwiftTerm
import Combine

/// SwiftUI view that wraps SwiftTerm's TerminalView and connects to a PTYSession.
///
/// This view provides a terminal interface that:
/// - Displays output from the PTYSession
/// - Captures keyboard input and sends it to the session
/// - Handles terminal resize events
/// - Manages the session lifecycle
@available(iOS 17.0, *)
@MainActor
public struct TerminalView: View, Sendable {
    @State private var viewModel: TerminalViewModel
    
    public init(session: any PTYSession) {
        _viewModel = State(initialValue: TerminalViewModel(session: session))
    }
    
    public var body: some View {
        GeometryReader { geometry in
            SwiftTermView(viewModel: viewModel)
                .onAppear {
                    viewModel.start()
                }
                .onDisappear {
                    viewModel.stop()
                }
                .onChange(of: geometry.size) { oldSize, newSize in
                    viewModel.handleResize(containerSize: newSize)
                }
        }
    }
}

/// UIViewRepresentable wrapper for SwiftTerm's TerminalView.
@available(iOS 17.0, *)
struct SwiftTermView: UIViewRepresentable {
    let viewModel: TerminalViewModel
    
    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.delegate = context.coordinator
        viewModel.attachTerminal(terminalView)
        return terminalView
    }
    
    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // No updates needed - terminal manages its own state
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let viewModel: TerminalViewModel
        
        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }
        
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            viewModel.handleTerminalResize(cols: newCols, rows: newRows)
        }
        
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            viewModel.sendInput(Data(data))
        }
        
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {
            // No-op: scroll tracking not needed
        }
        
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // No-op: title updates not propagated to SwiftUI
        }
        
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // No-op: directory tracking not needed
        }
        
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, modifiers: Int) {
            // No-op: link opening not implemented
        }
    }
}
#endif
