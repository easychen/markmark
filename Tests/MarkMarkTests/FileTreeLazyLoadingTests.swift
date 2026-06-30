import Foundation
import Observation
import Testing
@testable import MarkMark

@MainActor
@Suite("File tree lazy loading")
struct FileTreeLazyLoadingTests {

    @Test("scanDirectoryLevel is shallow and only marks Markdown as previewable")
    func scanDirectoryLevelIsShallowAndMarkdownOnly() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let childDir = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: false)
        try "# Root".write(to: root.appendingPathComponent("root.md"), atomically: true, encoding: .utf8)
        try "# Nested".write(to: childDir.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)
        try "{\"ok\":true}".write(to: root.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
        try "plain text".write(to: root.appendingPathComponent("unknown.foo"), atomically: true, encoding: .utf8)

        let fileService = FileService()
        let filteredNodes = try await fileService.scanDirectoryLevel(
            root,
            showHiddenFiles: false,
            showNonMarkdownFiles: false
        )

        #expect(filteredNodes.map(\.name) == ["child", "root.md"])
        let filteredChild = try #require(filteredNodes.first)
        #expect(filteredChild.isDirectory)
        #expect(!filteredChild.isChildrenLoaded)

        let allNodes = try await fileService.scanDirectoryLevel(
            root,
            showHiddenFiles: false,
            showNonMarkdownFiles: true
        )
        let markdownNode = try #require(allNodes.first { $0.name == "root.md" })
        #expect(markdownNode.isPreviewable)

        let jsonNode = try #require(allNodes.first { $0.name == "data.json" })
        #expect(!jsonNode.isPreviewable)

        let unknownNode = try #require(allNodes.first { $0.name == "unknown.foo" })
        #expect(!unknownNode.isPreviewable)
    }

    @Test("FileTreeViewModel loads root immediately and expands children on demand")
    func fileTreeViewModelLoadsChildrenOnDemand() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let childDir = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: false)
        try "# Root".write(to: root.appendingPathComponent("root.md"), atomically: true, encoding: .utf8)
        try "# Nested".write(to: childDir.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)

        let settings = SettingsModel()
        settings.showHiddenFiles = false
        settings.showNonMarkdownFiles = true
        let viewModel = FileTreeViewModel(settings: settings)

        await viewModel.loadDirectory(root)

        let rootNode = try #require(viewModel.nodes.first)
        #expect(rootNode.path == root)
        #expect(rootNode.isChildrenLoaded)
        #expect(viewModel.isExpanded(root))

        let childNode = try #require(rootNode.children?.first { $0.name == "child" })
        #expect(childNode.isDirectory)
        #expect(!childNode.isChildrenLoaded)
        #expect(childNode.children == nil)

        let loadedChildURL = childNode.path
        viewModel.expandDirectory(loadedChildURL)
        try await waitUntilLoaded(in: viewModel, url: loadedChildURL)

        let loadedChild = try #require(findNode(in: viewModel.nodes, url: loadedChildURL))
        #expect(loadedChild.isChildrenLoaded)
        #expect(loadedChild.children?.map(\.name) == ["nested.md"])
    }

    @Test("revealMarkdownFile loads only the ancestor chain")
    func revealMarkdownFileLoadsOnlyAncestorChain() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let targetDir = root
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
        let unrelatedDir = root.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelatedDir, withIntermediateDirectories: true)
        let target = targetDir.appendingPathComponent("target.md")
        try "# Target".write(to: target, atomically: true, encoding: .utf8)
        try "# Other".write(to: unrelatedDir.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)

        let settings = SettingsModel()
        settings.showHiddenFiles = false
        settings.showNonMarkdownFiles = true
        let viewModel = FileTreeViewModel(settings: settings)

        await viewModel.loadDirectory(root)
        await viewModel.revealMarkdownFile(target)

        let aNode = try #require(findNode(in: viewModel.nodes, url: root.appendingPathComponent("a", isDirectory: true)))
        let bNode = try #require(findNode(in: viewModel.nodes, url: targetDir))
        let unrelatedNode = try #require(findNode(in: viewModel.nodes, url: unrelatedDir))

        #expect(aNode.isChildrenLoaded)
        #expect(bNode.isChildrenLoaded)
        #expect(!unrelatedNode.isChildrenLoaded)
        #expect(viewModel.isExpanded(root))
        #expect(viewModel.isExpanded(aNode.path))
        #expect(viewModel.isExpanded(bNode.path))
        #expect(viewModel.activeNodeURL == target.markMarkCanonicalFileURL)
        #expect(viewModel.selectedFileURL == target.markMarkCanonicalFileURL)
    }

    @Test("revealDirectory activates a directory without selecting a file")
    func revealDirectoryActivatesDirectoryWithoutSelectingFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let targetDir = root
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let viewModel = FileTreeViewModel(settings: SettingsModel())
        await viewModel.loadDirectory(root)

        let didReveal = await viewModel.revealDirectory(targetDir)

        #expect(didReveal)
        #expect(viewModel.activeNodeURL == targetDir.markMarkCanonicalFileURL)
        #expect(viewModel.selectedFileURL == nil)
        #expect(viewModel.isExpanded(root))
        #expect(viewModel.isExpanded(root.appendingPathComponent("a", isDirectory: true).markMarkCanonicalFileURL))
        #expect(viewModel.isExpanded(targetDir.markMarkCanonicalFileURL))
    }

    @Test("revealMarkdownFile ignores files outside the current root")
    func revealMarkdownFileIgnoresFilesOutsideRoot() async throws {
        let root = try makeTemporaryDirectory()
        let outsideRoot = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let outsideFile = outsideRoot.appendingPathComponent("outside.md")
        try "# Outside".write(to: outsideFile, atomically: true, encoding: .utf8)

        let viewModel = FileTreeViewModel(settings: SettingsModel())
        await viewModel.loadDirectory(root)
        await viewModel.revealMarkdownFile(outsideFile)

        #expect(viewModel.activeNodeURL == root.markMarkCanonicalFileURL)
        #expect(viewModel.selectedFileURL == nil)
    }

    @Test("background refresh keeps loaded children visible while scanning")
    func backgroundRefreshKeepsLoadedChildrenVisibleWhileScanning() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = ControlledDirectoryScanner()
        let viewModel = FileTreeViewModel(settings: SettingsModel(), directoryScanner: scanner.scan)
        let oldFile = root.appendingPathComponent("old.md")
        scanner.enqueue(nodes: [fileNode(oldFile)])

        await viewModel.loadDirectory(root)
        #expect(rootChildren(in: viewModel)?.map(\.name) == ["old.md"])

        let refreshTask = Task { @MainActor in
            await viewModel.refreshDirectory(changedPaths: [oldFile])
        }
        await scanner.waitForPendingScanCount(1)

        let rootNodeDuringRefresh = try #require(findNode(in: viewModel.nodes, url: root))
        #expect(rootNodeDuringRefresh.childrenState.isLoaded)
        #expect(rootNodeDuringRefresh.children?.map { $0.name } == ["old.md"])

        scanner.completeNextScan(with: [fileNode(oldFile)])
        let didChange = await refreshTask.value

        #expect(!didChange)
        #expect(rootChildren(in: viewModel)?.map(\.name) == ["old.md"])
    }

    @Test("unchanged background refresh does not notify visible tree observers")
    func unchangedBackgroundRefreshDoesNotNotifyVisibleTreeObservers() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let scanner = ControlledDirectoryScanner()
        let viewModel = FileTreeViewModel(settings: SettingsModel(), directoryScanner: scanner.scan)
        let file = root.appendingPathComponent("same.md")
        scanner.enqueue(nodes: [fileNode(file)])
        scanner.enqueue(nodes: [fileNode(file)])

        await viewModel.loadDirectory(root)

        let visibleTreeChanges = ObservationCounter()
        withObservationTracking {
            _ = viewModel.nodes
            _ = viewModel.expandedDirs
            _ = viewModel.selectedFileURL
            _ = viewModel.activeNodeURL
            _ = viewModel.isLoading
            _ = viewModel.errorMessage
            _ = viewModel.isEmptyDirectory
        } onChange: {
            visibleTreeChanges.increment()
        }

        let didChange = await viewModel.refreshDirectory(changedPaths: [file])

        #expect(!didChange)
        #expect(visibleTreeChanges.value == 0)
    }

    @Test("background refresh ignores changes below an unexpanded directory")
    func backgroundRefreshIgnoresUnexpandedSubdirectoryChanges() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let childDir = root.appendingPathComponent("child", isDirectory: true)
        let nestedFile = childDir.appendingPathComponent("nested.md")
        let rootFile = root.appendingPathComponent("root.md")

        let scanner = ControlledDirectoryScanner()
        let viewModel = FileTreeViewModel(settings: SettingsModel(), directoryScanner: scanner.scan)
        scanner.enqueue(nodes: [
            directoryNode(childDir),
            fileNode(rootFile)
        ])

        await viewModel.loadDirectory(root)

        let didChange = await viewModel.refreshDirectory(changedPaths: [nestedFile])

        #expect(!didChange)
        #expect(scanner.scannedDirectories == [root])
        #expect(rootChildren(in: viewModel)?.map(\.name) == ["child", "root.md"])
    }

    @Test("background refresh updates only the expanded parent with direct child changes")
    func backgroundRefreshUpdatesOnlyExpandedParentWithDirectChildChanges() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let childDir = root.appendingPathComponent("child", isDirectory: true)
        let nestedFile = childDir.appendingPathComponent("nested.md")
        let addedFile = childDir.appendingPathComponent("added.md")
        let rootFile = root.appendingPathComponent("root.md")
        try FileManager.default.createDirectory(at: childDir, withIntermediateDirectories: true)

        let scanner = ControlledDirectoryScanner()
        let viewModel = FileTreeViewModel(settings: SettingsModel(), directoryScanner: scanner.scan)
        scanner.enqueue(nodes: [
            directoryNode(childDir),
            fileNode(rootFile)
        ])
        scanner.enqueue(nodes: [fileNode(nestedFile)], for: childDir)
        scanner.enqueue(nodes: [fileNode(addedFile), fileNode(nestedFile)], for: childDir)

        await viewModel.loadDirectory(root)
        viewModel.expandDirectory(childDir)
        try await waitUntilLoaded(in: viewModel, url: childDir)

        let didChange = await viewModel.refreshDirectory(changedPaths: [addedFile])

        #expect(didChange)
        #expect(scanner.scannedDirectories == [root, childDir, childDir])
        #expect(rootChildren(in: viewModel)?.map(\.name) == ["child", "root.md"])
        #expect(findNode(in: viewModel.nodes, url: childDir)?.children?.map(\.name) == ["added.md", "nested.md"])
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkMarkLazyTreeTests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.markMarkCanonicalFileURL
}

