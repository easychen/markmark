# MarkMark — 架构文档

## 1. 架构总览

采用 SwiftUI 原生的声明式架构，遵循 MVVM 模式。应用支持多窗口打开请求，并采用自定义三栏布局（HStack + NSViewRepresentable ResizeHandle）：左侧 Sidebar 目录树 + 中间内容区 + 右侧大纲面板。窗口使用 `.windowStyle(.hiddenTitleBar)` 隐藏系统标题栏，通过自定义 TitleBar 视图实现工具栏功能。使用 Swift Observation `@Observable` 进行状态管理，Swift 6.0 严格并发。

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ◉ ◉ ◉  ┌─ Sidebar ──┐  ┌──── Detail Area ─────────────┬─ Outline ─┐ │
│          │ ▼ 📁 docs   │  │  TitleBar (50px)             │  ▸ H1      │ │
│          │   📄 readme │  │  [≡] path  [渲染|原文] [📑]  │    ▸ H2    │ │
│          │   📷 logo   │  ├──────────────────────────────┤      ▸ H3  │ │
│          │ ▶ 📁 design │  │                              │  ▸ H1      │ │
│          │ 📄 index    │  │  Content (渲染/原文)           │    ▸ H2    │ │
│          │  [Settings] │  ├──────────────────────────────┤            │ │
│          └─────↕───────┘  │  Git Status (可选)           │            │ │
│                          └──────────────────────────────┴────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘

布局结构：
ContentView (HStack)
  ├── SidebarView (条件渲染，isSidebarVisible 控制显隐)
  │     └── FileTreeViewModel → FileService
  ├── ResizeHandle (NSViewRepresentable + NSView 鼠标事件)
  └── DetailView (圆角容器，左上/左下圆角)
        ├── TitleBar (内嵌于 DetailView，50px)
        ├── RenderedMarkdownView / RawMarkdownView / WelcomeView / ErrorView
        ├── OutlineView + OutlineResizeHandle (条件渲染，isOutlineVisible 控制)
        └── ProjectStatusView (条件渲染，isGitRepository 控制)
              └── GitViewModel → GitService
