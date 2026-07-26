import Foundation

/// Protocol abstracting the web authentication session for testability.
///
/// On Apple platforms, this wraps `ASWebAuthenticationSession`.
/// A mock implementation is provided for testing on all platforms.
public protocol WebAuthSessionProviding: Sendable {
    /// Presents a web authentication session and returns the callback URL.
    ///
    /// - Parameters:
    ///   - url: The URL to present (the /cli-auth endpoint).
    ///   - callbackScheme: The custom URL scheme to intercept for the callback.
    /// - Returns: The callback URL received after successful authentication.
    /// - Throws: ``AuthError/cancelled`` if the user cancels the session.
    /// - Throws: ``AuthError/sessionError(_:)`` for other session failures.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// The URL scheme used for the Coder authentication callback.
public let coderCallbackScheme = "coder"

/// Constructs the /cli-auth URL for a given Coder server.
///
/// - Parameter serverURL: The base URL of the Coder deployment.
/// - Returns: The full /cli-auth URL.
/// - Throws: ``AuthError/invalidServerURL`` if the URL cannot be constructed.
public func makeCLIAuthURL(for serverURL: URL) throws -> URL {
    guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
        throw AuthError.invalidServerURL
    }
    // Append /cli-auth to the existing path
    let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
    components.path = basePath + "/cli-auth"
    components.queryItems = [URLQueryItem(name: "redirect_uri", value: "\(coderCallbackScheme)://cli-auth")]
    guard let url = components.url else {
        throw AuthError.invalidServerURL
    }
    return url
}

#if canImport(AuthenticationServices)
import AuthenticationServices

/// A web authentication session provider backed by `ASWebAuthenticationSession`.
///
/// This is the production implementation used on iOS/macOS.
@available(iOS 17.0, macOS 14.0, *)
public final class ASWebAuthSessionProvider: WebAuthSessionProviding, Sendable {
    public init() {}

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // ASWebAuthenticationSession is not Sendable, so we create and
            // start it on the main actor.
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { callbackURL, error in
                    if let error = error as? ASWebAuthenticationSessionError {
                        switch error.code {
                        case .canceledLogin:
                            continuation.resume(throwing: AuthError.cancelled)
                        default:
                            continuation.resume(throwing: AuthError.sessionError(error.localizedDescription))
                        }
                        return
                    }

                    if let error = error {
                        continuation.resume(throwing: AuthError.sessionError(error.localizedDescription))
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        continuation.resume(throwing: AuthError.invalidCallbackURL)
                        return
                    }

                    continuation.resume(returning: callbackURL)
                }

                session.prefersEphemeralWebBrowserSession = true
                session.start()
            }
        }
    }
}
#endif

/// Thread-safe mutable state for the mock web auth session provider.
private final class MockWebAuthState: @unchecked Sendable {
    private let lock = NSLock()
    private var _callbackURL: URL?
    private var _error: Error?
    private var _authenticateCallCount = 0
    private var _capturedURL: URL?
    private var _capturedScheme: String?

    init(callbackURL: URL?, error: Error?) {
        self._callbackURL = callbackURL
        self._error = error
    }

    /// Atomically increments the call count, captures inputs, and returns current config.
    func recordCall(url: URL, scheme: String) -> (error: Error?, callbackURL: URL?) {
        lock.lock(); defer { lock.unlock() }
        _authenticateCallCount += 1
        _capturedURL = url
        _capturedScheme = scheme
        return (_error, _callbackURL)
    }

    var authenticateCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _authenticateCallCount
    }

    var capturedURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return _capturedURL
    }

    var capturedScheme: String? {
        lock.lock(); defer { lock.unlock() }
        return _capturedScheme
    }

    func configure(callbackURL: URL?, error: Error?) {
        lock.lock(); defer { lock.unlock() }
        _callbackURL = callbackURL
        _error = error
    }
}

/// A mock web authentication session provider for testing.
public final class MockWebAuthSessionProvider: WebAuthSessionProviding, Sendable {
    private let state: MockWebAuthState

    /// The number of times `authenticate` was called.
    public var authenticateCallCount: Int {
        state.authenticateCallCount
    }

    /// The URL that was passed to the most recent `authenticate` call.
    public var capturedURL: URL? {
        state.capturedURL
    }

    /// The callback scheme that was passed to the most recent `authenticate` call.
    public var capturedScheme: String? {
        state.capturedScheme
    }

    /// Creates a new mock provider.
    /// - Parameters:
    ///   - callbackURL: The callback URL to return on success.
    ///   - error: The error to throw (takes precedence over callbackURL).
    public init(callbackURL: URL? = nil, error: Error? = nil) {
        self.state = MockWebAuthState(callbackURL: callbackURL, error: error)
    }

    public func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let (error, callbackURL) = state.recordCall(url: url, scheme: callbackScheme)

        if let error {
            throw error
        }

        guard let callbackURL else {
            throw AuthError.invalidCallbackURL
        }

        return callbackURL
    }

    /// Configures the mock's behavior for subsequent calls.
    public func configure(callbackURL: URL? = nil, error: Error? = nil) {
        state.configure(callbackURL: callbackURL, error: error)
    }
}
