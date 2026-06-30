import Foundation

/// Pure launch-completion state machine.
///
/// AppKit and SwiftUI report launch facts in different callbacks:
/// - App finished launching.
/// - AppKit received a direct untitled launch request.
/// - LaunchServices supplied an explicit file/folder URL.
/// - The SwiftUI content window can receive notifications / openWindow calls.
///
/// Routing should happen only after the required facts are known, and explicit
/// URL opens must win over direct restore/welcome.
struct LaunchCompletionRoutingState: Equatable {
    enum Decision: Equatable {
        case wait
        case routeDirectLaunch
        case routeExplicitURL(URL)
        case suppressRestore
    }

    private(set) var didFinishLaunching = false
    private(set) var receivedUntitledLaunchRequest = false
    private(set) var contentWindowReady = false
    private(set) var didBecomeActive = false
    private(set) var didRoute = false

    private var explicitURL: URL?
    private var pendingStoreURL: URL?
    private var receivedExplicitIntent = false

    mutating func markDidFinishLaunching() {
        didFinishLaunching = true
    }

    mutating func markUntitledLaunchRequest() {
        receivedUntitledLaunchRequest = true
    }

    mutating func markContentWindowReady() {
        contentWindowReady = true
    }

    mutating func markDidBecomeActive() {
        didBecomeActive = true
    }

    mutating func markExplicitURL(_ url: URL) {
        explicitURL = url.markMarkCanonicalFileURL
        receivedExplicitIntent = true
    }

    mutating func markExplicitIntentWithoutURL() {
        receivedExplicitIntent = true
    }

    mutating func updatePendingStoreURL(_ url: URL?) {
        pendingStoreURL = url?.markMarkCanonicalFileURL
    }

    mutating func markRouted() {
        didRoute = true
    }

    var decision: Decision {
        guard !didRoute, didFinishLaunching, contentWindowReady else {
            return .wait
        }

        // In-memory explicit URL is the strongest signal for the current
        // LaunchServices event. Pending-store URLs still beat direct restore.
        if let explicitURL {
            return .routeExplicitURL(explicitURL)
        }
        if let pendingStoreURL {
            return .routeExplicitURL(pendingStoreURL)
        }
        if receivedExplicitIntent {
            return .suppressRestore
        }
        if receivedUntitledLaunchRequest {
            return .routeDirectLaunch
        }
        return .wait
    }
}
