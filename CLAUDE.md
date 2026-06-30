# CLAUDE.md — MarkMark 项目指南

> 本文件为 Claude Code 提供项目上下文，确保代码修改遵循项目规范。

## 项目简介

MarkMark 是一个原生 macOS Markdown 阅读器应用（fork 自 [davidhoo/MarkdownReader](https://github.com/davidhoo/MarkdownReader)）。在安静阅读的基础上加入 CriticMarkup 审阅标注与「一键复制给 AI」工作流。三栏布局：左侧目录树 + 中间渲染视图 + 右侧大纲导航。

> 命名约定：主可执行 target / 产物 / 源码目录 / Bundle ID 均已改为 MarkMark（`Sources/MarkMark`，可执行文件 `MarkMark`，资源 bundle `MarkMark_MarkMark.bundle`，Bundle ID `com.ft07.markmark`）。
> 仍保留 `MarkdownReader` 字样的是：共享库 target `MarkdownReaderKit`、Quick Look 扩展 target/二进制 `MarkdownReaderQL`、以及个别内部 Swift 文件/类型名（如 `MarkdownReaderApp.swift`）——它们是内部模块名，不面向用户，改名会牵动大量 import，故保留。
> UserDefaults 键与 `Notification.Name` 仍用 `com.markdownreader.*` 前缀（仅作唯一键，改动会清空用户设置）。

- **当前版本**: 2.0.16
- **最低部署**: macOS 14.0（自 fork 起从 macOS 26 → 15 → 14 逐步下调；渲染层由 SwiftUI WebView/WebPage 迁移回 WKWebView）
- **架构**: Universal binary（arm64 + x86_64），Intel 与 Apple Silicon 均原生运行
- **Bundle ID**: `com.ft07.markmark`
- **许可证**: MIT

## 技术栈

| 组件 | 选择 |
|------|------|
| 语言 | Swift 6.0（严格并发） |
| UI 框架 | SwiftUI |
| Markdown 渲染 | cmark-gfm + WKWebView（v2.x 已从 Textual 迁移） |
| 状态管理 | `@Observable`（非 ObservableObject） |
| 并发 | Swift Concurrency（async/await, `@MainActor`） |
| 构建系统 | Swift Package Manager |
| 本地化 | 自定义字典方案（L10n），非 Apple String Catalog |

## 项目结构

```
Sources/MarkMark/
├── App/
│   ├── MarkdownReaderApp.swift    # @main 入口，WindowGroup，菜单命令，Notification.Name 常量
│   └── AppDelegate.swift          # NSApplicationDelegate，冷/热启动文件处理
├── Models/
│   ├── FileNode.swift             # 目录树节点
│   ├── Document.swift             # 文档模型
│   ├── FileError.swift            # 错误类型枚举
│   ├── OutlineItem.swift          # 大纲标题模型（level, title, lineNumber）
│   ├── DisplayMode.swift          # 枚举：.rendered / .raw
│   ├── ThemeDefinition.swift      # 5 色主题 + 33 预设 + 自定义覆盖
│   └── SettingsModel.swift        # 设置单例（@Observable + UserDefaults）
├── ViewModels/
│   ├── AppViewModel.swift         # 全局 UI 状态（侧边栏、大纲、设置、窗口标题）
│   ├── DocumentViewModel.swift    # 文档加载/保存/脏跟踪/文件监控（最复杂，~568 行）
│   └── FileTreeViewModel.swift    # 目录树管理/键盘导航/文件操作
├── Views/
│   ├── ContentView.swift          # 主布局（~885 行），ViewModifier 事件处理模式
│   ├── SidebarView.swift          # 左侧目录树
│   ├── DetailView.swift           # 右侧主体区容器
│   ├── RenderedMarkdownView.swift  # WKWebView + cmark-gfm 渲染
│   ├── RawMarkdownView.swift      # 原文编辑包装
│   ├── SyntaxHighlightedEditor.swift  # NSTextView 编辑器（~534 行），per-file undo
│   ├── OutlineView.swift          # 右侧大纲面板
│   ├── SettingsView.swift         # 设置视图
│   ├── ResizeHandle.swift         # 侧边栏拖拽（NSViewRepresentable）
│   ├── OutlineResizeHandle.swift  # 大纲面板拖拽
│   ├── TrafficLightButtons.swift  # 自定义窗口控制按钮
│   ├── FileRowView.swift          # 文件/目录行
│   ├── WelcomeView.swift          # 空状态占位
│   └── ErrorView.swift            # 错误提示
└── Services/
    ├── FileService.swift          # 文件系统操作
    ├── OutlineService.swift       # Markdown 标题解析
    ├── ThemeColors.swift          # 主题色彩派生（5 色 → 12+ 语义 token）
    ├── MarkdownSyntaxHighlighter.swift  # 正则语法高亮（~729 行）
    ├── LanguageService.swift      # 系统语言检测
    ├── LocalizationService.swift  # L10n 字典（80+ 键，3 语言）
    ├── OpenPanelHelper.swift      # NSOpenPanel/NSSavePanel 工具
    └── FileSystemWatcher.swift    # FSEventStream 包装
```

## 构建与运行

```bash
# 构建（调试）
swift build

# 构建（发布）
swift build -c release

# 构建 .app 包（含签名）— Universal (arm64 + x86_64)
./build-app.sh --release --sign

# 打包 DMG（本地分享，ad-hoc 签名）— Universal (arm64 + x86_64)
./package.sh

# 打包 DMG（正式分发，Developer ID 签名 + 公证 + staple）★ 正式发布用这个
./package.sh -d

# 本地发布到 GitHub（构建 + 公证 + 上传）
./release-local.sh
```

> **正式发布必须用 `./package.sh -d`**（Developer ID 签名 + 公证）。
> 公证用 notarytool 钥匙串 profile `markmark`（`NOTARY_PROFILE` 可覆盖），签名身份
> `Developer ID Application: lijie chen (HUJ6HAE4VU)`，均存在本机钥匙串、**不在仓库**。
> 公证需联网。验证：`xcrun stapler validate MarkMark.dmg` +
> `spctl -a -vv MarkMark.app`（应为 `accepted / Notarized Developer ID`）。
> 不带 `-d` 时为 ad-hoc 签名，仅供本地试用，**不要用于发布**。

## 依赖

Swift Package 依赖：**swift-markdown**（传递依赖 swift-cmark）。

仓库内还随 app bundle 打包 Mermaid.js、KaTeX、Prism.js、CSS 等前端资源；Quick Look 扩展由 `build-app.sh` 手动链接并放入 `Contents/PlugIns/`。

## 架构模式 (MVVM)

```
用户操作 → View → ViewModel → Service → 文件系统
                ↑
                └── State 更新 → View 刷新
```

- **ViewModels**: 全部 `@MainActor @Observable`
- **Services**: 纯逻辑层，无 UI 依赖
- **通信**: ViewModel → View 通过状态绑定；App 菜单 → ViewModel 通过 `Notification.Name`

## 关键设计决策

1. **自定义 HStack 三栏布局**（非 NavigationSplitView）— 支持拖拽阈值、单文件模式、圆角 Detail 区域
2. **`.windowStyle(.hiddenTitleBar)`** + 自定义 TitleBar — Buddy 风格布局
3. **NSViewRepresentable ResizeHandle** — SwiftUI `DragGesture` 在 macOS 上不可靠
4. **`@Observable` + 手动 UserDefaults** — `@AppStorage` 与 `@Observable` 不兼容
5. **Per-file undo** — 通过 ObjC runtime swizzling `NSWindow.undoManager`
6. **Notification 通信** — 10 个 `Notification.Name` 常量连接 App 菜单和 ViewModel
7. **SettingsModel.shared 单例** — 跨视图共享设置状态

## 编码规范

- **Swift 6 严格并发**：ViewModel 必须标注 `@MainActor`，注意 Sendable 合规性
- **命名**：ViewModel 用 `XxxViewModel`，Service 用 `XxxService`，Model 用名词
- **视图事件处理**：使用 ViewModifier 模式（参见 ContentView 中的各种 ViewModifier）
- **本地化**：所有面向用户的字符串必须通过 `L10n` 枚举，支持简中/繁中/英文
- **主题**：颜色必须通过 `ThemeColors` Environment 获取，不硬编码色值
- **文件操作**：统一通过 `FileService`，不直接调用 FileManager

## 测试

当前项目已有 `MarkdownReaderKitTests` 和 `MarkMarkTests` 两个测试 target，运行：

```bash
swift test
```

## CI/CD

GitHub Actions (`.github/workflows/release.yml`)：
- 触发：版本 tag (`v*`) 或手动 dispatch
- **默认（推荐）流程**：push tag → CI 仅校验 CHANGELOG 并创建 **draft** release 占位（**不构建**）→
  本地 `./package.sh -d` 出公证包（universal）→ `gh release upload <tag> MarkMark.dmg MarkMark.zip --clobber`
  → `gh release edit <tag> --draft=false` 发布。`release-local.sh` 把后面几步自动化。
- 资产名固定为 `MarkMark.dmg` / `MarkMark.zip`（不带版本号）。
- 发布前需确认 CHANGELOG.md 包含对应版本号。
- ⚠️ **`ci-build` job（`workflow_dispatch` 勾 `use_ci_build`）是不推荐的后备**：它是
  `swift build --arch arm64`（**仅 arm64** + ad-hoc 签名），正是早期「Intel Mac 打不开」的根因，
  且有编辑模式文字不可见的已知 bug。正式发布**勿用**，务必走上面的本地公证包路径。

## 已知注意事项

- 同类型视图替换内容时 SwiftUI 可能不触发 `.onAppear`，需用 `.id(fileURL)` 强制重建
- `SyntaxHighlightedEditor` 使用 ObjC runtime swizzling，修改需谨慎
- `.hiddenTitleBar` 模式下全屏时红绿灯行为需特殊处理（76px → 32px）
- 全局设置单例 `SettingsModel.shared` 不适合多窗口场景

## 文档

- `docs/architecture.md` — 详细架构文档
- `docs/design.md` — UI/UX 设计文档
- `docs/requirements.md` — 需求追踪（P0/P1/P2）
- `CHANGELOG.md` — 版本变更记录
