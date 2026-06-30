import SwiftUI
import MarkdownReaderKit
import os

/// 应用委托，处理 macOS 应用生命周期事件
///
/// macOS 15+ 上 SwiftUI WindowGroup 可能在启动时先创建 untitled 默认窗口。
/// 修复策略：
/// - 启动完成路由由 AppKit 启动意图 + SwiftUI 内容窗口 ready 事件共同触发
/// - 显式外部打开：URL 路由优先于恢复上次位置，并收敛冷启动默认窗口
/// - 直接启动 / Dock reopen：确认无显式 URL 后，复用内容窗口执行 welcome/restore
/// - 热启动：外部打开走多窗口，同 URL 聚焦；内部打开替换当前 key window
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.ft07.markmark", category: "AppDelegate")
    private let launchStartedAt = Date()

    /// 冷启动时记录待处理的文件 URL
    var pendingOpenFileURL: URL?

    /// 冷启动时记录待处理的目录 URL
    var pendingOpenDirectoryURL: URL?

    /// 应用是否已经完成启动（用于区分冷启动和热启动）
    private var didFinishLaunching = false

    /// 启动完成路由只在真实事件到达后触发：
    /// AppKit 启动意图 + SwiftUI 内容窗口 ready + applicationDidFinishLaunching。
    private var didRouteLaunchCompletion = false
    private var shouldPruneLateColdExplicitOpenAfterDirectRoute = false
    private var launchRoutingState = LaunchCompletionRoutingState()
    private weak var launchReadyWindow: NSWindow?
    private var contentWindowReadyObserver: NSObjectProtocol?

    /// Finder Services 冷启动时，SwiftUI WindowGroup / openWindow 可能尚未就绪。
    /// 先暂存服务传入的目录，启动完成并拿到 WindowRouter 后再打开，避免服务请求卡住 Finder。
    private var pendingServiceOpenURLs: [URL] = []

    /// Services 启动时 SwiftUI 场景可能不会自动创建窗口，需要 fallback。
    private var fallbackWindows: [NSWindow] = []
    private var fallbackWindowObservers: [NSObjectProtocol] = []

    private lazy var pendingOpenStore = UserDefaultsPendingOpenStore()
    private lazy var openRequestCoordinator = OpenRequestCoordinator(
        router: AppDelegateOpenRequestRouter(appDelegate: self),
        settings: SettingsOpenRequestSettings(),
        pendingStore: pendingOpenStore
    )

    /// 应用即将完成启动
    func applicationWillFinishLaunching(_ notification: Notification) {
        logger.info("applicationWillFinishLaunching")
        NSApp.servicesProvider = self
        installContentWindowReadyObserver()
    }

    /// 允许普通直接启动创建 SwiftUI 的 untitled/nil 默认窗口。
    ///
    /// 这里不能全局返回 `false`：当用户从 Dock/Finder 直接打开 App、且
    /// 没有显式 URL 事件时，SwiftUI `WindowGroup(for:)` 需要这个 nil 窗口
    /// 来承载欢迎页/恢复上次位置逻辑。若完全阻止 untitled 窗口，LaunchServices
    /// 路径下应用会在启动早期没有任何可用窗口，表现为“点了打不开”。
    ///
    /// 显式 URL 打开仍由 `application(_:open:)` / launch completion 收敛到目标
    /// URL 窗口，并通过后续 prune 避免旧的默认窗口干扰。
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        launchRoutingState.markUntitledLaunchRequest()
        tryRouteLaunchCompletion()
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        launchRoutingState.markUntitledLaunchRequest()
        tryRouteLaunchCompletion()
        return false
    }

    /// 禁用 AppKit/SwiftUI 的系统窗口状态恢复。MarkMark 自己通过
    /// SettingsModel.lastOpened* 控制 restore；系统级恢复会在显式 URL 启动时
    /// 抢先恢复旧窗口，造成“拖 B 还打开 A / 一堆空窗口”。
    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    // MARK: - 窗口辅助

    /// 激活第一个不可见的可成为 key 的窗口（SwiftUI WindowGroup 创建的）
    /// SwiftUI 有时会创建不可见窗口来处理文件打开事件，需要手动激活
    /// 使用 canBecomeKey + isSheet + isPanel 判断，避免依赖私有类名
    private func activateFirstHiddenWindow() {
        for window in NSApp.windows {
            if !window.isSheet && window.canBecomeKey && !(window is NSPanel) {
                if !window.isVisible || window.isMiniaturized {
                    logger.info("Activating hidden window: title='\(window.title)'")
                    window.deminiaturize(nil)
                    window.setIsVisible(true)
                }
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Services / Finder 场景下强制把应用切到普通前台 App，并按需拉起已有隐藏窗口。
    ///
    /// 显式 URL 启动（Finder 拖到图标 / 打开方式 / 双击文件）不能先 reveal 隐藏窗口，
    /// 否则 SwiftUI 预建的 nil/恢复窗口会先闪一下，再被真正目标窗口替换。
    private func bringApplicationToFront(revealHiddenWindow: Bool = true) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        if revealHiddenWindow {
            activateFirstHiddenWindow()
        }
        if revealHiddenWindow {
            if #available(macOS 14.0, *) {
                NSRunningApplication.current.activate(options: [.activateAllWindows])
            } else {
                NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// 检查是否有可见窗口
    private func hasVisibleWindows() -> Bool {
        hasUsableWindow()
    }

    fileprivate func hasUsableWindow() -> Bool {
        NSApp.windows.contains {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) && !$0.isSheet
        }
    }

    // MARK: - 文件打开回调

    /// macOS 13+ URL 版本的文件打开回调
    /// 冷启动时在 applicationDidFinishLaunching 之前调用
    /// 热启动时直接调用
    func application(_ application: NSApplication, open urls: [URL]) {
        logger.info("application(_:open:) called with \(urls.count) URLs, didFinish=\(self.didFinishLaunching)")
        guard let first = urls.first else { return }

        if didFinishLaunching && didRouteLaunchCompletion {
            openRequestCoordinator.handleExternalOpen(
                urls: urls,
                reason: .finderOpen,
                isLaunchCompleted: true
            )
            if shouldPruneLateColdExplicitOpenAfterDirectRoute,
               Date().timeIntervalSince(launchStartedAt) < 3.0 {
                shouldPruneLateColdExplicitOpenAfterDirectRoute = false
                scheduleExclusiveColdExplicitWindowPrune(keeping: first)
                scheduleDirectLaunchDuplicateWindowPrune()
            } else if shouldPruneLateColdExplicitOpenAfterDirectRoute {
                shouldPruneLateColdExplicitOpenAfterDirectRoute = false
            }
        } else {
            // 冷启动：不要写 UserDefaults pending 与 SwiftUI URL WindowGroup 竞争。
            // 先只在 AppDelegate 内存里记录显式 URL；启动完成后如果 SwiftUI
            // 已经创建了 URL 绑定窗口就聚焦它，否则再补开一次。
            rememberPendingOpenURL(first)
            logger.info("Cold start: remembered explicit URL for post-launch routing")
            tryRouteLaunchCompletion()
        }
    }

    /// Finder 右键「服务」入口：接收选中的文件或文件夹 URL，并复用现有打开逻辑。
    @objc(openInMarkMark:userData:error:)
    func openInMarkMark(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let urls = openRequestCoordinator.serviceFileURLs(from: pasteboard)
        guard !urls.isEmpty else {
            error.pointee = "No file or folder URL was provided to MarkMark."
            logger.error("Services entry invoked without file or folder URLs")
            return
        }

        logger.info("Services entry opening \(urls.count) file/folder URL(s)")
        if !didRouteLaunchCompletion {
            launchRoutingState.markExplicitIntentWithoutURL()
        }
        pendingServiceOpenURLs = urls
        bringApplicationToFront()
        tryRouteLaunchCompletion()

        // 让 Finder 的 Services 调用尽快返回；实际打开目录等 SwiftUI openWindow 注册后异步完成。
        DispatchQueue.main.async { [weak self] in
            self?.openPendingServiceURLsWhenReady()
        }
    }

    private func openPendingServiceURLsWhenReady(attempt: Int = 0) {
        guard !pendingServiceOpenURLs.isEmpty else { return }

        bringApplicationToFront()

        if didFinishLaunching && (WindowRouter.shared.canOpenWindow || hasUsableWindow() || attempt >= 5) {
            let urls = pendingServiceOpenURLs
            pendingServiceOpenURLs.removeAll()
            clearPendingOpenURLDefaults()

            openRequestCoordinator.handleExternalOpen(
                urls: urls,
                reason: .finderService,
                isLaunchCompleted: true
            )
            scheduleActivationPulse()
            return
        }

        guard attempt < 20 else {
            // 极端兜底：如果 SwiftUI 窗口迟迟没有注册，至少把第一个目录写入 pending，
            // 下次普通启动仍可恢复，不让服务请求彻底丢失。
            if let first = pendingServiceOpenURLs.first {
                openRequestCoordinator.handleExternalOpen(
                    urls: [first],
                    reason: .finderService,
                    isLaunchCompleted: false
                )
                rememberPendingOpenURL(first)
            }
            logger.error("Timed out waiting for WindowRouter for Services open request")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.openPendingServiceURLsWhenReady(attempt: attempt + 1)
        }
    }

    private func schedulePendingOpenWatchdog(for url: URL, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.resolvePendingOpenIfStillUnconsumed(url, attempt: attempt)
        }
    }

    private func resolvePendingOpenIfStillUnconsumed(_ url: URL, attempt: Int) {
        if WindowRouter.shared.hasRegisteredWindow(for: url) {
            logger.info("Pending open already has a registered window; clearing pending: \(url.path)")
            clearPendingOpenURLDefaults()
            bringApplicationToFront()
            return
        }

        guard pendingOpenURLFromDefaults() == url.markMarkCanonicalFileURL else {
            logger.info("Pending open was consumed by ContentView")
            bringApplicationToFront()
            return
        }

        guard didFinishLaunching else {
            schedulePendingOpenWatchdog(for: url, attempt: attempt + 1)
            return
        }

        // 给初始 ContentView.task 一个短窗口读取 pending；若仍残留，说明打开事件到达太晚，
        // 需要 AppDelegate 主动路由，修复 Finder「打开方式」只恢复上次目录的问题。
        guard attempt >= 8 else {
            schedulePendingOpenWatchdog(for: url, attempt: attempt + 1)
            return
        }

        logger.info("Pending open was not consumed; routing explicitly: \(url.path)")
        clearPendingOpenURLDefaults()
        openRequestCoordinator.handleExternalOpen(
            urls: [url],
            reason: .finderOpen,
            isLaunchCompleted: true
        )
        scheduleActivationPulse()
    }

    private func pendingOpenURLFromDefaults() -> URL? {
        pendingOpenStore.pendingURL
    }

    fileprivate func routeURLsToApp(
        _ urls: [URL],
        reason: String,
        preferExistingWindow: Bool = false
    ) {
        guard !urls.isEmpty else { return }

        if preferExistingWindow, hasUsableWindow() {
            bringApplicationToFront(revealHiddenWindow: true)
            logger.info("Routing \(urls.count) URL(s) through existing window notifications, reason=\(reason)")
            for url in urls {
                postExternalOpenNotification(for: url)
            }
            scheduleActivationPulse()
            return
        }

        logger.info("Routing \(urls.count) URL(s) through WindowRouter/fallback windows, reason=\(reason)")
        for url in urls {
            if !WindowRouter.shared.openWindow(for: url) {
                openFallbackWindow(for: url)
            }
        }
    }


    private func scheduleActivationPulse(revealHiddenWindow: Bool = false) {
        bringApplicationToFront(revealHiddenWindow: revealHiddenWindow)
        for delay in [0.1, 0.4, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.bringApplicationToFront(revealHiddenWindow: revealHiddenWindow)
            }
        }
    }

    fileprivate func postOpenNotification(for url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        NotificationCenter.default.post(
            name: isDirectory.boolValue ? .openDirectory : .openFile,
            object: url
        )
    }

    private func postExternalOpenNotification(for url: URL) {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        NotificationCenter.default.post(
            name: isDirectory.boolValue ? .openExternalDirectory : .openExternalFile,
            object: url
        )
    }

    private func openFallbackWindow(for url: URL) {
        let rootView = ContentView(openedURL: url, registersWindowRouter: false, showsWindowTitle: false)
            .environment(\.language, SettingsModel.shared.languagePref.resolvedLanguage)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureFallbackWindow(window, hostingController: hostingController)
        fallbackWindows.append(window)
        observeFallbackWindowClose(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureFallbackWindow<Content: View>(_ window: NSWindow, hostingController: NSHostingController<Content>) {
        window.contentViewController = hostingController
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 650, height: 450)
        window.center()

        // fallback 窗口不走 SwiftUI .windowStyle(.hiddenTitleBar)，这里必须主动隐藏系统红绿灯。
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func observeFallbackWindowClose(_ window: NSWindow) {
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self, weak window] in
                guard let self, let window else { return }
                self.fallbackWindows.removeAll { $0 === window }
            }
        }
        fallbackWindowObservers.append(observer)
    }


    fileprivate func openFallbackWelcomeWindow() {
        let rootView = ContentView(openedURL: nil, registersWindowRouter: false, showsWindowTitle: false)
            .environment(\.language, SettingsModel.shared.languagePref.resolvedLanguage)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureFallbackWindow(window, hostingController: hostingController)
        fallbackWindows.append(window)
        observeFallbackWindowClose(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate func restoreLastLocationOrOpenWelcomeFallback() {
        if let dir = SettingsModel.shared.lastOpenedDirectory {
            routeURLsToApp([dir], reason: "restore-fallback")
        } else if let file = SettingsModel.shared.lastOpenedFile {
            routeURLsToApp([file], reason: "restore-fallback")
        } else {
            openFallbackWelcomeWindow()
        }
    }

    /// 把启动 / Dock reopen 产生的恢复类通知投递给确定的内容窗口。
    ///
    /// 事件驱动启动路由会比 SwiftUI 的 `controlActiveState == .key` 环境刷新更早；
    /// 如果继续依赖 `onActiveReceive`，通知可能在窗口刚 `makeKeyAndOrderFront`
    /// 但 SwiftUI 还未标记为 key 时被丢弃，表现为直接启动不恢复上次单文件。
    fileprivate func postWindowRoutedNotification(_ name: Notification.Name) {
        let targetWindow = launchReadyWindow
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first {
                $0.canBecomeKey && !($0 is NSPanel) && !$0.isSheet
            }
        NotificationCenter.default.post(name: name, object: targetWindow)
    }

    /// 记录冷启动显式打开请求，确保它优先于恢复上次位置。
    /// UserDefaults pending 由 OpenRequestCoordinator/PendingOpenStore 负责；这里仅保留
    /// AppDelegate 级别的启动期标记，用于 applicationDidFinishLaunching 的 restore guard。
    private func rememberPendingOpenURL(_ url: URL) {
        launchRoutingState.markExplicitURL(url)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            pendingOpenDirectoryURL = url
            pendingOpenFileURL = nil
        } else {
            pendingOpenFileURL = url
            pendingOpenDirectoryURL = nil
        }
    }


    private func rememberedLaunchOpenURL() -> URL? {
        pendingOpenFileURL ?? pendingOpenDirectoryURL
    }

    private func clearPendingOpenURLDefaults() {
        pendingOpenDirectoryURL = nil
        pendingOpenFileURL = nil
        pendingOpenStore.clear()
    }

    private func installContentWindowReadyObserver() {
        guard contentWindowReadyObserver == nil else { return }
        contentWindowReadyObserver = NotificationCenter.default.addObserver(
            forName: .contentWindowReadyForLaunchRouting,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let readyWindow = notification.object as? NSWindow
            let isUntitledLaunchWindow = notification.userInfo?["isUntitledLaunchWindow"] as? Bool == true
            MainActor.assumeIsolated {
                guard let self else { return }
                if let window = readyWindow {
                    self.launchReadyWindow = window
                }
                if isUntitledLaunchWindow {
                    self.launchRoutingState.markUntitledLaunchRequest()
                }
                self.launchRoutingState.markContentWindowReady()
                self.tryRouteLaunchCompletion()

                if !self.pendingServiceOpenURLs.isEmpty {
                    self.openPendingServiceURLsWhenReady()
                }
            }
        }
    }

    // MARK: - 应用生命周期

    /// 应用启动完成后，处理冷启动场景
    /// 如果有待处理文件 URL，ContentView.task 会通过 UserDefaults 读取并打开。
    /// 如果没有待处理文件且 reopenLastLocation 开启，发送 restoreLastLocation 通知。
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        // 在任何 SwiftUI 视图创建前设置 appearance，避免 NSTextView textColor 被 AppKit 覆盖
        // ContentView.task 中的 applyAppearance() 仍保留作为兜底
        let appearanceMode = SettingsModel.shared.appearanceMode
        if let nsAppearance = appearanceMode.nsAppearance {
            NSApp.appearance = nsAppearance
        }

        didFinishLaunching = true
        launchRoutingState.markDidFinishLaunching()
        logger.info("applicationDidFinishLaunching — pendingFile: \(self.pendingOpenFileURL != nil), pendingDir: \(self.pendingOpenDirectoryURL != nil)")

        tryRouteLaunchCompletion()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        launchRoutingState.markDidBecomeActive()
        tryRouteLaunchCompletion()
    }

    private func tryRouteLaunchCompletion() {
        guard !didRouteLaunchCompletion else { return }

        launchRoutingState.updatePendingStoreURL(pendingOpenStore.pendingURL)
        switch launchRoutingState.decision {
        case .wait:
            return
        case .routeExplicitURL(let url):
            completeLaunchRouting {
                shouldPruneLateColdExplicitOpenAfterDirectRoute = false
                pendingOpenFileURL = nil
                pendingOpenDirectoryURL = nil
                if WindowRouter.shared.hasRegisteredWindow(for: url) {
                    logger.info("Cold start: explicit open already has a registered window: \(url.path)")
                    WindowRouter.shared.openWindow(for: url)
                    scheduleActivationPulse()
                } else {
                    logger.info("Cold start: routing explicit open once: \(url.path)")
                    openRequestCoordinator.handleExternalOpen(
                        urls: [url],
                        reason: .finderOpen,
                        isLaunchCompleted: true
                    )
                }
                scheduleExclusiveColdExplicitWindowPrune(keeping: url)
                pendingOpenStore.clear()
            }
        case .suppressRestore:
            completeLaunchRouting {
                shouldPruneLateColdExplicitOpenAfterDirectRoute = false
                logger.info("Cold start: explicit open handled; restore suppressed")
            }
        case .routeDirectLaunch:
            completeLaunchRouting {
                shouldPruneLateColdExplicitOpenAfterDirectRoute = true
                // 只有确认不是显式 URL 启动后，才允许把 SwiftUI 预建窗口显示出来，
                // 再执行 MarkMark 自己的欢迎页/恢复上次位置逻辑。
                if let launchReadyWindow {
                    focusLaunchReadyWindow(launchReadyWindow)
                } else if !hasVisibleWindows() {
                    activateFirstHiddenWindow()
                }
                openRequestCoordinator.handleLaunchCompleted()
                scheduleDirectLaunchDuplicateWindowPrune()
            }
        }
    }

    private func focusLaunchReadyWindow(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if !window.isVisible {
            window.setIsVisible(true)
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completeLaunchRouting(_ route: () -> Void) {
        // 注册窗口拖拽：绕过 SwiftUI .onDrop，直接使用 AppKit NSDraggingDestination
        installFileDropHandler()
        route()
        didRouteLaunchCompletion = true
        launchRoutingState.markRouted()

        if !pendingServiceOpenURLs.isEmpty {
            openPendingServiceURLsWhenReady()
        }
    }

    /// 冷启动显式打开 URL 是排他入口：拖拽/打开方式/双击文件应压过默认欢迎页和系统恢复窗口。
    ///
    /// SwiftUI 可能先为直接启动创建 nil 窗口，再收到显式 URL 窗口；这里等目标 URL
    /// 窗口注册后再多次收敛，关闭默认/旧窗口。目标文件窗口自身也会注册
    /// `WindowRouter.open`，所以不需要保留 nil 宿主窗口来维持后续多窗口能力。
    private func scheduleExclusiveColdExplicitWindowPrune(keeping url: URL, attempt: Int = 0) {
        let delay = attempt == 0 ? 0.02 : 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if WindowRouter.shared.hasRegisteredWindow(for: url) {
                WindowRouter.shared.closeVisibleContentWindows(except: url)
                self.bringApplicationToFront(revealHiddenWindow: false)
            }
            if attempt < 12 {
                self.scheduleExclusiveColdExplicitWindowPrune(keeping: url, attempt: attempt + 1)
            }
        }
    }

    /// 普通直接启动没有显式 URL，但 macOS/SwiftUI 可能同时创建一个 nil 默认窗口和一个
    /// restore/welcome 窗口。冷启动完成后只保留当前 key/main 内容窗口，避免“打开 App
    /// 后出现两个窗口”。仅用于 launch completion 的无显式 URL 分支，不影响热打开多窗口。
    private func scheduleDirectLaunchDuplicateWindowPrune(attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.closeDuplicateVisibleContentWindowsKeepingKey()
            if attempt < 6 {
                self.scheduleDirectLaunchDuplicateWindowPrune(attempt: attempt + 1)
            }
        }
    }

    private func closeDuplicateVisibleContentWindowsKeepingKey() {
        let contentWindows = NSApp.windows.filter {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel) && !$0.isSheet
        }
        guard contentWindows.count > 1 else { return }

        let windowToKeep = NSApp.keyWindow ?? NSApp.mainWindow ?? contentWindows[0]
        for window in contentWindows where window !== windowToKeep {
            window.close()
        }
        windowToKeep.orderFrontRegardless()
        windowToKeep.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Dock 点击处理

    /// 用户点击 Dock 图标时调用
    /// 当所有窗口都关闭后点击 Dock 图标，激活隐藏窗口
    /// 根据 reopenLastLocation 设置决定恢复上次位置还是显示欢迎页
    /// 返回 false 阻止 SwiftUI WindowGroup 自动创建新窗口，避免双窗口 bug
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            logger.info("applicationShouldHandleReopen — activating hidden window")
            activateFirstHiddenWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.installFileDropHandler()
                self.openRequestCoordinator.handleDockReopen()
            }
        }
        return false
    }

    // MARK: - 窗口级拖拽处理

    /// 在窗口上安装文件拖拽处理器
    /// 完全绕过 SwiftUI .onDrop，直接使用 AppKit NSDraggingDestination
    /// 将 overlay 添加到 themeFrame（contentView.superview），确保在所有子视图之上
    private func installFileDropHandler() {
        for window in NSApp.windows {
            guard window.isVisible,
                  window.canBecomeKey,
                  !(window is NSPanel),
                  let contentView = window.contentView,
                  let themeFrame = contentView.superview else { continue }

            let existing = themeFrame.subviews.first(where: { $0 is FileDropOverlayView })
            if existing != nil { continue }

            let overlay = FileDropOverlayView()
            themeFrame.addSubview(overlay)
            overlay.frame = themeFrame.bounds
            overlay.autoresizingMask = [.width, .height]
            logger.info("FileDropOverlayView installed on theme frame of window '\(window.title)'")
        }
    }
}


