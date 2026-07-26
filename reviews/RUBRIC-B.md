# RUBRIC-B: Security, Concurrency, iOS Architecture

## Security
- **no-secrets-in-logs**: Tokens, cookies, passwords NEVER appear in os_log, print, or debugDescription.
- **keychain-access**: Keychain items use kSecAttrAccessibleWhenUnlockedThisDeviceOnly; no kSecAttrAccessibleAlways.
- **cookie-security**: WKWebView cookies have HttpOnly=true, Secure=true, proper domain scoping.
- **no-hardcoded-credentials**: No API keys, tokens, or passwords in source code.
- **input-validation**: User input validated before use; no injection vectors.
- **tls-validation**: No custom URLSessionDelegate that blindly trusts all certs in production.

## Concurrency (Swift 6 Strict)
- **actor-isolation**: Mutable shared state is actor-isolated; no data races.
- **main-actor**: UI updates happen on @MainActor; no UI mutations from background.
- **sendable-compliance**: All types crossing isolation boundaries conform to Sendable.
- **no-implicit-sharing**: No implicit reference sharing across isolation domains.
- **task-cancellation**: Long-running tasks check Task.isCancelled and clean up resources.

## iOS Architecture
- **retain-cycles**: No strong reference cycles in closures (use [weak self] or [unowned self] appropriately).
- **delegate-weak**: Delegates are weak references to prevent retain cycles.
- **lifecycle-aware**: ViewControllers/Views handle viewDidLoad/viewWillAppear/deinit correctly.
- **backgrounding**: WebSocket connections torn down on background; reconnected on foreground.
- **memory-management**: Large objects (images, buffers) released promptly; no retain cycles.

## Error Handling
- **typed-errors**: Errors are typed (enum: Error); no generic "Error" strings.
- **error-propagation**: Errors propagated to caller; no swallowed errors with empty catch.
- **user-facing-messages**: Error messages are user-friendly; no internal details leaked.
- **recovery-attempts**: Transient errors (network) have retry logic; permanent errors fail fast.

## Defensive Programming
- **no-force-unwraps**: No force unwraps (!) in production code; use guard let / if let.
- **no-force-casts**: No force casts (as!); use conditional casts (as?).
- **bounds-checking**: Array/collection access bounds-checked; no index-out-of-range.
- **integer-overflow**: Arithmetic on user input checked for overflow.

## API Misuse
- **urlsession-correct**: URLSession tasks resumed after creation; completion handlers called once.
- **websocket-lifecycle**: WebSocket connect/send/receive/error paths all handled.
- **wkwebview-config**: WKWebViewConfiguration set before load; cookies injected before navigation.
- **keychain-queries**: Keychain queries specify kSecReturnAttributes/kSecReturnData explicitly.
