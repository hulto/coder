import Testing
import Foundation
@testable import CoderUI
import CoderAuth

@Suite("LoginViewModel Tests")
@MainActor
struct LoginViewModelTests {

    @Test("Initial state is correct")
    func initialState() {
        let authService = AuthService(
            webAuthSession: MockWebAuthSessionProvider(),
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        #expect(viewModel.serverURL == "")
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Empty server URL shows error")
    func emptyServerURL() async {
        let authService = AuthService(
            webAuthSession: MockWebAuthSessionProvider(),
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = ""
        await viewModel.login()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "Please enter a server URL.")
    }

    @Test("Whitespace-only server URL shows error")
    func whitespaceServerURL() async {
        let authService = AuthService(
            webAuthSession: MockWebAuthSessionProvider(),
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = "   "
        await viewModel.login()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "Please enter a server URL.")
    }

    @Test("Invalid URL format shows error")
    func invalidURLFormat() async {
        let authService = AuthService(
            webAuthSession: MockWebAuthSessionProvider(),
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = "http://[::1"
        await viewModel.login()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "The server URL is invalid.")
    }

    @Test("Authentication success clears loading state")
    func authenticationSuccess() async {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=test_token_12345678")!
        )
        let authService = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = "https://coder.example.com"
        await viewModel.login()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Authentication error shows user-friendly message")
    func authenticationError() async {
        let mockWebAuth = MockWebAuthSessionProvider(
            error: AuthError.cancelled
        )
        let authService = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = "https://coder.example.com"
        await viewModel.login()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "Authentication was cancelled by the user.")
    }

    @Test("Loading state transitions correctly")
    func loadingStateTransitions() async {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=test_token_12345678")!
        )
        let authService = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        #expect(viewModel.isLoading == false)

        viewModel.serverURL = "https://coder.example.com"
        await viewModel.login()

        #expect(viewModel.isLoading == false)
    }

    @Test("Error is cleared on new login attempt")
    func errorClearedOnNewAttempt() async {
        let mockWebAuth = MockWebAuthSessionProvider(
            error: AuthError.cancelled
        )
        let authService = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        // First attempt - error
        viewModel.serverURL = "https://coder.example.com"
        await viewModel.login()
        #expect(viewModel.errorMessage != nil)

        // Second attempt - clears error first, then gets same error
        await viewModel.login()
        #expect(viewModel.errorMessage == "Authentication was cancelled by the user.")
    }

    @Test("isAuthenticated is false on a freshly constructed view model")
    func isAuthenticatedInitiallyFalse() {
        let authService = AuthService(
            webAuthSession: MockWebAuthSessionProvider(),
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        #expect(viewModel.isAuthenticated == false)
    }

    @Test("isAuthenticated becomes true after a successful login")
    func isAuthenticatedTrueAfterSuccess() async {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=test_token_12345678")!
        )
        let authService = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = "https://coder.example.com"
        await viewModel.login()

        #expect(viewModel.isAuthenticated == true)
    }

    @Test("isAuthenticated stays false after a failed login")
    func isAuthenticatedFalseAfterFailure() async {
        let mockWebAuth = MockWebAuthSessionProvider(
            error: AuthError.cancelled
        )
        let authService = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = "https://coder.example.com"
        await viewModel.login()

        #expect(viewModel.isAuthenticated == false)
        #expect(viewModel.errorMessage == "Authentication was cancelled by the user.")
    }

    @Test("isAuthenticated stays false when the server URL is empty")
    func isAuthenticatedFalseForEmptyURL() async {
        let authService = AuthService(
            webAuthSession: MockWebAuthSessionProvider(),
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = ""
        await viewModel.login()

        #expect(viewModel.isAuthenticated == false)
    }

    @Test("isAuthenticated stays false when the server URL is invalid")
    func isAuthenticatedFalseForInvalidURL() async {
        let authService = AuthService(
            webAuthSession: MockWebAuthSessionProvider(),
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        viewModel.serverURL = "http://[::1"
        await viewModel.login()

        #expect(viewModel.isAuthenticated == false)
    }

    @Test("isAuthenticated resets to false after a subsequent failed login")
    func isAuthenticatedResetsAfterSuccessThenFailure() async {
        let mockWebAuth = MockWebAuthSessionProvider(
            callbackURL: URL(string: "coder://cli-auth?session_token=test_token_12345678")!
        )
        let authService = AuthService(
            webAuthSession: mockWebAuth,
            keychainStore: InMemoryKeychainStore()
        )
        let viewModel = LoginViewModel(authService: authService)

        // First attempt succeeds.
        viewModel.serverURL = "https://coder.example.com"
        await viewModel.login()
        #expect(viewModel.isAuthenticated == true)

        // Flip the mock to fail, then retry.
        mockWebAuth.configure(error: AuthError.cancelled)
        await viewModel.login()

        #expect(viewModel.isAuthenticated == false)
    }
}
