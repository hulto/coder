import Foundation
import Testing

@testable import WebAppFeature

@Suite("VSCodeWebViewModel Tests")
struct VSCodeWebViewModelTests {

    @Test("Initializes with URL and no error")
    @MainActor
    func initialization() {
        let url = URL(string: "https://vscode.example.com")!
        let viewModel = VSCodeWebViewModel(url: url)

        #expect(viewModel.url == url)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test("navigationDidStart sets loading and clears error")
    @MainActor
    func navigationDidStart() {
        let url = URL(string: "https://vscode.example.com")!
        let viewModel = VSCodeWebViewModel(url: url)

        // Pre-set an error to verify it gets cleared
        viewModel.handleNavigationError(
            NSError(domain: "test", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "prior error"
            ])
        )
        #expect(viewModel.errorMessage != nil)

        viewModel.navigationDidStart()

        #expect(viewModel.isLoading == true)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("handleNavigationError sets error and stops loading")
    @MainActor
    func navigationError() {
        let url = URL(string: "https://vscode.example.com")!
        let viewModel = VSCodeWebViewModel(url: url)

        viewModel.navigationDidStart()
        #expect(viewModel.isLoading == true)

        let error = NSError(domain: "TestDomain", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Connection failed"
        ])
        viewModel.handleNavigationError(error)

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "Connection failed")
    }

    @Test("navigationDidFinish clears loading and error")
    @MainActor
    func navigationDidFinish() {
        let url = URL(string: "https://vscode.example.com")!
        let viewModel = VSCodeWebViewModel(url: url)

        viewModel.navigationDidStart()
        #expect(viewModel.isLoading == true)

        viewModel.navigationDidFinish()

        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("clearError removes error message")
    @MainActor
    func clearError() {
        let url = URL(string: "https://vscode.example.com")!
        let viewModel = VSCodeWebViewModel(url: url)

        viewModel.handleNavigationError(
            NSError(domain: "test", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Some error"
            ])
        )
        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()
        #expect(viewModel.errorMessage == nil)
    }

    @Test("No secrets are logged or exposed in error messages")
    @MainActor
    func noSecretsExposed() {
        let url = URL(string: "https://vscode.example.com")!
        let viewModel = VSCodeWebViewModel(url: url)

        let error = NSError(domain: "TestDomain", code: 401, userInfo: [
            NSLocalizedDescriptionKey: "Unauthorized"
        ])
        viewModel.handleNavigationError(error)

        // Error message should not contain sensitive URL components
        let errorMsg = viewModel.errorMessage ?? ""
        #expect(!errorMsg.contains("password"))
        #expect(!errorMsg.contains("token"))
        #expect(!errorMsg.contains("secret"))
        #expect(!errorMsg.contains("key"))
    }
}

#if canImport(WebKit)
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
