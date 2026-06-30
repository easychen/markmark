# Markdown Reader — 设计文档

## 1. 设计参考

主界面布局参考 Buddy macOS 的设计风格：
- 左侧 Sidebar 通顶通底，可拖拽调整宽度，可隐藏
- 右侧主内容区有圆角（左上、左下），视觉上与 Sidebar 分离
- 自定义 TitleBar（50px），内嵌功能按钮，不使用系统 NSToolbar
- 右侧可选大纲面板（OutlineView），可拖拽调整宽度
- 主题系统基于 5 色基础派生 12+ 语义 token，支持深色/浅色/跟随系统三种模式

与 Buddy 的差异：
- Markdown Reader 是 SwiftUI 原生应用（非 Electron），使用自定义 HStack 三栏布局
- 窗口样式使用 `.hiddenTitleBar`，实现自定义 TitleBar 和圆角 Detail 区域
- 新增右侧大纲导航面板（Buddy 无此面板）
- 目录树替代任务列表
- 底部 Git 状态栏（Buddy 无此功能）

## 2. 界面布局

### 2.1 主窗口（目录已打开）

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ◉ ◉ ◉  ┌─ Sidebar ──┐  ┌──── Detail Area ─────────────┬─ Outline ─┐ │
│          │ ▼ 📁 docs   │  │  TitleBar (50px)             │  ▸ H1      │ │
│          │   ▼ 📁 dev  │  │  [≡] path  [渲染|原文] [📑]  │    ▸ H2    │ │
│          │     📄 api  │  ├──────────────────────────────┤      ▸ H3  │ │
│          │     📄 setup│  │                              │  ▸ H1      │ │
│          │   📄 readme │  │   # Welcome to Markdown      │    ▸ H2    │ │
│          │ ▶ 📁 design │  │                              │            │ │
│          │ 📄 index    │  │   This is a **markdown** doc │            │ │
│          │ 📷 logo.png │  │                              │            │ │
│          │             │  │   - Feature one              │            │ │
│          │  [Settings] │  │   - Feature two              │            │ │
│          └─────↕───────┘  ├──────────────────────────────┤            │ │
│                          │  🔀 main ● 3 changes  [Commit]│            │ │
│                          └──────────────────────────────┴────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

关键视觉特征（参考 Buddy）：
- Sidebar 使用较深的背景色（surface token）
- 右侧主区域使用 `bgElevated` 稍亮的背景色，左上角和左下角带圆角
- Sidebar 和 Detail 之间有细微的 border 分隔线
- TitleBar 区域是拖拽区域（drag region），按钮为 no-drag
- 大纲面板使用 `bgElevated` 背景，与主内容区视觉一体
- 底部 Git 状态栏仅在 Git 仓库中显示

### 2.2 设置模式

当用户打开设置时（Cmd+,），左侧切换为设置导航菜单，右侧显示设置内容：

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ◉ ◉ ◉  ┌─ Settings ──┐  ┌──── Settings Content ───────────────────┐ │
│          │              │  │                                         │ │
│          │  ● General   │  │  Language:    [Auto ▾]                  │ │
│          │  ○ Appearance│  │  Display:     [Rendered ▾]              │ │
│          │              │  │  ...                                    │ │
│          │              │  │                                         │ │
│          └──────────────┘  └─────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

### 2.3 主窗口（首次启动 / 空状态）

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ◉ ◉ ◉    Markdown Reader                                              │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                                                                          │
│                                 📂                                       │
│                                                                          │
│                     Open a folder to get started                         │
│                                                                          │
│                 Press Cmd+O or click Open in toolbar                     │
│                                                                          │
│                                                                          │
│                                                                          │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### 2.4 窗口尺寸

- 默认宽度：900pt
- 默认高度：600pt
- Sidebar 默认宽度：240pt（与 Buddy 一致）
- Sidebar 最小宽度：150pt
- Sidebar 最大宽度：400pt
- 大纲面板默认宽度：200pt
- 大纲面板最小宽度：150pt
- 大纲面板最大宽度：350pt
- 主体区最小宽度：400pt
- TitleBar 高度：50pt

### 2.5 窗口配置

