import SwiftUI
import MarkdownReaderKit


private struct WindowCaptureView: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> CapturingNSView {
        let view = CapturingNSView(frame: .zero)
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: CapturingNSView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolveWindow()
    }

    final class CapturingNSView: NSView {
        var onResolve: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveWindow()
        }

        func resolveWindow() {
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.onResolve?(window)
            }
        }
    }
}

private struct LinkNavigationDirectoryChange: Equatable {
    let rootURL: URL
    let targetURL: URL
    let targetKind: MarkdownLinkNavigationPolicy.TargetKind
}

private struct NavigationHistoryObservedState: Equatable {
    let isSingleFileMode: Bool
    let rootDirectory: URL?
    let singleFileURL: URL?
    let selectedFileURL: URL?

    init(snapshot: NavigationHistorySnapshot) {
        isSingleFileMode = snapshot.isSingleFileMode
        rootDirectory = snapshot.rootDirectory
        singleFileURL = snapshot.singleFileURL
        selectedFileURL = snapshot.selectedFileURL
    }
}

/// 主视图，管理自定义 HStack 两列布局
/// 设置模式下左侧显示设置菜单，右侧显示设置内容
struct ContentView: View {
    /// 该窗口绑定的文件/目录 URL（值型 WindowGroup）。nil = 冷启动/欢迎页窗口。
    var openedURL: URL? = nil
    var registersWindowRouter: Bool = true
    var showsWindowTitle: Bool = true

    @State private var appViewModel = AppViewModel()
    @State private var fileTreeViewModel = FileTreeViewModel()
    @State private var documentViewModel = DocumentViewModel()
    @State private var navigationHistory = NavigationHistoryModel()
    @State private var settings = SettingsModel.shared
    @Environment(\.language) private var language
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    /// 缓存的主题颜色，避免每次 body 求值时重复执行 NSColor 色彩空间转换和混合运算
    /// 通过 .onChange(of: settings.resolvedTheme) 响应式更新
    @State private var themeColors: ThemeColors = ThemeColors.from(
        SettingsModel.shared.resolvedTheme
    )

    @State private var registeredOpenURL: URL?
    @State private var hostingWindow: NSWindow?
    @State private var linkNavigationDirectoryChange: LinkNavigationDirectoryChange?
    @State private var historyNavigationDirectoryChange: NavigationHistorySnapshot?
    @State private var isApplyingHistoryNavigation = false
    @State private var didRegisterLaunchWindowRouter = false
    @State private var didNotifyLaunchContentWindowReady = false

