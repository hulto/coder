import Foundation

/// Manages the Coder authentication flow using /cli-auth endpoint.
///
/// This service orchestrates the complete authentication lifecycle:
/// 1. Opens a web authentication session to the /cli-auth endpoint
/// 2. Extracts the session token from the callback URL
/// 3. Validates the token format
/// 4. Stores the token securely in the keychain
/// 5. Optionally gates token retrieval with biometric authentication
///
/// - Important: This service is designed for single-account use. Multi-account
///   support is out of scope for this task.
public actor AuthService {
    private let webAuthSession: WebAuthSessionProviding
    private let keychainStore: KeychainStoring
    private let biometricAuth: BiometricAuthenticating
    private let enableBiometrics: Bool

    #if canImport(Security) && canImport(AuthenticationServices)
    /// Creates a new authentication service with platform-default dependencies.
    ///
    /// On Apple platforms, this uses `ASWebAuthSessionProvider` and `SystemKeychainStore`.
    ///
    /// - Parameters:
    ///   - webAuthSession: The web authentication session provider.
    ///   - keychainStore: The keychain store for token persistence.
    ///   - biometricAuth: The biometric authenticator.
    ///   - enableBiometrics: Whether to require biometric authentication for token retrieval.
    @available(iOS 17.0, macOS 14.0, *)
    public init(
        webAuthSession: WebAuthSessionProviding = ASWebAuthSessionProvider(),
        keychainStore: KeychainStoring = SystemKeychainStore(),
        biometricAuth: BiometricAuthenticating = BiometricAuthenticator(),
        enableBiometrics: Bool = false
    ) {
        self.webAuthSession = webAuthSession
        self.keychainStore = keychainStore
        self.biometricAuth = biometricAuth
        self.enableBiometrics = enableBiometrics
    }
    #else
    /// Creates a new authentication service with injected dependencies.
    ///
    /// On non-Apple platforms, all dependencies must be provided explicitly.
    ///
    /// - Parameters:
    ///   - webAuthSession: The web authentication session provider.
    ///   - keychainStore: The keychain store for token persistence.
    ///   - biometricAuth: The biometric authenticator.
    ///   - enableBiometrics: Whether to require biometric authentication for token retrieval.
    public init(
        webAuthSession: WebAuthSessionProviding,
        keychainStore: KeychainStoring,
        biometricAuth: BiometricAuthenticating = BiometricAuthenticator(),
        enableBiometrics: Bool = false
    ) {
        self.webAuthSession = webAuthSession
        self.keychainStore = keychainStore
        self.biometricAuth = biometricAuth
        self.enableBiometrics = enableBiometrics
    }
    #endif

    /// Authenticates the user via the /cli-auth endpoint and stores the session token.
    ///
    /// This method:
    /// 1. Constructs the /cli-auth URL for the given server
    /// 2. Presents a web authentication session
    /// 3. Extracts the session token from the callback URL
    /// 4. Validates the token format
    /// 5. Stores the token in the keychain
    ///
    /// - Parameter serverURL: The base URL of the Coder deployment.
    /// - Returns: The authenticated session token.
    /// - Throws: ``AuthError`` if any step fails.
    public func authenticate(serverURL: URL) async throws -> String {
        // Construct the /cli-auth URL
        let authURL = try makeCLIAuthURL(for: serverURL)

        // Present web authentication session
        let callbackURL = try await webAuthSession.authenticate(
            url: authURL,
            callbackScheme: coderCallbackScheme
        )

        // Extract token from callback URL
        let rawToken = try extractToken(from: callbackURL)

        // Trim whitespace before validation and storage
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate token format
        try validateToken(token)

        // Store token in keychain
        let tokenData = Data(token.utf8)
        try keychainStore.store(data: tokenData, forKey: KeychainKeys.sessionToken)

        return token
    }

    /// Retrieves the stored session token, optionally requiring biometric authentication.
    ///
    /// When biometrics are enabled, the user must authenticate via Face ID or Touch ID
    /// before the token is returned.
    ///
    /// - Returns: The stored session token.
    /// - Throws: ``AuthError/noStoredToken`` if no token is stored.
    /// - Throws: ``AuthError/biometricFailed`` if biometric authentication fails.
    /// - Throws: ``AuthError/biometricNotAvailable`` if biometrics are unavailable.
    /// - Throws: ``AuthError/keychainError(statusCode:)`` if keychain access fails.
    public func getStoredToken() async throws -> String {
        // Require biometric authentication if enabled
        if enableBiometrics {
            guard biometricAuth.isAvailable() else {
                throw AuthError.biometricNotAvailable
            }
            try await biometricAuth.authenticate(reason: "Access your Coder session")
        }

        // Retrieve token from keychain
        guard let tokenData = try keychainStore.retrieve(forKey: KeychainKeys.sessionToken) else {
            throw AuthError.noStoredToken
        }

        guard let token = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.invalidTokenFormat
        }

        return token
    }

    /// Clears the stored session token from the keychain.
    ///
    /// - Throws: ``AuthError/keychainError(statusCode:)`` if the deletion fails.
    public func signOut() async throws {
        try keychainStore.delete(forKey: KeychainKeys.sessionToken)
    }

    /// Checks whether a session token is currently stored.
    ///
    /// - Returns: `true` if a token exists in the keychain.
    public func hasStoredToken() async -> Bool {
        do {
            return try keychainStore.retrieve(forKey: KeychainKeys.sessionToken) != nil
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    /// Extracts the session token from the authentication callback URL.
    ///
    /// The callback URL is expected to contain a `session_token` query parameter.
    nonisolated private func extractToken(from callbackURL: URL) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw AuthError.invalidCallbackURL
        }

        guard let tokenItem = components.queryItems?.first(where: { $0.name == "session_token" }),
              let token = tokenItem.value, !token.isEmpty else {
            throw AuthError.invalidCallbackURL
        }

        return token
    }

    /// Validates the session token format before storage.
    ///
    /// Rejects empty tokens and tokens shorter than 8 characters.
    /// The caller is responsible for trimming whitespace before calling this method.
    nonisolated private func validateToken(_ token: String) throws {
        guard !token.isEmpty, token.count >= 8 else {
            throw AuthError.invalidTokenFormat
        }
    }
}