窗口修饰符配置：
```
WindowGroup
  .windowStyle(.hiddenTitleBar)
  .defaultSize(width: 900, height: 600)
  .windowResizability(.contentMinSize)
```
- 最小窗口尺寸：650pt × 450pt（Sidebar 150pt + 主体 400pt + 100pt 标题栏余量）
- 红绿灯（traffic lights）：系统红绿灯被隐藏，替换为自定义 TrafficLightButtons
- TrafficLightButtons：hover 时显示图标，点击触发窗口关闭/最小化/缩放

## 3. 组件设计

### 3.1 Sidebar 目录树

**视觉规范（参考 Buddy Sidebar）：**
- 使用系统标准 Sidebar 样式（.sidebar）
- 顶部红绿灯区域 + 收起按钮（50px，与 TitleBar 对齐）
- 底部固定区域：Settings 按钮（参考 Buddy 底部固定设置入口）
- 中间区域：目录树列表，可滚动
- 目录图标：`folder.fill`（展开）/ `folder`（折叠）
- Markdown 文件图标：`doc.text`
- 非 Markdown 文件：`doc`，文字灰显（.secondary foregroundStyle）
- 当前选中行：系统高亮色背景（.bgSubtle）
- 行高：跟随系统默认

**Sidebar 宽度调整（参考 Buddy ResizeHandle）：**
- Sidebar 右边缘有拖拽手柄
- 拖拽可实时调整宽度（150pt ~ 400pt）
- 拖过 140px 阈值 → 自动隐藏 Sidebar
- 隐藏后恢复宽度为 240pt 默认值

**实现说明：**
- ResizeHandle 使用 NSViewRepresentable + NSView 鼠标事件（非 SwiftUI DragGesture，因 macOS 拖拽不可靠）
- 鼠标事件：mouseDown → mouseDragged → mouseUp，实时更新 sidebarWidth
- 拖拽结束时判断 `sidebarWidth < 140` → 设置 `isSidebarVisible = false` 并重置宽度
- 光标：通过 NSTrackingArea 管理 hover 光标为 `Cursor.resizeLeftRight`
- 分隔线视觉：1px 宽竖线，颜色使用 `border` token

**交互：**
- 单击文件 → 右侧显示内容
- 单击目录 → 展开/折叠（DisclosureGroup）
- ↑↓ 键 → 在目录树中移动选中项（通过 flattenedVisibleNodes 计算）
- Enter 键 → 打开文件/展开目录
- Sidebar 显隐切换：TitleBar 按钮 或 `Cmd+\`

### 3.2 TitleBar（参考 Buddy TitleBar）

自定义 TitleBar 内嵌在 DetailView 顶部，不使用系统 NSToolbar 或 SwiftUI `.toolbar` modifier。

**Sidebar 可见时：**
```
┌─────────────────────────────────────────────────────────────────────────┐
│          [≡ Sidebar]    文件路径    [渲染|原文]  [📑 Outline]            │
└─────────────────────────────────────────────────────────────────────────┘
```

**Sidebar 隐藏时：**
```
┌─────────────────────────────────────────────────────────────────────────┐
│  ◉ ◉ ◉  [≡ Sidebar]    文件路径    [渲染|原文]  [📑 Outline]            │
└─────────────────────────────────────────────────────────────────────────┘
```

**布局逻辑：**
- 左侧：红绿灯占位区（Sidebar 隐藏时显示 TrafficLightButtons，非全屏 76px / 全屏 32px）+ Sidebar 切换按钮
- 中间：当前文件路径（truncate，左对齐）
- 右侧：渲染/原文切换 Picker + 大纲面板切换按钮

**渲染/原文切换：**
- 使用 `Picker` 控件，Segmented 样式
- 两个选项：「渲染」和「原文」
- 默认选中「渲染」（可在设置中配置默认模式）
- 仅在有文件选中时可用，否则灰显

### 3.3 渲染视图（RenderedMarkdownView）

- 使用 Textual 的 `StructuredText` 视图渲染 Markdown 内容
- 支持标准 Markdown + GFM 扩展（表格、任务列表、删除线等）
- 使用 `.textual.structuredTextStyle(.gitHub)` 预设 GitHub 风格
- 自适应深色/浅色模式
- 代码块语法高亮（Textual 内置）
- 链接点击 → 在系统默认浏览器中打开（通过 NSWorkspace.shared.open）
- 使用 `.id(fileURL)` 确保文件切换时视图正确重建
- 内容区 padding 可配置（默认 20pt，范围 8-40pt）
- 原生文本选择：`.textual.textSelection(.enabled)`

### 3.4 原文视图（RawMarkdownView）

- 使用 SwiftUI TextEditor + 等宽字体（SF Mono）
- 默认启用 Word Wrap（不出现横向滚动条）
- 支持文本选择和复制
- 字体大小可配置（默认 13pt，范围 10-24pt）
- 行号显示（P2，未实现）
- 语法高亮（P2，未实现）

### 3.5 大纲面板（OutlineView）

**视觉规范：**
- 右侧面板，层级缩进显示（每级 14pt 缩进）
- 字号按层级递减：H1=13pt, H2=12.5pt, H3=12pt, H4-H6=11.5pt
- 前景色按层级使用不同透明度：层级越深越浅
- Hover 时显示行背景高亮
- 空状态显示「无标题」提示

**交互：**
- 点击标题项 → 跳转到对应位置（待实现 scroll-to-line）
- 大纲面板显隐：TitleBar 按钮 切换
- 宽度可拖拽调整（150-350pt，默认 200pt）

**实现说明：**
- OutlineResizeHandle：与 ResizeHandle 类似但拖拽方向相反（向左拖 = 变宽）
- OutlineService：解析 Markdown 标题，支持 ATX（`# Title`）和 Setext（`===`/`---`）风格
- 自动跳过代码块内的标题