    var body: some View {
        mainLayout
            .frame(minWidth: 650, minHeight: 450)
            .ignoresSafeArea()
            .background(themeColors.surface)
            .navigationTitle(showsWindowTitle ? appViewModel.windowTitle : "")
            .environment(\.language, settings.languagePref.resolvedLanguage)
            .applyThemeColors(themeColors)
            .tint(themeColors.accent)
            .modifier(FullScreenStateModifier(appViewModel: appViewModel))
            .modifier(KeyboardShortcutModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                toggleSidebar: toggleSidebarAndRemember
            ))
            .modifier(FileOpenModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel,
                settings: settings,
                acceptsExternalOpen: openedURL == nil,
                recordOpenedURL: { registerWindowURL($0) }
            ))
            .modifier(DirectoryChangeModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel,
                linkNavigationDirectoryChange: $linkNavigationDirectoryChange,
                historyNavigationDirectoryChange: $historyNavigationDirectoryChange,
                onLinkNavigationFinished: {
                    recordCurrentNavigationSnapshot()
                },
                onHistoryNavigationFinished: {
                    isApplyingHistoryNavigation = false
                    navigationHistory.replaceCurrent(currentNavigationSnapshot)
                }
            ))
            .modifier(SelectionChangeModifier(
                appViewModel: appViewModel,
                documentViewModel: documentViewModel,
                fileTreeViewModel: fileTreeViewModel,
                settings: settings
            ))
            .modifier(SettingsChangeModifier(
                appViewModel: appViewModel,
                fileTreeViewModel: fileTreeViewModel,
                settings: settings
            ))
            .modifier(ToggleSettingsModifier(appViewModel: appViewModel))
            .background(TrafficLightHider(bgColor: themeColors.bgSubtle))
            .background(WindowCloseGuard(documentViewModel: documentViewModel, settings: settings))
            .background(WindowCaptureView { window in
                hostingWindow = window
                if let registeredOpenURL {
                    WindowRouter.shared.attachWindow(window, to: registeredOpenURL)
                }
                notifyLaunchContentWindowReadyIfNeeded()
            })
            .task {
                // 连接 FileTreeViewModel 与 DocumentViewModel
                fileTreeViewModel.documentViewModel = documentViewModel
                applyAppearance(settings.appearanceMode)

                // 首次启动修正（issue #5）：SettingsModel.init 读取 NSApp.effectiveAppearance 过早，
                // 在系统为深色时会把 systemIsDark 误判为 false，导致 resolvedTheme 退回浅色主题
                // （白底），而窗口实际外观仍是系统深色 → 默认文字为白色 → 白底白字不可见。
                // 这里用权威的 SwiftUI colorScheme 重新播种，并刷新缓存的主题色。
                // （.onChange(of:colorScheme) 不会对初始值触发，故必须在此显式处理。）
                if settings.appearanceMode == .system {
                    let isDark = (colorScheme == .dark)
                    if settings.systemIsDark != isDark {
                        settings.systemIsDark = isDark
                    }
                }
                themeColors = ThemeColors.from(settings.resolvedTheme)

                // 注册多窗口路由：把 SwiftUI 的 openWindow(value:) 暴露给 AppDelegate。
                // 任意窗口注册即可（openWindow 是 App 级动作），多窗口互相覆盖等价。
                if registersWindowRouter {
                    WindowRouter.shared.open = { url in openWindow(value: url) }
                    didRegisterLaunchWindowRouter = true
                }

                // 本窗口绑定了具体 URL（多窗口场景：双击文件新开的窗口）→ 直接打开它，
                // 不读 UserDefaults pending，避免与冷启动初始窗口抢同一个 pending。
                if let url = openedURL {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                    clearPendingOpenDefaultsIfMatching(url)
                    registerWindowURL(url)
                    notifyLaunchContentWindowReadyIfNeeded()
                    if isDir.boolValue {
                        appViewModel.openDirectory(url)
                        settings.rememberOpenedDirectory(url)
                        settings.addRecentItem(url: url, isDirectory: true)
                        await fileTreeViewModel.loadDirectory(url)
                    } else {
                        appViewModel.openSingleFile(url)
                        fileTreeViewModel.selectedFileURL = url
                        settings.rememberOpenedSingleFile(url)
                        settings.addRecentItem(url: url, isDirectory: false)
                        await documentViewModel.loadFile(at: url)
                    }
                    return
                }

                // 检查 UserDefaults 中是否有待打开的文件（从 AppDelegate 写入）
                // 这是最可靠的后备机制：即使通知丢失（无窗口时），视图挂载后也能读取
                if let filePath = UserDefaults.standard.string(forKey: "pendingOpenFilePath") {
                    UserDefaults.standard.removeObject(forKey: "pendingOpenFilePath")
                    let url = URL(fileURLWithPath: filePath)
                    registerWindowURL(url)
                    appViewModel.openSingleFile(url)
                    fileTreeViewModel.selectedFileURL = url
                    settings.rememberOpenedSingleFile(url)
                    settings.addRecentItem(url: url, isDirectory: false)
                    // 冷启动时显式加载文件，避免依赖 SelectionChangeModifier 的异步触发
                    // 修复：双击 md 文件冷启动偶发显示欢迎页的 bug
                    await documentViewModel.loadFile(at: url)
                } else if let dirPath = UserDefaults.standard.string(forKey: "pendingOpenDirectoryPath") {
                    UserDefaults.standard.removeObject(forKey: "pendingOpenDirectoryPath")
                    let url = URL(fileURLWithPath: dirPath)
                    registerWindowURL(url)
                    appViewModel.openDirectory(url)
                    settings.rememberOpenedDirectory(url)
                    settings.addRecentItem(url: url, isDirectory: true)
                    // 冷启动时显式加载目录
                    await fileTreeViewModel.loadDirectory(url)
                }
                notifyLaunchContentWindowReadyIfNeeded()
                // 不在此处调用 restoreLastLocation()
                // 冷启动时，applicationDidFinishLaunching 通过 .restoreLastLocation 通知处理
                // 这样可以确保通知在视图完全挂载后才发送，避免时序问题
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetToWelcome)) { notification in
                guard shouldHandleWindowRoutedNotification(notification) else { return }
                resetToWelcome()
            }
            .onReceive(NotificationCenter.default.publisher(for: .restoreLastLocation)) { notification in
                guard shouldHandleWindowRoutedNotification(notification) else { return }
                restoreLastLocation()
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .performUndo)) { _ in
                documentViewModel.performUndo()
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .performRedo)) { _ in
                documentViewModel.performRedo()
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in
                navigateHistory(backward: true)
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in
                navigateHistory(backward: false)
            }
            .onChange(of: currentNavigationObservedState) { _, _ in
                scheduleNavigationHistoryRecord()
            }
            .onChange(of: colorScheme) { _, newScheme in
                // 仅在「跟随系统」模式下更新 systemIsDark
                // 避免手动选择浅色/深色时，colorScheme 变化污染 systemIsDark
                if settings.appearanceMode == .system {
                    settings.systemIsDark = (newScheme == .dark)
                }
            }
            .onChange(of: settings.appearanceMode) { _, newMode in
                // 切换到「跟随系统」时，立即刷新 systemIsDark 为当前系统外观
                if newMode == .system {
                    settings.systemIsDark = NSApp.effectiveAppearance
                        .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                }
            }
            // 主题变化时重新计算缓存的主题颜色
            // resolvedTheme 是 Equatable，仅在主题实际变更时触发
            .onChange(of: settings.resolvedTheme) { _, newTheme in
                themeColors = ThemeColors.from(newTheme)
            }
            .onChange(of: documentViewModel.isUntitled) { _, isUntitled in
                if !isUntitled {
                    appViewModel.hasUnsavedUntitled = false
                    appViewModel.untitledFileName = ""
                }
            }
    }

    // MARK: - 布局

    private var mainLayout: some View {
        HStack(spacing: 0) {
            if appViewModel.isShowingSettings {
                // 设置模式：左侧设置菜单
                SettingsSidebarView(appViewModel: appViewModel)
                    .frame(width: appViewModel.sidebarWidth)
                    .overlay(alignment: .trailing) {
                        floatingSidebarResizeHandle
                    }

                // 右侧设置内容
                SettingsContentView(appViewModel: appViewModel, settings: settings)
            } else {
                // 正常模式：文件树 + 文档
                // SidebarView 始终保留在视图树中，通过宽度 0 + clipping 隐藏，
                // 避免条件 if 导致 NSView 后端反复销毁/重建，引发 AppKit hit-testing
                // 与 SwiftUI 布局不同步（标题栏拖拽区域吞噬按钮点击）
                SidebarView(
                    fileTreeViewModel: fileTreeViewModel,
                    appViewModel: appViewModel,
                    documentViewModel: documentViewModel,
                    canNavigateBack: navigationHistory.canGoBack,
                    canNavigateForward: navigationHistory.canGoForward,
                    navigateBack: {
                        navigateHistory(backward: true)
                    },
                    navigateForward: {
                        navigateHistory(backward: false)
                    },
                    toggleSidebar: {
                        toggleSidebarAndRemember()
                    }
                )
                .frame(width: appViewModel.isSidebarVisible ? appViewModel.sidebarWidth : 0)
                .clipped()
                .allowsHitTesting(appViewModel.isSidebarVisible)
                .overlay(alignment: .trailing) {
                    if appViewModel.isSidebarVisible {
                        floatingSidebarResizeHandle
                    }
                }

                DetailView(
                    appViewModel: appViewModel,
                    documentViewModel: documentViewModel,
                    fileTreeViewModel: fileTreeViewModel,
                    settings: settings,
                    canNavigateBack: navigationHistory.canGoBack,
                    canNavigateForward: navigationHistory.canGoForward,
                    navigateBack: {
                        navigateHistory(backward: true)
                    },
                    navigateForward: {
                        navigateHistory(backward: false)
                    },
                    toggleSidebar: {
                        toggleSidebarAndRemember()
                    },
                    toggleOutline: {
                        toggleOutlineAndRemember()
                    },
                    onLocalMarkdownLink: { targetURL in
                        handleLocalMarkdownLink(targetURL)
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appViewModel.isShowingSettings)
    }

    /// 侧边栏拖拽热区：浮动吸附在侧边栏右缘，不作为 HStack 的独立布局列。
    private var floatingSidebarResizeHandle: some View {
        ResizeHandle(appViewModel: appViewModel)
            .offset(x: 4)
            .zIndex(10)
    }

    // MARK: - 方法

    private var currentNavigationSnapshot: NavigationHistorySnapshot {
        let selectedFileURL = fileTreeViewModel.selectedFileURL?.markMarkCanonicalFileURL
        let singleFileURL = appViewModel.singleFileURL?.markMarkCanonicalFileURL
        let rootDirectory = appViewModel.rootDirectory?.markMarkCanonicalFileURL
        let activeNodeURL = fileTreeViewModel.activeNodeURL?.markMarkCanonicalFileURL
            ?? selectedFileURL
            ?? rootDirectory
            ?? singleFileURL

        return NavigationHistorySnapshot(
            isSingleFileMode: appViewModel.isSingleFileMode,
            rootDirectory: rootDirectory,
            singleFileURL: singleFileURL,
            selectedFileURL: selectedFileURL ?? (appViewModel.isSingleFileMode ? singleFileURL : nil),
            activeNodeURL: activeNodeURL
        )
    }

    private var currentNavigationObservedState: NavigationHistoryObservedState {
        NavigationHistoryObservedState(snapshot: currentNavigationSnapshot)
    }

    private func scheduleNavigationHistoryRecord() {
        guard !isApplyingHistoryNavigation,
              linkNavigationDirectoryChange == nil,
              historyNavigationDirectoryChange == nil else { return }

        // Several navigation paths update root/selection in two adjacent state changes.
        // Recording on the next runloop captures the settled window state and avoids
        // transient entries such as “new root + previous selected file”.
        DispatchQueue.main.async {
            recordCurrentNavigationSnapshot()
        }
    }

    private func recordCurrentNavigationSnapshot() {
        guard !isApplyingHistoryNavigation,
              linkNavigationDirectoryChange == nil,
              historyNavigationDirectoryChange == nil else { return }
        navigationHistory.record(currentNavigationSnapshot)
    }

    private func navigateHistory(backward: Bool) {
        guard !isApplyingHistoryNavigation else { return }
        let target = backward ? navigationHistory.backTarget : navigationHistory.forwardTarget
        guard target != nil else {
            NSSound.beep()
            return
        }

        performAfterUntitledChangesResolved {
            let snapshot = backward ? navigationHistory.goBack() : navigationHistory.goForward()
            guard let snapshot else { return }
            applyHistorySnapshot(snapshot)
        }
    }

    private func performAfterUntitledChangesResolved(_ action: @escaping () -> Void) {
        guard documentViewModel.isUntitled && documentViewModel.isDirty else {
            action()
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
        alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
            let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName
            guard let saveURL = OpenPanelHelper.showSavePanel(
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) else { return }

            Task { @MainActor in
                await documentViewModel.saveAs(to: saveURL)
                appViewModel.hasUnsavedUntitled = false
                action()
            }
        case .alertSecondButtonReturn:
            documentViewModel.discardUntitledFile()
            appViewModel.hasUnsavedUntitled = false
            action()
        default:
            break
        }
    }

    private func applyHistorySnapshot(_ snapshot: NavigationHistorySnapshot) {
        isApplyingHistoryNavigation = true

        if snapshot.isSingleFileMode {
            guard let fileURL = snapshot.singleFileURL ?? snapshot.selectedFileURL else {
                resetToWelcome()
                isApplyingHistoryNavigation = false
                return
            }
            applySingleFileHistorySnapshot(fileURL)
            return
        }

        guard let rootURL = snapshot.rootDirectory else {
            resetToWelcome()
            isApplyingHistoryNavigation = false
            return
        }

        registerWindowURL(rootURL)
        settings.rememberOpenedDirectory(rootURL)
        if let selectedFileURL = snapshot.selectedFileURL {
            settings.rememberDirectorySelectedFile(selectedFileURL, rootDirectory: rootURL)
        }

        if appViewModel.isSingleFileMode
            || appViewModel.rootDirectory?.markMarkCanonicalFileURL != rootURL {
            historyNavigationDirectoryChange = snapshot
            appViewModel.openDirectory(rootURL)
            return
        }

        Task { @MainActor in
            await applyDirectoryHistorySnapshot(snapshot)
            isApplyingHistoryNavigation = false
            navigationHistory.replaceCurrent(currentNavigationSnapshot)
        }
    }

    private func applySingleFileHistorySnapshot(_ fileURL: URL) {
        let normalizedFileURL = fileURL.markMarkCanonicalFileURL
        registerWindowURL(normalizedFileURL)
        settings.rememberOpenedSingleFile(normalizedFileURL)
        appViewModel.openSingleFile(normalizedFileURL)
        fileTreeViewModel.clearDirectory(clearSelection: false)
        fileTreeViewModel.selectedFileURL = normalizedFileURL
        fileTreeViewModel.activeNodeURL = normalizedFileURL

        Task { @MainActor in
            await documentViewModel.loadFile(at: normalizedFileURL)
            isApplyingHistoryNavigation = false
            navigationHistory.replaceCurrent(currentNavigationSnapshot)
        }
    }

    @MainActor
    private func applyDirectoryHistorySnapshot(_ snapshot: NavigationHistorySnapshot) async {
        if let selectedFileURL = snapshot.selectedFileURL {
            await fileTreeViewModel.revealFile(selectedFileURL, select: true)
            await documentViewModel.loadFile(at: selectedFileURL)
        } else {
            fileTreeViewModel.selectedFileURL = nil
            documentViewModel.clearDocument()
        }

        if let activeNodeURL = snapshot.activeNodeURL {
            await fileTreeViewModel.revealNode(activeNodeURL, selectFile: false)
        }
    }

    private func clearPendingOpenDefaultsIfMatching(_ url: URL) {
        let canonicalURL = url.markMarkCanonicalFileURL
        let pendingFileKey = "pendingOpenFilePath"
        let pendingDirectoryKey = "pendingOpenDirectoryPath"
        let pendingFileURL = UserDefaults.standard.string(forKey: pendingFileKey)
            .map { URL(fileURLWithPath: $0).markMarkCanonicalFileURL }
        let pendingDirectoryURL = UserDefaults.standard.string(forKey: pendingDirectoryKey)
            .map { URL(fileURLWithPath: $0).markMarkCanonicalFileURL }

        if pendingFileURL == canonicalURL || pendingDirectoryURL == canonicalURL {
            UserDefaults.standard.removeObject(forKey: pendingFileKey)
            UserDefaults.standard.removeObject(forKey: pendingDirectoryKey)
        }
    }

    private func registerWindowURL(_ url: URL) {
        let canonicalURL = url.markMarkCanonicalFileURL
        if registeredOpenURL == canonicalURL { return }
        if let registeredOpenURL {
            WindowRouter.shared.unregisterOpenedURL(registeredOpenURL)
        }
        registeredOpenURL = canonicalURL
        WindowRouter.shared.registerOpenedURL(canonicalURL, window: windowForOpenRegistration())
    }

    private func notifyLaunchContentWindowReadyIfNeeded() {
        guard registersWindowRouter,
              didRegisterLaunchWindowRouter,
              !didNotifyLaunchContentWindowReady,
              let readyWindow = hostingWindow
        else { return }

        didNotifyLaunchContentWindowReady = true
        NotificationCenter.default.post(
            name: .contentWindowReadyForLaunchRouting,
            object: readyWindow,
            userInfo: [
                "isUntitledLaunchWindow": openedURL == nil
            ]
        )
    }

    private func windowForOpenRegistration() -> NSWindow? {
        if let hostingWindow { return hostingWindow }
        if let keyWindow = NSApp.keyWindow, keyWindow.isVisible, keyWindow.canBecomeKey, !(keyWindow is NSPanel), !keyWindow.isSheet {
            return keyWindow
        }
        if let mainWindow = NSApp.mainWindow, mainWindow.isVisible, mainWindow.canBecomeKey, !(mainWindow is NSPanel), !mainWindow.isSheet {
            return mainWindow
        }
        return NSApp.windows.first {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) && !$0.isSheet
        }
    }

    private func shouldHandleWindowRoutedNotification(_ notification: Notification) -> Bool {
        if let targetWindow = notification.object as? NSWindow {
            return hostingWindow === targetWindow
        }

        // Backward-compatible fallback for notifications posted without a
        // target window. Prefer AppKit's immediate key/main window state over
        // SwiftUI controlActiveState so startup routing cannot be dropped in
        // the narrow window before SwiftUI refreshes that environment value.
        guard let hostingWindow else { return false }
        if hostingWindow === NSApp.keyWindow || hostingWindow === NSApp.mainWindow {
            return true
        }

        let usableWindows = NSApp.windows.filter {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) && !$0.isSheet
        }
        return usableWindows.count == 1 && usableWindows[0] === hostingWindow
    }

    private func unregisterWindowURL() {
        if let registeredOpenURL {
            WindowRouter.shared.unregisterOpenedURL(registeredOpenURL)
            self.registeredOpenURL = nil
        }
    }

    private func handleLocalMarkdownLink(_ targetURL: URL) {
        let decision = MarkdownLinkNavigationPolicy.decide(
            sourceFileURL: documentViewModel.currentFileURL,
            currentRootURL: appViewModel.rootDirectory,
            targetURL: targetURL
        )

        switch decision.targetKind {
        case .missing:
            showMarkdownLinkFailure(
                titleKey: .markdownLinkMissingTitle,
                messageKey: .markdownLinkMissingMessage,
                targetURL: decision.targetURL
            )
            return
        case .unsupportedFile:
            showMarkdownLinkFailure(
                titleKey: .markdownLinkUnsupportedTitle,
                messageKey: .markdownLinkUnsupportedMessage,
                targetURL: decision.targetURL
            )
            return
        case .markdownFile, .directory:
            break
        }

        guard let rootURL = decision.rootURL else { return }
        if decision.requiresConfirmation && !confirmMarkdownLinkRootChange(decision) {
            return
        }

        applyMarkdownLinkNavigation(decision, rootURL: rootURL)
    }

    private func applyMarkdownLinkNavigation(
        _ decision: MarkdownLinkNavigationPolicy.Decision,
        rootURL: URL
    ) {
        let normalizedRoot = rootURL.markMarkCanonicalFileURL
        if appViewModel.rootDirectory?.markMarkCanonicalFileURL == normalizedRoot {
            Task { @MainActor in
                await revealMarkdownLinkTarget(decision)
            }
            return
        }

        linkNavigationDirectoryChange = LinkNavigationDirectoryChange(
            rootURL: normalizedRoot,
            targetURL: decision.targetURL,
            targetKind: decision.targetKind
        )
        registerWindowURL(normalizedRoot)
        settings.rememberOpenedDirectory(normalizedRoot)
        switch decision.targetKind {
        case .markdownFile:
            settings.rememberDirectorySelectedFile(decision.targetURL, rootDirectory: normalizedRoot)
        case .directory:
            if let currentFileURL = documentViewModel.currentFileURL {
                settings.rememberDirectorySelectedFile(currentFileURL, rootDirectory: normalizedRoot)
            }
        case .missing, .unsupportedFile:
            break
        }
        settings.addRecentItem(url: normalizedRoot, isDirectory: true)
        appViewModel.openDirectory(normalizedRoot)
    }

    @MainActor
    private func revealMarkdownLinkTarget(_ decision: MarkdownLinkNavigationPolicy.Decision) async {
        switch decision.targetKind {
        case .directory:
            await fileTreeViewModel.revealDirectory(decision.targetURL)
        case .markdownFile:
            await fileTreeViewModel.revealMarkdownFile(decision.targetURL)
        case .missing, .unsupportedFile:
            break
        }
        recordCurrentNavigationSnapshot()
    }

    private func confirmMarkdownLinkRootChange(_ decision: MarkdownLinkNavigationPolicy.Decision) -> Bool {
        guard let rootURL = decision.rootURL else { return false }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.tr(.markdownLinkExpandRootTitle, language: language)
        alert.informativeText = L10n.tr(
            .markdownLinkExpandRootMessage,
            language: language,
            args: [
                "root": rootURL.path,
                "target": decision.targetURL.path
            ]
        )
        alert.addButton(withTitle: L10n.tr(.markdownLinkOpenCommonRoot, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showMarkdownLinkFailure(
        titleKey: L10n.Key,
        messageKey: L10n.Key,
        targetURL: URL
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr(titleKey, language: language)
        alert.informativeText = L10n.tr(
            messageKey,
            language: language,
            args: ["target": targetURL.path]
        )
        alert.addButton(withTitle: L10n.tr(.confirm, language: language))
        alert.runModal()
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }

    /// 重置所有 ViewModel 状态，显示欢迎页
    /// 用于 Dock 点击重新激活时，避免恢复旧窗口的文档内容
    private func resetToWelcome() {
        navigationHistory.clear()
        unregisterWindowURL()
        appViewModel.rootDirectory = nil
        appViewModel.isSingleFileMode = false
        appViewModel.singleFileURL = nil
        appViewModel.selectedFile = nil
        appViewModel.hasUnsavedUntitled = false
        appViewModel.untitledFileName = ""
        appViewModel.isShowingSettings = false
        // 欢迎页无目录内容，隐藏 sidebar 避免显示空文件树
        if appViewModel.isSidebarVisible {
            appViewModel.isSidebarVisible = false
        }
        appViewModel.isOutlineVisible = false
        appViewModel.isAnnotationPanelVisible = false
        fileTreeViewModel.selectedFileURL = nil
        documentViewModel.clearDocument()
    }

    /// 恢复上次打开的位置（目录或文件）
    /// 用于 Dock 点击重新激活且 reopenLastLocation 开启时
    private func restoreLastLocation() {
        // 如果冷启动已通过 UserDefaults 打开了文件/目录，不覆盖
        // 修复：冷启动双击 md 文件时，applicationDidFinishLaunching 的 0.5s 延迟
        // 可能误发 .restoreLastLocation，覆盖掉 ContentView.task 已打开的文件
        if appViewModel.isSingleFileMode || appViewModel.rootDirectory != nil {
            return
        }
        if let dir = settings.lastOpenedDirectory {
            let normalizedDir = dir.markMarkCanonicalFileURL
            if let selectedFile = settings.restorableDirectorySelectedFile(for: normalizedDir) {
                historyNavigationDirectoryChange = NavigationHistorySnapshot(
                    isSingleFileMode: false,
                    rootDirectory: normalizedDir,
                    singleFileURL: nil,
                    selectedFileURL: selectedFile,
                    activeNodeURL: selectedFile
                )
            }
            registerWindowURL(dir)
            appViewModel.openDirectory(dir, sidebarVisible: settings.rememberedSidebarVisible)
            appViewModel.applyRememberedChromeState(
                sidebarVisible: settings.rememberedSidebarVisible,
                outlineVisible: settings.rememberedOutlineVisible
            )
            settings.addRecentItem(url: dir, isDirectory: true)
        } else if let file = settings.lastOpenedFile {
            registerWindowURL(file)
            appViewModel.openSingleFile(file, sidebarVisible: settings.rememberedSidebarVisible)
            appViewModel.applyRememberedChromeState(
                sidebarVisible: settings.rememberedSidebarVisible,
                outlineVisible: settings.rememberedOutlineVisible
            )
            fileTreeViewModel.selectedFileURL = file
            settings.addRecentItem(url: file, isDirectory: false)
            Task { @MainActor in
                await documentViewModel.loadFile(at: file)
            }
        } else {
            resetToWelcome()
        }
    }

    private func toggleSidebarAndRemember() {
        appViewModel.toggleSidebar()
        settings.rememberedSidebarVisible = appViewModel.isSidebarVisible
    }

    private func toggleOutlineAndRemember() {
        appViewModel.toggleOutline()
        settings.rememberedOutlineVisible = appViewModel.isOutlineVisible
    }
}

// MARK: - 设置侧边栏

/// 设置模式下的左侧菜单视图
struct SettingsSidebarView: View {
    let appViewModel: AppViewModel
    @Environment(\.language) private var language
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部区域：自定义红绿灯（50px）
            HStack(spacing: 0) {
                TrafficLightButtons()
                    .padding(.leading, 12)
                Spacer()
            }
            .frame(height: 50)
            .background(WindowDragArea())

            Rectangle().fill(themeColors.border).frame(height: 1)

            // 返回按钮
            Button {
                appViewModel.hideSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.tr(.settingsBackToApp, language: language))
                        .font(.system(size: 12))
                }
                .foregroundStyle(themeColors.fgSecondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 16)

            // 菜单项
            SettingsMenuItemView(
                title: L10n.tr(.settingsTabGeneral, language: language),
                icon: "gearshape",
                isSelected: appViewModel.settingsTab == .general
            ) {
                appViewModel.settingsTab = .general
            }

            SettingsMenuItemView(
                title: L10n.tr(.settingsTabAppearance, language: language),
                icon: "paintbrush",
                isSelected: appViewModel.settingsTab == .appearance
            ) {
                appViewModel.settingsTab = .appearance
            }

            Spacer()
        }
        .background(themeColors.bgSubtle)
    }
}

