import SwiftUI

// MARK: - 本地化服务

/// 简易本地化服务，参照 buddy-macos 的 i18n 字典方案
/// 使用扁平 key-value 结构，支持插值 {n}
public enum L10n {

    // MARK: - Key 定义

    /// 所有本地化键，与 buddy-macos 的 settings key 结构对齐
    public enum Key: String, CaseIterable, Sendable {
        // 应用名称
        case appName

        // 设置 - 菜单/导航
        case settingsMenuLabel
        case settingsBackToApp

        // 设置 - 标签页
        case settingsTabGeneral
        case settingsTabAppearance

        // 设置 - 通用
        case settingsGeneralLanguageTitle
        case settingsGeneralLanguageDesc
        case settingsGeneralDisplayTitle
        case settingsGeneralDisplayMode

        // 设置 - 渲染宽度
        case settingsGeneralRenderedWidthTitle
        case settingsGeneralRenderedWidthDesc
        case settingsGeneralMaxWidthFollowsWindow

        // 设置 - 启动
        case settingsGeneralStartupTitle
        case settingsGeneralReopenLastLocation

        // 设置 - 文件树
        case settingsGeneralFileTreeTitle
        case settingsGeneralShowHiddenFiles
        case settingsGeneralShowNonMarkdownFiles

        // 设置 - 默认打开程序
        case settingsGeneralDefaultOpenerTitle
        case settingsGeneralDefaultOpenerDesc
        case settingsGeneralSetAsDefault
        case settingsGeneralIsDefault
        case settingsGeneralSetDefaultFailed

        // 设置 - 命令行工具
        case settingsGeneralCommandLineTitle
        case settingsGeneralCommandLineDesc
        case settingsGeneralCommandLineInstalled
        case settingsGeneralCommandLineInstallFailed
        case settingsGeneralCommandLineUninstallFailed

        // 设置 - Quick Look 预览
        case settingsGeneralQuickLookTitle
        case settingsGeneralQuickLookDesc
        case settingsGeneralQuickLookEnabled

        // 设置 - 外观 - 主题模式
        case settingsAppearanceThemeTitle
        case settingsAppearanceThemeDesc
        case settingsAppearanceModeLight
        case settingsAppearanceModeLightDesc
        case settingsAppearanceModeDark
        case settingsAppearanceModeDarkDesc
        case settingsAppearanceModeSystem
        case settingsAppearanceModeSystemDesc

        // 设置 - 外观 - 配色方案
        case settingsAppearanceSchemeTitle
        case settingsAppearanceSchemeDesc

        // 设置 - 外观 - 自定义颜色
        case settingsAppearanceCustomTitle
        case settingsAppearanceCustomDesc
        case settingsAppearanceCustomSurface
        case settingsAppearanceCustomInk
        case settingsAppearanceCustomAccent
        case settingsAppearanceCustomSuccess
        case settingsAppearanceCustomDanger

        // 设置 - 外观 - 对比度
        case settingsAppearanceContrastTitle
        case settingsAppearanceContrastDesc
        case settingsAppearanceContrastLow
        case settingsAppearanceContrastHigh

        // 设置 - 外观 - 字体排版（保留）
        case settingsAppearanceTypographyTitle
        case settingsAppearanceSourceFontSize
        case settingsAppearanceContentPadding

        // 语言选项
        case languageAuto
        case languageZhCN
        case languageZhTW
        case languageEn

        // 显示模式
        case displayModeRendered
        case displayModeRaw

        // 通用操作
        case open
        case save
        case reset
        case confirm

        // 菜单 / 剪贴板标注
        case newFromClipboard
        case clipboardScratchName

        // 未保存更改提醒
        case unsavedChangesTitle
        case unsavedChangesMessage
        case unsavedSave
        case unsavedDontSave
        case unsavedCancel

        // 文件外部删除提醒
        case fileDeletedTitle
        case fileDeletedMessage
        case fileDeletedSaveAs
        case fileDeletedDiscard

        // 文件外部修改提醒
        case fileModifiedExternallyTitle
        case fileModifiedExternallyMessage
        case fileModifiedExternallyReload
        case fileModifiedExternallyDontRemind

        // 打开最近
        case openRecent
        case openRecentEmpty
        case openRecentFiles
        case openRecentFolders
        case clearRecentItems

        // 标题栏
        case titleBarToggleSidebar
        case titleBarDisplayMode
        case titleBarOpen
        case titleBarSave
        case titleBarReload
        case titleBarToggleOutline
        case titleBarCopyPath

        // CriticMarkup 审阅标注
        case titleBarCopyForAI
        case titleBarCopyMenu
        case copyForAIMenu
        case copyCriticMenu
        case copyFragmentsMenu
        case copyPromptMenu
        case copiedToast
        // 应用 / 放弃所有标注
        case titleBarAnnotationActions
        case applyAnnotationsMenu
        case applyAnnotationsConfirmTitle
        case applyAnnotationsConfirmMessage
        case discardAnnotationsMenu
        case discardAnnotationsConfirmTitle
        case discardAnnotationsConfirmMessage
        // 编辑菜单：撤销 / 重做
        case editUndo
        case editRedo
        // 导航菜单：后退 / 前进
        case navigationBack
        case navigationForward
        // 标注列表面板
        case titleBarAnnotationPanel
        case annotationGroupNew
        case annotationGroupHistory
        case annotationSelectAll
        case annotationSelectNew
        case annotationCopySelected
        case annotationStale
        case annotationEmpty
        // AI 提示词模板
        case aiPromptDefaultTemplate
        case settingsAIPromptTitle
        case settingsAIPromptDescription
        case settingsAIPromptReset
        case criticDelete
        case criticHighlight
        case criticComment
        case criticReplace
        case criticConfirm
        case criticCancel
        case criticEdit
        case criticCommentHint
        case criticReplaceHint
        case criticNotFound

        // 大纲
        case outlineTitle
        case outlineEmpty

        // 侧边栏
        case loading
        case emptyDirectoryMessage
        case sidebarSettings
        case sidebarSettingsButton

        // 欢迎页
        case welcomeOpenFolder
        case welcomePressCmdO
        case selectFileHint
        case welcomeDropHint

