import Foundation
import Testing

@testable import WebAppFeature

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
#endif
}