private struct SettingsMenuItemView: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.themeColors) private var themeColors

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(isSelected ? themeColors.ink : themeColors.fgSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? themeColors.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

// MARK: - 设置内容视图

/// 设置模式下的右侧内容区域
struct SettingsContentView: View {
    let appViewModel: AppViewModel
    @Bindable var settings: SettingsModel
    @Environment(\.themeColors) private var themeColors

    private var currentLanguage: Language {
        settings.languagePref.resolvedLanguage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch appViewModel.settingsTab {
                case .general:
                    GeneralSettingsView(settings: settings, language: currentLanguage)
                case .appearance:
                    AppearanceSettingsView(settings: settings, language: currentLanguage)
                }
            }
            .frame(minWidth: 480, maxWidth: 896)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 40)
            .padding(.vertical, 40)
        }
        .scrollIndicators(.automatic)
        .scrollContentBackground(.hidden)
        .background(themeColors.surface, in: .rect(
            topLeadingRadius: 10,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        ))
        .clipShape(.rect(
            topLeadingRadius: 10,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        ))
        .background(themeColors.bgSubtle)
        .overlay(
            LeftEdgeShape(radius: 10)
                .stroke(themeColors.border, lineWidth: 1)
        )
    }
}

// MARK: - 全屏状态监听