```

## 2. 技术选型

| 组件 | 选择 | 理由 |
|------|------|------|
| UI 框架 | SwiftUI | macOS 原生，声明式 |
| Markdown 渲染 | cmark-gfm + WKWebView (v2.x) | 完整 GFM 扩展语法，支持 Mermaid/PlantUML/KaTeX/Prism.js，替代 Textual |
| 目录树 | 按需加载的递归 DisclosureGroup | 原生树形展示方案，支持自定义行样式，展开目录时再读取子层级 |
| 布局 | 自定义 HStack + NSViewRepresentable ResizeHandle | 支持自定义拖拽阈值（140px 自动隐藏）、单文件模式无 Sidebar、圆角 Detail 区域；NavigationSplitView 无法满足这些需求；SwiftUI DragGesture 在 macOS 上不可靠 |
| 窗口样式 | .windowStyle(.hiddenTitleBar) | 支持自定义 TitleBar 视图和圆角 Detail 区域；系统 NSToolbar 无法实现 Buddy 风格布局 |
| 文件系统 | FileManager + URL | 原生文件访问 |
| 异步 | Swift Concurrency (async/await) | 现代异步方案，Swift 6 严格并发检查 |
| 状态管理 | Swift Observation `@Observable` | 更简洁的观察机制 |
| 本地化 | 自定义字典方案 | 不依赖 Apple String Catalog，灵活支持动态语言切换 |
| Git 集成 | Process + /usr/bin/git | 轻量级，无需额外依赖 |

## 3. 模块划分

### 3.1 App 层

- **MarkdownReaderApp**: 应用入口，WindowGroup 配置（`.windowStyle(.hiddenTitleBar)` + `.defaultSize(width: 900, height: 600)`），最低部署目标 macOS 14
  - 值型 `WindowGroup(for: URL.self)` 承载多窗口打开：不同 URL 新窗口，同 URL 聚焦已有窗口
  - 菜单命令：Cmd+, (设置)、Cmd+O (打开)、Cmd+\ (切换 Sidebar)、Cmd+[ / Cmd+] (后退/前进)、Cmd+F/G (查找导航)
  - `openWindow(value:)` 注册到 `WindowRouter`，供 AppKit 层打开外部 URL
- **AppDelegate**: AppKit 生命周期 adapter，接收 LaunchServices open URL、Finder Services、Dock reopen、窗口拖拽 overlay 安装
  - 不直接决定产品语义，而是把外部打开、启动完成、Dock reopen 交给 `OpenRequestCoordinator`
  - 保留隐藏窗口激活、activation pulse、fallback window 等 macOS/SwiftUI 时序兜底
- **OpenRequestCoordinator**: 打开请求路由的深模块，统一决定 Open Request 的处理方式
  - External Open：双击、打开方式、拖到 App 图标、Finder Services → 多窗口路径
  - Internal Open：打开最近、欢迎页最近文件等 App 内导航 → 替换当前 key window；无窗口时退化为多窗口路径
  - Restore Request：仅在无 pending/external URL 时恢复上次位置或显示欢迎页
  - Pending Open：冷启动早期写入 UserDefaults，等待初始 `ContentView.task` 消费，watchdog 未消费时再显式路由
- **WindowRouter**: SwiftUI/AppKit 之间的窗口分发 adapter
  - 封装 `openWindow(value:)`，并为 App 内打开入口调用 `OpenRequestCoordinator.handleInternalOpen`

### 3.2 视图层 (Views)

| 视图 | 职责 |
|------|------|
| ContentView | 主视图，管理三栏布局 + 设置模式切换，应用 ViewModifier 模式处理各种事件 |
| DetailView | 右侧主体区容器（圆角），包含 TitleBar、内容区、大纲面板、Git 状态栏 |
| SidebarView | 左侧目录树，展示文件结构，顶部提供打开/剪贴板/历史导航按钮，底部固定 Settings 按钮 |
| FileRowView | 目录树中单个文件/目录行（SF Symbols 图标） |
| OutlineView | 右侧大纲面板，层级缩进显示标题结构 |
| OutlineResizeHandle | 大纲面板拖拽调整宽度（拖拽方向与 ResizeHandle 相反） |
| ResizeHandle | Sidebar 边缘分隔线 + 拖拽调整宽度（NSViewRepresentable + NSView 鼠标事件） |
| SettingsView | 设置视图，两栏布局（General / Appearance） |
| RenderedMarkdownView | Markdown 渲染显示视图（WKWebView + cmark-gfm） |
| RawMarkdownView | Markdown 原文显示视图（TextEditor + SF Mono） |
| ProjectStatusView | 底部 Git 状态栏（分支、变更、commit+push） |
| TrafficLightButtons | 自定义窗口控制按钮（close/minimize/zoom），hover 显示图标 |
| TitleBarIconButton | 标题栏紧凑图标按钮，统一 hover / disabled 反馈 |
| WelcomeView | 空状态占位视图，提示用户打开目录 |
| ErrorView | 错误提示视图（文件读取失败等） |

### 3.3 视图模型层 (ViewModels)

| ViewModel | 职责 |
|-----------|------|
| AppViewModel | 全局状态：rootDirectory, selectedFile, isSidebarVisible, sidebarWidth, isOutlineVisible, outlineWidth, isShowingSettings, isFullscreen, windowTitle（使用 @Observable） |
| DocumentViewModel | 管理当前文档状态，文件读取（FileService），渲染/原文切换，大纲解析（OutlineService） |
| FileTreeViewModel | 管理目录树数据（FileService），目录展开/折叠，键盘导航，并提供 revealDirectory / revealFile 只加载祖先链路 |
| NavigationHistoryModel | 窗口内历史栈，记录 root、单文件、selected file、active node，用于 `⌘[` / `⌘]` 后退前进 |
| GitViewModel | 管理 Git 状态刷新（GitService），commit+push 工作流 |

### 3.4 模型层 (Models)

| Model | 职责 |
|-------|------|
| FileNode | 文件/目录节点模型（name, path, isDirectory, isMarkdown, children, isChildrenLoaded） |
| Document | 当前文档模型（content, filePath, id） |
| DisplayMode | 枚举：.rendered / .raw |
| FileError | 错误类型枚举：permissionDenied, encodingError, fileNotFound, unsupportedFileType, unknown |
| OutlineItem | 大纲项模型：level (1-6), title, lineNumber |
| SettingsModel | 设置单例（@Observable + UserDefaults）：语言、显示模式、主题、字号、边距等 11+ 配置项 |
| ThemeDefinition | 主题定义：5 核心色 + 对比度；PresetThemes 枚举定义 33 套预设（20 深色 + 13 浅色）；ThemeCustomOverrides 支持自定义覆盖 |

### 3.5 服务层 (Services)

| Service | 职责 |
|---------|------|
| FileService | 文件系统操作：按层扫描目录（可配置隐藏文件/非 Markdown 过滤）、读取 Markdown 内容、打开时文本嗅探 fallback |
| GitService | Git 操作：通过 Process 调用 /usr/bin/git，提供 status/add/commit/push 功能，解析 porcelain 格式输出 |
| LanguageService | 语言检测：通过 Locale.current 检测系统语言，区分 zh-CN/zh-TW/en |
| LocalizationService (L10n) | 本地化服务：80+ 键值的字典方案，支持 {n} 插值，3 语言完整翻译，SwiftUI Environment 注入 |
| OutlineService | 大纲解析：从 Markdown 文本提取标题（ATX + Setext 风格），跳过代码块内的标题 |
| ThemeColors | 主题色彩服务：基于 ThemeDefinition + 对比度派生 12+ 语义 token，SwiftUI Environment 注入 |

## 4. 数据流

```
用户操作 → View → ViewModel → Service → 文件系统/Git
                  ↑
                  └── State 更新 → View 刷新
