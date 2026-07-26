import Testing
import Foundation
@testable import CoderAuth

// MARK: - AuthService Tests

@Suite("AuthService Tests")
struct AuthServiceTests {
    private let testServerURL = URL(string: "https://coder.example.com")!

    @Test("authenticate succeeds with valid callback")
    func authenticateSuccess() async throws {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=valid-token-12345678")!
        )
        let mockKeychain = InMemoryKeychainStore()
        let mockBiometric = MockBiometricAuthenticator()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain,
            biometricAuth: mockBiometric
        )

        let token = try await service.authenticate(serverURL: testServerURL)

        #expect(token == "valid-token-12345678")
        #expect(mockWebAuth.authenticateCallCount == 1)
        #expect(mockKeychain.count == 1)
    }

    @Test("authenticate constructs correct auth URL")
    func authenticateURLConstruction() async throws {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=valid-token-12345678")!
        )
        let mockKeychain = InMemoryKeychainStore()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        _ = try await service.authenticate(serverURL: testServerURL)

        let capturedURL = try #require(mockWebAuth.capturedURL)
        #expect(capturedURL.absoluteString.contains("/cli-auth"))
        #expect(capturedURL.absoluteString.contains("redirect_uri=coder://cli-auth"))
        #expect(mockWebAuth.capturedScheme == "coder")
    }

    @Test("authenticate handles user cancellation")
    func authenticateCancellation() async throws {
        let mockWebAuth = MockWebAuthSessionProvider(error: AuthError.cancelled)
        let mockKeychain = InMemoryKeychainStore()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        await #expect(throws: AuthError.cancelled) {
            try await service.authenticate(serverURL: testServerURL)
        }

        #expect(mockKeychain.count == 0)
    }

    @Test("authenticate rejects callback without token")
    func authenticateInvalidCallback() async throws {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth")!
        )
        let mockKeychain = InMemoryKeychainStore()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        await #expect(throws: AuthError.invalidCallbackURL) {
            try await service.authenticate(serverURL: testServerURL)
        }
    }

    @Test("authenticate rejects empty token")
    func authenticateEmptyToken() async throws {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=")!
        )
        let mockKeychain = InMemoryKeychainStore()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        await #expect(throws: AuthError.invalidCallbackURL) {
            try await service.authenticate(serverURL: testServerURL)
        }
    }

    @Test("authenticate rejects short token")
    func authenticateShortToken() async throws {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=short")!
        )
        let mockKeychain = InMemoryKeychainStore()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        await #expect(throws: AuthError.invalidTokenFormat) {
            try await service.authenticate(serverURL: testServerURL)
        }
    }

    @Test("getStoredToken retrieves stored token")
    func getStoredTokenSuccess() async throws {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()
        let mockBiometric = MockBiometricAuthenticator()

        // Store a token first
        let tokenData = Data("valid-token-12345678".utf8)
        try mockKeychain.store(data: tokenData, forKey: KeychainKeys.sessionToken)

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain,
            biometricAuth: mockBiometric
        )

        let retrievedToken = try await service.getStoredToken()
        #expect(retrievedToken == "valid-token-12345678")
    }

    @Test("getStoredToken throws when no token exists")
    func getStoredTokenNoToken() async throws {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        await #expect(throws: AuthError.noStoredToken) {
            try await service.getStoredToken()
        }
    }

    @Test("getStoredToken requires biometrics when enabled")
    func getStoredTokenWithBiometrics() async throws {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()
        let mockBiometric = MockBiometricAuthenticator(available: true, shouldSucceed: true)

        let tokenData = Data("valid-token-12345678".utf8)
        try mockKeychain.store(data: tokenData, forKey: KeychainKeys.sessionToken)

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain,
            biometricAuth: mockBiometric,
            enableBiometrics: true
        )

        let token = try await service.getStoredToken()
        #expect(token == "valid-token-12345678")
        #expect(mockBiometric.authenticateCallCount == 1)
    }

    @Test("getStoredToken fails when biometrics unavailable")
    func getStoredTokenBiometricsUnavailable() async throws {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()
        let mockBiometric = MockBiometricAuthenticator(available: false)

        let tokenData = Data("valid-token-12345678".utf8)
        try mockKeychain.store(data: tokenData, forKey: KeychainKeys.sessionToken)

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain,
            biometricAuth: mockBiometric,
            enableBiometrics: true
        )

        await #expect(throws: AuthError.biometricNotAvailable) {
            try await service.getStoredToken()
        }
    }

    @Test("getStoredToken fails when biometric auth fails")
    func getStoredTokenBiometricFailed() async throws {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()
        let mockBiometric = MockBiometricAuthenticator(available: true, shouldSucceed: false)

        let tokenData = Data("valid-token-12345678".utf8)
        try mockKeychain.store(data: tokenData, forKey: KeychainKeys.sessionToken)

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain,
            biometricAuth: mockBiometric,
            enableBiometrics: true
        )

        await #expect(throws: AuthError.biometricFailed) {
            try await service.getStoredToken()
        }
    }

    @Test("signOut removes stored token")
    func signOut() async throws {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()

        let tokenData = Data("valid-token-12345678".utf8)
        try mockKeychain.store(data: tokenData, forKey: KeychainKeys.sessionToken)

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        try await service.signOut()
        #expect(mockKeychain.count == 0)
    }

    @Test("hasStoredToken returns true when token exists")
    func hasStoredTokenTrue() async throws {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()

        let tokenData = Data("valid-token-12345678".utf8)
        try mockKeychain.store(data: tokenData, forKey: KeychainKeys.sessionToken)

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        let hasToken = await service.hasStoredToken()
        #expect(hasToken == true)
    }

    @Test("hasStoredToken returns false when no token exists")
    func hasStoredTokenFalse() async {
        let mockWebAuth = MockWebAuthSessionProvider()
        let mockKeychain = InMemoryKeychainStore()

        let service = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: mockKeychain
        )

        let hasToken = await service.hasStoredToken()
        #expect(hasToken == false)
    }
}
