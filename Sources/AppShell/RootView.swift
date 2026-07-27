import SwiftUI
import CoderAuth
import CoderUI
import WebAppFeature

/// The app's root view, responsible for resolving launch state once and
/// switching between the login screen and the primary web shell.
struct RootView: View {
    private enum LaunchState {
        case checking
        case signedOut
        case signedIn
    }

    private let authService: AuthService

    @State private var launchState: LaunchState = .checking
    @State private var loginViewModel: LoginViewModel
    @State private var signedInURL: URL?
    @State private var signedInToken: String = ""

    init(authService: AuthService) {
        self.authService = authService
        _loginViewModel = State(initialValue: LoginViewModel(authService: authService))
    }

    var body: some View {
        Group {
            switch launchState {
            case .checking:
                ProgressView()

            case .signedOut:
                LoginView(viewModel: loginViewModel)
                    .onChange(of: loginViewModel.isAuthenticated) { _, authenticated in
                        guard authenticated else { return }
                        if let url = URL(string: loginViewModel.serverURL) {
                            signedInURL = url
                            AppSettings.shared.baseURL = url.absoluteString
                            Task {
                                signedInToken = (try? await authService.getStoredToken()) ?? ""
                                launchState = .signedIn
                            }
                        }
                    }

            case .signedIn:
                if let url = signedInURL {
                    CoderWebView(url: url, token: signedInToken.isEmpty ? nil : signedInToken)
                } else {
                    // No URL was recoverable from the Keychain; require re-login.
                    ProgressView()
                        .task { launchState = .signedOut }
                }
            }
        }
        .task {
            guard case .checking = launchState else { return }
            guard await authService.hasStoredToken() else {
                launchState = .signedOut
                return
            }
            // Recover persisted URL and token so CoderWebView can resume the session.
            guard let url = await authService.getStoredServerURL() else {
                launchState = .signedOut
                return
            }
            signedInURL = url
            signedInToken = (try? await authService.getStoredToken()) ?? ""
            AppSettings.shared.baseURL = url.absoluteString
            launchState = .signedIn
        }
        .onReceive(NotificationCenter.default.publisher(for: .coderResetSession)) { _ in
            signedInURL = nil
            signedInToken = ""
            loginViewModel = LoginViewModel(authService: authService)
            launchState = .signedOut
        }
    }
}
