import Observation
import SwiftUI
import MarkdownReaderKit

typealias DirectoryLevelScanner = @MainActor (
    _ directory: URL,
    _ showHiddenFiles: Bool,
    _ showNonMarkdownFiles: Bool
) async throws -> [FileNode]

/// 目录树视图模型，管理目录树数据和展开/折叠状态
@MainActor
@Observable
final class FileTreeViewModel {

    // MARK: - 状态

    /// 目录树根节点
    var nodes: [FileNode] = []

    /// 已展开的目录 URL 集合
    var expandedDirs: Set<URL> = []

    /// 当前选中的文件 URL
    var selectedFileURL: URL? {
        didSet {
            if let selectedFileURL {
                activeNodeURL = selectedFileURL
            }
        }
    }

    /// 当前键盘/鼠标 active 的节点 URL（目录和文件都可以 active）
    var activeNodeURL: URL?

    /// 是否正在加载
    var isLoading: Bool = false

    /// 错误信息
    var errorMessage: String?

    /// 是否为空目录（无 Markdown 文件）
    var isEmptyDirectory: Bool = false

    /// 当前界面语言（右键菜单对话框使用）
    var language: Language = .en

    // MARK: - 依赖

    @ObservationIgnored private let fileService: FileService

    /// 设置模型（用于读取文件树过滤设置）
    var settings: SettingsModel

    /// 文档视图模型（弱引用，用于协调重命名/删除/移动时的编辑状态）
    weak var documentViewModel: DocumentViewModel?

    /// 文件系统监控器
    @ObservationIgnored private let fileSystemWatcher = FileSystemWatcher()

    /// 是否正在刷新（防止并发刷新）
    @ObservationIgnored private var isRefreshing = false

    /// 是否有待处理的刷新请求
    @ObservationIgnored private var needsRefresh = false

    /// 目录加载世代号。切换根目录或整批刷新时递增，用于丢弃过期异步结果。
    @ObservationIgnored private var directoryLoadGeneration = 0

    /// 每个目录当前有效加载任务的 token，用于避免同一目录的旧异步结果覆盖新状态。
    @ObservationIgnored private var directoryLoadTokens: [URL: UUID] = [:]

    /// 已加载但折叠期间收到变化事件的目录。下次展开时后台刷新，不影响当前可见列表。
    @ObservationIgnored private var staleDirectories: Set<URL> = []

    // MARK: - 初始化

    @ObservationIgnored private let directoryScanner: DirectoryLevelScanner

    init(
        fileService: FileService = FileService(),
        settings: SettingsModel = SettingsModel.shared,
        directoryScanner: DirectoryLevelScanner? = nil
    ) {
        self.fileService = fileService
        self.settings = settings
        self.directoryScanner = directoryScanner ?? { directory, showHiddenFiles, showNonMarkdownFiles in
            try await fileService.scanDirectoryLevel(
                directory,
                showHiddenFiles: showHiddenFiles,
                showNonMarkdownFiles: showNonMarkdownFiles
            )
        }
    }

    // MARK: - 方法

    /// 加载目录树
    /// - Parameter directory: 根目录 URL
    func loadDirectory(_ directory: URL) async {
        let directory = directory.markMarkCanonicalFileURL
        directoryLoadGeneration += 1
        let generation = directoryLoadGeneration
        directoryLoadTokens.removeAll()

        isLoading = false
        errorMessage = nil
        isEmptyDirectory = false
        needsRefresh = false
        isRefreshing = false
        staleDirectories.removeAll()

        // 停止之前的监控
        fileSystemWatcher.stopWatching()

        // 根目录先作为可见节点出现，子节点异步加载。这样首屏不再等待完整递归扫描。
        nodes = [FileNode(
            name: directory.lastPathComponent,
            path: directory,
            isDirectory: true,
            childrenState: .loading
        )]
        expandedDirs = [directory]
        if activeNodeURL == nil {
            activeNodeURL = selectedFileURL ?? directory
        }

        startWatching(directory)
        await loadChildren(for: directory, force: true, generation: generation)
    }

