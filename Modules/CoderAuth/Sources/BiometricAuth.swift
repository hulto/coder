import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Protocol abstracting biometric authentication for testability.
public protocol BiometricAuthenticating: Sendable {
    /// Evaluates whether biometric authentication is available on this device.
    /// - Returns: `true` if biometric authentication (Face ID or Touch ID) is available.
    func isAvailable() -> Bool

    /// Authenticates the user using biometrics.
    /// - Parameter reason: The reason displayed to the user for authentication.
    /// - Throws: ``AuthError/biometricNotAvailable`` if biometrics are not available.
    /// - Throws: ``AuthError/biometricFailed`` if authentication fails or is cancelled.
    func authenticate(reason: String) async throws
}

/// Biometric authentication using LocalAuthentication framework.
///
/// This class provides Face ID and Touch ID authentication on supported devices.
/// On non-Apple platforms, it always reports biometrics as unavailable.
public final class BiometricAuthenticator: BiometricAuthenticating, Sendable {
    public init() {}

    public func isAvailable() -> Bool {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        #else
        return false
        #endif
    }

    public func authenticate(reason: String) async throws {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AuthError.biometricNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if !success {
                throw AuthError.biometricFailed
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.biometricFailed
        }
        #else
        throw AuthError.biometricNotAvailable
        #endif
    }
}

/// Thread-safe mutable state for the mock biometric authenticator.
private final class MockBiometricState: @unchecked Sendable {
    private let lock = NSLock()
    private var _available: Bool
    private var _shouldSucceed: Bool
    private var _authenticateCallCount = 0

    init(available: Bool, shouldSucceed: Bool) {
        self._available = available
        self._shouldSucceed = shouldSucceed
    }

    var available: Bool {
        lock.lock(); defer { lock.unlock() }
        return _available
    }

    var shouldSucceed: Bool {
        lock.lock(); defer { lock.unlock() }
        return _shouldSucceed
    }

    @discardableResult
    func incrementCallCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        _authenticateCallCount += 1
        return _authenticateCallCount
    }

    var authenticateCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _authenticateCallCount
    }

    func configure(available: Bool? = nil, shouldSucceed: Bool? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let available { _available = available }
        if let shouldSucceed { _shouldSucceed = shouldSucceed }
    }
}

/// A mock biometric authenticator for testing.
public final class MockBiometricAuthenticator: BiometricAuthenticating, Sendable {
    private let state: MockBiometricState

    /// The number of times `authenticate` was called.
    public var authenticateCallCount: Int {
        state.authenticateCallCount
    }

    /// Creates a new mock authenticator.
    /// - Parameters:
    ///   - available: Whether biometrics appear available. Defaults to `true`.
    ///   - shouldSucceed: Whether authentication should succeed. Defaults to `true`.
    public init(available: Bool = true, shouldSucceed: Bool = true) {
        self.state = MockBiometricState(available: available, shouldSucceed: shouldSucceed)
    }

    public func isAvailable() -> Bool {
        state.available
    }

    public func authenticate(reason: String) async throws {
        _ = state.incrementCallCount()

        guard state.available else {
            throw AuthError.biometricNotAvailable
        }

        guard state.shouldSucceed else {
            throw AuthError.biometricFailed
        }
    }

    /// Updates the mock's behavior.
    public func configure(available: Bool? = nil, shouldSucceed: Bool? = nil) {
        state.configure(available: available, shouldSucceed: shouldSucceed)
    }
}
