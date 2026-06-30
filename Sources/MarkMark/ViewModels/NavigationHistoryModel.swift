import Foundation

/// A lightweight, window-local history entry for MarkMark navigation.
///
/// The entry intentionally stores document/tree state instead of WebView URLs:
/// Markdown links can switch the sidebar root, reveal a directory without changing
/// the right-hand document, or upgrade single-file mode into a directory tree.
struct NavigationHistorySnapshot: Equatable, Sendable {
    let isSingleFileMode: Bool
    let rootDirectory: URL?
    let singleFileURL: URL?
    let selectedFileURL: URL?
    let activeNodeURL: URL?

    init(
        isSingleFileMode: Bool,
        rootDirectory: URL?,
        singleFileURL: URL?,
        selectedFileURL: URL?,
        activeNodeURL: URL?
    ) {
        self.isSingleFileMode = isSingleFileMode
        self.rootDirectory = rootDirectory?.markMarkCanonicalFileURL
        self.singleFileURL = singleFileURL?.markMarkCanonicalFileURL
        self.selectedFileURL = selectedFileURL?.markMarkCanonicalFileURL
        self.activeNodeURL = activeNodeURL?.markMarkCanonicalFileURL
    }

    var hasLocation: Bool {
        rootDirectory != nil || singleFileURL != nil || selectedFileURL != nil || activeNodeURL != nil
    }
}

@MainActor
@Observable
final class NavigationHistoryModel {
    private(set) var backStack: [NavigationHistorySnapshot] = []
    private(set) var forwardStack: [NavigationHistorySnapshot] = []
    private(set) var currentSnapshot: NavigationHistorySnapshot?

    private let maximumEntries: Int

    init(maximumEntries: Int = 100) {
        self.maximumEntries = maximumEntries
    }

    var canGoBack: Bool {
        !backStack.isEmpty
    }

    var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    var backTarget: NavigationHistorySnapshot? {
        backStack.last
    }

    var forwardTarget: NavigationHistorySnapshot? {
        forwardStack.last
    }

    func record(_ snapshot: NavigationHistorySnapshot) {
        guard snapshot.hasLocation else {
            clear()
            return
        }

        guard let currentSnapshot else {
            self.currentSnapshot = snapshot
            return
        }

        guard currentSnapshot != snapshot else { return }

        backStack.append(currentSnapshot)
        trimBackStackIfNeeded()
        forwardStack.removeAll()
        self.currentSnapshot = snapshot
    }

    func replaceCurrent(_ snapshot: NavigationHistorySnapshot) {
        currentSnapshot = snapshot.hasLocation ? snapshot : nil
    }

    func clear() {
        backStack.removeAll()
        forwardStack.removeAll()
        currentSnapshot = nil
    }

    func goBack() -> NavigationHistorySnapshot? {
        guard let currentSnapshot, let target = backStack.popLast() else { return nil }
        forwardStack.append(currentSnapshot)
        self.currentSnapshot = target
        return target
    }

    func goForward() -> NavigationHistorySnapshot? {
        guard let currentSnapshot, let target = forwardStack.popLast() else { return nil }
        backStack.append(currentSnapshot)
        trimBackStackIfNeeded()
        self.currentSnapshot = target
        return target
    }

    private func trimBackStackIfNeeded() {
        guard backStack.count > maximumEntries else { return }
        backStack.removeFirst(backStack.count - maximumEntries)
    }
}
