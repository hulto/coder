#if canImport(SwiftUI)
import SwiftUI
import CoderAuth

/// A SwiftUI view that provides a login interface for Coder deployments.
///
/// The view displays a server URL input field, a login button, loading indicator,
/// and error messages. It integrates with ``LoginViewModel`` for state management
/// and ``AuthService`` for authentication.
///
/// ## Usage
/// ```swift
/// let authService = AuthService()
/// LoginView(viewModel: LoginViewModel(authService: authService))
/// ```
@available(iOS 17.0, macOS 14.0, *)
public struct LoginView: View {
    @Bindable var viewModel: LoginViewModel
    
    /// Creates a new login view.
    ///
    /// - Parameter viewModel: The view model managing login state.
    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            Text("Sign In")
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityLabel("Sign In to Coder")
            
            TextField("Server URL", text: $viewModel.serverURL)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .accessibilityLabel("Server URL input field")
                .accessibilityHint("Enter the URL of your Coder deployment")
            
            if viewModel.isLoading {
                ProgressView()
                    .accessibilityLabel("Signing in")
            } else {
                Button("Sign In") {
                    Task {
                        await viewModel.login()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Sign In button")
                .accessibilityHint("Tap to authenticate with the Coder server")
            }
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error message")
                    .accessibilityValue(errorMessage)
            }
        }
        .padding()
    }
}

#if DEBUG
@available(iOS 17.0, macOS 14.0, *)
#Preview {
    let authService = AuthService(
        webAuthSession: MockWebAuthSessionProvider(),
        keychainStore: InMemoryKeychainStore()
    )
    return LoginView(viewModel: LoginViewModel(authService: authService))
}
#endif

#endif
