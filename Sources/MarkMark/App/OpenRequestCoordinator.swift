import Foundation
import AppKit
import Darwin

/// Source category for an open request.
///
/// The coordinator does not care about the exact AppKit callback that produced
/// the request; it only needs enough context to preserve product semantics.
enum OpenReason: Equatable {
    case finderOpen
    case openWith
    case dragToAppIcon
    case finderService
}

/// Minimal routing interface used by `OpenRequestCoordinator`.
///
/// Tests and production code cross the same seam: callers describe a user
/// intent, and the router performs the visible window action.
@MainActor
protocol OpenRequestRouting: AnyObject {
    var hasUsableWindow: Bool { get }

    func openExternalURL(_ url: URL)
    func replaceActiveWindow(with url: URL)
    func restoreLastLocation()
    func resetToWelcome()
}

@MainActor
protocol OpenRequestSettingsProviding {
    var reopenLastLocation: Bool { get }
}

@MainActor
protocol PendingOpenStoring: AnyObject {
    var pendingURL: URL? { get }

    func store(_ url: URL)
    func clear()
}

/// Coordinates MarkMark's open-request product semantics.
///
/// Rules intentionally kept here instead of in AppDelegate/ContentView:
/// - external explicit opens win over session restore;
/// - external opens use the multi-window path;
/// - internal opens replace the active window when possible;
/// - launch/reopen without explicit URL restores or shows welcome.
extension URL {
    /// Stable file URL identity for LaunchServices/UserDefaults comparisons.
    /// macOS may hand the same temp path to different layers as `/tmp/...` or
    /// `/private/tmp/...`; comparing resolved file URLs prevents watchdog false
    /// negatives that leave pending opens unconsumed.
    var markMarkCanonicalFileURL: URL {
        guard isFileURL else { return standardized }
        let standardizedPath = standardizedFileURL.path
        if let resolved = standardizedPath.withCString({ realpath($0, nil) }) {
            defer { free(resolved) }
            return URL(fileURLWithPath: String(cString: resolved))
        }
        return resolvingSymlinksInPath().standardizedFileURL
    }
}

@MainActor
final class OpenRequestCoordinator {
    private let router: OpenRequestRouting
    private let settings: OpenRequestSettingsProviding
    private let pendingStore: PendingOpenStoring

    init(
        router: OpenRequestRouting,
        settings: OpenRequestSettingsProviding,
        pendingStore: PendingOpenStoring
    ) {
        self.router = router
        self.settings = settings
        self.pendingStore = pendingStore
    }

    func handleExternalOpen(
        urls: [URL],
        reason: OpenReason,
        isLaunchCompleted: Bool
    ) {
        guard !urls.isEmpty else { return }

        if isLaunchCompleted {
            pendingStore.clear()
            for url in urls {
                router.openExternalURL(url.markMarkCanonicalFileURL)
            }
        } else if let first = urls.first {
            // Cold launch: let the initial SwiftUI window consume this pending
            // URL. Multi-select cold launch preserves the existing first-URL
            // behavior until the WindowGroup is ready.
            pendingStore.store(first)
        }
    }

    func handleInternalOpen(url: URL) {
        let canonicalURL = url.markMarkCanonicalFileURL
        if router.hasUsableWindow {
            router.replaceActiveWindow(with: canonicalURL)
        } else {
            router.openExternalURL(canonicalURL)
        }
    }

    func serviceFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let readOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objectURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: readOptions
        ) as? [URL]) ?? []

        let filenamePasteboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let filenameURLs = (pasteboard.propertyList(forType: filenamePasteboardType) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }

        var seen = Set<URL>()
        return (objectURLs + filenameURLs).compactMap { url in
            guard url.isFileURL else { return nil }
            let canonicalURL = url.markMarkCanonicalFileURL
            guard !seen.contains(canonicalURL) else { return nil }
            seen.insert(canonicalURL)
            return FileManager.default.fileExists(atPath: canonicalURL.path) ? canonicalURL : nil
        }
    }

    func handleServiceOpen(
        pasteboard: NSPasteboard,
        isLaunchCompleted: Bool
    ) -> Bool {
        let urls = serviceFileURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }
        handleExternalOpen(
            urls: urls,
            reason: .finderService,
            isLaunchCompleted: isLaunchCompleted
        )
        return true
    }

    func handleLaunchCompleted() {
        guard pendingStore.pendingURL == nil else { return }
        routeRestoreOrWelcome()
    }

    func handleDockReopen() {
        guard pendingStore.pendingURL == nil else { return }
        routeRestoreOrWelcome()
    }

    private func routeRestoreOrWelcome() {
        if settings.reopenLastLocation {
            router.restoreLastLocation()
        } else {
            router.resetToWelcome()
        }
    }
}

// MARK: - Production adapters

struct SettingsOpenRequestSettings: OpenRequestSettingsProviding {
    var reopenLastLocation: Bool {
        SettingsModel.shared.reopenLastLocation
    }
}

final class UserDefaultsPendingOpenStore: PendingOpenStoring {
    private enum Keys {
        static let file = "pendingOpenFilePath"
        static let directory = "pendingOpenDirectoryPath"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    var pendingURL: URL? {
        if let filePath = defaults.string(forKey: Keys.file) {
            return URL(fileURLWithPath: filePath).markMarkCanonicalFileURL
        }
        if let dirPath = defaults.string(forKey: Keys.directory) {
            return URL(fileURLWithPath: dirPath).markMarkCanonicalFileURL
        }
        return nil
    }

    func store(_ url: URL) {
        var isDirectory: ObjCBool = false
        let canonicalURL = url.markMarkCanonicalFileURL
        fileManager.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            defaults.set(canonicalURL.path, forKey: Keys.directory)
            defaults.removeObject(forKey: Keys.file)
        } else {
            defaults.set(canonicalURL.path, forKey: Keys.file)
            defaults.removeObject(forKey: Keys.directory)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Keys.file)
        defaults.removeObject(forKey: Keys.directory)
    }
}

@MainActor
final class NotificationOpenRequestRouter: OpenRequestRouting {
    var hasUsableWindow: Bool {
        NSApp.windows.contains {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) && !$0.isSheet
        }
    }

    func openExternalURL(_ url: URL) {
        if WindowRouter.shared.canOpenWindow {
            WindowRouter.shared.openWindow(for: url)
        } else {
            replaceActiveWindow(with: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func replaceActiveWindow(with url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        NotificationCenter.default.post(
            name: isDirectory.boolValue ? .openDirectory : .openFile,
            object: url
        )
    }

    func restoreLastLocation() {
        NotificationCenter.default.post(name: .restoreLastLocation, object: nil)
    }

    func resetToWelcome() {
        NotificationCenter.default.post(name: .resetToWelcome, object: nil)
    }
}