### 3.6 设置视图（SettingsView）

两栏布局：左侧导航菜单 + 右侧设置内容。

**通用设置（General）：**
- 语言偏好：Auto / 简体中文 / 繁体中文 / English
- 默认显示模式：渲染 / 原文
- 启动恢复：重新打开上次位置
- 文件树过滤：显示隐藏文件 / 显示非 Markdown 文件
- 默认 Markdown 打开程序：检查/设置当前应用为默认

**外观设置（Appearance）：**
- 主题模式卡片：浅色 / 深色 / 跟随系统
- 配色方案网格：8 列，每张卡片显示 surface/accent/ink 色块预览
- 自定义颜色条：5 个基础色（surface/ink/accent/success/danger），每个支持：
  - 行内 hex 编辑
  - 原生 NSColorPanel 颜色选择器（实时预览）
- 对比度滑块：0-100，实时影响派生色值
- 字体排版：源码字号步进器（10-24pt）+ 内容边距步进器（8-40pt）

**行为说明：**
- 切换配色方案时清除自定义颜色覆盖
- 自定义颜色与基础色通过 resolveTheme() 合并
- 所有设置通过 @Observable + UserDefaults 即时持久化

### 3.7 Git 状态面板（ProjectStatusView）

底部状态栏，仅在 Git 仓库中显示。

```
┌──────────────────────────────────────────────────────────────────────────┐
│  🔀 main  ● 3 changes ▾ │  [输入 commit message...]  [Commit & Push]   │
└──────────────────────────────────────────────────────────────────────────┘
```

**展开状态：**
- Staged 文件列表（绿色标记）
- Modified 文件列表（蓝色标记）
- Untracked 文件列表（红色标记）

**交互：**
- 点击变更计数 → 展开/收起文件列表
- 输入 commit message + 点击 Commit & Push
- 成功后显示 Toast 通知

### 3.8 Welcome 视图

- 居中显示文件夹图标 + 提示文字
- 主文字：根据语言本地化显示
- 副文字：「Press Cmd+O or click Open in toolbar」
- 提供 Open 按钮直接触发打开对话框

### 3.9 Error 视图

- 显示错误类型图标（SF Symbol: exclamationmark.triangle）
- 显示错误描述文字（中文本地化）
- 场景：文件权限不足、编码异常、非 Markdown 文件点击、文件不存在

## 4. 交互设计

