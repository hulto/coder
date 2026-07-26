import Foundation

/// Errors that can occur during authentication operations.
///
/// This enum covers the full authentication lifecycle: web-based login,
/// token storage, biometric gating, and token validation.
///
/// - Note: Descriptions never include raw token values or secrets.
public enum AuthError: Error, Sendable, Equatable {
    /// The Coder server URL was invalid or could not be constructed.
    case invalidServerURL

    /// The user cancelled the authentication flow.
    case cancelled

    /// The callback URL from the web authentication session did not contain a valid token.
    case invalidCallbackURL

    /// The session token failed format validation before storage.
    case invalidTokenFormat

    /// A keychain operation failed with the given OSStatus code.
    case keychainError(statusCode: Int32)

    /// No stored session token was found in the keychain.
    case noStoredToken

    /// The web authentication session encountered an error.
    case sessionError(String)

    /// Biometric authentication was not available on this device.
    case biometricNotAvailable

    /// The user failed or declined biometric authentication.
    case biometricFailed

    /// The authentication flow encountered an unexpected error.
    case unexpected(String)
}

extension AuthError: CustomStringConvertible {
    /// A user-facing description that never includes secrets or token values.
    public var description: String {
        switch self {
        case .invalidServerURL:
            return "The server URL is invalid."
        case .cancelled:
            return "Authentication was cancelled by the user."
        case .invalidCallbackURL:
            return "The authentication callback URL was invalid."
        case .invalidTokenFormat:
            return "The session credential format is invalid."
        case .keychainError(let statusCode):
            return "Keychain error (status: \(statusCode))."
        case .noStoredToken:
            return "No stored session credential found."
        case .sessionError(let message):
            return "Authentication session error: \(message)"
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .biometricFailed:
            return "Biometric authentication failed or was declined."
        case .unexpected(let message):
            return "Unexpected error: \(message)"
        }
    }
}