private struct FullScreenStateModifier: ViewModifier {
    let appViewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                appViewModel.isFullScreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                appViewModel.isFullScreen = false
            }
    }
}

// MARK: - 快捷键监听

private struct KeyboardShortcutModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let toggleSidebar: () -> Void

    func body(content: Content) -> some View {
        content
            .onActiveReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                toggleSidebar()
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .switchToRendered)) { _ in
                documentViewModel.switchDisplayMode(.rendered)
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .switchToRaw)) { _ in
                documentViewModel.switchDisplayMode(.raw)
            }
    }
}

// MARK: - 文件打开通知

private struct FileOpenModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel
    let settings: SettingsModel
    let acceptsExternalOpen: Bool
    let recordOpenedURL: (URL) -> Void
    @Environment(\.language) private var language

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openExternalDirectory)) { notification in
                guard acceptsExternalOpen, let url = notification.object as? URL else { return }
                openDirectory(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openExternalFile)) { notification in
                guard acceptsExternalOpen, let url = notification.object as? URL else { return }
                openFile(url)
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .openDirectory)) { notification in
                guard let url = notification.object as? URL else { return }
                openDirectory(url)
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .openFile)) { notification in
                guard let url = notification.object as? URL else { return }
                openFile(url)
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .newFromClipboard)) { _ in
                // 从剪贴板新建标注：将剪贴板文本写入临时文件并以渲染模式打开
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    NSSound.beep()
                    return
                }
                let createScratch = {
                    let name = L10n.tr(.clipboardScratchName, language: language) + ".md"
                    let result = documentViewModel.createScratchFile(content: text, fileName: name)
                    guard result != nil else { return }
                    fileTreeViewModel.selectedFileURL = nil
                    appViewModel.selectedFile = nil
                    appViewModel.hasUnsavedUntitled = true
                    appViewModel.untitledFileName = documentViewModel.fileName
                }
                if documentViewModel.isUntitled && documentViewModel.isDirty {
                    handleUnsavedChangesBeforeAction { proceed in
                        guard proceed else { return }
                        createScratch()
                    }
                } else {
                    createScratch()
                }
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
                Task {
                    await documentViewModel.save()
                }
            }
            .onActiveReceive(NotificationCenter.default.publisher(for: .saveAsFile)) { _ in
                let language = settings.languagePref.resolvedLanguage
                let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
                let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

                if let saveURL = OpenPanelHelper.showSavePanel(
                    language: language,
                    defaultDirectory: defaultDir,
                    suggestedName: suggestedName
                ) {
                    Task {
                        await documentViewModel.saveAs(to: saveURL)
                        appViewModel.hasUnsavedUntitled = false

                        if let rootDir = appViewModel.rootDirectory,
                           MarkdownLinkNavigationPolicy.contains(saveURL, inOrEqualTo: rootDir) {
                            await fileTreeViewModel.loadDirectory(rootDir)
                            fileTreeViewModel.selectedFileURL = saveURL
                            settings.rememberDirectorySelectedFile(saveURL, rootDirectory: rootDir)
                        } else if appViewModel.isSingleFileMode {
                            settings.rememberOpenedSingleFile(saveURL)
                        } else {
                            settings.lastOpenedFile = saveURL
                        }

                        // 更新最近打开记录
                        settings.addRecentItem(url: saveURL, isDirectory: false)
                    }
                }
            }
    }

    private func openDirectory(_ url: URL) {
        // 幂等保护：如果已经在显示此目录，跳过
        if appViewModel.rootDirectory == url { return }
        if documentViewModel.isUntitled && documentViewModel.isDirty {
            handleUnsavedChangesBeforeAction { proceed in
                guard proceed else { return }
                applyOpenDirectory(url)
            }
        } else {
            applyOpenDirectory(url)
        }
    }

    private func applyOpenDirectory(_ url: URL) {
        recordOpenedURL(url)
        appViewModel.openDirectory(url)
        settings.rememberOpenedDirectory(url)
        settings.addRecentItem(url: url, isDirectory: true)
    }

    private func openFile(_ url: URL) {
        // 幂等保护：如果已经在显示此文件，跳过（防止 application(_:open:) 和 .onOpenURL 同时触发导致重复打开）
        if documentViewModel.currentFileURL == url { return }
        if documentViewModel.isUntitled && documentViewModel.isDirty {
            handleUnsavedChangesBeforeAction { proceed in
                guard proceed else { return }
                applyOpenFile(url)
            }
        } else {
            applyOpenFile(url)
        }
    }

    private func applyOpenFile(_ url: URL) {
        recordOpenedURL(url)
        appViewModel.openSingleFile(url)
        fileTreeViewModel.selectedFileURL = url
        settings.rememberOpenedSingleFile(url)
        settings.addRecentItem(url: url, isDirectory: false)
        // 不需要显式调用 loadFile — selectedFileURL 变化会触发 SelectionChangeModifier 统一加载
    }

    /// 通用未保存修改弹窗处理
    /// 仅在临时新建文件（isUntitled && isDirty）有未保存更改时调用
    /// 弹窗确认后执行操作，保护临时文件内容不丢失
    /// - Parameter completion: 回调，`proceed` 为 true 表示用户选择保存或放弃，可继续操作；false 表示取消
    private func handleUnsavedChangesBeforeAction(completion: @escaping (_ proceed: Bool) -> Void) {
        let language = settings.languagePref.resolvedLanguage

        let alert = NSAlert()
        alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
        alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // 保存：临时新建文件走另存为流程
            let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
            let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

            if let saveURL = OpenPanelHelper.showSavePanel(
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) {
                Task {
                    await documentViewModel.saveAs(to: saveURL)
                    appViewModel.hasUnsavedUntitled = false

                    // 如果保存在当前目录下，刷新文件树
                    if let rootDir = appViewModel.rootDirectory,
                       MarkdownLinkNavigationPolicy.contains(saveURL, inOrEqualTo: rootDir) {
                        await fileTreeViewModel.loadDirectory(rootDir)
                        fileTreeViewModel.selectedFileURL = saveURL
                        settings.rememberDirectorySelectedFile(saveURL, rootDirectory: rootDir)
                    } else if appViewModel.isSingleFileMode {
                        settings.rememberOpenedSingleFile(saveURL)
                    } else {
                        settings.lastOpenedFile = saveURL
                    }

                    settings.addRecentItem(url: saveURL, isDirectory: false)
                    completion(true)
                }
            } else {
                // 用户取消了另存为，不继续操作
                completion(false)
            }

        case .alertSecondButtonReturn:
            // 不保存
            documentViewModel.discardUntitledFile()
            appViewModel.hasUnsavedUntitled = false
            completion(true)

        default:
            // 取消
            completion(false)
        }
    }
}

