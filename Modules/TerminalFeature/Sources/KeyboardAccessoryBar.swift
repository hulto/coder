#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// Keyboard accessory bar providing quick access to common terminal keys.
///
/// This view displays buttons for Escape, Control, Tab, and arrow keys
/// that are difficult or impossible to type on iPad keyboards.
///
/// The bar integrates with a ``PTYSession`` to send the appropriate
/// byte sequences when buttons are tapped.
@available(iOS 17.0, *)
@MainActor
public struct KeyboardAccessoryBar: View, Sendable {
    @State private var viewModel: KeyboardAccessoryViewModel

    public init(session: any PTYSession) {
        _viewModel = State(initialValue: KeyboardAccessoryViewModel(session: session))
    }

    public var body: some View {
        HStack(spacing: 8) {
            accessoryButton("Esc") {
                viewModel.sendEsc()
            }

            accessoryButton("Ctrl") {
                viewModel.toggleControlMode()
            }
            .background(
                viewModel.controlMode ? Color.accentColor.opacity(0.3) : Color.clear
            )
            .cornerRadius(8)

            accessoryButton("Tab") {
                viewModel.sendTab()
            }

            Spacer()

            arrowButton("arrow.up") {
                viewModel.sendUpArrow()
            }

            arrowButton("arrow.down") {
                viewModel.sendDownArrow()
            }

            arrowButton("arrow.left") {
                viewModel.sendLeftArrow()
            }

            arrowButton("arrow.right") {
                viewModel.sendRightArrow()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func accessoryButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .frame(minWidth: 44, minHeight: 32)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func arrowButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .frame(minWidth: 36, minHeight: 32)
        }
        .buttonStyle(.bordered)
    }
}
#endif
