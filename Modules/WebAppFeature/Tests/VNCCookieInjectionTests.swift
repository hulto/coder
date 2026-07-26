import Foundation
import Testing

@testable import WebAppFeature

#if canImport(WebKit)
import WebKit
#endif

@Suite("VNC Cookie Injection Tests")
struct VNCCookieInjectionTests {

    @Test("ViewModel stores optional token")
    @MainActor
    func viewModelStoresToken() {
        let url = URL(string: "https://vnc.example.com")!
        let token = "test-session-token-123"

        let viewModel = VNCWebViewModel(url: url, token: token)

        #expect(viewModel.url == url)
        #expect(viewModel.token == token)
    }

    @Test("ViewModel token defaults to nil")
    @MainActor
    func viewModelTokenDefaults() {
        let url = URL(string: "https://vnc.example.com")!
        let viewModel = VNCWebViewModel(url: url)

        #expect(viewModel.token == nil)
    }

    @Test("Token is not exposed in error messages")
    @MainActor
    func tokenNotExposedInErrors() {
        let url = URL(string: "https://vnc.example.com")!
        let secretToken = "super-secret-token-xyz"
        let viewModel = VNCWebViewModel(url: url, token: secretToken)

        let error = NSError(domain: "TestDomain", code: 401, userInfo: [
            NSLocalizedDescriptionKey: "Unauthorized"
        ])
        viewModel.handleNavigationError(error)

        // Error message should not contain the token
        let errorMsg = viewModel.errorMessage ?? ""
        #expect(!errorMsg.contains(secretToken))
    }

#if canImport(WebKit)
    @Test("CookieInjector creates valid cookie for VNC URL")
    func cookieInjectorCreatesCookie() {
        let url = URL(string: "https://vnc.example.com/path")!
        let token = "test-token-abc"

        let cookie = CookieInjector.makeCookie(for: url, token: token)

        #expect(cookie != nil)
        #expect(cookie?.name == CookieInjector.cookieName)
        #expect(cookie?.value == token)
        #expect(cookie?.domain == "vnc.example.com")
        #expect(cookie?.path == "/")
        #expect(cookie?.isSecure == true)
        #expect(cookie?.isHTTPOnly == true)
    }

    @Test("CookieInjector returns nil for invalid URL")
    func cookieInjectorInvalidURL() {
        let url = URL(string: "file:///local/path")!
        let token = "test-token"

        let cookie = CookieInjector.makeCookie(for: url, token: token)

        #expect(cookie == nil)
    }

    @Test("CookieInjector extracts domain correctly")
    func cookieInjectorDomainExtraction() {
        let url1 = URL(string: "https://vnc.example.com")!
        let url2 = URL(string: "https://vnc.sub.example.org:8080/path")!

        #expect(CookieInjector.domain(from: url1) == "vnc.example.com")
        #expect(CookieInjector.domain(from: url2) == "vnc.sub.example.org")
    }

    @Test("CookieInjector returns nil for non-HTTPS URL")
    func cookieInjectorRejectsNonHTTPS() {
        let url = URL(string: "http://vnc.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")

        #expect(cookie == nil)
    }

    @Test("injectCookies stores the session cookie for a VNC URL")
    @MainActor
    func injectCookiesStoresSessionCookie() async throws {
        let webView = WKWebView()
        let url = URL(string: "https://vnc.example.com/path")!
        let token = "test-vnc-session-token"

        try await CookieInjector.injectCookies(into: webView, for: url, token: token)

        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let sessionCookie = cookies.first { $0.name == CookieInjector.cookieName }

        #expect(sessionCookie != nil)
        #expect(sessionCookie?.value == token)
        #expect(sessionCookie?.domain == "vnc.example.com")
    }

    @Test("injectCookies throws for invalid URL and stores no cookie")
    @MainActor
    func injectCookiesThrowsForInvalidURL() async {
        let webView = WKWebView()
        let url = URL(string: "http://vnc.example.com")!

        await #expect(throws: CookieInjectionError.self) {
            try await CookieInjector.injectCookies(into: webView, for: url, token: "test-token")
        }

        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        #expect(cookies.isEmpty)
    }

    @Test("Injection completes before load is triggered")
    @MainActor
    func injectionPrecedesLoad() async throws {
        // Exercises the ordering contract that VNCWebView.makeUIView relies
        // on: injectCookies() must fully complete (cookie visible in the
        // store) before any navigation request is issued. We simulate the
        // call site's sequencing directly, since UIViewRepresentable.
        // makeUIView cannot be invoked outside of SwiftUI rendering.
        let webView = WKWebView()
        let url = URL(string: "https://vnc.example.com")!
        let token = "ordering-test-token"

        try await CookieInjector.injectCookies(into: webView, for: url, token: token)

        // At this point (post-await, pre-load) the cookie must already be
        // visible in the store, matching the sequencing the call site
        // depends on to load an authenticated session.
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let injectedBeforeLoad = cookies.contains { $0.name == CookieInjector.cookieName }

        #expect(injectedBeforeLoad)
    }

    @Test("VNCWebView can be created with a URL and token")
    @MainActor
    func viewCreationWithToken() {
        let url = URL(string: "https://vnc.example.com")!
        let view = VNCWebView(url: url, token: "test-token")
        // View was successfully constructed; body is non-optional so no nil check needed.
        _ = view.body
    }
#endif
}