        // 右键菜单
        case contextMenuNewFile
        case contextMenuNewSubdirectory
        case contextMenuRename
        case contextMenuMoveTo
        case contextMenuDelete
        case contextMenuReload
        case contextMenuCopyPath

        // 右键菜单 - 对话框
        case renameTitle
        case renameMessage
        case renameEmptyName
        case renameNameExists
        case deleteTitle
        case deleteMessage
        case deleteDirectoryMessage
        case moveSelectFolder

        // 自动更新
        case updateAvailableTitle
        case updateAvailableVersion
        case updateChecking
        case updateUpToDate
        case updateDownload
        case updateDownloading
        case updateDownloadComplete
        case updateInstall
        case updateInstallAndRestart
        case updateInstalling
        case updateLater
        case updateSkipVersion
        case updateCancel
        case updateError
        case updateModeAuto
        case updateModeManual
        case updateInstallInstructionsTitle
        case updateManualInstallInstructions
        case updateReleaseNotesTitle
        case checkForUpdates

        // 查找替换
        case findBarSearchPlaceholder
        case findBarReplacePlaceholder
        case findBarFindNext
        case findBarFindPrevious
        case findBarReplace
        case findBarReplaceAll
        case findBarNoResults
        case findBarCaseSensitive
        case findBarWholeWord
        case findBarRegularExpression
        case findBarFind
        case findBarFindAndReplace

        // Markdown 本地链接导航
        case markdownLinkExpandRootTitle
        case markdownLinkExpandRootMessage
        case markdownLinkOpenCommonRoot
        case markdownLinkMissingTitle
        case markdownLinkMissingMessage
        case markdownLinkUnsupportedTitle
        case markdownLinkUnsupportedMessage

        // 导出 PDF
        case exportPDF
        case titleBarExportPDF
        case exportPDFSuccess
        case exportPDFFailed

        // 导出 HTML
        case exportHTML
        case titleBarExportHTML
        case exportHTMLSuccess
        case exportHTMLFailed

        // 拖拽
        case unsupportedFileTypeAlert
    }

    // MARK: - 翻译字典