// MARK: - 目录变化

private struct DirectoryChangeModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel
    @Binding var linkNavigationDirectoryChange: LinkNavigationDirectoryChange?
    @Binding var historyNavigationDirectoryChange: NavigationHistorySnapshot?
    let onLinkNavigationFinished: () -> Void
    let onHistoryNavigationFinished: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: appViewModel.rootDirectory) { _, newDirectory in
                if let dir = newDirectory {
                    if let snapshot = historyNavigationDirectoryChange,
                       snapshot.rootDirectory == dir.markMarkCanonicalFileURL {
                        Task { @MainActor in
                            await fileTreeViewModel.loadDirectory(dir)
                            await applyDirectorySnapshot(snapshot)
                            historyNavigationDirectoryChange = nil
                            onHistoryNavigationFinished()
                        }
                        return
                    }

                    if let change = linkNavigationDirectoryChange,
                       change.rootURL == dir.markMarkCanonicalFileURL {
                        fileTreeViewModel.activeNodeURL = nil
                        Task { @MainActor in
                            await fileTreeViewModel.loadDirectory(dir)
                            switch change.targetKind {
                            case .directory:
                                await fileTreeViewModel.revealDirectory(change.targetURL)
                            case .markdownFile:
                                await fileTreeViewModel.revealMarkdownFile(change.targetURL)
                            case .missing, .unsupportedFile:
                                break
                            }
                            linkNavigationDirectoryChange = nil
                            onLinkNavigationFinished()
                        }
                        return
                    }

                    // 清除选中状态，避免旧选中 URL 与新目录状态不同步
                    // （例如：从单文件模式切到目录模式时，selectedFileURL 仍指向旧文件，
                    // 但 documentViewModel 已被清空，导致点击同一文件不触发 onChange）
                    fileTreeViewModel.selectedFileURL = nil
                    fileTreeViewModel.activeNodeURL = nil
                    documentViewModel.clearDocument()
                    Task {
                        await fileTreeViewModel.loadDirectory(dir)
                    }
                } else {
                    fileTreeViewModel.clearDirectory(clearSelection: false)
                }
            }
    }

    @MainActor
    private func applyDirectorySnapshot(_ snapshot: NavigationHistorySnapshot) async {
        if let selectedFileURL = snapshot.selectedFileURL {
            await fileTreeViewModel.revealFile(selectedFileURL, select: true)
            await documentViewModel.loadFile(at: selectedFileURL)
        } else {
            fileTreeViewModel.selectedFileURL = nil
            documentViewModel.clearDocument()
        }

        if let activeNodeURL = snapshot.activeNodeURL {
            await fileTreeViewModel.revealNode(activeNodeURL, selectFile: false)
        }
    }
}

