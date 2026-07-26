import Testing
import Foundation
@testable import CoderAuth

// MARK: - KeychainManager Tests

@Suite("KeychainManager Tests")
struct KeychainManagerTests {
    @Test("store and retrieve data")
    func storeAndRetrieve() throws {
        let store = InMemoryKeychainStore()
        let data = Data("test-data".utf8)

        try store.store(data: data, forKey: "test-key")
        let retrieved = try store.retrieve(forKey: "test-key")

        #expect(retrieved == data)
    }

    @Test("retrieve returns nil for non-existent key")
    func retrieveNonExistent() throws {
        let store = InMemoryKeychainStore()
        let retrieved = try store.retrieve(forKey: "non-existent")
        #expect(retrieved == nil)
    }

    @Test("store overwrites existing data")
    func storeOverwrite() throws {
        let store = InMemoryKeychainStore()
        let data1 = Data("data1".utf8)
        let data2 = Data("data2".utf8)

        try store.store(data: data1, forKey: "test-key")
        try store.store(data: data2, forKey: "test-key")
        let retrieved = try store.retrieve(forKey: "test-key")

        #expect(retrieved == data2)
    }

    @Test("delete removes data")
    func delete() throws {
        let store = InMemoryKeychainStore()
        let data = Data("test-data".utf8)

        try store.store(data: data, forKey: "test-key")
        try store.delete(forKey: "test-key")
        let retrieved = try store.retrieve(forKey: "test-key")

        #expect(retrieved == nil)
    }

    @Test("delete non-existent key does not throw")
    func deleteNonExistent() throws {
        let store = InMemoryKeychainStore()
        try store.delete(forKey: "non-existent")
        // Should not throw
    }

    @Test("multiple keys are independent")
    func multipleKeys() throws {
        let store = InMemoryKeychainStore()
        let data1 = Data("data1".utf8)
        let data2 = Data("data2".utf8)

        try store.store(data: data1, forKey: "key1")
        try store.store(data: data2, forKey: "key2")

        let retrieved1 = try store.retrieve(forKey: "key1")
        let retrieved2 = try store.retrieve(forKey: "key2")

        #expect(retrieved1 == data1)
        #expect(retrieved2 == data2)
    }

    @Test("count reflects stored items")
    func count() throws {
        let store = InMemoryKeychainStore()
        #expect(store.count == 0)

        try store.store(data: Data("data1".utf8), forKey: "key1")
        #expect(store.count == 1)

        try store.store(data: Data("data2".utf8), forKey: "key2")
        #expect(store.count == 2)

        try store.delete(forKey: "key1")
        #expect(store.count == 1)
    }

    @Test("reset clears all data")
    func reset() throws {
        let store = InMemoryKeychainStore()

        try store.store(data: Data("data1".utf8), forKey: "key1")
        try store.store(data: Data("data2".utf8), forKey: "key2")
        store.reset()

        #expect(store.count == 0)
        #expect(try store.retrieve(forKey: "key1") == nil)
        #expect(try store.retrieve(forKey: "key2") == nil)
    }

    @Test("concurrent access is safe")
    func concurrentAccess() async throws {
        let store = InMemoryKeychainStore()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let data = Data("data-\(i)".utf8)
                    try? store.store(data: data, forKey: "key-\(i)")
                    _ = try? store.retrieve(forKey: "key-\(i)")
                }
            }
        }

        #expect(store.count == 100)
    }
}

// MARK: - makeCLIAuthURL Tests

@Suite("makeCLIAuthURL Tests")
struct CLIAuthURLTests {
    @Test("constructs correct URL")
    func constructURL() throws {
        let serverURL = URL(string: "https://coder.example.com")!
        let authURL = try makeCLIAuthURL(for: serverURL)

        #expect(authURL.absoluteString.contains("/cli-auth"))
        #expect(authURL.absoluteString.contains("redirect_uri=coder://cli-auth"))
    }

    @Test("preserves server path")
    func preservePath() throws {
        let serverURL = URL(string: "https://coder.example.com/deploy")!
        let authURL = try makeCLIAuthURL(for: serverURL)

        #expect(authURL.absoluteString.contains("/deploy/cli-auth"))
    }

    @Test("uses correct callback scheme")
    func callbackScheme() throws {
        let serverURL = URL(string: "https://coder.example.com")!
        let authURL = try makeCLIAuthURL(for: serverURL)

        #expect(authURL.absoluteString.contains("coder://cli-auth"))
    }
}

// MARK: - AuthError Tests

@Suite("AuthError Tests")
struct AuthErrorTests {
    @Test("error descriptions do not contain secrets")
    func errorDescriptions() {
        let errors: [AuthError] = [
            .invalidServerURL,
            .cancelled,
            .invalidCallbackURL,
            .invalidTokenFormat,
            .keychainError(statusCode: -25300),
            .noStoredToken,
            .biometricNotAvailable,
            .biometricFailed,
            .unexpected("test"),
        ]

        for error in errors {
            let description = error.description
            #expect(!description.contains("token"))
            #expect(!description.contains("secret"))
            #expect(!description.contains("password"))
        }
    }

    @Test("AuthError is Equatable")
    func equatable() {
        #expect(AuthError.cancelled == AuthError.cancelled)
        #expect(AuthError.noStoredToken == AuthError.noStoredToken)
        #expect(AuthError.keychainError(statusCode: -25300) == AuthError.keychainError(statusCode: -25300))
        #expect(AuthError.cancelled != AuthError.noStoredToken)
    }
}
