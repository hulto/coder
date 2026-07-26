import Foundation
import Testing

@testable import WebAppFeature

#if canImport(WebKit)
import WebKit

/// Mock WKHTTPCookieStore for testing cookie injection without a real web view.
final class MockHTTPCookieStore: NSObject, WKHTTPCookieStore, @unchecked Sendable {
    private var _cookies: [HTTPCookie] = []
    private let lock = NSLock()

    var cookies: [HTTPCookie] {
        lock.lock()
        defer { lock.unlock() }
        return _cookies
    }

    func setCookie(_ cookie: HTTPCookie, completionHandler: (() -> Void)?) {
        lock.lock()
        _cookies.append(cookie)
        lock.unlock()
        completionHandler?()
    }

    func getAllCookies(_ completionHandler: @escaping ([HTTPCookie]) -> Void) {
        lock.lock()
        let cookies = _cookies
        lock.unlock()
        completionHandler(cookies)
    }

    func delete(_ cookie: HTTPCookie, completionHandler: (() -> Void)?) {
        lock.lock()
        _cookies.removeAll { $0 == cookie }
        lock.unlock()
        completionHandler?()
    }

    func addObserver(_ observer: WKHTTPCookieStoreObserver) {
        // no-op for testing
    }

    func removeObserver(_ observer: WKHTTPCookieStoreObserver) {
        // no-op for testing
    }
}

@Suite("CookieInjector Tests")
struct CookieInjectorTests {

    @Test("Extracts domain from URL correctly")
    func extractDomain() {
        let url = URL(string: "https://vscode.example.com")!
        let domain = CookieInjector.domain(from: url)
        #expect(domain == "vscode.example.com")
    }

    @Test("Returns nil for URL without host")
    func extractDomainNoHost() {
        let url = URL(string: "file:///path/to/file")!
        let domain = CookieInjector.domain(from: url)
        #expect(domain == nil)
    }

    @Test("Creates cookie with correct name")
    func cookieName() {
        let url = URL(string: "https://vscode.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")
        #expect(cookie?.name == "coder_session_token")
    }

    @Test("Creates cookie with correct value")
    func cookieValue() {
        let url = URL(string: "https://vscode.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "my-secret-token")
        #expect(cookie?.value == "my-secret-token")
    }

    @Test("Creates cookie with correct domain")
    func cookieDomain() {
        let url = URL(string: "https://vscode.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")
        #expect(cookie?.domain == "vscode.example.com")
    }

    @Test("Creates cookie with correct path")
    func cookiePath() {
        let url = URL(string: "https://vscode.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")
        #expect(cookie?.path == "/")
    }

    @Test("Creates cookie with Secure flag")
    func cookieSecure() {
        let url = URL(string: "https://vscode.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")
        #expect(cookie?.isSecure == true)
    }

    @Test("Creates cookie with HttpOnly flag")
    func cookieHttpOnly() {
        let url = URL(string: "https://vscode.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")
        #expect(cookie?.isHTTPOnly == true)
    }

    @Test("Returns nil for invalid URL")
    func invalidURL() {
        let url = URL(string: "file:///path")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")
        #expect(cookie == nil)
    }

    @Test("Cookie properties dictionary contains all required keys")
    func cookiePropertiesKeys() {
        let url = URL(string: "https://vscode.example.com")!
        let properties = CookieInjector.cookieProperties(for: url, token: "test-token")

        #expect(properties != nil)
        #expect(properties?[.name] as? String == "coder_session_token")
        #expect(properties?[.value] as? String == "test-token")
        #expect(properties?[.domain] as? String == "vscode.example.com")
        #expect(properties?[.path] as? String == "/")
        #expect(properties?[.secure] as? Bool == true)
        #expect(properties?[HTTPCookiePropertyKey("HttpOnly")] as? Bool == true)
        #expect(properties?[HTTPCookiePropertyKey("SameSite")] as? String == "None")
    }

    @Test("Returns nil properties for URL without host")
    func cookiePropertiesNoHost() {
        let url = URL(string: "file:///path")!
        let properties = CookieInjector.cookieProperties(for: url, token: "test-token")
        #expect(properties == nil)
    }

    @Test("Cookie name is coder_session_token")
    func cookieNameConstant() {
        #expect(CookieInjector.cookieName == "coder_session_token")
    }

    @Test("Mock cookie store records injected cookies")
    func mockStoreRecordsCookies() async {
        let mockStore = MockHTTPCookieStore()
        let url = URL(string: "https://vscode.example.com")!
        let cookie = CookieInjector.makeCookie(for: url, token: "test-token")!

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            mockStore.setCookie(cookie) {
                continuation.resume()
            }
        }

        #expect(mockStore.cookies.count == 1)
        #expect(mockStore.cookies.first?.name == "coder_session_token")
        #expect(mockStore.cookies.first?.value == "test-token")
    }

    @Test("Multiple cookies can be stored in mock")
    func multipleCookiesInMock() async {
        let mockStore = MockHTTPCookieStore()
        let url1 = URL(string: "https://vscode1.example.com")!
        let url2 = URL(string: "https://vscode2.example.com")!

        let cookie1 = CookieInjector.makeCookie(for: url1, token: "token1")!
        let cookie2 = CookieInjector.makeCookie(for: url2, token: "token2")!

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            mockStore.setCookie(cookie1) {
                mockStore.setCookie(cookie2) {
                    continuation.resume()
                }
            }
        }

        #expect(mockStore.cookies.count == 2)
        #expect(mockStore.cookies[0].domain == "vscode1.example.com")
        #expect(mockStore.cookies[0].value == "token1")
        #expect(mockStore.cookies[1].domain == "vscode2.example.com")
        #expect(mockStore.cookies[1].value == "token2")
    }
}

@Suite("VSCodeWebView Tests")
struct VSCodeWebViewCreationTests {
    @Test("View can be created with a URL")
    @MainActor
    func viewCreation() {
        let url = URL(string: "https://vscode.example.com")!
        let view = VSCodeWebView(url: url)
        // View was successfully constructed; body is non-optional so no nil check needed.
        _ = view.body
    }

    @Test("View can be created with a URL and token")
    @MainActor
    func viewCreationWithToken() {
        let url = URL(string: "https://vscode.example.com")!
        let view = VSCodeWebView(url: url, token: "test-token")
        _ = view.body
    }
}
#endif