```

1. 用户在 SidebarView 点击文件 → FileTreeViewModel 更新选中状态
2. DocumentViewModel 监听选中变化 → FileService 读取文件内容 → OutlineService 解析大纲
3. DocumentViewModel 更新 content/outlineItems 状态 → DetailView 刷新显示
4. 用户切换渲染/原文 → DocumentViewModel 更新 displayMode → DetailView 切换子视图
5. 用户拖拽 ResizeHandle → AppViewModel 更新 sidebarWidth，低于 140px 阈值时 isSidebarVisible = false
6. 用户点击 TitleBar Sidebar 按钮 / Cmd+\ → AppViewModel 切换 isSidebarVisible → HStack 条件渲染 SidebarView
7. 用户点击 Outline 按钮 → AppViewModel 切换 isOutlineVisible → DetailView 条件渲染 OutlineView
8. 用户打开设置 → AppViewModel 切换 isShowingSettings → ContentView 切换到设置模式
9. GitViewModel 定期刷新状态 → GitService 执行 git status → ProjectStatusView 更新显示
10. 用户点击相对 Markdown 链接 → WebView 拦截 `mr:///...` → ContentView 应用 MarkdownLinkNavigationPolicy → FileTreeViewModel reveal / DocumentViewModel 打开目标，并写入 NavigationHistoryModel
11. 用户按 Cmd+[ / Cmd+] → NavigationHistoryModel 弹出目标快照 → ContentView 恢复 root、selected file 与 active node

## 5. 依赖关系

```
MarkdownReaderApp (.windowStyle(.hiddenTitleBar))
  └── ContentView (HStack)
        ├── SidebarView (if isSidebarVisible)
        │     ├── FileRowView
        │     └── FileTreeViewModel (@Observable) → FileService
        ├── ResizeHandle (NSViewRepresentable + NSView 鼠标事件)
        └── DetailView (圆角容器)
              ├── TrafficLightButtons (if !isSidebarVisible)
              ├── TitleBar (内嵌于 DetailView)
              ├── RenderedMarkdownView (WKWebView + cmark-gfm)
              ├── RawMarkdownView (TextEditor)
              ├── WelcomeView
              ├── ErrorView
              ├── OutlineView + OutlineResizeHandle (if isOutlineVisible)
              │     └── OutlineService → OutlineItem
              ├── ProjectStatusView (if isGitRepository)
              │     └── GitViewModel (@Observable) → GitService
              └── DocumentViewModel (@Observable) → FileService + OutlineService

AppViewModel (@Observable, @MainActor)
  ├── rootDirectory: URL?
  ├── selectedFile: FileNode?
  ├── isSidebarVisible: Bool
  ├── sidebarWidth: CGFloat
  ├── isOutlineVisible: Bool
  ├── outlineWidth: CGFloat
  ├── isShowingSettings: Bool
  └── isFullscreen: Bool

SettingsModel (@Observable, singleton)
  └── UserDefaults (持久化所有设置)

ThemeColors
  └── ThemeDefinition (5 核心色 + 对比度)
        └── SwiftUI Environment (themeColors)

LocalizationService
  └── SwiftUI Environment (language)
```