### 4.1 快捷键

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| `Cmd+O` | 打开目录/文件 | NSOpenPanel，支持目录和 .md 文件 |
| `Cmd+,` | 打开设置 | 切换到设置模式 |
| `Cmd+\` | 切换 Sidebar 显隐 | 沿用既有侧边栏快捷键 |
| `Cmd+Shift+E` | 切换到渲染视图 | |
| `Cmd+Shift+R` | 切换到原文视图 | |
| `Cmd+[` / `Cmd+]` | 后退 / 前进 | Codex / 浏览器风格历史导航 |
| `Cmd+F` | 文件内搜索 | 已实现 |

### 4.2 文件打开方式

1. **菜单/快捷键打开**：Cmd+O → NSOpenPanel → 选择目录或 .md 文件
2. **Finder 双击打开**：注册为 .md/.markdown 默认打开程序后，双击直接打开
3. **拖拽打开**（P2，未实现）

### 4.3 窗口标题

- 无目录打开时：`Markdown Reader`
- 目录已打开时：`Markdown Reader — <目录名>`

## 5. 状态管理

### 5.1 全局状态（AppViewModel）

```
AppViewModel (@Observable, @MainActor)
  ├── rootDirectory: URL?              // 当前打开的根目录
  ├── selectedFile: FileNode?          // 当前选中的文件
  ├── isSidebarVisible: Bool           // Sidebar 是否可见
  ├── sidebarWidth: CGFloat            // Sidebar 当前宽度
  ├── isOutlineVisible: Bool           // 大纲面板是否可见
  ├── outlineWidth: CGFloat            // 大纲面板当前宽度
  ├── isShowingSettings: Bool          // 是否显示设置模式
  ├── isFullscreen: Bool               // 是否全屏
  └── windowTitle: String              // 窗口标题
```

### 5.2 文档状态（DocumentViewModel）

```
DocumentViewModel (@Observable, @MainActor)
  ├── content: String                  // 文件原始内容
  ├── currentFileURL: URL?             // 当前文件 URL
  ├── fileName: String                 // 文件名
  ├── displayMode: DisplayMode         // .rendered | .raw
  ├── isLoading: Bool                  // 加载状态
  ├── fileError: FileError?            // 读取错误
  └── outlineItems: [OutlineItem]      // 大纲项列表
```

### 5.3 目录树状态（FileTreeViewModel）

```
FileTreeViewModel (@Observable, @MainActor)
  ├── nodes: [FileNode]                // 目录树数据
  ├── expandedDirs: Set<URL>           // 已展开的目录
  ├── selectedFileURL: URL?            // 当前选中的文件 URL
  ├── isLoading: Bool                  // 加载状态
  └── errorMessage: String?            // 错误信息
```

### 5.4 Git 状态（GitViewModel）

```
GitViewModel (@Observable, @MainActor)
  ├── gitStatus: GitStatus?            // Git 状态信息
  ├── isGitRepository: Bool            // 是否在 Git 仓库中
  ├── isCommitting: Bool               // 是否正在提交
  ├── commitMessage: String            // Commit 消息
  ├── successMessage: String?          // 成功提示
  └── errorMessage: String?            // 错误提示
```

### 5.5 设置状态（SettingsModel）

```
SettingsModel (@Observable, singleton)
  ├── languagePref: LanguagePref       // auto / zh-CN / zh-TW / en
  ├── defaultDisplayMode: DisplayMode  // 渲染 / 原文
  ├── reopenLastLocation: Bool         // 启动恢复
  ├── showHiddenFiles: Bool            // 显示隐藏文件
  ├── showNonMarkdownFiles: Bool       // 显示非 Markdown 文件
  ├── isDefaultMdOpener: Bool          // 是否为默认打开程序
  ├── appearanceMode: AppearanceMode   // light / dark / system
  ├── themeId: String                  // 主题 ID
  ├── themeCustomOverrides: ThemeCustomOverrides  // 自定义颜色覆盖
  ├── sourceFontSize: Int              // 源码字号（10-24pt）
  ├── contentPadding: Int              // 内容边距（8-40pt）
  ├── lastOpenedDirectory: URL?        // 上次打开的目录
  └── lastOpenedFile: URL?             // 上次打开的文件
