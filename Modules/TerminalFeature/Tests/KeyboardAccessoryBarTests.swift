import Testing
import Foundation
@testable import TerminalFeature

// MARK: - Mock PTYSession

final class MockSession: PTYSession, @unchecked Sendable {
    let output: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    var sentData: [Data] = []
    var resizeCalls: [(cols: Int, rows: Int)] = []

    init() {
        var cont: AsyncStream<Data>.Continuation!
        output = AsyncStream { cont = $0 }
        continuation = cont
    }

    func send(_ data: Data) async throws {
        sentData.append(data)
    }

    func resize(cols: Int, rows: Int) async throws {
        resizeCalls.append((cols: cols, rows: rows))
    }
}

// MARK: - TerminalKeySequences Tests

@Suite("TerminalKeySequences Tests")
struct TerminalKeySequencesTests {
    @Test("Escape sequence is 0x1B")
    func escapeSequence() {
        let data = TerminalKeySequences.escapeSequence()
        #expect(data == Data([0x1B]))
    }

    @Test("Tab sequence is 0x09")
    func tabSequence() {
        let data = TerminalKeySequences.tabSequence()
        #expect(data == Data([0x09]))
    }

    @Test("Up arrow is ESC[A")
    func upArrow() {
        let data = TerminalKeySequences.upArrowSequence()
        #expect(data == Data([0x1B, 0x5B, 0x41]))
    }

    @Test("Down arrow is ESC[B")
    func downArrow() {
        let data = TerminalKeySequences.downArrowSequence()
        #expect(data == Data([0x1B, 0x5B, 0x42]))
    }

    @Test("Right arrow is ESC[C")
    func rightArrow() {
        let data = TerminalKeySequences.rightArrowSequence()
        #expect(data == Data([0x1B, 0x5B, 0x43]))
    }

    @Test("Left arrow is ESC[D")
    func leftArrow() {
        let data = TerminalKeySequences.leftArrowSequence()
        #expect(data == Data([0x1B, 0x5B, 0x44]))
    }

    @Test("Control character for A is 0x01")
    func controlA() {
        let data = TerminalKeySequences.controlCharacter(for: "A")
        #expect(data == Data([0x01]))
    }

    @Test("Control character for C is 0x03")
    func controlC() {
        let data = TerminalKeySequences.controlCharacter(for: "C")
        #expect(data == Data([0x03]))
    }

    @Test("Control character for Z is 0x1A")
    func controlZ() {
        let data = TerminalKeySequences.controlCharacter(for: "Z")
        #expect(data == Data([0x1A]))
    }

    @Test("Control character is case-insensitive")
    func controlCaseInsensitive() {
        let lower = TerminalKeySequences.controlCharacter(for: "c")
        let upper = TerminalKeySequences.controlCharacter(for: "C")
        #expect(lower == upper)
    }

    @Test("Control character returns nil for non-letters")
    func controlNonLetter() {
        #expect(TerminalKeySequences.controlCharacter(for: "1") == nil)
        #expect(TerminalKeySequences.controlCharacter(for: " ") == nil)
    }
}

// MARK: - KeyboardAccessoryViewModel Tests

#if canImport(Observation)
@Suite("KeyboardAccessoryViewModel Tests")
@MainActor
struct KeyboardAccessoryViewModelTests {
    @Test("Initializes with control mode off")
    func initialState() {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        #expect(vm.controlMode == false)
    }

    @Test("sendEsc sends 0x1B")
    func sendEsc() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendEsc()
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x1B]))
    }

    @Test("sendTab sends 0x09")
    func sendTab() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendTab()
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x09]))
    }

    @Test("sendUpArrow sends ESC[A")
    func sendUpArrow() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendUpArrow()
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x1B, 0x5B, 0x41]))
    }

    @Test("sendDownArrow sends ESC[B")
    func sendDownArrow() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendDownArrow()
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x1B, 0x5B, 0x42]))
    }

    @Test("sendRightArrow sends ESC[C")
    func sendRightArrow() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendRightArrow()
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x1B, 0x5B, 0x43]))
    }

    @Test("sendLeftArrow sends ESC[D")
    func sendLeftArrow() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendLeftArrow()
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x1B, 0x5B, 0x44]))
    }

    @Test("toggleControlMode toggles on and off")
    func toggleControlMode() {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        #expect(vm.controlMode == false)
        vm.toggleControlMode()
        #expect(vm.controlMode == true)
        vm.toggleControlMode()
        #expect(vm.controlMode == false)
    }

    @Test("sendControlSequence sends Ctrl+C (0x03)")
    func sendControlC() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendControlSequence(for: "C")
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x03]))
    }

    @Test("sendControlSequence deactivates control mode")
    func sendControlDeactivatesMode() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.toggleControlMode()
        #expect(vm.controlMode == true)
        vm.sendControlSequence(for: "C")
        #expect(vm.controlMode == false)
    }

    @Test("sendKey in control mode sends control char and deactivates mode")
    func sendKeyInControlMode() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.toggleControlMode()
        vm.sendKey("C")
        try await Task.sleep(for: .milliseconds(10))
        #expect(vm.controlMode == false)
        #expect(session.sentData.count == 1)
        #expect(session.sentData[0] == Data([0x03]))
    }

    @Test("sendKey outside control mode does nothing")
    func sendKeyOutsideControlMode() async throws {
        let session = MockSession()
        let vm = KeyboardAccessoryViewModel(session: session)
        vm.sendKey("C")
        try await Task.sleep(for: .milliseconds(10))
        #expect(session.sentData.isEmpty)
        #expect(vm.controlMode == false)
    }
}
#endif
