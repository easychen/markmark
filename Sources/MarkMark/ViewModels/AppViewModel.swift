import SwiftUI
import MarkdownReaderKit

/// 设置标签页，供 AppViewModel 和 ContentView 使用
enum SettingsTab: String, CaseIterable {
    case general
    case appearance
}

/// 全局应用状态，管理窗口级别的状态
@MainActor
@Observable
final class AppViewModel {

    // MARK: - 目录状态

    /// 当前打开的根目录
    var rootDirectory: URL? {
        didSet { updateWindowTitle() }
    }

    /// 是否为单文件模式（直接打开单个文件，无目录树）
    var isSingleFileMode: Bool = false

    /// 单文件模式下打开的文件 URL
    var singleFileURL: URL?

    // MARK: - 选中状态

    /// 当前选中的文件节点
    var selectedFile: FileNode?

    // MARK: - Sidebar 状态

    /// Sidebar 是否可见（首次启动默认隐藏）
    var isSidebarVisible: Bool = false

    /// Sidebar 当前宽度
    var sidebarWidth: CGFloat = 240

    /// Sidebar 默认宽度
    static let defaultSidebarWidth: CGFloat = 240

    /// Sidebar 最小宽度
    static let minSidebarWidth: CGFloat = 150

    /// Sidebar 最大宽度
    static let maxSidebarWidth: CGFloat = 400

    /// Sidebar 自动隐藏阈值
    static let sidebarHideThreshold: CGFloat = 140

    // MARK: - 大纲状态

    /// 大纲侧边栏是否可见
    var isOutlineVisible: Bool = false

    /// 大纲侧边栏宽度
    var outlineWidth: CGFloat = 200

    /// 大纲侧边栏默认宽度
    static let defaultOutlineWidth: CGFloat = 200

    /// 大纲侧边栏最小宽度
    static let minOutlineWidth: CGFloat = 150

    /// 大纲侧边栏最大宽度
    static let maxOutlineWidth: CGFloat = 350

    /// 标注列表面板是否可见（与大纲面板互斥，共用宽度与拖拽手柄）
    var isAnnotationPanelVisible: Bool = false

    // MARK: - 设置状态

    /// 是否显示设置界面（窗口内状态切换，而非弹窗）
    var isShowingSettings: Bool = false

    /// 设置界面的当前标签页
    var settingsTab: SettingsTab = .general

    // MARK: - 窗口标题

    /// 窗口标题
    var windowTitle: String = "MarkMark"

    // MARK: - 全屏状态

    /// 是否处于全屏模式
    var isFullScreen: Bool = false

    // MARK: - 查找替换状态

    /// 查找面板是否可见
    var isFindBarVisible: Bool = false

    // MARK: - 方法

    /// 切换 Sidebar 显隐
    func toggleSidebar() {
        withAnimation(.spring(duration: 0.25)) {
            isSidebarVisible.toggle()
            if isSidebarVisible {
                sidebarWidth = Self.defaultSidebarWidth
            }
        }
    }

    /// 切换大纲侧边栏显隐
    func toggleOutline() {
        withAnimation(.spring(duration: 0.25)) {
            isOutlineVisible.toggle()
            if isOutlineVisible {
                isAnnotationPanelVisible = false
                outlineWidth = Self.defaultOutlineWidth
            }
        }
    }

    /// 应用用户记住的窗口 chrome 状态。用于恢复上次打开位置，不表示用户本次主动切换。
    func applyRememberedChromeState(sidebarVisible: Bool, outlineVisible: Bool) {
        isSidebarVisible = sidebarVisible
        if sidebarVisible {
            sidebarWidth = Self.defaultSidebarWidth
        }

        isOutlineVisible = outlineVisible
        if outlineVisible {
            isAnnotationPanelVisible = false
            outlineWidth = Self.defaultOutlineWidth
        }
    }

    /// 切换标注列表面板显隐（与大纲互斥）
    func toggleAnnotationPanel() {
        withAnimation(.spring(duration: 0.25)) {
            isAnnotationPanelVisible.toggle()
            if isAnnotationPanelVisible {
                isOutlineVisible = false
                outlineWidth = Self.defaultOutlineWidth
            }
        }
    }

