#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import SwiftTerm

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
    private let session: any PTYSession

    public init(session: any PTYSession) {
        self.session = session
        _viewModel = State(initialValue: TerminalViewModel(session: session))
    }

    public var body: some View {
        VStack(spacing: 0) {
            SwiftTermView(viewModel: viewModel)
                // frame(maxHeight: .infinity) tells VStack that this child is
                // flexible. VStack then measures the keyboard bar at its fixed
                // natural height first and proposes the remaining space to
                // SwiftTermView, so sizeThatFits receives the exact available
                // height instead of the full VStack height. Without this flag
                // VStack compresses SwiftTermView after the fact, leaving
                // bounds.height as a non-cellHeight multiple and breaking
                // Metal's floor(offsetY/cellH) row calculation.
                .frame(maxHeight: .infinity)
                .onAppear { viewModel.start() }
                .onDisappear { viewModel.stop() }
            KeyboardAccessoryBar(session: session)
        }
        .background {
            // Extend the terminal background behind the home indicator.
            Color.black.ignoresSafeArea()
        }
    }
}

/// UIViewRepresentable wrapper for SwiftTerm's TerminalView.
@available(iOS 17.0, *)
struct SwiftTermView: UIViewRepresentable {
    let viewModel: TerminalViewModel

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        // Prevent UIScrollView from automatically adding safe-area insets.
        // SwiftTerm's updateScroller() uses adjustedContentInset.bottom in its
        // maxContentOffsetY() clamp, while the Metal renderer does not include
        // that inset in its own maxOffset. A non-zero inset causes the scroller
        // to accept a larger contentOffset than Metal renders from, shifting the
        // visible window up and clipping the cursor row at the bottom.
        terminalView.contentInsetAdjustmentBehavior = .never
        terminalView.terminalDelegate = context.coordinator
        viewModel.attachTerminal(terminalView)
        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {}

    // Snap the proposed height to an exact rows * cellHeight multiple before
    // SwiftTerm's layoutSubviews runs. This guarantees that bounds.height is
    // always a multiple of cellHeight from the first layout pass onward, so
    // updateScroller() always lands contentOffset.y on a row boundary and
    // the Metal renderer's floor(offsetY / cellHeight) picks the correct first
    // row. Without this snap the initial bounds are fractional, updateScroller
    // clamps contentOffset below the true bottom, and the Metal renderer shows
    // one scrollback row at the top, pushing the cursor row off the bottom.
    //
    // cellHeight is derived by dividing getOptimalFrameSize().height (which
    // equals currentRows * cellHeight) by the current row count. Both values
    // are updated atomically by SwiftTerm, so the ratio is always correct.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SwiftTerm.TerminalView, context: Context) -> CGSize? {
        guard let proposedWidth = proposal.width,
              let proposedHeight = proposal.height,
              proposedHeight > 0 else { return nil }
        let optimalFrame = uiView.getOptimalFrameSize()
        guard optimalFrame.height > 1 else { return nil }
        let currentRows = CGFloat(max(1, context.coordinator.viewModel.rows))
        let cellHeight = optimalFrame.height / currentRows
        guard cellHeight > 1 else { return nil }
        let rows = max(1, Int(proposedHeight / cellHeight))
        return CGSize(width: proposedWidth, height: CGFloat(rows) * cellHeight)
    }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        let viewModel: TerminalViewModel

        init(viewModel: TerminalViewModel) { self.viewModel = viewModel }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            Task { @MainActor [viewModel] in
                viewModel.handleTerminalResize(cols: newCols, rows: newRows)
            }
        }

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            Task { @MainActor [viewModel] in
                viewModel.sendInput(Data(data))
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}
#endif