```

## 6. 配色与主题

### 6.1 主题系统

**基础定义（ThemeDefinition）：**
- 5 个核心色：surface（背景）、ink（文字）、accent（强调）、success（成功）、danger（危险）
- 1 个对比度值：0-100，控制派生色的明暗程度

**预设主题（23 套）：**

深色主题（15 套）：
Buddy Dark, Codex Dark, Dracula, Catppuccin Mocha, Catppuccin Macchiato, Nord, One Dark Pro, Tokyo Night, Gruvbox Dark, Kanagawa Wave, Rose Pine, GitHub Dark, Material Palenight, Ayu Dark, Vitesse Dark

浅色主题（8 套）：
Buddy Light, Codex Light, Catppuccin Latte, GitHub Light, Gruvbox Light, Kanagawa Lotus, One Light, Rose Pine Dawn

**自定义覆盖（ThemeCustomOverrides）：**
- 可覆盖任意核心色（hex 值）
- 未覆盖的属性回退到基础主题
- 切换配色方案时清除覆盖

**主题解析（resolveTheme）：**
- 将基础主题 + 自定义覆盖合并为最终主题
- 注入 SwiftUI 环境供所有视图使用

### 6.2 语义色值（ThemeColors）

基于 5 核心色 + 对比度派生 12+ 语义 token：

| 语义 Token | 用途 | 派生逻辑 |
|------------|------|----------|
| surface | 主背景 | 核心色 |
| ink | 主文字 | 核心色 |
| accent | 强调/链接 | 核心色 |
| success | 成功/新增 | 核心色 |
| danger | 危险/删除 | 核心色 |
| bgElevated | Detail 区域背景 | surface + 亮度偏移 |
| bgSubtle | 选中行背景 | surface + ink 混合 |
| bgMuted | 次要背景 | surface + 更多亮度偏移 |
| fgSecondary | 次要文字 | ink 透明度降低 |
| fgMuted | 灰显文字 | ink 透明度进一步降低 |
| accentHover | 强调色 hover | accent + 亮度偏移 |
| accentSoft | 柔和强调背景 | accent + surface 混合 |
| border | 分隔线 | ink 低透明度 |
| borderSubtle | 细分隔线 | ink 更低透明度 |

**派生机制：**
- 深色模式：surface 为底，ink 覆盖量随对比度增大
- 浅色模式：surface 为底，ink 覆盖量随对比度减小
- Color mixing：使用 `Color.mix(with:fraction:)` 实现精确混合

### 6.3 外观模式

- `.light`：强制浅色模式（NSAppearance 维度）
- `.dark`：强制深色模式
- `.system`：跟随 macOS 系统设置

## 7. 本地化

### 7.1 语言检测

- Auto 模式：通过 `Locale.current` 检测系统语言
  - 中文简体：script == Hant && (region == TW/HK/MO) → 繁体，否则 → 简体
  - 其他语言：默认英文
- 手动选择：zh-CN / zh-TW / en

### 7.2 本地化系统

- 自定义字典方案（非 Apple String Catalog）
- 80+ 本地化键值，覆盖全部 UI 文字
- 支持 `{n}` 插值（如 `"{n} changes"`）
- 通过 SwiftUI EnvironmentValues.language 注入

## 8. 图标与视觉资产

- 应用图标：全套 macOS AppIcon 尺寸（16x16 至 512x512@2x）
- 文件/目录图标：使用 SF Symbols
  - 目录（展开）：`folder.fill`
  - 目录（折叠）：`folder`
  - Markdown 文件：`doc.text`
  - 其他文件：`doc`（灰显）
- 设置导航图标：`gearshape`（General）、`paintbrush`（Appearance）

## 9. 动效

- Sidebar 显隐：自定义动画，时长 0.25s
- 文件切换：无特殊动画，直接替换内容
- 选中行高亮：系统默认过渡
- Sidebar 宽度拖拽：实时同步宽度变化
- TrafficLightButtons：hover 时渐显图标
- Toast 通知：成功提交后淡入淡出

## 10. 非功能约束

- 只读浏览，不支持编辑
- 不做同步/云端功能
- 不支持多窗口（首版）
- 不支持插件系统
- 最低系统版本：macOS 15.0 (Sequoia)
- Swift 6.0 严格并发