    /// 刷新目录树（由文件系统监控触发，不显示加载状态，保留展开和选中状态）
    @discardableResult
    func refreshDirectory(changedPaths: [URL]? = nil) async -> Bool {
        if isRefreshing {
            // 已有刷新在进行中，标记需要再次刷新
            needsRefresh = true
            return false
        }

        guard let dir = rootDirectory else { return false }

        // 检查根目录是否仍然存在
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            // 根目录已被删除或移动
            clearDirectory()
            errorMessage = "目录已被删除或移动"
            return true
        }

        isRefreshing = true
        var didChange = false

        let directoriesToRefresh = refreshDirectories(for: changedPaths, root: dir)
        for directory in directoriesToRefresh where directoryExists(directory) {
            let directoryDidChange = await loadChildren(for: directory, force: true, showsLoading: false)
            didChange = didChange || directoryDidChange
        }

        // 清理已不存在的展开目录。懒加载后不再用“已加载树包含”判断存在性。
        var refreshedExpandedDirs = expandedDirs.filter { directoryExists($0) }
        refreshedExpandedDirs.insert(dir)
        if refreshedExpandedDirs != expandedDirs {
            expandedDirs = refreshedExpandedDirs
        }
        staleDirectories = staleDirectories.filter { directoryExists($0) }

        // 如果选中的文件已不存在，清除选中。
        // 单文件模式下，选中文件可能不在根目录树中；仅清理当前根目录内的缺失项。
        if let selected = selectedFileURL,
           selected.path.hasPrefix(dir.path + "/"),
           !FileManager.default.fileExists(atPath: selected.path) {
            selectedFileURL = nil
            didChange = true
        }

        if let active = activeNodeURL,
           active.path.hasPrefix(dir.path),
           !FileManager.default.fileExists(atPath: active.path) {
            activeNodeURL = selectedFileURL ?? dir
            didChange = true
        }

        if errorMessage != nil {
            errorMessage = nil
        }
        isRefreshing = false

        // 如果刷新期间有新的变更，再次刷新
        if needsRefresh {
            needsRefresh = false
            Task { @MainActor in
                await refreshDirectory()
            }
        }