    private static let en: [Key: String] = [
        .appName: "MarkMark",
        .settingsMenuLabel: "Settings\u{2026}",
        .settingsBackToApp: "Back to App",
        .settingsTabGeneral: "General",
        .settingsTabAppearance: "Appearance",
        .settingsGeneralLanguageTitle: "Language",
        .settingsGeneralLanguageDesc: "Choose the interface language. \"Auto\" follows your system.",
        .settingsGeneralDisplayTitle: "Display",
        .settingsGeneralDisplayMode: "Default display mode",
        .settingsGeneralRenderedWidthTitle: "Rendered Width",
        .settingsGeneralRenderedWidthDesc: "Control the maximum width of rendered content. When off, a fixed width is used.",
        .settingsGeneralMaxWidthFollowsWindow: "Follow window width",
        .settingsGeneralStartupTitle: "Startup",
        .settingsGeneralReopenLastLocation: "Reopen last location on launch",
        .settingsGeneralFileTreeTitle: "File Tree",
        .settingsGeneralShowHiddenFiles: "Show hidden files",
        .settingsGeneralShowNonMarkdownFiles: "Show non-Markdown files",
        .settingsGeneralDefaultOpenerTitle: "Default Markdown Opener",
        .settingsGeneralDefaultOpenerDesc: "Set MarkMark as the default application for opening .md, .markdown, .mdown, .mkd files.",
        .settingsGeneralSetAsDefault: "Set as Default",
        .settingsGeneralIsDefault: "MarkMark is the default Markdown opener",
        .settingsGeneralSetDefaultFailed: "Failed to set as default opener. Please try again.",
        .settingsGeneralCommandLineTitle: "Command Line Tool",
        .settingsGeneralCommandLineDesc: "Install the `mdr` command to open files from Terminal. Example: mdr README.md",
        .settingsGeneralCommandLineInstalled: "mdr command is available in Terminal",
        .settingsGeneralCommandLineInstallFailed: "Failed to install command line tool. Please try again.",
        .settingsGeneralCommandLineUninstallFailed: "Failed to uninstall command line tool. Please try again.",
        .settingsGeneralQuickLookTitle: "Quick Look Preview",
        .settingsGeneralQuickLookDesc: "Enable Markdown rendering in Finder Quick Look (press Space to preview).",
        .settingsGeneralQuickLookEnabled: "Enable Quick Look preview",
        .settingsAppearanceThemeTitle: "Theme",
        .settingsAppearanceThemeDesc: "Choose the application appearance mode.",
        .settingsAppearanceModeLight: "Light",
        .settingsAppearanceModeLightDesc: "Always use light appearance",
        .settingsAppearanceModeDark: "Dark",
        .settingsAppearanceModeDarkDesc: "Always use dark appearance",
        .settingsAppearanceModeSystem: "System",
        .settingsAppearanceModeSystemDesc: "Follow system setting",
        .settingsAppearanceSchemeTitle: "Color Scheme",
        .settingsAppearanceSchemeDesc: "Choose a preset color scheme for the current mode.",
        .settingsAppearanceCustomTitle: "Custom Colors",
        .settingsAppearanceCustomDesc: "Customize individual color tokens. Changes override the current scheme.",
        .settingsAppearanceCustomSurface: "Surface",
        .settingsAppearanceCustomInk: "Ink",
        .settingsAppearanceCustomAccent: "Accent",
        .settingsAppearanceCustomSuccess: "Success",
        .settingsAppearanceCustomDanger: "Danger",
        .settingsAppearanceContrastTitle: "Contrast",
        .settingsAppearanceContrastDesc: "Adjust the contrast between background and foreground layers.",
        .settingsAppearanceContrastLow: "Low",
        .settingsAppearanceContrastHigh: "High",
        .settingsAppearanceTypographyTitle: "Typography",
        .settingsAppearanceSourceFontSize: "Source font size",
        .settingsAppearanceContentPadding: "Content padding",
        .languageAuto: "Auto / Auto Detect",
        .languageZhCN: "Simplified Chinese",
        .languageZhTW: "Traditional Chinese",
        .languageEn: "English",
        .displayModeRendered: "Rendered",
        .displayModeRaw: "Raw",
        .open: "Open",
        .save: "Save",
        .reset: "Reset",
        .confirm: "OK",
        .newFromClipboard: "New Annotation from Clipboard",
        .clipboardScratchName: "Clipboard Annotation",
        .unsavedChangesTitle: "Unsaved Changes",
        .unsavedChangesMessage: "Your changes will be lost if you don't save them. Do you want to save before closing?",
        .unsavedSave: "Save",
        .unsavedDontSave: "Don't Save",
        .unsavedCancel: "Cancel",
        .fileDeletedTitle: "File Deleted",
        .fileDeletedMessage: "The file \"{name}\" was deleted externally. You have unsaved changes.",
        .fileDeletedSaveAs: "Save As\u{2026}",
        .fileDeletedDiscard: "Discard Changes",
        .openRecent: "Open Recent",
        .openRecentEmpty: "No Recent Items",
        .openRecentFiles: "Files",
        .openRecentFolders: "Folders",
        .clearRecentItems: "Clear Menu",
        .titleBarToggleSidebar: "Toggle Sidebar (⌘\\)",
        .titleBarDisplayMode: "Display Mode",
        .titleBarOpen: "Open (⌘O)",
        .titleBarSave: "Save (⌘S)",
        .titleBarReload: "Reload",
        .titleBarToggleOutline: "Toggle Outline",
        .titleBarCopyPath: "Copy Path",
        .titleBarCopyForAI: "Copy annotated doc for AI",
        .titleBarCopyMenu: "Copy for AI / CriticMarkup (⌘⇧C for AI)",
        .copyForAIMenu: "Copy for AI (with instructions)",
        .copyCriticMenu: "Copy CriticMarkup",
        .copyFragmentsMenu: "Copy New Annotated Fragments",
        .copyPromptMenu: "Copy AI Prompt",
        .copiedToast: "Copied",
        .titleBarAnnotationActions: "Apply or discard all annotations",
        .applyAnnotationsMenu: "Apply All Annotations…",
        .applyAnnotationsConfirmTitle: "Apply all annotations?",
        .applyAnnotationsConfirmMessage: "Deletions and replacements will be applied to the text; highlights and comments will be removed. This cannot be undone.",
        .discardAnnotationsMenu: "Discard All Annotations…",
        .discardAnnotationsConfirmTitle: "Discard all annotations?",
        .discardAnnotationsConfirmMessage: "This removes every CriticMarkup mark and restores the original text. This cannot be undone.",
        .editUndo: "Undo",
        .editRedo: "Redo",
        .navigationBack: "Back",
        .navigationForward: "Forward",
        .titleBarAnnotationPanel: "Annotations",
        .annotationGroupNew: "New this session",
        .annotationGroupHistory: "Existing",
        .annotationSelectAll: "Select All",
        .annotationSelectNew: "New Only",
        .annotationCopySelected: "Copy Selected Fragments",
        .annotationStale: "Stale",
        .annotationEmpty: "No annotations",
        .aiPromptDefaultTemplate: """
        The content below contains review annotations in CriticMarkup syntax:
        - {++ addition ++}        suggested addition
        - {-- deletion --}        suggested removal
        - {~~ old ~> new ~~}      suggested replacement
        - {>> comment <<}         my comment/question
        - {== highlight ==}       part I want to focus on

        ---

        {{MarkMark:content}}
        """,
        .settingsAIPromptTitle: "AI Prompt Template",
        .settingsAIPromptDescription: "Used by \"Copy for AI\" and \"Copy AI Prompt\". {{MarkMark:content}} marks where the document is inserted.",
        .settingsAIPromptReset: "Restore Default",
        .criticDelete: "Delete",
        .criticHighlight: "Highlight",
        .criticComment: "Comment",
        .criticReplace: "Replace",
        .criticConfirm: "Apply",
        .criticCancel: "Cancel",
        .criticEdit: "Edit",
        .criticCommentHint: "Add a comment…",
        .criticReplaceHint: "Replace with…",
        .criticNotFound: "Could not locate the selection in the source",
        .fileModifiedExternallyTitle: "File Modified Externally",
        .fileModifiedExternallyMessage: "The file has been modified by another application. Reloading will discard your current changes.",
        .fileModifiedExternallyReload: "Reload",
        .fileModifiedExternallyDontRemind: "Don't remind me again",
        .outlineTitle: "Outline",
        .outlineEmpty: "No headings",
        .loading: "Loading...",
        .emptyDirectoryMessage: "No Markdown files in this directory",
        .sidebarSettings: "Settings (⌘,)",
        .sidebarSettingsButton: "Settings",
        .welcomeOpenFolder: "Open a folder to get started",
        .welcomePressCmdO: "Press Cmd+O or click Open in toolbar",
        .welcomeDropHint: "or drag a file or folder here",
        .selectFileHint: "Select a Markdown file to read",
        .contextMenuNewFile: "New File",
        .contextMenuNewSubdirectory: "New Subdirectory",
        .contextMenuRename: "Rename",
        .contextMenuMoveTo: "Move to\u{2026}",
        .contextMenuDelete: "Move to Trash",
        .contextMenuReload: "Reload",
        .contextMenuCopyPath: "Copy Path",
        .renameTitle: "Rename",
        .renameMessage: "Enter a new name for \"{name}\":",
        .renameEmptyName: "Name cannot be empty.",
        .renameNameExists: "An item with this name already exists.",
        .deleteTitle: "Move to Trash",
        .deleteMessage: "Are you sure you want to move \"{name}\" to the Trash?",
        .deleteDirectoryMessage: "Are you sure you want to move \"{name}\" and all its contents to the Trash?",
        .moveSelectFolder: "Select Destination Folder",
        .updateAvailableTitle: "Update Available",
        .updateAvailableVersion: "Version {version}",
        .updateChecking: "Checking for updates\u{2026}",
        .updateUpToDate: "MarkMark is up to date.",
        .updateDownload: "Download",
        .updateDownloading: "Downloading update\u{2026}",
        .updateDownloadComplete: "Download complete. Click Install to continue.",
        .updateInstall: "Install",
        .updateInstallAndRestart: "Install & Restart",
        .updateInstalling: "Installing update\u{2026}",
        .updateLater: "Later",
        .updateSkipVersion: "Skip This Version",
        .updateCancel: "Cancel",
        .updateError: "Update check failed.",
        .updateModeAuto: "Auto install & restart",
        .updateModeManual: "Manual install required",
        .updateInstallInstructionsTitle: "Installation",
        .updateManualInstallInstructions: "1. Download the .dmg file and open it\n2. Drag MarkMark into the Applications folder\n3. On first launch, macOS may say the developer cannot be verified:\n   \u{2022} Open System Settings \u{2192} Privacy & Security\n   \u{2022} Find the blocked app and click Open Anyway\n   \u{2022} Or run in Terminal: xattr -cr /Applications/MarkMark.app\n4. You can also right-click the app and choose Open",
        .updateReleaseNotesTitle: "Release Notes",
        .checkForUpdates: "Check for Updates\u{2026}",
        .findBarSearchPlaceholder: "Search",
        .findBarReplacePlaceholder: "Replace",
        .findBarFindNext: "Find Next",
        .findBarFindPrevious: "Find Previous",
        .findBarReplace: "Replace",
        .findBarReplaceAll: "Replace All",
        .findBarNoResults: "No results",
        .findBarCaseSensitive: "Match Case",
        .findBarWholeWord: "Match Whole Word",
        .findBarRegularExpression: "Use Regular Expression",
        .findBarFind: "Find",
        .findBarFindAndReplace: "Find and Replace",
        .markdownLinkExpandRootTitle: "Open linked location?",
        .markdownLinkExpandRootMessage: "This link points outside the current folder. MarkMark will switch the sidebar root to:\n{root}\n\nTarget:\n{target}",
        .markdownLinkOpenCommonRoot: "Open Common Folder",
        .markdownLinkMissingTitle: "Linked item not found",
        .markdownLinkMissingMessage: "The linked file or folder does not exist:\n{target}",
        .markdownLinkUnsupportedTitle: "Unsupported link target",
        .markdownLinkUnsupportedMessage: "MarkMark can open Markdown files and folders from relative links. This target is not supported:\n{target}",
        .exportPDF: "Export PDF\u{2026}",
        .titleBarExportPDF: "Export PDF (⌘⌥E) / HTML (⌘⇧E)",
        .exportPDFSuccess: "PDF exported successfully",
        .exportPDFFailed: "Failed to export PDF",
        .exportHTML: "Export HTML\u{2026}",
        .titleBarExportHTML: "Export HTML",
        .exportHTMLSuccess: "HTML exported successfully",
        .exportHTMLFailed: "Failed to export HTML",
        .unsupportedFileTypeAlert: "Unsupported file type (.{ext}). Only Markdown files can be opened.",
    ]

