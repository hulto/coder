import Foundation

/// Persistent, non-secret configuration for the Coder app.
///
/// Backed by UserDefaults (@AppStorage equivalent) and survives app restarts.
/// Session tokens are stored in the Keychain via AuthService, not here.
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private enum Keys {
        static let baseURL = "coder_base_url"
        static let nativeInterception = "coder_native_interception"
    }

    private init() {}

    /// The base URL of the user's self-hosted Coder deployment.
    public var baseURL: String {
        get { UserDefaults.standard.string(forKey: Keys.baseURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.baseURL) }
    }

    /// When true, matching routes redirect to native views instead of WKWebView.
    ///
    /// Keep false until native implementations for VS Code, terminal, and VNC are complete.
    public var enableNativeInterception: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.nativeInterception) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.nativeInterception) }
    }
}
