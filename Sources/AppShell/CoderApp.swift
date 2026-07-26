import SwiftUI
import CoderAuth

/// The Coder iOS app entry point.
///
/// Owns the single long-lived ``AuthService`` instance and hosts the app's
/// only window. ``RootView`` decides what to show based on whether a session
/// token is already stored in the Keychain.
@main
struct CoderApp: App {
    private let authService = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService)
        }
    }
}