    /// 切换查找面板显隐
    func toggleFindBar(expandReplace: Bool = false) {
        withAnimation(.easeOut(duration: 0.2)) {
            isFindBarVisible.toggle()
        }
    }

    /// 显示查找面板
    func showFindBar(expandReplace: Bool = false) {
        withAnimation(.easeOut(duration: 0.2)) {
            isFindBarVisible = true
        }
    }

    /// 隐藏查找面板
    func hideFindBar() {
        withAnimation(.easeOut(duration: 0.2)) {
            isFindBarVisible = false
        }
    }

    /// 进入设置界面
    func showSettings(tab: SettingsTab = .general) {
        settingsTab = tab
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingSettings = true
        }
    }

    /// 退出设置界面
    func hideSettings() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingSettings = false
        }
    }

    /// 切换设置界面（Cmd+, 快捷键使用）
    func toggleSettings() {
        if isShowingSettings {
            hideSettings()
        } else {
            showSettings()
        }
    }

    /// 更新 Sidebar 宽度（拖拽时调用）
    func updateSidebarWidth(_ width: CGFloat) {
        sidebarWidth = width
    }

    /// 处理拖拽结束，判断是否隐藏 Sidebar
    func handleDragEnded() {
        if sidebarWidth < Self.sidebarHideThreshold {
            withAnimation(.spring(duration: 0.25)) {
                isSidebarVisible = false
                sidebarWidth = Self.defaultSidebarWidth
            }
        } else {
            // 限制宽度范围
            sidebarWidth = max(Self.minSidebarWidth, min(Self.maxSidebarWidth, sidebarWidth))
        }
    }

    /// 更新大纲侧边栏宽度（拖拽时调用）
    func updateOutlineWidth(_ width: CGFloat) {
        outlineWidth = width
    }

    /// 处理大纲侧边栏拖拽结束，限制宽度范围
    func handleOutlineDragEnded() {
        outlineWidth = max(Self.minOutlineWidth, min(Self.maxOutlineWidth, outlineWidth))
    }

    /// 打开目录
    func openDirectory(_ url: URL, sidebarVisible: Bool = true) {
        rootDirectory = url
        isSingleFileMode = false
        singleFileURL = nil
        selectedFile = nil
        if sidebarVisible {
            // 目录模式默认恢复 Sidebar；恢复上次位置时可传入用户记住的状态覆盖默认值。
            guard !isSidebarVisible else { return }
            withAnimation(.spring(duration: 0.25)) {
                isSidebarVisible = true
                sidebarWidth = Self.defaultSidebarWidth
            }
        } else if isSidebarVisible {
            withAnimation(.spring(duration: 0.25)) {
                isSidebarVisible = false
            }
        }
    }

    /// 打开单个文件（单文件模式，Sidebar 默认隐藏但可手动打开）
    func openSingleFile(_ url: URL, sidebarVisible: Bool = false) {
        // 先设置单文件模式属性，再清空 rootDirectory
        // 因为 rootDirectory 的 didSet 会调用 updateWindowTitle()
        // 如果先清空 rootDirectory，此时 isSingleFileMode/singleFileURL 尚未设置
        // 会导致窗口标题无法正确显示文件名
        isSingleFileMode = true
        singleFileURL = url
        selectedFile = nil
        rootDirectory = nil
        if sidebarVisible {
            if !isSidebarVisible {
                withAnimation(.spring(duration: 0.25)) {
                    isSidebarVisible = true
                    sidebarWidth = Self.defaultSidebarWidth
                }
            }
        } else if isSidebarVisible {
            withAnimation(.spring(duration: 0.25)) {
                isSidebarVisible = false
            }
        }
    }

    // MARK: - 私有方法

    var hasUnsavedUntitled: Bool = false
    var untitledFileName: String = ""

    private func updateWindowTitle() {
        if hasUnsavedUntitled {
            windowTitle = "MarkMark — \(untitledFileName)"
        } else if isSingleFileMode, let url = singleFileURL {
            windowTitle = "MarkMark — \(url.lastPathComponent)"
        } else if let dir = rootDirectory {
            windowTitle = "MarkMark — \(dir.lastPathComponent)"
        } else {
            windowTitle = "MarkMark"
        }
    }
}
