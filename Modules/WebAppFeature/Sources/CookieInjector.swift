#if canImport(WebKit)
import Foundation
import WebKit

/// An error thrown when cookie injection cannot complete.
public enum CookieInjectionError: Error, Sendable, Equatable {
    /// The target URL has no host, or does not use HTTPS.
    case invalidURL
}

/// Injects authentication cookies into web views for seamless SSO.
///
/// Uses the session token from CoderAuth to set a `coder_session_token`
/// cookie on the target domain, enabling authenticated access to VS Code Web
/// without requiring users to re-authenticate.
public struct CookieInjector: Sendable {

    /// The name of the Coder session cookie.
    public static let cookieName = "coder_session_token"

    /// Extracts the domain (host) from a URL.
    ///
    /// - Note: This returns the actual host component of the URL (e.g. "vnc.example.com"),
    ///         not a wildcard domain with a leading dot (e.g. ".example.com").
    /// - Parameter url: The URL to extract the domain from.
    /// - Returns: The host component of the URL, or nil if not present.
    public static func domain(from url: URL) -> String? {
        url.host
    }

    /// Builds the cookie properties dictionary for the session token.
    ///
    /// Sets the following attributes:
    /// - Name: `coder_session_token`
    /// - Domain: extracted from the URL
    /// - Path: `/`
    /// - Secure: `true`
    /// - HttpOnly: `true`
    /// - SameSite: `None`
    ///
    /// - Parameters:
    ///   - url: The target URL whose domain will receive the cookie.
    ///   - token: The session token value.
    /// - Returns: The cookie properties dictionary, or nil if the URL has no
    ///   host or does not use HTTPS. A Secure cookie minted for a non-HTTPS
    ///   URL would be silently refused by WebKit, masking the real failure.
    public static func cookieProperties(
        for url: URL,
        token: String
    ) -> [HTTPCookiePropertyKey: Any]? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard let host = domain(from: url) else { return nil }
        return [
            .name: cookieName,
            .value: token,
            .domain: host,
            .path: "/",
            .secure: true,
            HTTPCookiePropertyKey("HttpOnly"): true,
            HTTPCookiePropertyKey("SameSite"): "None"
        ]
    }

    /// Creates an HTTPCookie for the session token.
    /// - Parameters:
    ///   - url: The target URL whose domain will receive the cookie.
    ///   - token: The session token value.
    /// - Returns: The configured HTTPCookie, or nil if the URL is invalid.
    public static func makeCookie(for url: URL, token: String) -> HTTPCookie? {
        guard let properties = cookieProperties(for: url, token: token) else { return nil }
        return HTTPCookie(properties: properties)
    }

    /// Injects the `coder_session_token` cookie into a WKWebView.
    ///
    /// The cookie is set on the domain extracted from the provided URL,
    /// with HttpOnly, Secure, and SameSite=None attributes.
    /// Errors during injection are logged without exposing the token value.
    ///
    /// - Parameters:
    ///   - webView: The WKWebView to inject the cookie into.
    ///   - url: The target URL whose domain will receive the cookie.
    ///   - token: The session token value.
    /// - Throws: `CookieInjectionError.invalidURL` if the target URL has no
    ///   host or does not use HTTPS. Callers must not proceed to load the
    ///   URL when this throws, since the session would otherwise load
    ///   unauthenticated with no user-visible signal of the failure.
    @MainActor
    public static func injectCookies(into webView: WKWebView, for url: URL, token: String) async throws {
        guard let cookie = makeCookie(for: url, token: token) else {
            print("[CookieInjector] Failed to create cookie, invalid URL")
            throw CookieInjectionError.invalidURL
        }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        await cookieStore.setCookie(cookie)
    }
}
#endif
