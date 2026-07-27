import SwiftUI
import CoderAuth

extension Notification.Name {
    static let coderResetSession = Notification.Name("com.coder.resetSession")
}

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
        .commands {
            CommandGroup(after: .newItem) {
                Button("Sign Out") {
                    Task {
                        try? await authService.resetSession()
                        NotificationCenter.default.post(name: .coderResetSession, object: nil)
                    }
                }
            }
        }
    }
}