// MARK: - Open request router adapter

@MainActor
private final class AppDelegateOpenRequestRouter: OpenRequestRouting {
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    var hasUsableWindow: Bool {
        appDelegate?.hasUsableWindow() ?? false
    }

    func openExternalURL(_ url: URL) {
        appDelegate?.routeURLsToApp([url], reason: "open-request-coordinator")
    }

    func replaceActiveWindow(with url: URL) {
        appDelegate?.postOpenNotification(for: url)
    }

    func restoreLastLocation() {
        if appDelegate?.hasUsableWindow() == true {
            appDelegate?.postWindowRoutedNotification(.restoreLastLocation)
        } else {
            appDelegate?.restoreLastLocationOrOpenWelcomeFallback()
        }
    }

    func resetToWelcome() {
        if appDelegate?.hasUsableWindow() == true {
            appDelegate?.postWindowRoutedNotification(.resetToWelcome)
        } else {
            appDelegate?.openFallbackWelcomeWindow()
        }
    }
}

// MARK: - 文件拖拽覆盖视图

/// 透明 NSView 覆盖层，直接实现 NSDraggingDestination 处理文件拖拽
///
/// 完全绕过 SwiftUI 的 .onDrop 机制。
/// 安装在窗口 themeFrame 上，位于所有子视图之上。
/// hitTest 始终返回 nil — macOS 拖拽系统通过 registerForDraggedTypes + 视图 frame
/// 独立路由拖拽事件，不依赖 hitTest；返回 nil 确保所有鼠标事件（点击、滚动等）
/// 透传到下层 SwiftUI 视图。
final class FileDropOverlayView: NSView {

