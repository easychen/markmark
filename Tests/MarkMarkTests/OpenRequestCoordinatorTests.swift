import Testing
import Foundation
import AppKit
@testable import MarkMark

@MainActor
@Suite("Open request routing")
struct OpenRequestCoordinatorTests {

    @Test("external open after launch routes every URL through the external window path")
    func externalOpenAfterLaunchUsesExternalWindows() {
        let router = RecordingOpenRequestRouter(hasUsableWindow: true)
        let pending = InMemoryPendingOpenStore()
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: true),
            pendingStore: pending
        )
        let first = URL(fileURLWithPath: "/tmp/a.md")
        let second = URL(fileURLWithPath: "/tmp/b.md")

        coordinator.handleExternalOpen(urls: [first, second], reason: .finderOpen, isLaunchCompleted: true)

        #expect(router.actions == [.openExternalURL(first.markMarkCanonicalFileURL), .openExternalURL(second.markMarkCanonicalFileURL)])
        #expect(pending.pendingURL == nil)
    }

    @Test("external open before launch stores the first URL as pending instead of restoring")
    func coldExternalOpenStoresPending() {
        let router = RecordingOpenRequestRouter(hasUsableWindow: false)
        let pending = InMemoryPendingOpenStore()
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: true),
            pendingStore: pending
        )
        let url = URL(fileURLWithPath: "/tmp/cold.md")

        coordinator.handleExternalOpen(urls: [url], reason: .finderOpen, isLaunchCompleted: false)
        coordinator.handleLaunchCompleted()

        #expect(pending.pendingURL == url)
        #expect(router.actions.isEmpty)
    }

    @Test("launch completion restores only when no pending explicit open exists")
    func launchCompletionRestoresOnlyWithoutPendingOpen() {
        let router = RecordingOpenRequestRouter(hasUsableWindow: true)
        let pending = InMemoryPendingOpenStore()
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: true),
            pendingStore: pending
        )

        coordinator.handleLaunchCompleted()

        #expect(router.actions == [.restoreLastLocation])
    }

    @Test("launch completion does not restore over a pending explicit open")
    func launchCompletionDoesNotRestoreOverPendingOpen() {
        let router = RecordingOpenRequestRouter(hasUsableWindow: true)
        let pending = InMemoryPendingOpenStore()
        pending.store(URL(fileURLWithPath: "/tmp/pending.md"))
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: true),
            pendingStore: pending
        )

        coordinator.handleLaunchCompleted()

        #expect(router.actions.isEmpty)
    }

    @Test("launch completion resets to welcome when restore is disabled")
    func launchCompletionResetsWhenRestoreDisabled() {
        let router = RecordingOpenRequestRouter(hasUsableWindow: true)
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: false),
            pendingStore: InMemoryPendingOpenStore()
        )

        coordinator.handleLaunchCompleted()

        #expect(router.actions == [.resetToWelcome])
    }

    @Test("internal open replaces the active window")
    func internalOpenReplacesActiveWindow() {
        let router = RecordingOpenRequestRouter(hasUsableWindow: true)
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: true),
            pendingStore: InMemoryPendingOpenStore()
        )
        let url = URL(fileURLWithPath: "/tmp/recent.md")

        coordinator.handleInternalOpen(url: url)

        #expect(router.actions == [.replaceActiveWindow(url.markMarkCanonicalFileURL)])
    }

    @Test("internal open without a usable window falls back to the external window path")
    func internalOpenWithoutUsableWindowOpensExternally() {
        let router = RecordingOpenRequestRouter(hasUsableWindow: false)
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: true),
            pendingStore: InMemoryPendingOpenStore()
        )
        let url = URL(fileURLWithPath: "/tmp/recent-no-window.md")

        coordinator.handleInternalOpen(url: url)

        #expect(router.actions == [.openExternalURL(url.markMarkCanonicalFileURL)])
    }


    @Test("service pasteboard accepts both files and folders as external opens")
    func servicePasteboardAcceptsFilesAndFolders() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkMarkServiceOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("service.md")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("# Service".utf8))
        let directoryURL = tempRoot.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkMarkServiceOpen-\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([fileURL as NSURL, directoryURL as NSURL]))

        let router = RecordingOpenRequestRouter(hasUsableWindow: true)
        let coordinator = OpenRequestCoordinator(
            router: router,
            settings: StaticOpenRequestSettings(reopenLastLocation: true),
            pendingStore: InMemoryPendingOpenStore()
        )

        #expect(coordinator.handleServiceOpen(pasteboard: pasteboard, isLaunchCompleted: true))
        #expect(router.actions == [.openExternalURL(fileURL.markMarkCanonicalFileURL), .openExternalURL(directoryURL.markMarkCanonicalFileURL)])
    }


    @Test("pending store canonicalizes symlinked file paths for watchdog comparisons")
    func pendingStoreCanonicalizesSymlinkedFilePaths() throws {
        let suiteName = "MarkMarkTests.PendingCanonical.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tmpURL = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("MarkMarkCanonical-\(UUID().uuidString).md")
        FileManager.default.createFile(atPath: tmpURL.path, contents: Data("# Canonical".utf8))
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let store = UserDefaultsPendingOpenStore(defaults: defaults)
        store.store(tmpURL)

        #expect(store.pendingURL == tmpURL.markMarkCanonicalFileURL)
        #expect(store.pendingURL != nil)
    }

    @Test("UserDefaults pending store keeps file and directory pending keys mutually exclusive")
    func userDefaultsPendingStoreSeparatesFileAndDirectory() throws {
        let suiteName = "MarkMarkTests.PendingOpen.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkMarkPendingOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("note.md")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("# Note".utf8))
        let directoryURL = tempRoot.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let store = UserDefaultsPendingOpenStore(defaults: defaults)

        store.store(fileURL)
        #expect(store.pendingURL == fileURL.markMarkCanonicalFileURL)
        #expect(defaults.string(forKey: "pendingOpenFilePath") == fileURL.markMarkCanonicalFileURL.path)
        #expect(defaults.string(forKey: "pendingOpenDirectoryPath") == nil)

        store.store(directoryURL)
        #expect(store.pendingURL == directoryURL.markMarkCanonicalFileURL)
        #expect(defaults.string(forKey: "pendingOpenFilePath") == nil)
        #expect(defaults.string(forKey: "pendingOpenDirectoryPath") == directoryURL.markMarkCanonicalFileURL.path)

        store.clear()
        #expect(store.pendingURL == nil)
    }
}

@MainActor
private final class RecordingOpenRequestRouter: OpenRequestRouting {
    enum Action: Equatable {
        case openExternalURL(URL)
        case replaceActiveWindow(URL)
        case restoreLastLocation
        case resetToWelcome
    }

    var actions: [Action] = []
    var hasUsableWindow: Bool

    init(hasUsableWindow: Bool) {
        self.hasUsableWindow = hasUsableWindow
    }

    func openExternalURL(_ url: URL) {
        actions.append(.openExternalURL(url))
    }

    func replaceActiveWindow(with url: URL) {
        actions.append(.replaceActiveWindow(url))
    }

    func restoreLastLocation() {
        actions.append(.restoreLastLocation)
    }

    func resetToWelcome() {
        actions.append(.resetToWelcome)
    }
}

private struct StaticOpenRequestSettings: OpenRequestSettingsProviding {
    let reopenLastLocation: Bool
}

private final class InMemoryPendingOpenStore: PendingOpenStoring {
    private(set) var pendingURL: URL?

    func store(_ url: URL) {
        pendingURL = url
    }

    func clear() {
        pendingURL = nil
    }
}
