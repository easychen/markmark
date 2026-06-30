import SwiftUI
import MarkdownReaderKit
import WebKit

/// 仅绘制左侧边缘（含圆角）的 Shape，用于左边框描边
struct LeftEdgeShape: Shape {
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // 从顶部开始，绘制左上圆角
        path.move(to: CGPoint(x: radius, y: 0))
        path.addArc(
            tangent1End: CGPoint(x: 0, y: 0),
            tangent2End: CGPoint(x: 0, y: radius),
            radius: radius
        )
        // 左侧直线
        path.addLine(to: CGPoint(x: 0, y: rect.height - radius))
        // 左下圆角
        path.addArc(
            tangent1End: CGPoint(x: 0, y: rect.height),
            tangent2End: CGPoint(x: radius, y: rect.height),
            radius: radius
        )
        return path
    }
}

/// 右侧主体区容器（圆角），包含内容区和底部项目状态栏
struct DetailView: View {
    let appViewModel: AppViewModel
    let documentViewModel: DocumentViewModel
    let fileTreeViewModel: FileTreeViewModel
    let settings: SettingsModel
    var canNavigateBack: Bool = false
    var canNavigateForward: Bool = false
    var navigateBack: () -> Void = {}
    var navigateForward: () -> Void = {}
    var toggleSidebar: () -> Void = {}
    var toggleOutline: () -> Void = {}
    var onLocalMarkdownLink: (URL) -> Void = { _ in }
    @Environment(\.language) private var language
    @Environment(\.themeColors) private var themeColors

    /// 查找替换 ViewModel
    @State private var findReplaceViewModel = FindReplaceViewModel()

    /// NSTextView 搜索引用，用于 Raw 模式搜索/高亮/替换
    @State private var textViewSearchRef = TextViewSearchRef()

    /// 刷新确认弹窗状态
    @State private var showReloadAlert = false
    @State private var dontRemindAgain = false

    @State private var isDropTargeted = false

    @State private var showUnsupportedFileAlert = false
    @State private var unsupportedFileExt = ""

    /// 渲染模式下当前可见标题的行号（用于大纲高亮同步）
    @State private var activeOutlineLineNumber: Int?

    /// PDF 导出失败提示
    @State private var showExportPDFError = false

    @State private var showExportHTMLError = false

    /// 导出 / CriticMarkup 复用的 WKWebView 句柄
    @State private var webViewHandle = WebViewHandle()

    /// 应用 / 放弃所有标注确认弹窗
    @State private var showApplyAnnotationsAlert = false
    @State private var showDiscardAnnotationsAlert = false

    /// 「已复制」轻提示
    @State private var copiedToastVisible = false
    @State private var copiedToastGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            Rectangle().fill(themeColors.border).frame(height: 1)