// MARK: - 文件选中变化

private struct SelectionChangeModifier: ViewModifier {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel
    let settings: SettingsModel

    func body(content: Content) -> some View {
        content
            .onChange(of: fileTreeViewModel.selectedFileURL) { oldURL, newURL in
                if let url = newURL {
                    if documentViewModel.isUntitled && documentViewModel.isDirty {
                        handleFileSwitchWithUnsavedChanges(from: oldURL, to: url)
                    } else {
                        Task {
                            await documentViewModel.loadFile(at: url)
                        }
                        let node = findFileNode(in: fileTreeViewModel.nodes, url: url)
                        appViewModel.selectedFile = node
                        if appViewModel.isSingleFileMode {
                            settings.rememberOpenedSingleFile(url)
                        } else {
                            settings.rememberDirectorySelectedFile(url, rootDirectory: appViewModel.rootDirectory)
                        }
                    }
                } else {
                    if let deletedURL = oldURL,
                       !FileManager.default.fileExists(atPath: deletedURL.path),
                       documentViewModel.isDirty {
                        handleDeletedFileWithUnsavedChanges(deletedURL)
                    } else if !documentViewModel.isUntitled && !appViewModel.isSingleFileMode {
                        // 单文件模式下不响应 selectedFileURL 变 nil 而取消文档
                        // 单文件模式的文档生命周期应独立于文件树选中状态
                        documentViewModel.deselectCurrentFile()
                    }
                    appViewModel.selectedFile = nil
                }
            }
    }

