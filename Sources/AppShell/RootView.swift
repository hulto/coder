import SwiftUI
import CoderAuth
import CoderUI

/// The app's root view, responsible for resolving launch state once and
/// switching between the login screen and the signed-in placeholder.
struct RootView: View {
    private enum LaunchState {
        case checking
        case signedOut
        case signedIn
    }

    private let authService: AuthService

    @State private var launchState: LaunchState = .checking
    @State private var loginViewModel: LoginViewModel

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
                        if authenticated {
                            launchState = .signedIn
                        }
                    }
            case .signedIn:
                SignedInPlaceholderView(serverURL: loginViewModel.serverURL)
            }
        }
        .task {
            // Resolve the launch state exactly once by checking the Keychain
            // for an existing session token.
            guard launchState == .checking else { return }
            let hasToken = await authService.hasStoredToken()
            launchState = hasToken ? .signedIn : .signedOut
        }
    }
}

/// A minimal placeholder shown after a successful sign-in.
///
/// There is no workspace list or detail UI yet, so this screen exists solely
/// to confirm the app navigated past login. It never displays the session
/// token, only the non-secret server URL the user entered.
struct SignedInPlaceholderView: View {
    let serverURL: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Signed in")
                .font(.title)
                .fontWeight(.bold)
            if !serverURL.isEmpty {
                Text(serverURL)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