@MainActor
private final class ControlledDirectoryScanner {
    private var queuedNodesByDirectory: [URL?: [[FileNode]]] = [:]
    private var continuations: [CheckedContinuation<[FileNode], Error>] = []

    private(set) var scannedDirectories: [URL] = []

    func enqueue(nodes: [FileNode], for directory: URL? = nil) {
        queuedNodesByDirectory[directory?.markMarkCanonicalFileURL, default: []].append(nodes)
    }

    func scan(
        directory: URL,
        showHiddenFiles: Bool,
        showNonMarkdownFiles: Bool
    ) async throws -> [FileNode] {
        let canonicalDirectory = directory.markMarkCanonicalFileURL
        scannedDirectories.append(canonicalDirectory)

        if var queued = queuedNodesByDirectory[canonicalDirectory], !queued.isEmpty {
            let nodes = queued.removeFirst()
            queuedNodesByDirectory[canonicalDirectory] = queued
            return nodes
        }

        if var queued = queuedNodesByDirectory[nil], !queued.isEmpty {
            let nodes = queued.removeFirst()
            queuedNodesByDirectory[nil] = queued
            return nodes
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func completeNextScan(with nodes: [FileNode]) {
        guard !continuations.isEmpty else {
            Issue.record("No pending scan to complete")
            return
        }
        continuations.removeFirst().resume(returning: nodes)
    }

    func waitForPendingScanCount(_ count: Int) async {
        for _ in 0..<50 {
            if continuations.count >= count {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for pending scan count \(count)")
    }
}

private func fileNode(_ url: URL) -> FileNode {
    FileNode(
        name: url.lastPathComponent,
        path: url.markMarkCanonicalFileURL,
        isDirectory: false,
        isMarkdown: FileService.isTreeDisplayExtension(url)
    )
}

private func directoryNode(_ url: URL, childrenState: DirectoryChildrenState = .notLoaded) -> FileNode {
    FileNode(
        name: url.lastPathComponent,
        path: url.markMarkCanonicalFileURL,
        isDirectory: true,
        childrenState: childrenState
    )
}

@MainActor
private func rootChildren(in viewModel: FileTreeViewModel) -> [FileNode]? {
    viewModel.nodes.first?.children
}

private final class ObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.withLock { _value }
    }

    func increment() {
        lock.withLock {
            _value += 1
        }
    }
}

@MainActor
private func waitUntilLoaded(in viewModel: FileTreeViewModel, url: URL) async throws {
    for _ in 0..<50 {
        if findNode(in: viewModel.nodes, url: url)?.isChildrenLoaded == true {
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    Issue.record("Timed out waiting for directory to load: \(url.path)")
}

private func findNode(in nodes: [FileNode], url: URL) -> FileNode? {
    for node in nodes {
        if node.path == url { return node }
        if let children = node.children,
           let found = findNode(in: children, url: url) {
            return found
        }
    }
    return nil
}