    /// 文件切换时的未保存修改弹窗（仅临时新建文件触发）
    private func handleFileSwitchWithUnsavedChanges(from oldURL: URL?, to newURL: URL) {
        guard documentViewModel.currentFileURL != newURL else { return }

        let language = settings.languagePref.resolvedLanguage

        let alert = NSAlert()
        alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
        alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
        alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // 保存：临时新建文件走另存为流程
            let defaultDir = settings.lastOpenedDirectory ?? settings.lastOpenedFile?.deletingLastPathComponent()
            let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

            if let saveURL = OpenPanelHelper.showSavePanel(
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) {
                Task {
                    await documentViewModel.saveAs(to: saveURL)
                    appViewModel.hasUnsavedUntitled = false
                    await documentViewModel.loadFile(at: newURL)
                    let node = findFileNode(in: fileTreeViewModel.nodes, url: newURL)
                    appViewModel.selectedFile = node

                    if let rootDir = appViewModel.rootDirectory,
                       saveURL.path.hasPrefix(rootDir.path + "/") {
                        await fileTreeViewModel.loadDirectory(rootDir)
                        fileTreeViewModel.selectedFileURL = saveURL
                    }
                }
            } else {
                fileTreeViewModel.selectedFileURL = oldURL
            }

        case .alertSecondButtonReturn:
            documentViewModel.discardUntitledFile()
            appViewModel.hasUnsavedUntitled = false
            Task {
                await documentViewModel.loadFile(at: newURL)
            }
            let node = findFileNode(in: fileTreeViewModel.nodes, url: newURL)
            appViewModel.selectedFile = node

        default:
            fileTreeViewModel.selectedFileURL = oldURL
        }
    }

    /// 处理文件被外部删除且有未保存修改的情况
    private func handleDeletedFileWithUnsavedChanges(_ deletedURL: URL) {
        let language = settings.languagePref.resolvedLanguage
        let fileName = deletedURL.lastPathComponent

        let alert = NSAlert()
        alert.messageText = L10n.tr(.fileDeletedTitle, language: language)
        alert.informativeText = L10n.tr(.fileDeletedMessage, language: language, args: ["name": fileName])
        alert.alertStyle = .warning

        alert.addButton(withTitle: L10n.tr(.fileDeletedSaveAs, language: language))
        alert.addButton(withTitle: L10n.tr(.fileDeletedDiscard, language: language))

        // 「另存为」为默认按钮（回车键）
        alert.buttons[0].keyEquivalent = "\r"
        // 「放弃更改」为 Esc 或 Cmd+D
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // 另存为
            let defaultDir = settings.lastOpenedDirectory ?? deletedURL.deletingLastPathComponent()
            let suggestedName = documentViewModel.fileName.isEmpty ? "Untitled.md" : documentViewModel.fileName

            if let saveURL = OpenPanelHelper.showSavePanel(
                language: language,
                defaultDirectory: defaultDir,
                suggestedName: suggestedName
            ) {
                Task {
                    await documentViewModel.saveAs(to: saveURL)
                    documentViewModel.deselectCurrentFile()
                    appViewModel.selectedFile = nil

                    // 如果保存在当前目录下，刷新文件树并选中
                    if let rootDir = appViewModel.rootDirectory,
                       saveURL.path.hasPrefix(rootDir.path) {
                        await fileTreeViewModel.refreshDirectory()
                        fileTreeViewModel.selectedFileURL = saveURL
                    }
                }
            } else {
                // 用户取消了另存为，保留当前文档内容让用户继续操作
                // 但文件树中已无此文件，需要重新选中以避免状态不一致
                appViewModel.selectedFile = nil
            }

        default:
            // 放弃更改
            documentViewModel.deselectCurrentFile()
            appViewModel.selectedFile = nil
        }
    }

    private func findFileNode(in nodes: [FileNode], url: URL) -> FileNode? {
        for node in nodes {
            if node.path == url { return node }
            if node.isDirectory, let children = node.children {
                if let found = findFileNode(in: children, url: url) { return found }
            }
        }
        return nil
    }
}

