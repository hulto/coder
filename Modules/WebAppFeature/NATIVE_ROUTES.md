# Adding Native View Overrides to the Route Interceptor

When a native implementation is ready for a Coder route (VS Code Web, terminal,
VNC), enable it by completing the steps below. The feature flag
`AppSettings.shared.enableNativeInterception` gates all interception, so shipping
the code before it is ready is safe.

## Step 1: Classify the new route in `RouteInterceptor.classify`

Open `NavigationManager.swift` and add a path-matching rule inside
`RouteInterceptor.classify(_:baseURL:)`. Only URLs on the same host as `baseURL`
reach this code, so external navigations are always `.passThrough`.

```swift
// Example: Coder's built-in web terminal paths are /workspace/{owner}/{name}/terminal
if path.range(of: #"^/workspace/[^/]+/[^/]+/terminal"#, options: .regularExpression) != nil {
    return .terminal(url)
}
```

## Step 2: Add a `RouteInterceptor` case if needed

If the new route does not fit an existing case (`vscodeWeb`, `terminal`, `vnc`),
add one:

```swift
public enum RouteInterceptor: Sendable {
    case passThrough
    case vscodeWeb(URL)
    case terminal(URL)
    case vnc(URL)
    case myNewRoute(URL)   // new
}
```

## Step 3: Handle the case in `decidePolicyFor`

In `NavigationManager.decidePolicyFor`, add a branch for the new case that mirrors
the existing ones:

```swift
case .myNewRoute(let target):
    logger.debug("Route: myNewRoute \(target.absoluteString)")
    if enableNativeInterception {
        handleNativeMyRoute(url: target)
        decisionHandler(.cancel)
    } else {
        decisionHandler(.allow)
    }
```

## Step 4: Replace the stub with a real presentation

Replace the stub method with code that presents the native SwiftUI or UIKit view.
Use `topmostViewController()` (see `VSCodeWebView.swift` for the pattern) or an
environment-injected router if you have one wired up in AppShell.

```swift
private func handleNativeMyRoute(url: URL) {
    // Present MyNativeView using the existing scene/window infrastructure.
}
```

## Step 5: Enable the flag for the new route

Once the native view is tested, set the flag in a debug build or via a settings
screen:

```swift
AppSettings.shared.enableNativeInterception = true
```

The flag is global for now. Per-route granularity can be added to `AppSettings`
when multiple routes are in production simultaneously.
