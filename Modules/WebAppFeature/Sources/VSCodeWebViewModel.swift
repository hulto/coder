import Foundation
#if canImport(WebKit)
import WebKit
#endif
import Observation

/// View model managing VS Code Web navigation state.
///
/// Core state management is platform-independent. WebKit-specific
/// integration is handled by the SwiftUI view layer.
@MainActor
@Observable
public final class VSCodeWebViewModel: @unchecked Sendable {
    /// Current error message to display, if any.
    public private(set) var errorMessage: String?

    /// Whether the web view is currently loading content.
    public private(set) var isLoading: Bool = false

    /// The URL being loaded.
    public let url: URL

    #if canImport(WebKit)
    /// Weak reference to the WKWebView for cleanup.
    weak var webView: WKWebView?
    #endif

    /// Creates a view model for the given VS Code Web URL.
    /// - Parameter url: The URL to load in the web view.
    public init(url: URL) {
        self.url = url
    }

    /// Called when navigation begins.
    public func navigationDidStart() {
        isLoading = true
        errorMessage = nil
    }

    /// Called when navigation fails with an error.
    /// - Parameter error: The error that occurred during navigation.
    public func handleNavigationError(_ error: Error) {
        isLoading = false
        errorMessage = error.localizedDescription
    }

    /// Called when navigation finishes successfully.
    public func navigationDidFinish() {
        isLoading = false
        errorMessage = nil
    }

    /// Resets the error state.
    public func clearError() {
        errorMessage = nil
    }

    /// Stops loading and updates the loading state.
    public func stopLoading() {
        isLoading = false
    }

    /// Cleans up the web view by stopping loading and removing the navigation delegate.
    public func cleanup() {
        #if canImport(WebKit)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        #endif
        isLoading = false
    }
}
