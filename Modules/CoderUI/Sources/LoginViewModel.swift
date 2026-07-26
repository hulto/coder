import Foundation
import Observation
import CoderAuth

/// View model for the login screen that manages authentication state.
///
/// This view model coordinates between the SwiftUI view and AuthService,
/// handling user input, authentication flow, and state transitions.
///
/// - Important: This type is designed for Swift 6 strict concurrency and is Sendable.
@Observable
@MainActor
public final class LoginViewModel: Sendable {
    /// The server URL entered by the user.
    public var serverURL: String = ""
    
    /// Whether authentication is currently in progress.
    public private(set) var isLoading: Bool = false
    
    /// An error message to display to the user, or nil if no error.
    public private(set) var errorMessage: String?
    
    private let authService: AuthService
    
    /// Creates a new login view model.
    ///
    /// - Parameter authService: The authentication service to use for login.
    public init(authService: AuthService) {
        self.authService = authService
    }
    
    /// Initiates the authentication flow with the current server URL.
    ///
    /// This method:
    /// 1. Validates the server URL is not empty
    /// 2. Sets loading state
    /// 3. Calls AuthService.authenticate()
    /// 4. Handles success or error
    ///
    /// - Throws: Re-throws errors from AuthService for caller handling.
    public func login() async {
        // Clear previous error
        errorMessage = nil
        
        // Validate input
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            errorMessage = "Please enter a server URL."
            return
        }
        
        // Construct URL
        guard let url = URL(string: trimmedURL) else {
            errorMessage = "The server URL is invalid."
            return
        }
        
        // Set loading state
        isLoading = true
        
        do {
            // Attempt authentication
            _ = try await authService.authenticate(serverURL: url)
            
            // Success - clear loading state
            isLoading = false
            
            // Note: Navigation or success callback would be handled by the view
        } catch {
            // Handle error
            isLoading = false
            errorMessage = makeUserFriendlyError(error)
        }
    }
    
    /// Converts an error to a user-friendly message.
    ///
    /// - Parameter error: The error to convert.
    /// - Returns: A user-friendly error message.
    private nonisolated func makeUserFriendlyError(_ error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.description
        }
        return "An unexpected error occurred. Please try again."
    }
}