// MARK: - 设置变化

private struct SettingsChangeModifier: ViewModifier {
    let appViewModel: AppViewModel
    let fileTreeViewModel: FileTreeViewModel
    let settings: SettingsModel

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.showHiddenFiles) { _, _ in reloadFileTree() }
            .onChange(of: settings.showNonMarkdownFiles) { _, _ in reloadFileTree() }
            .onChange(of: settings.languagePref.resolvedLanguage) { _, newLanguage in
                fileTreeViewModel.language = newLanguage
            }
    }

    private func reloadFileTree() {
        guard let dir = appViewModel.rootDirectory else { return }
        fileTreeViewModel.selectedFileURL = nil
        fileTreeViewModel.activeNodeURL = nil
        Task {
            await fileTreeViewModel.loadDirectory(dir)
        }
    }
}

// MARK: - 切换设置（Cmd+,）

private struct ToggleSettingsModifier: ViewModifier {
    let appViewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onActiveReceive(NotificationCenter.default.publisher(for: .toggleSettings)) { _ in
                appViewModel.toggleSettings()
            }
    }
}

// MARK: - 隐藏红绿灯

/// 通过 NSViewRepresentable 隐藏窗口红绿灯按钮
/// viewDidMoveToWindow 在视图挂载到窗口时调用，确保能获取到 window 实例
private struct TrafficLightHider: NSViewRepresentable {
    let bgColor: Color

    func makeNSView(context: Context) -> NSView {
        let view = TrafficLightObserverView()
        view.bgColor = NSColor(bgColor)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let observer = nsView as? TrafficLightObserverView {
            observer.bgColor = NSColor(bgColor)
            observer.updateWindowBackground()
        }
    }

    private final class TrafficLightObserverView: NSView {
        var bgColor: NSColor = .windowBackgroundColor

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // 隐藏红绿灯按钮
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            // 确保内容延伸到标题栏区域
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            // 移除标题栏底部分隔线
            window.titlebarSeparatorStyle = .none
            // 设置窗口背景色匹配 bgSubtle
            updateWindowBackground()
            // 初始化 NSWindow.undoManager swizzling
            // 替换窗口的 undoManager getter 返回 per-file UndoManager
            NSWindow.swizzleUndoManager()
        }

        func updateWindowBackground() {
            guard let window else { return }
            window.backgroundColor = bgColor
        }
    }
}

// MARK: - 窗口关闭保护（未保存更改提醒）

/// 通过 NSViewRepresentable 设置窗口代理，在关闭前检查未保存更改
/// 使用 performClose 触发 windowShouldClose，展示保存/不保存/取消对话框
private struct WindowCloseGuard: NSViewRepresentable {
    let documentViewModel: DocumentViewModel
    let settings: SettingsModel

    func makeNSView(context: Context) -> NSView {
        let view = WindowCloseGuardView()
        view.documentViewModel = documentViewModel
        view.settings = settings
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowCloseGuardView)?.documentViewModel = documentViewModel
        (nsView as? WindowCloseGuardView)?.settings = settings
    }

    /// 持有窗口代理的 NSView，在 viewDidMoveToWindow 中设置代理
    private final class WindowCloseGuardView: NSView, NSWindowDelegate {
        weak var documentViewModel: DocumentViewModel?
        weak var settings: SettingsModel?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let doc = documentViewModel else { return true }

            // 仅对临时新建文件且有未保存更改时弹窗提醒
            // 普通脏文件（已保存在磁盘）允许自由关闭，不弹窗
            if !(doc.isUntitled && doc.isDirty) { return true }

            let language = settings?.languagePref.resolvedLanguage ?? .en

            // 显示未保存更改提醒
            let alert = NSAlert()
            alert.messageText = L10n.tr(.unsavedChangesTitle, language: language)
            alert.informativeText = L10n.tr(.unsavedChangesMessage, language: language)
            alert.alertStyle = .warning

            alert.addButton(withTitle: L10n.tr(.unsavedSave, language: language))
            alert.addButton(withTitle: L10n.tr(.unsavedDontSave, language: language))
            alert.addButton(withTitle: L10n.tr(.unsavedCancel, language: language))

            // 设置「保存」为默认按钮（回车键）
            alert.buttons[0].keyEquivalent = "\r"
            // 设置「不保存」为 Cmd+D 快捷键
            alert.buttons[1].keyEquivalent = "d"
            alert.buttons[1].keyEquivalentModifierMask = .command
            // 设置「取消」为 Esc 键
            alert.buttons[2].keyEquivalent = "\u{1b}"

            let response = alert.runModal()

            switch response {
            case .alertFirstButtonReturn:
                // 保存：临时新建文件走另存为流程
                let defaultDir = settings?.lastOpenedDirectory ?? settings?.lastOpenedFile?.deletingLastPathComponent()
                let suggestedName = doc.fileName.isEmpty ? "Untitled.md" : doc.fileName

                if let saveURL = OpenPanelHelper.showSavePanel(
                    language: language,
                    defaultDirectory: defaultDir,
                    suggestedName: suggestedName
                ) {
                    Task {
                        await doc.saveAs(to: saveURL)
                        // 保存成功后关闭窗口
                        sender.close()
                    }
                }
                // 用户取消了另存为，不关闭窗口
                return false

            case .alertSecondButtonReturn:
                // 不保存，清理临时文件后关闭
                if let url = doc.currentFileURL {
                    try? FileManager.default.removeItem(at: url)
                }
                return true

            default:
                // 取消，不关闭窗口
                return false
            }
        }
    }
}