    private let logger = Logger(subsystem: "com.ft07.markmark", category: "FileDropOverlay")

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
        logger.info("viewDidMoveToSuperview — superview: \(self.superview != nil ? "yes" : "no"), frame: \(NSStringFromRect(self.frame))")
    }

    override func draw(_ dirtyRect: NSRect) {
    }

    // MARK: - hitTest 策略

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 始终返回 nil：透传所有鼠标事件（点击、滚动）
        // macOS 拖拽系统通过 registerForDraggedTypes + 视图 frame 独立路由拖拽事件
        return nil
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let canAccept = canAcceptDrag(sender)
        logger.info("draggingEntered — canAccept: \(canAccept)")
        guard canAccept else { return [] }
        NotificationCenter.default.post(name: .dragHoverChanged, object: true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        logger.info("draggingExited")
        NotificationCenter.default.post(name: .dragHoverChanged, object: false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        logger.info("performDragOperation")
        NotificationCenter.default.post(name: .dragHoverChanged, object: false)

        let pasteboard = sender.draggingPasteboard

        let urls: [URL]
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            urls = fileURLs
        } else if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
                  !paths.isEmpty {
            urls = paths.map { URL(fileURLWithPath: $0) }
        } else {
            return false
        }

        guard let url = urls.first else { return false }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }

        Task { @MainActor in
            for url in urls {
                WindowRouter.shared.openWindow(for: url.markMarkCanonicalFileURL)
            }
        }
        return true
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    // MARK: - 辅助

    private func canAcceptDrag(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadObject(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) {
            return true
        }
        if pasteboard.types?.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) == true {
            return true
        }
        return false
    }
}
