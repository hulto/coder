import Foundation
#if canImport(WebKit)
import WebKit
#endif
import Observation

/// View model managing VNC web view navigation state.
///
/// Core state management is platform-independent. WebKit-specific
/// integration is handled by the SwiftUI view layer.
@MainActor
@Observable
final class VNCWebViewModel {
    /// Current error message to display, if any.
    private(set) var errorMessage: String?

    /// Whether the web view is currently loading content.
    private(set) var isLoading: Bool = false

    /// The URL being loaded.
    let url: URL

    /// Optional session token for cookie injection.
    let token: String?

    #if canImport(WebKit)
    /// Weak reference to the WKWebView for cleanup.
    weak var webView: WKWebView?
    #endif

    /// Handle to the in-flight cookie-injection task, if any.
    ///
    /// Stored so `cleanup()` can cancel it, preventing a dismissed view from
    /// injecting a token and starting a load after teardown.
    var injectionTask: Task<Void, Never>?

    /// Creates a view model for the given VNC URL.
    /// - Parameters:
    ///   - url: The URL to load in the web view.
    ///   - token: Optional session token for cookie injection.
    init(url: URL, token: String? = nil) {
        self.url = url
        self.token = token
    }

    /// Called when navigation begins.
    func navigationDidStart() {
        isLoading = true
        errorMessage = nil
    }

    /// Called when navigation fails with an error.
    /// - Parameter error: The error that occurred during navigation.
    func handleNavigationError(_ error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription
    }

    /// Called when navigation finishes successfully.
    func navigationDidFinish() {
        isLoading = false
        errorMessage = nil
    }

    /// Resets the error state.
    func clearError() {
        errorMessage = nil
    }

    /// Stops loading and updates the loading state.
    func stopLoading() {
        isLoading = false
    }

    /// Cleans up the web view by stopping loading and removing the navigation delegate.
    func cleanup() {
        injectionTask?.cancel()
        injectionTask = nil
        #if canImport(WebKit)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        #endif
        isLoading = false
    }
}