        return didChange
    }

    /// 停止文件监控并清空目录树
    /// - Parameter clearSelection: 是否清除选中状态，默认 true。
    ///   切换单文件模式时传 false，避免 selectedFileURL 瞬时 nil 翻转触发 SelectionChangeModifier。
    func clearDirectory(clearSelection: Bool = true) {
        fileSystemWatcher.stopWatching()
        nodes = []
        expandedDirs = []
        if clearSelection {
            selectedFileURL = nil
            activeNodeURL = nil
        }
        errorMessage = nil
        isEmptyDirectory = false
        isRefreshing = false
        needsRefresh = false
        directoryLoadGeneration += 1
        directoryLoadTokens.removeAll()
        staleDirectories.removeAll()
    }

    /// 切换目录展开/折叠
    func toggleExpand(_ url: URL) {
        if expandedDirs.contains(url) {
            collapseDirectory(url)
        } else {
            expandDirectory(url)
        }
    }

    func setExpanded(_ url: URL, expanded: Bool) {
        if expanded {
            expandDirectory(url)
        } else {
            collapseDirectory(url)
        }
    }

    func expandDirectory(_ url: URL) {
        let url = url.markMarkCanonicalFileURL
        expandedDirs.insert(url)
        if staleDirectories.remove(url) != nil {
            Task { @MainActor in
                await loadChildren(for: url, force: true, showsLoading: false)
            }
        } else {
            loadChildrenIfNeeded(for: url)
        }
    }

    func collapseDirectory(_ url: URL) {
        expandedDirs.remove(url.markMarkCanonicalFileURL)
    }

    /// 展开并定位到目录树中的目标目录，只加载 root 到目标之间的祖先链路。
    @discardableResult
    func revealDirectory(_ directory: URL) async -> Bool {
        guard let root = rootDirectory else { return false }
        let rootURL = root.markMarkCanonicalFileURL
        let targetURL = directory.markMarkCanonicalFileURL
        guard MarkdownLinkNavigationPolicy.contains(targetURL, inOrEqualTo: rootURL) else { return false }

        let directories = ancestorDirectories(from: rootURL, to: targetURL)
        for directory in directories {
            expandedDirs.insert(directory)
            await loadChildren(for: directory)
        }
        activeNodeURL = targetURL
        return true
    }

    /// 展开并选中目录树中的目标 Markdown 文件，只加载 root 到父目录之间的祖先链路。
    func revealMarkdownFile(_ fileURL: URL) async {
        _ = await revealFile(fileURL, select: true)
    }

    /// 展开并定位到目录树中的目标文件，只加载 root 到父目录之间的祖先链路。
    /// - Parameter select: true 时同时设置 selectedFileURL 并触发文档打开；false 时只设置 activeNodeURL。
    @discardableResult
    func revealFile(_ fileURL: URL, select: Bool) async -> Bool {
        let targetURL = fileURL.markMarkCanonicalFileURL
        guard await revealDirectory(targetURL.deletingLastPathComponent()) else { return false }
        activeNodeURL = targetURL
        if select {
            selectedFileURL = targetURL
        }
        return true
    }

    /// 展开并定位到目录树中的目标节点。目录只 active；文件可选择是否打开。
    @discardableResult
    func revealNode(_ url: URL, selectFile: Bool = false) async -> Bool {
        let targetURL = url.markMarkCanonicalFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            return false
        }
        if isDirectory.boolValue {
            return await revealDirectory(targetURL)
        }
        return await revealFile(targetURL, select: selectFile)
    }

    /// 判断目录是否已展开
    func isExpanded(_ url: URL) -> Bool {
        expandedDirs.contains(url)
    }

    /// 让节点进入 active 态；文件 active 后会立即选中并打开。
    func activateNode(_ node: FileNode) {
        activeNodeURL = node.path
        if !node.isDirectory {
            selectFile(node)
        }
    }

    /// 选中文件（包括非 .md 文件，以触发错误提示）
    func selectFile(_ node: FileNode) {
        if node.isDirectory { return }
        activeNodeURL = node.path
        selectedFileURL = node.path
    }

    /// 获取扁平化的可见节点列表（用于键盘导航）
    func flattenedVisibleNodes() -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            result.append(node)
            if node.isDirectory, expandedDirs.contains(node.path), let children = node.children {
                result.append(contentsOf: flattenChildren(children))
            }
        }
        return result
    }

    /// 在扁平列表中移动 active 项；移动到文件时立即打开，移动到目录时只更新 active 态。
    func moveSelection(direction: Int) -> FileNode? {
        let flat = flattenedVisibleNodes()
        guard !flat.isEmpty else { return nil }

        let currentIndex: Int
        if let currentURL = activeNodeURL ?? selectedFileURL,
           let idx = flat.firstIndex(where: { $0.path == currentURL }) {
            currentIndex = idx
        } else {
            currentIndex = -1
        }

        let newIndex = max(0, min(flat.count - 1, currentIndex + direction))
        let node = flat[newIndex]
        activateNode(node)

        return node
    }

    /// 展开 active 目录。文件 active 时不处理。
    func expandActiveNode() {
        guard let node = activeNode() else { return }
        if node.isDirectory {
            expandDirectory(node.path)
        }
    }

    /// 收起 active 目录；若目录已收起或 active 为文件，则移动到父目录。
    func collapseActiveNodeOrMoveToParent() {
        guard let node = activeNode() else { return }
        if node.isDirectory, expandedDirs.contains(node.path) {
            expandedDirs.remove(node.path)
            return
        }
        if let parent = parentDirectoryNode(for: node.path) {
            activeNodeURL = parent.path
        }
    }

    /// 按需加载目录的一层子节点。
    private func loadChildrenIfNeeded(for directory: URL) {
        guard let node = findNode(in: nodes, url: directory), node.isDirectory else { return }
        switch node.childrenState {
        case .notLoaded, .failed:
            Task { @MainActor in
                await loadChildren(for: directory)
            }
        case .loading, .loaded:
            break
        }
    }

    /// 加载指定目录的一层内容，并保留已加载子目录的状态。
    @discardableResult
    private func loadChildren(
        for directory: URL,
        force: Bool = false,
        generation: Int? = nil,
        showsLoading: Bool = true
    ) async -> Bool {
        guard let node = findNode(in: nodes, url: directory), node.isDirectory else { return false }
        if !force {
            switch node.childrenState {
            case .loading, .loaded:
                return false
            case .notLoaded, .failed:
                break
            }
        }

        let previousState = node.childrenState
        let shouldShowLoading = showsLoading || !previousState.isLoaded
        let expectedGeneration = generation ?? directoryLoadGeneration
        let loadToken = UUID()
        directoryLoadTokens[directory] = loadToken
        if shouldShowLoading {
            setDirectoryChildrenState(for: directory, to: .loading)
        }

        do {
            var children = try await directoryScanner(
                directory,
                settings.showHiddenFiles,
                settings.showNonMarkdownFiles
            )
            guard expectedGeneration == directoryLoadGeneration,
                  directoryLoadTokens[directory] == loadToken else { return false }

            // 扫描期间其他目录可能已经完成加载；用最新状态合并，避免刷新覆盖展开结果。
            let currentStates = directoryChildrenStateByPath(from: nodes)
            preserveDirectoryStates(in: &children, using: currentStates)
            let newState = DirectoryChildrenState.loaded(children)
            let currentState = findNode(in: nodes, url: directory)?.childrenState
            let didChange = currentState != newState
            if didChange {
                setDirectoryChildrenState(for: directory, to: newState)
            }
            directoryLoadTokens[directory] = nil
            staleDirectories.remove(directory)
            if directory == rootDirectory {
                if isEmptyDirectory != children.isEmpty {
                    isEmptyDirectory = children.isEmpty
                }
                if errorMessage != nil {
                    errorMessage = nil
                }
            }
            return didChange
        } catch {
            guard expectedGeneration == directoryLoadGeneration,
                  directoryLoadTokens[directory] == loadToken else { return false }

            let message = error.localizedDescription
            var didChange = false
            if shouldShowLoading {
                let failedState = DirectoryChildrenState.failed(message)
                if findNode(in: nodes, url: directory)?.childrenState != failedState {
                    setDirectoryChildrenState(for: directory, to: failedState)
                    didChange = true
                }
            }
            directoryLoadTokens[directory] = nil
            if directory == rootDirectory {
                if shouldShowLoading {
                    errorMessage = message
                }
                isEmptyDirectory = false
            }
            return didChange
        }
    }

    private func activeNode() -> FileNode? {
        guard let url = activeNodeURL ?? selectedFileURL else { return nil }
        return findNode(in: nodes, url: url)
    }

    private func parentDirectoryNode(for url: URL) -> FileNode? {
        let parentURL = url.deletingLastPathComponent()
        return findNode(in: nodes, url: parentURL).flatMap { $0.isDirectory ? $0 : nil }
    }

    private func findNode(in nodes: [FileNode], url: URL) -> FileNode? {
        for node in nodes {
            if node.path == url { return node }
            if let children = node.children, let found = findNode(in: children, url: url) {
                return found
            }
        }
        return nil
    }

    // MARK: - 新建文件

    /// 在指定目录下创建新的 Markdown 文件
    /// - Parameter directory: 目标目录 URL，若为 nil 则使用根目录
    /// - Returns: 新建文件的 URL，失败返回 nil
    func createNewFile(in directory: URL? = nil) -> URL? {
        let targetDir = directory ?? rootDirectory
        guard let dir = targetDir else { return nil }

        // 生成不重名的文件名
        var fileName = "Untitled.md"
        var fileURL = dir.appendingPathComponent(fileName)
        var counter = 1
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileName = "Untitled \(counter).md"
            fileURL = dir.appendingPathComponent(fileName)
            counter += 1
        }

        // 创建空文件
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            return nil
        }

        // 刷新目标目录的一层内容即可，避免整棵树重扫。
        Task {
            expandedDirs.insert(dir)
            await loadChildren(for: dir, force: true)
            selectedFileURL = fileURL
        }

        return fileURL
    }

    /// 根目录 URL（供外部访问）
    var rootDirectory: URL? {
        nodes.first?.path
    }

    // MARK: - 文件监控

    /// 开始监控目录变化
    private func startWatching(_ directory: URL) {
        fileSystemWatcher.startWatching(url: directory) { [weak self] changedPaths in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshDirectory(changedPaths: changedPaths)
            }
        }
    }

    /// 收集所有节点路径（用于清理展开状态和选中状态）
    private func collectAllPaths(from nodes: [FileNode]) -> [URL] {
        var paths: [URL] = []
        for node in nodes {
            paths.append(node.path)
            if let children = node.children {
                paths.append(contentsOf: collectAllPaths(from: children))
            }
        }
        return paths
    }

    // MARK: - 私有方法

    private func loadedDirectoryPaths(from nodes: [FileNode]) -> [URL] {
        var paths: [URL] = []
        for node in nodes where node.isDirectory {
            if node.isChildrenLoaded || node.path == rootDirectory {
                paths.append(node.path)
            }
            if let children = node.children {
                paths.append(contentsOf: loadedDirectoryPaths(from: children))
            }
        }
        return paths
    }

    private func refreshDirectories(for changedPaths: [URL]?, root: URL) -> [URL] {
        guard let changedPaths, !changedPaths.isEmpty else {
            return visibleLoadedDirectoryPaths(from: nodes, root: root)
        }

        let loadedDirectories = Set(loadedDirectoryPaths(from: nodes))
        var refreshDirectories = Set<URL>()

        for changedPath in changedPaths {
            let changedURL = changedPath.markMarkCanonicalFileURL
            if changedURL == root {
                refreshDirectories.insert(root)
                continue
            }

            let parent = changedURL.deletingLastPathComponent().markMarkCanonicalFileURL
            guard MarkdownLinkNavigationPolicy.contains(parent, inOrEqualTo: root) else {
                continue
            }

            if parent == root || expandedDirs.contains(parent) {
                refreshDirectories.insert(parent)
            } else if loadedDirectories.contains(parent),
                      findNode(in: nodes, url: parent)?.childrenState.isLoaded == true {
                staleDirectories.insert(parent)
            }
        }

        return refreshDirectories.sorted { lhs, rhs in
            lhs.pathComponents.count == rhs.pathComponents.count
                ? lhs.path < rhs.path
                : lhs.pathComponents.count < rhs.pathComponents.count
        }
    }

    private func visibleLoadedDirectoryPaths(from nodes: [FileNode], root: URL) -> [URL] {
        loadedDirectoryPaths(from: nodes)
            .filter { $0 == root || expandedDirs.contains($0) }
            .sorted { lhs, rhs in
                lhs.pathComponents.count == rhs.pathComponents.count
                    ? lhs.path < rhs.path
                    : lhs.pathComponents.count < rhs.pathComponents.count
            }
    }

    private func directoryChildrenStateByPath(from nodes: [FileNode]) -> [URL: DirectoryChildrenState] {
        var states: [URL: DirectoryChildrenState] = [:]
        collectDirectoryChildrenStates(from: nodes, into: &states)
        return states
    }

    private func collectDirectoryChildrenStates(
        from nodes: [FileNode],
        into states: inout [URL: DirectoryChildrenState]
    ) {
        for node in nodes where node.isDirectory {
            states[node.path] = node.childrenState
            if let children = node.children {
                collectDirectoryChildrenStates(from: children, into: &states)
            }
        }
    }

    private func preserveDirectoryStates(
        in children: inout [FileNode],
        using states: [URL: DirectoryChildrenState]
    ) {
        for index in children.indices where children[index].isDirectory {
            if let previousState = states[children[index].path] {
                children[index].childrenState = previousState
            }
        }
    }

    private func setDirectoryChildrenState(for directory: URL, to state: DirectoryChildrenState) {
        updateNode(directory) { node in
            guard node.isDirectory else { return }
            node.childrenState = state
        }
    }

    private func updateNode(_ url: URL, transform: (inout FileNode) -> Void) {
        updateNode(in: &nodes, url: url, transform: transform)
    }

    @discardableResult
    private func updateNode(
        in nodes: inout [FileNode],
        url: URL,
        transform: (inout FileNode) -> Void
    ) -> Bool {
        for index in nodes.indices {
            if nodes[index].path == url {
                transform(&nodes[index])
                return true
            }
            if var children = nodes[index].children,
               updateNode(in: &children, url: url, transform: transform) {
                nodes[index].children = children
                return true
            }
        }
        return false
    }

    private func directoryExists(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func ancestorDirectories(from root: URL, to target: URL) -> [URL] {
        let rootURL = root.markMarkCanonicalFileURL
        let targetURL = target.markMarkCanonicalFileURL
        guard MarkdownLinkNavigationPolicy.contains(targetURL, inOrEqualTo: rootURL) else { return [] }

        let rootComponents = rootURL.pathComponents
        let targetComponents = targetURL.pathComponents
        let relativeComponents = targetComponents.dropFirst(rootComponents.count)

        var result = [rootURL]
        var current = rootURL
        for component in relativeComponents {
            current = current.appendingPathComponent(component, isDirectory: true).markMarkCanonicalFileURL
            result.append(current)
        }
        return result
    }

    private func flattenChildren(_ children: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in children {
            result.append(node)
            if node.isDirectory, expandedDirs.contains(node.path), let subChildren = node.children {
                result.append(contentsOf: flattenChildren(subChildren))
            }
        }
        return result
    }

    // MARK: - 右键菜单操作

    /// 在指定目录下新建 Markdown 文件（右键菜单用，与工具栏逻辑一致）
    /// - Parameter directory: 目标目录 URL
    func createNewFileInDirectory(_ directory: URL) {
        _ = createNewFile(in: directory)
    }

    /// 在指定目录下新建子目录
    /// - Parameter parentDirectory: 父目录 URL
    func createSubdirectory(in parentDirectory: URL) {
        // 生成不重名的目录名
        var dirName = "New Folder"
        var dirURL = parentDirectory.appendingPathComponent(dirName)
        var counter = 1
        while FileManager.default.fileExists(atPath: dirURL.path) {
            dirName = "New Folder \(counter)"
            dirURL = parentDirectory.appendingPathComponent(dirName)
            counter += 1
        }

        do {
            try fileService.createDirectory(in: parentDirectory, name: dirName)
            Task {
                expandedDirs.insert(parentDirectory)
                await loadChildren(for: parentDirectory, force: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 重命名文件或目录
    /// - Parameter node: 要重命名的节点
    func renameItem(_ node: FileNode) {
        let alert = NSAlert()
        alert.messageText = L10n.tr(.renameTitle, language: language)
        alert.informativeText = L10n.tr(.renameMessage, language: language, args: ["name": node.name])
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = node.name
        // 如果是文件，选中不含扩展名的部分
        if !node.isDirectory {
            let nameWithoutExt = node.name.replacingOccurrences(
                of: ".\(node.path.pathExtension)",
                with: "",
                options: .anchored
            )
            let extRange = NSRange(location: 0, length: nameWithoutExt.utf16.count)
            // 延迟选中文件名（不含扩展名），确保文本框已准备好
            DispatchQueue.main.async {
                if let editor = textField.currentEditor() {
                    editor.selectedRange = extRange
                }
            }
        }
        alert.accessoryView = textField

        alert.addButton(withTitle: L10n.tr(.confirm, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        // 确保 NSAlert 在前台
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else { return }

        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            showError(L10n.tr(.renameEmptyName, language: language))
            return
        }
        guard newName != node.name else { return }

        // 检查同名项是否已存在
        let newURL = node.path.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: newURL.path) {
            showError(L10n.tr(.renameNameExists, language: language))
            return
        }

        do {
            let renamedURL = try fileService.renameItem(at: node.path, to: newName)
            // 更新 DocumentViewModel 的引用
            if let docVM = documentViewModel {
                docVM.handleFileRenamed(from: node.path, to: renamedURL)
            }
            // 更新选中状态
            if selectedFileURL == node.path {
                selectedFileURL = renamedURL
            }
            // 更新展开状态
            if node.isDirectory {
                if expandedDirs.contains(node.path) {
                    expandedDirs.remove(node.path)
                    expandedDirs.insert(renamedURL)
                }
            }
            Task {
                await refreshDirectory()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 删除文件或目录（移到废纸篓）
    /// - Parameter node: 要删除的节点
    func deleteItem(_ node: FileNode) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        if node.isDirectory {
            alert.messageText = L10n.tr(.deleteTitle, language: language)
            alert.informativeText = L10n.tr(.deleteDirectoryMessage, language: language, args: ["name": node.name])
        } else {
            alert.messageText = L10n.tr(.deleteTitle, language: language)
            alert.informativeText = L10n.tr(.deleteMessage, language: language, args: ["name": node.name])
        }

        alert.addButton(withTitle: L10n.tr(.contextMenuDelete, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else { return }

        do {
            // 如果删除的是当前正在编辑的文件，先保存或清理编辑状态
            if let docVM = documentViewModel {
                docVM.handleFileDeleted(at: node.path)
            }
            try fileService.trashItem(at: node.path)
            // 清除选中状态
            if selectedFileURL == node.path || (node.isDirectory && selectedFileURL?.path.hasPrefix(node.path.path + "/") == true) {
                selectedFileURL = nil
            }
            // 清除展开状态
            if node.isDirectory {
                expandedDirs = expandedDirs.filter { !$0.path.hasPrefix(node.path.path + "/") && $0 != node.path }
            }
            Task {
                await refreshDirectory()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 移动文件或目录到其他位置
    /// - Parameter node: 要移动的节点
    func moveItem(_ node: FileNode) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr(.moveSelectFolder, language: language)
        panel.directoryURL = rootDirectory

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        // 不能移动到自身或自身子目录
        if destination.path.hasPrefix(node.path.path) {
            return
        }
        // 检查目标位置是否已存在同名项
        let destinationPath = destination.appendingPathComponent(node.name)
        if FileManager.default.fileExists(atPath: destinationPath.path) {
            showError(L10n.tr(.renameNameExists, language: language))
            return
        }

        do {
            let movedURL = try fileService.moveItem(at: node.path, to: destination)
            // 更新 DocumentViewModel 的引用
            if let docVM = documentViewModel {
                docVM.handleFileMoved(from: node.path, to: movedURL)
            }
            // 更新选中状态
            if selectedFileURL == node.path {
                selectedFileURL = movedURL
            }
            // 清理展开状态中的旧路径
            if node.isDirectory {
                let oldExpanded = expandedDirs.filter { $0.path.hasPrefix(node.path.path) }
                for oldURL in oldExpanded {
                    expandedDirs.remove(oldURL)
                    let relativePath = oldURL.path.replacingOccurrences(of: node.path.path, with: movedURL.path)
                    expandedDirs.insert(URL(fileURLWithPath: relativePath))
                }
            }
            Task {
                await refreshDirectory()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 显示错误提示
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