    private static let zhCN: [Key: String] = [
        .appName: "MarkMark",
        .settingsMenuLabel: "设置\u{2026}",
        .settingsBackToApp: "返回应用",
        .settingsTabGeneral: "通用",
        .settingsTabAppearance: "外观",
        .settingsGeneralLanguageTitle: "界面语言",
        .settingsGeneralLanguageDesc: "选择应用界面的语言。「自动检测」会跟随系统。",
        .settingsGeneralDisplayTitle: "显示",
        .settingsGeneralDisplayMode: "默认显示模式",
        .settingsGeneralRenderedWidthTitle: "渲染宽度",
        .settingsGeneralRenderedWidthDesc: "控制渲染内容的最大宽度。关闭时使用固定宽度。",
        .settingsGeneralMaxWidthFollowsWindow: "跟随窗口宽度",
        .settingsGeneralStartupTitle: "启动",
        .settingsGeneralReopenLastLocation: "启动时重新打开上次位置",
        .settingsGeneralFileTreeTitle: "文件树",
        .settingsGeneralShowHiddenFiles: "显示隐藏文件",
        .settingsGeneralShowNonMarkdownFiles: "显示非 Markdown 文件",
        .settingsGeneralDefaultOpenerTitle: "默认 Markdown 打开程序",
        .settingsGeneralDefaultOpenerDesc: "将 MarkMark 设置为 .md、.markdown、.mdown、.mkd 文件的默认打开程序。",
        .settingsGeneralSetAsDefault: "设为默认",
        .settingsGeneralIsDefault: "MarkMark 已是默认 Markdown 打开程序",
        .settingsGeneralSetDefaultFailed: "设置默认打开程序失败，请重试。",
        .settingsGeneralCommandLineTitle: "命令行工具",
        .settingsGeneralCommandLineDesc: "安装 mdr 命令，可在终端中打开文件。例如：mdr README.md",
        .settingsGeneralCommandLineInstalled: "mdr 命令已在终端中可用",
        .settingsGeneralCommandLineInstallFailed: "安装命令行工具失败，请重试。",
        .settingsGeneralCommandLineUninstallFailed: "卸载命令行工具失败，请重试。",
        .settingsGeneralQuickLookTitle: "Quick Look 预览",
        .settingsGeneralQuickLookDesc: "在 Finder 中按空格键预览 Markdown 文件的渲染效果。",
        .settingsGeneralQuickLookEnabled: "启用 Quick Look 预览",
        .settingsAppearanceThemeTitle: "主题",
        .settingsAppearanceThemeDesc: "选择应用的外观模式。",
        .settingsAppearanceModeLight: "浅色",
        .settingsAppearanceModeLightDesc: "始终使用浅色外观",
        .settingsAppearanceModeDark: "深色",
        .settingsAppearanceModeDarkDesc: "始终使用深色外观",
        .settingsAppearanceModeSystem: "跟随系统",
        .settingsAppearanceModeSystemDesc: "跟随系统设置",
        .settingsAppearanceSchemeTitle: "配色方案",
        .settingsAppearanceSchemeDesc: "为当前模式选择预设配色方案。",
        .settingsAppearanceCustomTitle: "自定义颜色",
        .settingsAppearanceCustomDesc: "自定义各颜色令牌。修改将覆盖当前方案的对应颜色。",
        .settingsAppearanceCustomSurface: "背景色",
        .settingsAppearanceCustomInk: "文字色",
        .settingsAppearanceCustomAccent: "强调色",
        .settingsAppearanceCustomSuccess: "成功色",
        .settingsAppearanceCustomDanger: "危险色",
        .settingsAppearanceContrastTitle: "对比度",
        .settingsAppearanceContrastDesc: "调整背景与前景层之间的对比度。",
        .settingsAppearanceContrastLow: "低",
        .settingsAppearanceContrastHigh: "高",
        .settingsAppearanceTypographyTitle: "字体与排版",
        .settingsAppearanceSourceFontSize: "源码字号",
        .settingsAppearanceContentPadding: "内容边距",
        .languageAuto: "自动检测",
        .languageZhCN: "简体中文",
        .languageZhTW: "繁體中文",
        .languageEn: "English",
        .displayModeRendered: "渲染",
        .displayModeRaw: "编辑",
        .open: "打开",
        .save: "保存",
        .reset: "重置",
        .confirm: "确认",
        .newFromClipboard: "从剪贴板新建标注",
        .clipboardScratchName: "剪贴板标注",
        .unsavedChangesTitle: "未保存的更改",
        .unsavedChangesMessage: "如果不保存，您的更改将会丢失。关闭前是否保存？",
        .unsavedSave: "保存",
        .unsavedDontSave: "不保存",
        .unsavedCancel: "取消",
        .fileDeletedTitle: "文件已被删除",
        .fileDeletedMessage: "文件「{name}」已被外部删除，您有未保存的更改。",
        .fileDeletedSaveAs: "另存为\u{2026}",
        .fileDeletedDiscard: "放弃更改",
        .openRecent: "打开最近使用",
        .openRecentEmpty: "无最近打开的项",
        .openRecentFiles: "文件",
        .openRecentFolders: "文件夹",
        .clearRecentItems: "清除菜单",
        .titleBarToggleSidebar: "切换侧边栏 (⌘\\)",
        .titleBarDisplayMode: "显示模式",
        .titleBarOpen: "打开 (⌘O)",
        .titleBarSave: "保存 (⌘S)",
        .titleBarReload: "重新加载",
        .titleBarToggleOutline: "切换大纲",
        .titleBarCopyPath: "复制路径",
        .titleBarCopyForAI: "复制标注文档给 AI",
        .titleBarCopyMenu: "复制给 AI / CriticMarkup 原文（给 AI：⌘⇧C）",
        .copyForAIMenu: "复制给 AI（含说明）",
        .copyCriticMenu: "复制 CriticMarkup",
        .copyFragmentsMenu: "复制本次新增的标注片段",
        .copyPromptMenu: "复制 AI 提示词",
        .copiedToast: "已复制",
        .titleBarAnnotationActions: "应用或放弃所有标注",
        .applyAnnotationsMenu: "应用所有标注…",
        .applyAnnotationsConfirmTitle: "应用所有标注？",
        .applyAnnotationsConfirmMessage: "删除和替换将直接修改正文，高亮和评论将被移除。此操作无法撤销。",
        .discardAnnotationsMenu: "放弃所有标注…",
        .discardAnnotationsConfirmTitle: "放弃所有标注？",
        .discardAnnotationsConfirmMessage: "将移除所有 CriticMarkup 标注并恢复原文，此操作无法撤销。",
        .editUndo: "撤销",
        .editRedo: "重做",
        .navigationBack: "后退",
        .navigationForward: "前进",
        .titleBarAnnotationPanel: "标注列表",
        .annotationGroupNew: "本次新增",
        .annotationGroupHistory: "历史标注",
        .annotationSelectAll: "全选",
        .annotationSelectNew: "只选新增",
        .annotationCopySelected: "复制所选片段",
        .annotationStale: "已失效",
        .annotationEmpty: "暂无标注",
        .aiPromptDefaultTemplate: """
        下面的内容中包含使用 CriticMarkup 语法的审阅标注，标记含义如下：
        - {++ 新增内容 ++}        建议新增
        - {-- 删除内容 --}        建议删除
        - {~~ 旧内容 ~> 新内容 ~~} 建议替换为新内容
        - {>> 评论 <<}            我的评论/疑问
        - {== 高亮内容 ==}        我重点关注的部分

        ---

        {{MarkMark:content}}
        """,
        .settingsAIPromptTitle: "AI 提示词模板",
        .settingsAIPromptDescription: "「复制给 AI」与「复制 AI 提示词」共用。{{MarkMark:content}} 为正文插入位置占位符。",
        .settingsAIPromptReset: "恢复默认",
        .criticDelete: "删除",
        .criticHighlight: "高亮",
        .criticComment: "评论",
        .criticReplace: "替换",
        .criticConfirm: "应用",
        .criticCancel: "取消",
        .criticEdit: "编辑",
        .criticCommentHint: "输入评论…",
        .criticReplaceHint: "替换为…",
        .criticNotFound: "无法在源码中定位选区（试试只选不跨格式的文字）",
        .fileModifiedExternallyTitle: "文件已被外部修改",
        .fileModifiedExternallyMessage: "文件已被其他应用修改，重新加载将丢弃当前未保存的更改。",
        .fileModifiedExternallyReload: "重新加载",
        .fileModifiedExternallyDontRemind: "以后不再提醒",
        .outlineTitle: "大纲",
        .outlineEmpty: "暂无标题",
        .loading: "加载中...",
        .emptyDirectoryMessage: "该目录下无 Markdown 文件",
        .sidebarSettings: "设置 (⌘,)",
        .sidebarSettingsButton: "设置",
        .welcomeOpenFolder: "打开文件夹开始阅读",
        .welcomePressCmdO: "按 Cmd+O 或点击工具栏中的打开按钮",
        .welcomeDropHint: "或拖拽文件/文件夹到此处",
        .selectFileHint: "选择 Markdown 文件开始阅读",
        .contextMenuNewFile: "新建文档",
        .contextMenuNewSubdirectory: "新建子目录",
        .contextMenuRename: "重命名",
        .contextMenuMoveTo: "移动到\u{2026}",
        .contextMenuDelete: "移到废纸篓",
        .contextMenuReload: "重新加载",
        .contextMenuCopyPath: "复制路径",
        .renameTitle: "重命名",
        .renameMessage: "输入「{name}」的新名称：",
        .renameEmptyName: "名称不能为空。",
        .renameNameExists: "已存在同名项目。",
        .deleteTitle: "移到废纸篓",
        .deleteMessage: "确定要将「{name}」移到废纸篓吗？",
        .deleteDirectoryMessage: "确定要将「{name}」及其所有内容移到废纸篓吗？",
        .moveSelectFolder: "选择目标文件夹",
        .updateAvailableTitle: "发现新版本",
        .updateAvailableVersion: "版本 {version}",
        .updateChecking: "正在检查更新\u{2026}",
        .updateUpToDate: "MarkMark 已是最新版本。",
        .updateDownload: "下载",
        .updateDownloading: "正在下载更新\u{2026}",
        .updateDownloadComplete: "下载完成，点击「安装」继续。",
        .updateInstall: "安装",
        .updateInstallAndRestart: "安装并重启",
        .updateInstalling: "正在安装更新\u{2026}",
        .updateLater: "稍后",
        .updateSkipVersion: "跳过此版本",
        .updateCancel: "取消",
        .updateError: "检查更新失败。",
        .updateModeAuto: "自动安装并重启",
        .updateModeManual: "需手动安装",
        .updateInstallInstructionsTitle: "安装说明",
        .updateManualInstallInstructions: "1. 下载 .dmg 文件，双击打开\n2. 将 MarkMark 拖入「应用程序」文件夹\n3. 首次打开时，macOS 可能提示「无法验证开发者」：\n   \u{2022} 打开「系统设置 \u{2192} 隐私与安全性」\n   \u{2022} 找到被阻止的 app，点击「仍要打开」\n   \u{2022} 或在终端运行：xattr -cr /Applications/MarkMark.app\n4. 也可以直接右键点击 app \u{2192} 选择「打开」",
        .updateReleaseNotesTitle: "更新内容",
        .checkForUpdates: "检查更新\u{2026}",
        .findBarSearchPlaceholder: "搜索",
        .findBarReplacePlaceholder: "替换",
        .findBarFindNext: "查找下一个",
        .findBarFindPrevious: "查找上一个",
        .findBarReplace: "替换",
        .findBarReplaceAll: "全部替换",
        .findBarNoResults: "无结果",
        .findBarCaseSensitive: "区分大小写",
        .findBarWholeWord: "全词匹配",
        .findBarRegularExpression: "使用正则表达式",
        .findBarFind: "查找",
        .findBarFindAndReplace: "查找和替换",
        .markdownLinkExpandRootTitle: "打开链接位置？",
        .markdownLinkExpandRootMessage: "这个链接指向当前文件夹之外。MarkMark 会将左侧目录根切换为：\n{root}\n\n目标：\n{target}",
        .markdownLinkOpenCommonRoot: "打开共同父目录",
        .markdownLinkMissingTitle: "链接目标不存在",
        .markdownLinkMissingMessage: "链接指向的文件或目录不存在：\n{target}",
        .markdownLinkUnsupportedTitle: "不支持的链接目标",
        .markdownLinkUnsupportedMessage: "MarkMark 仅支持通过相对链接打开 Markdown 文件和目录。此目标不支持：\n{target}",
        .exportPDF: "导出 PDF\u{2026}",
        .titleBarExportPDF: "导出 PDF (⌘⌥E) / HTML (⌘⇧E)",
        .exportPDFSuccess: "PDF 导出成功",
        .exportPDFFailed: "PDF 导出失败",
        .exportHTML: "导出 HTML\u{2026}",
        .titleBarExportHTML: "导出 HTML",
        .exportHTMLSuccess: "HTML 导出成功",
        .exportHTMLFailed: "HTML 导出失败",
        .unsupportedFileTypeAlert: "不支持的文件类型（.{ext}）。仅支持打开 Markdown 文件。",
    ]

