import Foundation

/// Pure utility for generating terminal key sequences.
///
/// Provides static methods for generating ANSI escape sequences and
/// control characters for common terminal keys that are difficult to
/// type on iPad keyboards.
enum TerminalKeySequences: Sendable {
    /// Escape byte (0x1B).
    static func escapeSequence() -> Data {
        Data([0x1B])
    }

    /// Tab character (0x09).
    static func tabSequence() -> Data {
        Data([0x09])
    }

    /// ANSI cursor up arrow sequence (ESC[A).
    static func upArrowSequence() -> Data {
        Data([0x1B, 0x5B, 0x41])
    }

    /// ANSI cursor down arrow sequence (ESC[B).
    static func downArrowSequence() -> Data {
        Data([0x1B, 0x5B, 0x42])
    }

    /// ANSI cursor right arrow sequence (ESC[C).
    static func rightArrowSequence() -> Data {
        Data([0x1B, 0x5B, 0x43])
    }

    /// ANSI cursor left arrow sequence (ESC[D).
    static func leftArrowSequence() -> Data {
        Data([0x1B, 0x5B, 0x44])
    }

    /// Control character for a given letter (A-Z → 0x01–0x1A).
    ///
    /// Returns `nil` for non-letter characters.
    static func controlCharacter(for letter: Character) -> Data? {
        let upper = letter.uppercased()
        guard upper.count == 1,
            let scalar = upper.unicodeScalars.first,
            scalar.value >= 0x41,  // "A"
            scalar.value <= 0x5A  // "Z"
        else {
            return nil
        }
        return Data([UInt8(scalar.value - 0x40)])
    }
}

#if canImport(Observation)
import Observation

/// View model managing keyboard accessory bar state and key sequence delivery.
///
/// Tracks control-mode toggle and sends the appropriate byte sequences
/// to the underlying ``PTYSession`` when accessory-bar buttons are tapped.
@Observable
@MainActor
final class KeyboardAccessoryViewModel {
    /// Whether control mode is active.
    ///
    /// When `true`, the next letter key tap sends the corresponding
    /// control character (e.g. C → 0x03 for Ctrl-C) and deactivates
    /// control mode.
    private(set) var controlMode = false

    private let session: any PTYSession

    init(session: any PTYSession) {
        self.session = session
    }

    /// Sends the Escape byte (0x1B) to the session.
    func sendEsc() {
        let data = TerminalKeySequences.escapeSequence()
        Task { try? await session.send(data) }
    }

    /// Toggles control mode on or off.
    func toggleControlMode() {
        controlMode.toggle()
    }

    /// Sends the Tab character (0x09) to the session.
    func sendTab() {
        let data = TerminalKeySequences.tabSequence()
        Task { try? await session.send(data) }
    }

    /// Sends the up-arrow ANSI sequence (ESC[A).
    func sendUpArrow() {
        let data = TerminalKeySequences.upArrowSequence()
        Task { try? await session.send(data) }
    }

    /// Sends the down-arrow ANSI sequence (ESC[B).
    func sendDownArrow() {
        let data = TerminalKeySequences.downArrowSequence()
        Task { try? await session.send(data) }
    }

    /// Sends the right-arrow ANSI sequence (ESC[C).
    func sendRightArrow() {
        let data = TerminalKeySequences.rightArrowSequence()
        Task { try? await session.send(data) }
    }

    /// Sends the left-arrow ANSI sequence (ESC[D).
    func sendLeftArrow() {
        let data = TerminalKeySequences.leftArrowSequence()
        Task { try? await session.send(data) }
    }

    /// Sends a key, dispatching to the control-character path when
    /// control mode is active, or the normal path otherwise.
    func sendKey(_ character: Character) {
        if controlMode {
            controlMode = false
            guard let data = TerminalKeySequences.controlCharacter(for: character) else {
                return
            }
            Task { try? await session.send(data) }
        }
    }

    /// Sends a control character for the given letter directly.
    func sendControlSequence(for letter: Character) {
        controlMode = false
        guard let data = TerminalKeySequences.controlCharacter(for: letter) else {
            return
        }
        Task { try? await session.send(data) }
    }
}
#endif