            // 内容区域
            contentArea
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeColors.accent, lineWidth: 2)
                            .padding(4)
                    }
                }
                .overlay(alignment: .bottom) {
                    if copiedToastVisible {
                        Text(L10n.tr(.copiedToast, language: language))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(themeColors.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(themeColors.surface))
                            .overlay(Capsule().strokeBorder(themeColors.border))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                            .padding(.bottom, 20)
                            .transition(.opacity)
                    }
                }
        }
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
        .onActiveReceive(NotificationCenter.default.publisher(for: .reloadFile)) { _ in
            handleReloadButtonTapped()
        }
        .onActiveReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            exportPDF()
        }
        .onActiveReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
            exportHTML()
        }
        .onActiveReceive(NotificationCenter.default.publisher(for: .copyForAI)) { _ in
            copyForAI()
        }
        .onActiveReceive(NotificationCenter.default.publisher(for: .applyAllAnnotations)) { _ in
            if documentHasAnnotations { showApplyAnnotationsAlert = true }
        }
        .onActiveReceive(NotificationCenter.default.publisher(for: .discardAllAnnotations)) { _ in
            if documentHasAnnotations { showDiscardAnnotationsAlert = true }
        }
        .alert(L10n.tr(.applyAnnotationsConfirmTitle, language: language), isPresented: $showApplyAnnotationsAlert) {
            Button(L10n.tr(.applyAnnotationsMenu, language: language), role: .destructive) {
                documentViewModel.applyAllAnnotations()
            }
            Button(L10n.tr(.unsavedCancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.tr(.applyAnnotationsConfirmMessage, language: language))
        }
        .alert(L10n.tr(.discardAnnotationsConfirmTitle, language: language), isPresented: $showDiscardAnnotationsAlert) {
            Button(L10n.tr(.discardAnnotationsMenu, language: language), role: .destructive) {
                documentViewModel.discardAllAnnotations()
            }
            Button(L10n.tr(.unsavedCancel, language: language), role: .cancel) {}
        } message: {
            Text(L10n.tr(.discardAnnotationsConfirmMessage, language: language))
        }
        // 拖拽视觉反馈：由 AppKit FileDropOverlayView 发送
        .onReceive(NotificationCenter.default.publisher(for: .dragHoverChanged)) { notification in
            if let isTargeted = notification.object as? Bool {
                isDropTargeted = isTargeted
            }
        }
        // 不支持文件类型提示：由 AppKit FileDropOverlayView 发送
        .onReceive(NotificationCenter.default.publisher(for: .unsupportedFileTypeDropped)) { notification in
            if let ext = notification.object as? String {
                unsupportedFileExt = ext
                showUnsupportedFileAlert = true
            }
        }
        .alert(L10n.tr(.exportPDFFailed, language: language), isPresented: $showExportPDFError) {
            Button(L10n.tr(.confirm, language: language), role: .cancel) {}
        }
        .alert(L10n.tr(.exportHTMLFailed, language: language), isPresented: $showExportHTMLError) {
            Button(L10n.tr(.confirm, language: language), role: .cancel) {}
        }
        .alert(
            L10n.tr(.unsupportedFileTypeAlert, language: language, args: ["ext": unsupportedFileExt]),
            isPresented: $showUnsupportedFileAlert
        ) {
            Button(L10n.tr(.confirm, language: language), role: .cancel) {}
        }
    }

    // MARK: - TitleBar

    @ViewBuilder
    private var titleBar: some View {
        HStack(spacing: 0) {
            if !appViewModel.isSidebarVisible {
                TrafficLightButtons()
                    .padding(.leading, 12)

                TitleBarIconButton(
                    systemName: "sidebar.leading",
                    helpText: L10n.tr(.titleBarToggleSidebar, language: language)
                ) {
                    toggleSidebar()
                }
                .padding(.leading, 8)

                TitleBarIconButton(
                    systemName: "folder.fill",
                    helpText: L10n.tr(.titleBarOpen, language: language)
                ) {
                    OpenPanelHelper.show(language: language)
                }
                .padding(.leading, 2)

                // 从剪贴板新建标注（始终可用，无需打开目录）
                TitleBarIconButton(
                    systemName: "doc.on.clipboard",
                    helpText: "\(L10n.tr(.newFromClipboard, language: language)) (⌘N)"
                ) {
                    NotificationCenter.default.post(name: .newFromClipboard, object: nil)
                }
                .padding(.leading, 2)

                TitleBarIconButton(
                    systemName: "chevron.left",
                    helpText: "\(L10n.tr(.navigationBack, language: language)) (⌘[)",
                    isEnabled: canNavigateBack,
                    action: navigateBack
                )
                .padding(.leading, 8)

                TitleBarIconButton(
                    systemName: "chevron.right",
                    helpText: "\(L10n.tr(.navigationForward, language: language)) (⌘])",
                    isEnabled: canNavigateForward,
                    action: navigateForward
                )
                .padding(.leading, 2)
            }

            // 文件路径或 Untitled 标识（左对齐，仅在有文档时显示）
            if documentViewModel.hasDocument {
                if documentViewModel.isUntitled {
                    Text(documentViewModel.fileName)
                        .font(.system(size: 12))
                        .foregroundStyle(themeColors.fgMuted)
                        .padding(.leading, 12)
                } else if let path = documentViewModel.currentFileURL?.path {
                    Text(path)
                        .font(.system(size: 12))
                        .foregroundStyle(themeColors.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 12)

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(path, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(themeColors.fgMuted)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr(.titleBarCopyPath, language: language))
                    .padding(.leading, 2)
                }
            }

            Spacer()

            // MarkMark 无编辑功能，移除渲染/编辑切换。

            // 操作按钮组与大纲图标下对齐，横向间隔一致
            HStack(alignment: .bottom, spacing: 8) {
                // 刷新按钮（常驻；文件被外部修改时以强调色提示）
                if documentViewModel.hasDocument {
                    TitleBarIconButton(
                        systemName: "arrow.clockwise",
                        helpText: L10n.tr(.titleBarReload, language: language),
                        foregroundColor: documentViewModel.isFileModifiedExternally ? themeColors.accent : themeColors.fgMuted
                    ) {
                        handleReloadButtonTapped()
                    }
                }

                // 保存按钮（在渲染模式切换右侧）
                if documentViewModel.hasDocument && documentViewModel.isMarkdownDocument {
                    TitleBarIconButton(
                        systemName: "arrow.down.doc.fill",
                        helpText: L10n.tr(.titleBarSave, language: language),
                        isEnabled: documentViewModel.isDirty,
                        foregroundColor: documentViewModel.isDirty ? themeColors.accent : themeColors.fgMuted
                    ) {
                        NotificationCenter.default.post(name: .saveFile, object: nil)
                    }

                    TitleBarIconMenu(
                        systemName: "square.and.arrow.up",
                        helpText: L10n.tr(.titleBarExportPDF, language: language),
                        foregroundColor: themeColors.fgMuted
                    ) {
                        Button {
                            exportPDF()
                        } label: {
                            Label(L10n.tr(.exportPDF, language: language), systemImage: "doc.richtext")
                        }
                        .keyboardShortcut("e", modifiers: [.command, .option])

                        Button {
                            exportHTML()
                        } label: {
                            Label(L10n.tr(.exportHTML, language: language), systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    }

                    // 应用 / 放弃所有标注（仅当存在标注时显示）
                    if documentHasAnnotations {
                        TitleBarIconMenu(
                            systemName: "checkmark.circle.badge.xmark",
                            helpText: L10n.tr(.titleBarAnnotationActions, language: language),
                            foregroundColor: themeColors.fgMuted
                        ) {
                            Button {
                                showApplyAnnotationsAlert = true
                            } label: {
                                Label(L10n.tr(.applyAnnotationsMenu, language: language), systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                showDiscardAnnotationsAlert = true
                            } label: {
                                Label(L10n.tr(.discardAnnotationsMenu, language: language), systemImage: "eraser")
                            }
                        }
                    }

                    // 复制：macOS 标准下拉按钮（图标 + 内联 chevron），单击即展开菜单。
                    TitleBarIconMenu(
                        systemName: "doc.on.doc",
                        helpText: L10n.tr(.titleBarCopyMenu, language: language),
                        foregroundColor: themeColors.fgMuted
                    ) {
                        Button {
                            copyForAI()
                        } label: {
                            Label(L10n.tr(.copyForAIMenu, language: language), systemImage: "sparkles")
                        }
                        .keyboardShortcut("c", modifiers: [.command, .shift])

                        Button {
                            copySessionFragments()
                        } label: {
                            Label(L10n.tr(.copyFragmentsMenu, language: language), systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        Button {
                            copyCritic()
                        } label: {
                            Label(L10n.tr(.copyCriticMenu, language: language), systemImage: "doc.on.doc")
                        }
                        Button {
                            copyPrompt()
                        } label: {
                            Label(L10n.tr(.copyPromptMenu, language: language), systemImage: "text.quote")
                        }
                    }

                    // 标注列表面板切换
                    TitleBarIconButton(
                        systemName: "highlighter",
                        helpText: L10n.tr(.titleBarAnnotationPanel, language: language),
                        isEnabled: documentViewModel.hasDocument,
                        foregroundColor: annotationPanelButtonColor
                    ) {
                        appViewModel.toggleAnnotationPanel()
                    }
                }

                // 大纲切换按钮（始终显示在 titlebar 最右侧）
                TitleBarIconButton(
                    systemName: "sidebar.right",
                    helpText: L10n.tr(.titleBarToggleOutline, language: language),
                    isEnabled: documentViewModel.hasDocument && documentViewModel.isMarkdownDocument,
                    foregroundColor: outlineButtonColor
                ) {
                    toggleOutline()
                }
            }
            .padding(.trailing, 12)
        }
        .frame(height: 50)
        .background(WindowDragArea())
        .zIndex(10)
        .alert(L10n.tr(.fileModifiedExternallyTitle, language: language), isPresented: $showReloadAlert) {
            Button(L10n.tr(.fileModifiedExternallyReload, language: language), role: .destructive) {
                Task {
                    await documentViewModel.reloadFromDisk()
                }
                if dontRemindAgain {
                    settings.skipFileModifiedAlert = true
                }
            }
            Button(L10n.tr(.unsavedCancel, language: language), role: .cancel) {
                dontRemindAgain = false
            }
        } message: {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr(.fileModifiedExternallyMessage, language: language))
                Toggle(L10n.tr(.fileModifiedExternallyDontRemind, language: language), isOn: $dontRemindAgain)
            }
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var contentArea: some View {
        if documentViewModel.hasDocument {
            documentContentWithOutline
        } else if appViewModel.rootDirectory == nil && !appViewModel.isSingleFileMode {
            WelcomeView(appViewModel: appViewModel, settings: settings)
        } else if let error = documentViewModel.fileError {
            ErrorView(
                icon: "exclamationmark.triangle",
                message: error.localizedDescription
            )
        } else if documentViewModel.isLoading {
            // 仅在首次加载（无已有文档）时显示进度指示器
            ProgressView()
                .tint(themeColors.fgSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !appViewModel.isSingleFileMode && fileTreeViewModel.isEmptyDirectory {
            ErrorView(
                icon: "folder",
                message: L10n.tr(.emptyDirectoryMessage, language: language)
            )
        } else {
            selectFilePlaceholder
        }
    }

    // MARK: - 文档内容（带大纲分栏）

    @ViewBuilder
    private var documentContentWithOutline: some View {
        HStack(spacing: 0) {
            // 左侧：Markdown 主内容区
            documentContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 右侧：大纲 / 标注列表侧边栏（互斥，共用宽度与拖拽手柄）
            if appViewModel.isOutlineVisible && documentViewModel.isMarkdownDocument {
                OutlineResizeHandle(appViewModel: appViewModel)

                outlineSidebar
                    .frame(width: appViewModel.outlineWidth)
            } else if appViewModel.isAnnotationPanelVisible && documentViewModel.isMarkdownDocument {
                OutlineResizeHandle(appViewModel: appViewModel)

                AnnotationPanelView(documentViewModel: documentViewModel, onCopied: { flashCopiedToast() })
                    .frame(width: appViewModel.outlineWidth)
            }
        }
    }

    // MARK: - 大纲侧边栏

    /// 大纲按钮颜色：激活时强调色，有文档时次要色，无文档时弱化色
    /// 处理刷新按钮点击
    private func handleReloadButtonTapped() {
        if documentViewModel.isDirty && !settings.skipFileModifiedAlert {
            showReloadAlert = true
        } else {
            Task {
                await documentViewModel.reloadFromDisk()
            }
        }
    }

    // MARK: - CriticMarkup

    /// 当前文档是否包含 CriticMarkup 标注
    private var documentHasAnnotations: Bool {
        documentViewModel.isMarkdownDocument && CriticMarkup.hasMarkup(documentViewModel.content)
    }

    /// 传给渲染视图选词工具条的本地化文案
    private var criticLabels: [String: String] {
        [
            "delete": L10n.tr(.criticDelete, language: language),
            "highlight": L10n.tr(.criticHighlight, language: language),
            "comment": L10n.tr(.criticComment, language: language),
            "replace": L10n.tr(.criticReplace, language: language),
            "confirm": L10n.tr(.criticConfirm, language: language),
            "cancel": L10n.tr(.criticCancel, language: language),
            "edit": L10n.tr(.criticEdit, language: language),
            "notFound": L10n.tr(.criticNotFound, language: language),
            "commentHint": L10n.tr(.criticCommentHint, language: language),
            "replaceHint": L10n.tr(.criticReplaceHint, language: language),
        ]
    }

    /// 复制带标注的文档（含引导提示词模板）到剪贴板，供粘贴给 AI
    private func copyForAI() {
        guard documentViewModel.hasDocument, documentViewModel.isMarkdownDocument else { return }
        let prompt = settings.resolvedAIPrompt(language: language)
        writeToPasteboard(CriticMarkup.exportForAI(documentViewModel.content, prompt: prompt))
    }

    /// 复制带 CriticMarkup 标注的原文（不含 AI 引导说明）
    private func copyCritic() {
        guard documentViewModel.hasDocument, documentViewModel.isMarkdownDocument else { return }
        writeToPasteboard(documentViewModel.content)
    }

    /// 复制本次会话新增的标注片段（含上下文，纯片段不带提示头）；
    /// 没有本次新增时打开标注列表面板，让用户从历史标注中自选
    private func copySessionFragments() {
        guard documentViewModel.hasDocument, documentViewModel.isMarkdownDocument else { return }
        let annotations = documentViewModel.sessionMatchedAnnotations()
        guard !annotations.isEmpty else {
            if !appViewModel.isAnnotationPanelVisible {
                appViewModel.toggleAnnotationPanel()
            }
            return
        }
        let fragments = CriticMarkup.fragments(for: annotations, in: documentViewModel.content)
        writeToPasteboard(CriticMarkup.exportFragments(fragments))
    }

    /// 复制 AI 提示词模板本身（剥掉正文占位符）
    private func copyPrompt() {
        let prompt = settings.resolvedAIPrompt(language: language)
            .replacingOccurrences(of: CriticMarkup.contentPlaceholder, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        writeToPasteboard(prompt)
    }

    private func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        flashCopiedToast()
    }

    /// 复制成功的轻提示（1.2 秒后自动消失；连续复制时顺延）
    private func flashCopiedToast() {
        copiedToastGeneration += 1
        let generation = copiedToastGeneration
        withAnimation(.easeOut(duration: 0.15)) { copiedToastVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if generation == copiedToastGeneration {
                withAnimation(.easeIn(duration: 0.25)) { copiedToastVisible = false }
            }
        }
    }

    private func exportPDF() {
        guard documentViewModel.hasDocument, documentViewModel.isMarkdownDocument else { return }
        let language = settings.languagePref.resolvedLanguage
        let stem = URL(fileURLWithPath: documentViewModel.fileName).deletingPathExtension().lastPathComponent
        let suggestedName = stem.isEmpty ? "Untitled.pdf" : "\(stem).pdf"
        let defaultDir = settings.lastOpenedDirectory
            ?? documentViewModel.currentFileURL?.deletingLastPathComponent()

        guard let saveURL = OpenPanelHelper.showExportPDFPanel(
            language: language,
            defaultDirectory: defaultDir,
            suggestedName: suggestedName
        ) else { return }

        Task {
            await exportPDF(to: saveURL)
        }
    }

    private func exportPDF(to url: URL) async {
        do {
            let data: Data
            if let webView = webViewHandle.webView, documentViewModel.displayMode == .rendered {
                data = try await PDFExportService.exportFromWebView(webView)
            } else {
                let baseURL = documentViewModel.currentFileURL?.deletingLastPathComponent()
                let contentWidth: CGFloat
                if settings.maxContentWidthFollowsWindow {
                    contentWidth = max(980, NSApp.keyWindow?.contentRect(forFrameRect: NSApp.keyWindow?.frame ?? .zero).width ?? 980)
                } else {
                    contentWidth = 980
                }
                let html = MarkdownHTMLService.buildFullHTML(
                    content: documentViewModel.content,
                    themeCSS: themeColors.cssCustomProperties + themeColors.codeHighlightCSS,
                    contentPadding: settings.contentPaddingPoints,
                    maxContentWidthFollowsWindow: settings.maxContentWidthFollowsWindow,
                    baseURL: baseURL,
                    isDark: settings.resolvedThemeType == .dark
                )
                data = try await PDFExportService.export(
                    html: html,
                    baseURL: baseURL,
                    contentWidth: contentWidth,
                    contentPadding: settings.contentPaddingPoints
                )
            }
            try data.write(to: url)
        } catch {
            showExportPDFError = true
        }
    }

    private func exportHTML() {
        guard documentViewModel.hasDocument, documentViewModel.isMarkdownDocument else { return }
        let language = settings.languagePref.resolvedLanguage
        let stem = URL(fileURLWithPath: documentViewModel.fileName).deletingPathExtension().lastPathComponent
        let suggestedName = stem.isEmpty ? "Untitled.html" : "\(stem).html"
        let defaultDir = settings.lastOpenedDirectory
            ?? documentViewModel.currentFileURL?.deletingLastPathComponent()

        guard let saveURL = OpenPanelHelper.showExportHTMLPanel(
            language: language,
            defaultDirectory: defaultDir,
            suggestedName: suggestedName
        ) else { return }

        let stemTitle = stem
        let baseURL = documentViewModel.currentFileURL?.deletingLastPathComponent()
        let content = documentViewModel.content
        let themeCSS = themeColors.cssCustomProperties + themeColors.codeHighlightCSS
        let padding = settings.contentPaddingPoints
        let followsWindow = settings.maxContentWidthFollowsWindow
        let isDark = settings.resolvedThemeType == .dark

        Task {
            let html = HTMLExportService.buildSelfContainedHTML(
                content: content,
                title: stemTitle,
                themeCSS: themeCSS,
                contentPadding: padding,
                maxContentWidthFollowsWindow: followsWindow,
                baseURL: baseURL,
                isDark: isDark
            )
            do {
                try html.data(using: .utf8)?.write(to: saveURL)
            } catch {
                showExportHTMLError = true
            }
        }
    }

    private var outlineButtonColor: Color {
        if appViewModel.isOutlineVisible {
            return themeColors.accent
        } else if documentViewModel.hasDocument {
            return themeColors.fgSecondary
        } else {
            return themeColors.fgMuted
        }
    }

    private var annotationPanelButtonColor: Color {
        appViewModel.isAnnotationPanelVisible ? themeColors.accent : themeColors.fgMuted
    }

    private var outlineSidebar: some View {
        OutlineView(
            items: documentViewModel.outlineItems,
            onSelect: { item in
                documentViewModel.requestScrollToLine(item.lineNumber)
            },
            activeLineNumber: activeOutlineLineNumber
        )
    }

    // MARK: - 查找替换

    private var isUsingTextSearch: Bool {
        documentViewModel.isPlainTextDocument
    }

    private var isSearchableDocument: Bool {
        documentViewModel.isMarkdownDocument || documentViewModel.isPlainTextDocument
    }

    private var canReplaceInCurrentView: Bool {
        // 当前仅提供渲染阅读与 CriticMarkup 标注，不开放原文替换。
        false
    }

    private func openFindBar() {
        guard isSearchableDocument else { return }
        if !appViewModel.isFindBarVisible {
            appViewModel.showFindBar()
        }
    }

    private func openFindAndReplace() {
        guard isSearchableDocument else { return }
        if !appViewModel.isFindBarVisible {
            appViewModel.showFindBar()
        }
        findReplaceViewModel.expandReplace()
    }

    private func closeFindBar() {
        textViewSearchRef.clearSearchHighlights()
        findReplaceViewModel.clearSearch()
        appViewModel.hideFindBar()
    }

    private func performSearch() {
        guard isSearchableDocument else { return }
        let text = documentViewModel.content
        findReplaceViewModel.performSearch(in: text)

        if isUsingTextSearch {
            if findReplaceViewModel.hasResults {
                textViewSearchRef.reapplySearchHighlights(
                    matchRanges: findReplaceViewModel.matchRanges,
                    currentIndex: findReplaceViewModel.currentMatchIndex
                )
                textViewSearchRef.selectMatch(
                    at: findReplaceViewModel.currentMatchIndex,
                    in: findReplaceViewModel.matchRanges
                )
            } else {
                textViewSearchRef.clearSearchHighlights()
            }
        } else if findReplaceViewModel.hasResults {
            if let line = findReplaceViewModel.currentMatchLine {
                documentViewModel.requestScrollToLine(line)
            }
        }
    }

    private func performFindNext() {
        guard findReplaceViewModel.hasResults else {
            if !appViewModel.isFindBarVisible { openFindBar() }
            performSearch()
            return
        }
        findReplaceViewModel.goToNextMatch()
        navigateToCurrentMatch()
    }

    private func performFindPrevious() {
        guard findReplaceViewModel.hasResults else {
            if !appViewModel.isFindBarVisible { openFindBar() }
            performSearch()
            return
        }
        findReplaceViewModel.goToPreviousMatch()
        navigateToCurrentMatch()
    }

    private func navigateToCurrentMatch() {
        if isUsingTextSearch {
            textViewSearchRef.reapplySearchHighlights(
                matchRanges: findReplaceViewModel.matchRanges,
                currentIndex: findReplaceViewModel.currentMatchIndex
            )
            textViewSearchRef.selectMatch(
                at: findReplaceViewModel.currentMatchIndex,
                in: findReplaceViewModel.matchRanges
            )
        } else if let line = findReplaceViewModel.currentMatchLine {
            documentViewModel.requestScrollToLine(line)
        }
    }

    private func performReplace() {
        guard canReplaceInCurrentView,
              let currentRange = findReplaceViewModel.currentMatchRange else { return }

        let _ = textViewSearchRef.replaceCurrentMatch(at: currentRange, with: findReplaceViewModel.replaceText)
        documentViewModel.content = textViewSearchRef.textView?.string ?? documentViewModel.content
        performSearch()
    }

    private func performReplaceAll() {
        guard canReplaceInCurrentView,
              !findReplaceViewModel.matchRanges.isEmpty else { return }

        let _ = textViewSearchRef.replaceAllMatches(ranges: findReplaceViewModel.matchRanges, with: findReplaceViewModel.replaceText)
        documentViewModel.content = textViewSearchRef.textView?.string ?? documentViewModel.content
        performSearch()
    }

    // MARK: - 文档内容视图

    @ViewBuilder
    private var selectFilePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundStyle(themeColors.fgMuted)
            Text(L10n.tr(.selectFileHint, language: language))
                .font(.subheadline)
                .foregroundStyle(themeColors.fgSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 文档内容视图

    @ViewBuilder
    private var documentContentView: some View {
        ZStack {
            if documentViewModel.isPlainTextDocument {
                // 非 Markdown 文本：只读 Raw 文本兜底查看，不开放 Markdown 渲染/标注能力。
                RawMarkdownView(
                    content: Binding(
                        get: { documentViewModel.content },
                        set: { documentViewModel.content = $0 }
                    ),
                    fontSize: CGFloat(settings.sourceFontSize),
                    contentPadding: settings.contentPaddingPoints,
                    fileURL: documentViewModel.currentFileURL,
                    isEditable: false,
                    isMarkdownSyntaxHighlightingEnabled: false,
                    // 只读文本预览不主动成为 first responder，避免从左侧文件树打开 .txt/.json/.log
                    // 后抢走键盘焦点，导致上下左右导航失效。用户仍可点击文本区域后选择/搜索。
                    isActive: false,
                    isFindBarVisible: appViewModel.isFindBarVisible,
                    searchRef: textViewSearchRef,
                    onCursorLineNumberChanged: { lineNumber in
                        documentViewModel.cursorLineNumber = lineNumber
                    }
                )
                .id(documentViewModel.currentFileURL)
            } else {
                // Markdown：仅渲染视图。文本兜底不进入此分支。
                WebViewMarkdownView(
                    content: documentViewModel.content,
                    fileURL: documentViewModel.currentFileURL,
                    contentPadding: settings.contentPaddingPoints,
                    maxContentWidthFollowsWindow: settings.maxContentWidthFollowsWindow,
                    scrollToLine: documentViewModel.scrollToLineRequest,
                    themeCSS: themeColors.cssCustomProperties + themeColors.codeHighlightCSS,
                    isDark: settings.resolvedThemeType == .dark,
                    searchQuery: findReplaceViewModel.searchText,
                    searchCaseSensitive: findReplaceViewModel.isCaseSensitive,
                    searchWholeWord: findReplaceViewModel.isWholeWord,
                    searchCurrentIndex: findReplaceViewModel.currentMatchIndex,
                    isFindBarVisible: appViewModel.isFindBarVisible,
                    onVisibleHeadingChanged: { heading in
                        activeOutlineLineNumber = heading?.lineNumber
                    },
                    onVisibleLineChanged: { lineNumber in
                        documentViewModel.renderedVisibleLineNumber = lineNumber
                    },
                    onCriticAction: { action in
                        documentViewModel.applyCriticAction(action)
                    },
                    onLocalLinkActivated: onLocalMarkdownLink,
                    criticLabels: criticLabels,
                    handle: webViewHandle
                )
                .onChange(of: documentViewModel.scrollToLineRequest) { _, newValue in
                    if newValue != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            documentViewModel.clearScrollRequest()
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if appViewModel.isFindBarVisible, documentViewModel.hasDocument, isSearchableDocument {
                FindReplaceBar(
                    viewModel: findReplaceViewModel,
                    isRawMode: canReplaceInCurrentView,
                    onFindNext: { performFindNext() },
                    onFindPrevious: { performFindPrevious() },
                    onReplace: { performReplace() },
                    onReplaceAll: { performReplaceAll() },
                    onClose: { closeFindBar() }
                )
                .padding(.trailing, 16)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appViewModel.isFindBarVisible)
        .onChange(of: findReplaceViewModel.searchText) { _, _ in performSearch() }
        .onChange(of: findReplaceViewModel.isCaseSensitive) { _, _ in performSearch() }
        .onChange(of: findReplaceViewModel.isWholeWord) { _, _ in performSearch() }
        .onChange(of: findReplaceViewModel.isRegularExpression) { _, _ in performSearch() }
        .onActiveReceive(NotificationCenter.default.publisher(for: .findInDocument)) { _ in openFindBar() }
        .onActiveReceive(NotificationCenter.default.publisher(for: .findNext)) { _ in performFindNext() }
        .onActiveReceive(NotificationCenter.default.publisher(for: .findPrevious)) { _ in performFindPrevious() }
        .onActiveReceive(NotificationCenter.default.publisher(for: .findAndReplace)) { _ in openFindAndReplace() }
    }
}