外部依赖：
- swift-markdown: `https://github.com/apple/swift-markdown.git` (SPM)
  - 传递依赖：swift-cmark
- cmark-gfm: 内嵌 C 源码，GFM 扩展解析
- Mermaid.js: 本地打包，图表渲染
- KaTeX: 本地打包，数学公式渲染
- Prism.js: 本地打包，代码语法高亮
- PlantUML: 在线渲染（需网络），SVG 输出

## 6. 关键设计决策

| 决策 | 选择 | 备选 | 理由 |
|------|------|------|------|
| 布局方案 | 自定义 HStack + NSViewRepresentable ResizeHandle | NavigationSplitView | 支持自定义拖拽阈值（140px 自动隐藏 Sidebar）、单文件模式无 Sidebar、圆角 Detail 区域；SwiftUI DragGesture 在 macOS 上不可靠 |
| 窗口样式 | .windowStyle(.hiddenTitleBar) + 内嵌 TitleBar | 系统 NSToolbar (.toolbar) | 支持圆角 Detail 区域和自定义拖拽区域；系统 .toolbar 无法实现 Buddy 风格布局 |
| Markdown 渲染 | cmark-gfm + WKWebView (v2.x) | Textual / MarkdownUI | 完整 GFM 扩展，支持 Mermaid/PlantUML/KaTeX/Prism.js，WKWebView 原生选择 |
| 状态管理 | Swift Observation `@Observable` | ObservableObject | 更简洁，无需 @Published |
| 目录树渲染 | 递归 DisclosureGroup | OutlineGroup | 更灵活的自定义行样式控制 |
| 本地化方案 | 自定义字典 + Environment | Apple String Catalog | 支持动态语言切换，不依赖编译时字符串目录 |
| 主题系统 | 5 核心色 + 对比度派生 | 固定色值方案 | 少量基础色派生大量语义 token，统一调性，自定义覆盖回退到基础主题 |
| Git 集成 | Process + /usr/bin/git | SwiftGit2 / libgit2 | 零依赖，满足 status/commit/push 基本需求 |
| 非 .md 文件展示 | 灰显显示 | 完全过滤 | 让用户看到完整目录结构，但明确标识不可预览 |
| 设置持久化 | @Observable + UserDefaults | CoreData / File | 设置数据简单，UserDefaults 足够；@Observable didSet 即时同步 |

## 7. 已知注意事项

- **视图重建**：同一类型视图替换内容时 SwiftUI 可能不触发 `.onAppear`，需用 `.id(fileURL)` 强制重建视图
- **WKWebView 渲染**：JS/CSS 资源已本地打包，Mermaid/KaTeX/Prism.js 无需网络；PlantUML 需要网络连接
- **Swift 6 严格并发**：需处理 Sendable 合规性和 actor 隔离，ViewModel 需标注 `@MainActor`
- **自定义布局窗口 resize 状态同步**：窗口 resize 时需注意 sidebarWidth 累积偏移问题
- **全屏模式适配**：`.hiddenTitleBar` 模式下全屏时需处理红绿灯行为（红绿灯区域宽度从 76px 变为 32px）和 TitleBar 的自动隐藏/显示
- **Git Process 依赖**：GitService 依赖 /usr/bin/git，Xcode 命令行工具需预装
- **大纲 scroll-to-line**：OutlineItem 存储 lineNumber，渲染视图与原文视图均需保持跳转回归