    private static let zhTW: [Key: String] = [
        .appName: "MarkMark",
        .settingsMenuLabel: "設定\u{2026}",
        .settingsBackToApp: "返回應用",
        .settingsTabGeneral: "一般",
        .settingsTabAppearance: "外觀",
        .settingsGeneralLanguageTitle: "介面語言",
        .settingsGeneralLanguageDesc: "選擇應用介面的語言。「自動偵測」會跟隨系統。",
        .settingsGeneralDisplayTitle: "顯示",
        .settingsGeneralDisplayMode: "預設顯示模式",
        .settingsGeneralRenderedWidthTitle: "渲染寬度",
        .settingsGeneralRenderedWidthDesc: "控制渲染內容的最大寬度。關閉時使用固定寬度。",
        .settingsGeneralMaxWidthFollowsWindow: "跟隨視窗寬度",
        .settingsGeneralStartupTitle: "啟動",
        .settingsGeneralReopenLastLocation: "啟動時重新開啟上次位置",
        .settingsGeneralFileTreeTitle: "檔案樹",
        .settingsGeneralShowHiddenFiles: "顯示隱藏檔案",
        .settingsGeneralShowNonMarkdownFiles: "顯示非 Markdown 檔案",
        .settingsGeneralDefaultOpenerTitle: "預設 Markdown 開啟程式",
        .settingsGeneralDefaultOpenerDesc: "將 MarkMark 設為 .md、.markdown、.mdown、.mkd 檔案的預設開啟程式。",
        .settingsGeneralSetAsDefault: "設為預設",
        .settingsGeneralIsDefault: "MarkMark 已是預設 Markdown 開啟程式",
        .settingsGeneralSetDefaultFailed: "設定預設開啟程式失敗，請重試。",
        .settingsGeneralCommandLineTitle: "命令列工具",
        .settingsGeneralCommandLineDesc: "安裝 mdr 命令，可在終端機中開啟檔案。例如：mdr README.md",
        .settingsGeneralCommandLineInstalled: "mdr 命令已在終端機中可用",
        .settingsGeneralCommandLineInstallFailed: "安裝命令列工具失敗，請重試。",
        .settingsGeneralCommandLineUninstallFailed: "解除安裝命令列工具失敗，請重試。",
        .settingsGeneralQuickLookTitle: "Quick Look 預覽",
        .settingsGeneralQuickLookDesc: "在 Finder 中按空白鍵預覽 Markdown 檔案的渲染效果。",
        .settingsGeneralQuickLookEnabled: "啟用 Quick Look 預覽",
        .settingsAppearanceThemeTitle: "主題",
        .settingsAppearanceThemeDesc: "選擇應用的外觀模式。",
        .settingsAppearanceModeLight: "淺色",
        .settingsAppearanceModeLightDesc: "始終使用淺色外觀",
        .settingsAppearanceModeDark: "深色",
        .settingsAppearanceModeDarkDesc: "始終使用深色外觀",
        .settingsAppearanceModeSystem: "跟隨系統",
        .settingsAppearanceModeSystemDesc: "跟隨系統設定",
        .settingsAppearanceSchemeTitle: "配色方案",
        .settingsAppearanceSchemeDesc: "為目前模式選擇預設配色方案。",
        .settingsAppearanceCustomTitle: "自訂顏色",
        .settingsAppearanceCustomDesc: "自訂各顏色令牌。修改將覆蓋目前方案的對應顏色。",
        .settingsAppearanceCustomSurface: "背景色",
        .settingsAppearanceCustomInk: "文字色",
        .settingsAppearanceCustomAccent: "強調色",
        .settingsAppearanceCustomSuccess: "成功色",
        .settingsAppearanceCustomDanger: "危險色",
        .settingsAppearanceContrastTitle: "對比度",
        .settingsAppearanceContrastDesc: "調整背景與前景層之間的對比度。",
        .settingsAppearanceContrastLow: "低",
        .settingsAppearanceContrastHigh: "高",
        .settingsAppearanceTypographyTitle: "字體與排版",
        .settingsAppearanceSourceFontSize: "原始碼字號",
        .settingsAppearanceContentPadding: "內容邊距",
        .languageAuto: "自動偵測",
        .languageZhCN: "简体中文",
        .languageZhTW: "繁體中文",
        .languageEn: "English",
        .displayModeRendered: "渲染",
        .displayModeRaw: "編輯",
        .open: "開啟",
        .save: "儲存",
        .reset: "重設",
        .confirm: "確認",
        .newFromClipboard: "從剪貼簿新建標註",
        .clipboardScratchName: "剪貼簿標註",
        .unsavedChangesTitle: "未儲存的變更",
        .unsavedChangesMessage: "如果不儲存，您的變更將會遺失。關閉前是否儲存？",
        .unsavedSave: "儲存",
        .unsavedDontSave: "不儲存",
        .unsavedCancel: "取消",
        .fileDeletedTitle: "檔案已被刪除",
        .fileDeletedMessage: "檔案「{name}」已被外部刪除，您有未儲存的變更。",
        .fileDeletedSaveAs: "另存為\u{2026}",
        .fileDeletedDiscard: "放棄變更",
        .openRecent: "開啟最近使用",
        .openRecentEmpty: "無最近開啟的項目",
        .openRecentFiles: "檔案",
        .openRecentFolders: "資料夾",
        .clearRecentItems: "清除選單",
        .titleBarToggleSidebar: "切換側邊欄 (⌘\\)",
        .titleBarDisplayMode: "顯示模式",
        .titleBarOpen: "開啟 (⌘O)",
        .titleBarSave: "儲存 (⌘S)",
        .titleBarReload: "重新載入",
        .titleBarToggleOutline: "切換大綱",
        .titleBarCopyPath: "複製路徑",
        .titleBarCopyForAI: "複製標註文件給 AI",
        .titleBarCopyMenu: "複製給 AI / CriticMarkup 原文（給 AI：⌘⇧C）",
        .copyForAIMenu: "複製給 AI（含說明）",
        .copyCriticMenu: "複製 CriticMarkup",
        .copyFragmentsMenu: "複製本次新增的標註片段",
        .copyPromptMenu: "複製 AI 提示詞",
        .copiedToast: "已複製",
        .titleBarAnnotationActions: "套用或放棄所有標註",
        .applyAnnotationsMenu: "套用所有標註…",
        .applyAnnotationsConfirmTitle: "套用所有標註？",
        .applyAnnotationsConfirmMessage: "刪除和替換將直接修改正文，高亮和評論將被移除。此操作無法復原。",
        .discardAnnotationsMenu: "放棄所有標註…",
        .discardAnnotationsConfirmTitle: "放棄所有標註？",
        .discardAnnotationsConfirmMessage: "將移除所有 CriticMarkup 標註並恢復原文，此操作無法復原。",
        .editUndo: "復原",
        .editRedo: "重做",
        .navigationBack: "後退",
        .navigationForward: "前進",
        .titleBarAnnotationPanel: "標註清單",
        .annotationGroupNew: "本次新增",
        .annotationGroupHistory: "歷史標註",
        .annotationSelectAll: "全選",
        .annotationSelectNew: "只選新增",
        .annotationCopySelected: "複製所選片段",
        .annotationStale: "已失效",
        .annotationEmpty: "暫無標註",
        .aiPromptDefaultTemplate: """
        下面的內容中包含使用 CriticMarkup 語法的審閱標註，標記含義如下：
        - {++ 新增內容 ++}        建議新增
        - {-- 刪除內容 --}        建議刪除
        - {~~ 舊內容 ~> 新內容 ~~} 建議替換為新內容
        - {>> 評論 <<}            我的評論/疑問
        - {== 高亮內容 ==}        我重點關注的部分

        ---

        {{MarkMark:content}}
        """,
        .settingsAIPromptTitle: "AI 提示詞模板",
        .settingsAIPromptDescription: "「複製給 AI」與「複製 AI 提示詞」共用。{{MarkMark:content}} 為正文插入位置佔位符。",
        .settingsAIPromptReset: "恢復預設",
        .criticDelete: "刪除",
        .criticHighlight: "高亮",
        .criticComment: "評論",
        .criticReplace: "替換",
        .criticConfirm: "套用",
        .criticCancel: "取消",
        .criticEdit: "編輯",
        .criticCommentHint: "輸入評論…",
        .criticReplaceHint: "替換為…",
        .criticNotFound: "無法在源碼中定位選區（試試只選不跨格式的文字）",
        .fileModifiedExternallyTitle: "檔案已被外部修改",
        .fileModifiedExternallyMessage: "檔案已被其他應用修改，重新載入將捨棄目前未儲存的變更。",
        .fileModifiedExternallyReload: "重新載入",
        .fileModifiedExternallyDontRemind: "以後不再提醒",
        .outlineTitle: "大綱",
        .outlineEmpty: "暫無標題",
        .loading: "載入中...",
        .emptyDirectoryMessage: "此目錄下無 Markdown 檔案",
        .sidebarSettings: "設定 (⌘,)",
        .sidebarSettingsButton: "設定",
        .welcomeOpenFolder: "開啟資料夾開始閱讀",
        .welcomePressCmdO: "按 Cmd+O 或點擊工具列中的開啟按鈕",
        .welcomeDropHint: "或拖拽檔案/資料夾到此處",
        .selectFileHint: "選擇 Markdown 檔案開始閱讀",
        .contextMenuNewFile: "新增檔案",
        .contextMenuNewSubdirectory: "新增子目錄",
        .contextMenuRename: "重新命名",
        .contextMenuMoveTo: "移動到\u{2026}",
        .contextMenuDelete: "移到垃圾桶",
        .contextMenuReload: "重新載入",
        .contextMenuCopyPath: "複製路徑",
        .renameTitle: "重新命名",
        .renameMessage: "輸入「{name}」的新名稱：",
        .renameEmptyName: "名稱不能為空。",
        .renameNameExists: "已存在同名項目。",
        .deleteTitle: "移到垃圾桶",
        .deleteMessage: "確定要將「{name}」移到垃圾桶嗎？",
        .deleteDirectoryMessage: "確定要將「{name}」及其所有內容移到垃圾桶嗎？",
        .moveSelectFolder: "選擇目標資料夾",
        .updateAvailableTitle: "發現新版本",
        .updateAvailableVersion: "版本 {version}",
        .updateChecking: "正在檢查更新\u{2026}",
        .updateUpToDate: "MarkMark 已是最新版本。",
        .updateDownload: "下載",
        .updateDownloading: "正在下載更新\u{2026}",
        .updateDownloadComplete: "下載完成，點擊「安裝」繼續。",
        .updateInstall: "安裝",
        .updateInstallAndRestart: "安裝並重新啟動",
        .updateInstalling: "正在安裝更新\u{2026}",
        .updateLater: "稍後",
        .updateSkipVersion: "跳過此版本",
        .updateCancel: "取消",
        .updateError: "檢查更新失敗。",
        .updateModeAuto: "自動安裝並重新啟動",
        .updateModeManual: "需手動安裝",
        .updateInstallInstructionsTitle: "安裝說明",
        .updateManualInstallInstructions: "1. 下載 .dmg 檔案，雙擊開啟\n2. 將 MarkMark 拖入「應用程式」資料夾\n3. 首次開啟時，macOS 可能提示「無法驗證開發者」：\n   \u{2022} 開啟「系統設定 \u{2192} 隱私權與安全性」\n   \u{2022} 找到被阻擋的 app，點擊「仍要開啟」\n   \u{2022} 或在終端機執行：xattr -cr /Applications/MarkMark.app\n4. 也可以直接右鍵點擊 app \u{2192} 選擇「開啟」",
        .updateReleaseNotesTitle: "更新內容",
        .checkForUpdates: "檢查更新\u{2026}",
        .findBarSearchPlaceholder: "搜尋",
        .findBarReplacePlaceholder: "取代",
        .findBarFindNext: "尋找下一個",
        .findBarFindPrevious: "尋找上一個",
        .findBarReplace: "取代",
        .findBarReplaceAll: "全部取代",
        .findBarNoResults: "無結果",
        .findBarCaseSensitive: "區分大小寫",
        .findBarWholeWord: "全字匹配",
        .findBarRegularExpression: "使用規則表達式",
        .findBarFind: "尋找",
        .findBarFindAndReplace: "尋找和取代",
        .markdownLinkExpandRootTitle: "開啟連結位置？",
        .markdownLinkExpandRootMessage: "這個連結指向目前資料夾之外。MarkMark 會將左側目錄根切換為：\n{root}\n\n目標：\n{target}",
        .markdownLinkOpenCommonRoot: "開啟共同父目錄",
        .markdownLinkMissingTitle: "連結目標不存在",
        .markdownLinkMissingMessage: "連結指向的檔案或目錄不存在：\n{target}",
        .markdownLinkUnsupportedTitle: "不支援的連結目標",
        .markdownLinkUnsupportedMessage: "MarkMark 僅支援透過相對連結開啟 Markdown 檔案和目錄。此目標不支援：\n{target}",
        .exportPDF: "匯出 PDF\u{2026}",
        .titleBarExportPDF: "匯出 PDF (⌘⌥E) / HTML (⌘⇧E)",
        .exportPDFSuccess: "PDF 匯出成功",
        .exportPDFFailed: "PDF 匯出失敗",
        .exportHTML: "匯出 HTML\u{2026}",
        .titleBarExportHTML: "匯出 HTML",
        .exportHTMLSuccess: "HTML 匯出成功",
        .exportHTMLFailed: "HTML 匯出失敗",
        .unsupportedFileTypeAlert: "不支援的檔案類型（.{ext}）。僅支援開啟 Markdown 檔案。",
    ]

    // MARK: - 查找

    private static func dictionary(for language: Language) -> [Key: String] {
        switch language {
        case .zhCN: zhCN
        case .zhTW: zhTW
        case .en: en
        }
    }

    public static func tr(_ key: Key, language: Language) -> String {
        dictionary(for: language)[key] ?? key.rawValue
    }

    public static func tr(_ key: Key, language: Language, args: [String: String]) -> String {
        var result = tr(key, language: language)
        for (k, v) in args {
            result = result.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return result
    }
}

// MARK: - SwiftUI Environment 支持

private struct LanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: Language = .en
}

extension EnvironmentValues {
    public var language: Language {
        get { self[LanguageEnvironmentKey.self] }
        set { self[LanguageEnvironmentKey.self] = newValue }
    }
}

extension View {
    public func withLanguage(_ language: Language) -> some View {
        environment(\.language, language)
    }
}
