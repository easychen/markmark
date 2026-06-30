import Foundation

/// 目录子节点加载状态。
///
/// 旧的 `children: [FileNode]?` 无法区分「未加载」「加载中」「已加载为空」，
/// 懒加载目录树需要把这些状态显式建模。
indirect enum DirectoryChildrenState: Hashable, Sendable {
    case notLoaded
    case loading
    case loaded([FileNode])
    case failed(String)

    var children: [FileNode]? {
        if case let .loaded(children) = self {
            return children
        }
        return nil
    }

    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

/// 文件/目录节点模型，用于构建目录树。
struct FileNode: Identifiable, Hashable, Sendable {
    let id: URL
    let name: String
    let path: URL
    let isDirectory: Bool
    let isMarkdown: Bool
    var childrenState: DirectoryChildrenState

    var children: [FileNode]? {
        get {
            childrenState.children
        }
        set {
            childrenState = newValue.map { .loaded($0) } ?? .notLoaded
        }
    }

    /// 当前主窗口是否可以直接打开该节点。
    ///
    /// 非 Markdown 文件可在侧边栏展示，但打开时只显示 unsupported 错误，不再作为预览类型处理。
    var isPreviewable: Bool {
        isMarkdown
    }

    init(
        name: String,
        path: URL,
        isDirectory: Bool,
        isMarkdown: Bool = false,
        children: [FileNode]? = nil,
        childrenState: DirectoryChildrenState? = nil
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isMarkdown = isDirectory ? false : isMarkdown
        if isDirectory {
            self.childrenState = childrenState ?? children.map { .loaded($0) } ?? .notLoaded
        } else {
            self.childrenState = .notLoaded
        }
    }

    /// 目录节点的子节点是否已加载（懒加载标记）
    var isChildrenLoaded: Bool {
        childrenState.isLoaded
    }

    var isChildrenLoading: Bool {
        childrenState.isLoading
    }
}
