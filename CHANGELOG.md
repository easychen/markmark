# Changelog

本项目的所有重要变更都会记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [2.0.16] - 2026-06-29

### 修复

- **独立启动恢复上次打开明显偏慢**：冷启动完成后不再固定等待 1.2 秒来区分「直接打开 App」与「显式打开文件/目录」。现在改为事件驱动：AppKit 先记录直接启动或显式路径意图，SwiftUI 内容窗口 ready 后立即路由；显式打开 md/目录仍优先于恢复逻辑并会收敛掉默认窗口
- **块级 / 行内数学公式中的 LaTeX 被误改写**：`$$...$$` 与 `$...$` 转换后未被保护，块内含 `^` / `~` / `==` 的 LaTeX（如 `$$e^{-x^2}$$`）会被随后的上标 / 下标 / 高亮预处理插入 `<sup>` / `<sub>` / `<mark>`，导致阅读视图、PDF 导出与新增的 HTML 导出中公式渲染错乱。现在数学公式转换结果与代码区域一同进入保护占位符、在预处理末尾统一还原，彻底隔离后续行内正则

### 新增

- **导出为 HTML**：「文件 → 导出 HTML…」（⌘⇧E）及标题栏导出菜单新增 HTML 导出，生成**自包含单文件 HTML**——markdown.css / 主题样式、Prism 代码高亮、KaTeX（含数学字体 base64 内联）、Mermaid 与 `markdown-reader.js` 全部内联，正文图片转为 base64 data URL，导出文件不含任何 `mr://` 引用，可脱离 app 在任意浏览器离线打开并保持与阅读视图一致的渲染。导出页中标注为**只读查看**：点击评论气泡仍可查看评论内容，但不提供新建 / 编辑 / 删除等编辑入口。Mermaid / KaTeX 仅在文档实际用到时才内联以控制体积（#11）
- **本地 Markdown 链接与历史导航**：渲染视图中的相对 Markdown 链接现在可在应用内导航，目录链接只定位左侧目录树，md 链接打开对应文档；越出当前 root 时确认后切到共同父目录。新增窗口内后退 / 前进历史栈，快捷键为 `⌘[` / `⌘]`，标题栏提供对应按钮并带 disabled 状态

### 改进

- **Finder「用 MarkMark 打开」服务、侧边栏目录懒加载、非 Markdown 文本只读预览**：新增 Finder Services 入口（文件 / 目录，简繁英三语）；统一外部（Finder / Services / 拖到图标 / `open`）与内部打开请求路由（`OpenRequestCoordinator`），修复显式打开被「恢复上次位置」覆盖及冷启动 / 窗口复用问题；侧边栏目录树改为首屏只加载根目录、展开时按需加载且扫描阶段不读文件内容；非 Markdown 的 UTF-8 / UTF-16 文本文件支持只读查看（图片 / 二进制仍不支持）（#12，by @flashsoft）
- **侧边栏切换与标题栏图标反馈**：保留 `⌘\` 切换侧边栏；左上角标题栏图标统一 hover 背景和禁用态反馈

## [2.0.15] - 2026-06-18

### 改进

- **单文件模式侧栏与目录树模式显示一致**：直接打开单个 Markdown 文件时，侧栏不再使用单独手写的行视图，改为构造轻量 `FileNode` 并复用 `FileRowView`，使选中高亮、图标位置、可点击区域与目录树模式完全一致（#10，by @flashsoft）
- **侧边栏支持键盘导航**：`FileTreeViewModel` 新增 `activeNodeURL`，目录与文件都可进入 active 态——↑ / ↓ 在可见节点间移动，→ 展开目录、← 收起目录或移动到父目录，Return 在目录上切换展开 / 在文件上打开；active 项移出可视区域时自动滚回中间（#10，by @flashsoft）

### 新增

- **支持把文件或目录拖到 Dock 图标打开**：在 `Info.plist` 的 `CFBundleDocumentTypes` 中补充 `public.folder`，让 Finder / Dock 可将目录作为可打开目标交给 MarkMark；同时明确显式打开目标优先于「恢复上次位置」，并为极早期启动（`openWindow` 尚未注册）补充 pending open 兜底，避免打开请求丢失（#10，by @flashsoft）

## [2.0.14] - 2026-06-17

### 修复

- **渲染模式下无法撤销标注操作（Cmd+Z / 编辑→撤销 无效，且发出系统提示音）**：移除原文编辑模式后，CriticMarkup 标注（评论 / 高亮 / 删除 / 替换）都在只读 WKWebView 上进行，按 Cmd+Z 没有任何响应。本版接管「编辑」菜单的撤销 / 重做命令，并为每个文件维护一个 CriticMarkup 专用 `UndoManager`：每次标注前对文档内容（含会话标注记录）做快照，Cmd+Z / Cmd+Shift+Z 即可逐步撤销 / 重做。该专用管理器独立于窗口 `UndoManager`，避免被 WKWebView 弹窗输入框（评论 / 替换需打字）的文本输入撤销污染——此前正是这种污染导致「评论 / 替换」撤销时出现「按一下没反应、再按才生效」的死按（#8）
- **评论内容中的连续空行会破坏 CriticMarkup 格式**：评论文本原样写入 `{>> ... <<}`，若含空行（连续换行），cmark 会按空行拆段，使 `{>>` 与 `<<}` 落入不同段落，导致标注配对失败、评论气泡错乱。现提交评论时自动折叠连续空行为单个换行并去除首尾空白（前端 JS 清洗 + Swift 端兜底双保险）（#6）
- **首次启动时「跟随系统」主题在深色系统下显示异常（白底白字、文字不可见）**：`SettingsModel` 初始化时过早读取 `NSApp.effectiveAppearance`，系统为深色时被误判为浅色，解析出的主题退回浅色（白底），而窗口实际仍是系统深色外观、默认文字渲染为白色 → 白底白字。现在视图出现时用权威的 SwiftUI `colorScheme` 重新校正系统深浅色并刷新主题（#5）

### 改进

- **评论弹窗防误触关闭、保护未提交草稿**：此前在评论 / 替换输入框打字时，点击外部或按 Esc 会静默丢弃已输入内容。现在输入框非空时点击外部不再关闭弹窗；评论取消 / Esc 关闭前按「位置（行号 + 选中文本）」暂存草稿，对同一处重新写评论时自动恢复（#7）

## [2.0.13] - 2026-06-17

### 修复

- **左侧文件栏点击区域与选中高亮仍不一致（接续 2.0.12）**：2.0.12 将高亮改为行内容 `.background` 后，高亮反而小于可点击区域——高亮被内缩 padding 收窄、文件图标有一半落在底色之外。本版把选中高亮填满整行内容，并将 List 默认行内边距清零（`.listRowInsets` 归零），令选中高亮、`.contentShape` 命中区域与可点击区域三者完全一致并撑满整行宽度；行内边距上移到行视图自身，图标始终完整落在高亮内（#9，by @flashsoft）

## [2.0.12] - 2026-06-16

### 新增

- **支持 macOS 14 与 Intel 芯片**：最低部署版本由 macOS 15 下调至 macOS 14；构建产物为 universal binary（arm64 + x86_64，主程序与 Quick Look 扩展均覆盖），Intel Mac 可原生运行。Quick Look 扩展链接时显式指定 `-mmacosx-version-min=14.0`，确保最低系统版本一致

### 修复

- **左侧文件栏点击区域小于选中高亮**：选中态高亮原先用 `.listRowBackground` 铺满整行单元格（含 List 默认行内边距、且不随层级缩进），而可点击区域只覆盖按钮内容，导致点在高亮边缘却选不中。现将高亮改为行内容的 `.background` 绘制并配合 `.contentShape`，使高亮 ⊆ 可点击区域，消除「看着选中却点不中」的死区
- **预发布版本号被误判为旧版**：`parseVersion` 解析 `2.0.12-beta.1` 时，`12-beta` 段会被 `Int()` 解析失败而丢弃，导致 beta 版被误判为旧版本。现先按 `-` 截断，仅比较数字主版本

## [2.0.11] - 2026-06-13

### 修复

- **关闭所有窗口后，从「打开最近」或快捷方式打开文件会失败**：应用保持运行但无任何窗口时，顶部「文件 → 打开最近」发出的通知只投递给当前 key 窗口（`onActiveReceive`），零窗口时无人接收被静默丢弃；表现为只弹出首页、目标文件未定位、窗口也不激活，需手动点 Dock 图标才出现新窗口。现「打开最近」改由 `WindowRouter` 统一路由：有可用窗口时仍在当前窗口内打开（行为不变），零窗口时自动新建窗口承载目标文件并激活前台。Finder 右键「打开方式」的热启动路径走同一套 `openWindow(value:)`，同样受益

## [2.0.10] - 2026-06-12

### 修复

- **应用内更新后仍启动旧版本**：「守夜人」更新脚本在替换完成后校验可执行文件时硬编码了改名前的旧名 `MarkdownReader`，而实际可执行文件为 `MarkMark`，校验恒失败 → 误判为坏包 → 回滚到 `Contents.old` 并重启旧版本。现改为从 `CFBundleExecutable` 动态读取可执行文件名（预检查处过时的兜底名一并修正）。注意：此修复运行在新版本中，已安装的 2.0.9 及更早改名后版本仍带旧脚本，需手动下载 DMG 覆盖安装一次，之后的应用内更新方可正常

## [2.0.9] - 2026-06-12

### 修复

- **Quick Look 预览中显示无效的标注悬浮工具条**：QuickLook 为只读沙盒环境，标注无法保存，选词时却仍弹出删除/高亮/评论/替换工具条，造成误导（#4，by @yujunhui）。现 `buildContentAwareHTML` 新增 `isQuickLook` 标记，预览时通过脚本标签传入，`markdown-reader.js` 据此跳过标注选区监听的初始化；CriticMarkup 的高亮、评论标记等渲染效果不受影响照常显示

### 变更

- **官网改为中英文双语**：`pages/index.html` 增加多语言方案，按浏览器语言自动选择中文 / 英文，导航栏提供一键切换并记忆选择（localStorage）
- **README 改为中英文双语**：顶部提供语言切换锚点，英文与简体中文内容并列

## [2.0.8] - 2026-06-10

### 新增

- **从剪贴板新建标注**：⌘N / 标题栏剪贴板按钮 / 欢迎页按钮，将剪贴板 Markdown 写入临时文件并以渲染模式打开，标注后可直接复制或另存为；切换文件时自动清理临时文件
- **标注列表面板**：标题栏高亮笔按钮打开（与大纲互斥、共用拖拽调宽），按「本次新增 / 历史标注」分组列出全部 CriticMarkup 标注，支持勾选（默认选中本次新增）、全选 / 只选新增、复制所选片段、点击跳转；定位不到的会话记录置灰显示「已失效」
- **复制菜单扩展为四项**：复制给 AI（含说明）/ 复制本次新增的标注片段 / 复制 CriticMarkup / 复制 AI 提示词；无本次新增时自动打开标注面板供手动勾选
- **标注片段提取**：默认取标注所在整段并附最近标题线索，段落超 400 字时以标注为中心逐句扩展，单句超长按字符截断；片段间以 `[...]` 标示省略
- **AI 提示词模板进设置**：可自定义「复制给 AI」的引导文案，支持 `{{MarkMark:content}}` 正文占位符，一键恢复默认；默认模板改为说明性文案（解释 CriticMarkup 标记含义）
- **应用 / 放弃所有标注**：标题栏一级按钮与文件菜单双入口，各带确认弹窗——应用执行删除/替换并去除高亮评论，放弃还原标注前原文
- **「已复制」轻提示**：所有复制操作成功后内容区底部弹出提示

### 变更

- **移除新建空文件功能**：应用已无编辑模式，⌘N 与标题栏新建按钮改为「从剪贴板新建标注」
- **刷新按钮常驻**：原仅在文件被外部修改时显示，现有文档即显示（外部修改时以强调色提示）

### 修复

- **取消选择后选区首尾字符残留高亮**：规避 WebKit Custom Highlight 删除后不重绘边界字符的 bug——pending 高亮改为仅评论/替换输入态启用，清除时先 clear() 再删除并强制重绘

## [2.0.7] - 2026-06-10

### 修复

- **Universal 包资源 404（2.0.6 重大回归）**：universal 构建产出的 SPM 资源 bundle 为 Xcode 式布局（`Contents/Resources/Resources/`），而 `mr://` scheme handler、PDF 导出与 Quick Look 扩展仍按单架构扁平布局查找，导致安装版 css/js 全部 404——主题样式全部丢失、选词标注菜单不出现。三处资源查找现已兼容两种布局
- **选词工具条输入态死锁**：评论/替换输入框打开后若直接点击文档其他位置，输入态标记会永久拦截 selectionchange，之后选中任何文字都不再弹出工具条（需重开文件才能恢复）。现点击工具条外部即关闭输入框并复位

## [2.0.6] - 2026-06-10

### 修复

- **检查更新指向错误仓库**：`UpdateService` 的 GitHub Releases 仓库从遗留的 `davidhoo/MarkdownReader` 修正为 `easychen/markmark`，不再误提示升级到上游 Markdown Reader 版本（#2，by @NicCraver）
- **更新弹窗不跟随界面语言**：更新 sheet 挂在 WindowGroup 层、不在 ContentView 注入语言的子树内，导致弹窗恒为英文；现为 sheet 显式注入 `.environment(\.language)`（#2）

### 变更

- **DMG 手动安装弹窗优化**：使用本地化「安装说明」（简中/繁中/英文），从 Release body 提取 changelog 单独展示为「更新内容」，并替换遗留的 Markdown Reader 产品名（#2）
- `release-local.sh` release notes 模板中的产品名更正为 MarkMark

## [2.0.5] - 2026-06-09

### 修复

- **冷启动双击 md 文件偶发显示欢迎页**：ContentView.task 中冷启动时显式调用 `loadFile`，不再依赖 SelectionChangeModifier 的异步触发；同时显式加载目录，避免时序竞争
- **冷启动恢复位置误覆盖**：`restoreLastLocation()` 新增守护检查，若冷启动已通过 UserDefaults 打开了文件/目录，不再发送 `.restoreLastLocation` 通知覆盖
- **AppDelegate 冷启动待处理 URL 检测增强**：同时检查 UserDefaults 中的 `pendingOpenFilePath` / `pendingOpenDirectoryPath`，防止 `application(_:open:)` 延迟调用时误发恢复位置通知
- **切换文件时旧错误状态未清除**：`DocumentViewModel.loadFile` 开头先清除 `fileError`，修复从不支持格式文件切换到 md 文件时 `hasDocument` 始终为 false、DetailView 继续显示 ErrorView 的问题

## [2.0.4] - 2026-06-09

### 变更

- **标题栏按钮布局优化**：操作按钮（刷新、保存、导出、大纲）整合为 HStack 对齐组，底部对齐并与大纲图标下对齐，横向间距统一为 8pt，移除独立的 `.padding` 修饰符，视觉更紧凑一致

## [2.0.3] - 2026-06-09

### 新增

- **代码块一键复制**：渲染视图中的代码块右上角悬停显示复制按钮，点击即可复制代码内容
  - 优先使用 `navigator.clipboard` API，降级使用 `document.execCommand('copy')`
  - 复制成功后按钮变为对勾图标，2 秒后自动恢复
  - 样式使用主题 CSS 变量，自动适配深色/浅色主题

## [2.0.2] - 2026-06-09

### 新增

- **PDF 导出**：新增 `PDFExportService`，支持将渲染视图导出为 PDF 文件，自动等待图片、Mermaid、PlantUML 渲染完成后再导出，菜单快捷键 `Cmd+Option+E`
- **拖拽打开文件**：重写拖拽系统，绕过 SwiftUI `.onDrop`，直接使用 AppKit `NSDraggingDestination`，在窗口 themeFrame 上安装 `FileDropOverlayView`，支持拖拽 .md/.markdown/.mdown/.mkd/.txt 文件到窗口打开
- **多扩展名支持**：全面支持 .md / .markdown / .mdown / .mkd 扩展名
  - `FileService` 新增 `markdownExtensions` / `treeDisplayExtensions` 靆合及 `isMarkdownFile()` / `detectMarkdownContent()` 方法
  - `OpenPanelHelper` 文件选择面板和另存为面板支持所有 Markdown 扩展名
  - `SettingsModel` 默认打开程序检查和设置同时覆盖 .md/.markdown/.mdown/.mkd 四种扩展名
  - `Info.plist` 新增 `CFBundleTypeExtensions` 和 `mdown`/`mkd` 扩展名声明
- **纯文本模式**：`.txt` 文件加载时通过内容特征检测判断是否为 Markdown，非 Markdown 的 .txt 以纯文本模式加载（仅编辑模式，禁止切换渲染）
- **窗口拖动区域**：新增 `WindowDragArea` / `WindowDragNSView`，支持自定义标题栏区域的窗口拖动
- **不支持文件类型提示**：拖入不支持的文件类型时弹出提示弹窗，告知用户具体扩展名
- **本地化新增**：`exportPDF`、`exportPDFFailed`、`unsupportedFileTypeAlert` 等键值

### 变更

- **DMG/ZIP 命名简化**：DMG 和 ZIP 文件名不再包含版本号后缀，统一为 `MarkdownReader.dmg` / `MarkdownReader.zip`
- **DMG 卷名简化**：卷名从 `Markdown Reader $VERSION` 简化为 `Markdown Reader`
- **删除 QLMarkdown 子模块**：移除未使用的 QLMarkdown submodule 引用
- **架构文档更新**：新增 `architecture.pdf`

### 修复

- **语法高亮斜体跨行匹配**：斜体正则不再使用 `.dotMatchesLineSeparators`，遵守 CommonMark 段落边界规范
- **下划线斜体误匹配**：`_text_` 模式增加左侧/右侧非字母数字边界检查，避免 `tag_name`、`APP_PATH` 等标识符中的下划线被误解析为斜体
- **语法高亮部分覆盖跳过**：`highlightDeletion` / `highlightInsertion` / `highlightItalic` 新增 `isPartiallyCovered` 检查，跳过跨越代码块边界的匹配

## [2.0.1] - 2026-06-08

### 变更

- **文档更新**：README、CLAUDE.md、架构文档、需求文档同步 v2.0 渲染引擎迁移变更
- **官网更新**：GitHub Pages 更新至 v2.0.0，新增 Quick Look、Mermaid & PlantUML、数学公式、命令行工具等功能展示
- **MPE 预设主题补充**：网站主题预览从 23 套更新为 33 套（新增 5 深色 + 5 浅色 MPE 主题）
- **下载页更新**：系统要求更新为 macOS 26+ (Tahoe)，架构标注更新为 Apple Silicon 原生支持

## [2.0.0] - 2026-06-08

### 新增

- **WKWebView 渲染引擎**：渲染模式从 Textual 迁移至 cmark-gfm + WKWebView，支持完整的 GFM 扩展语法（表格、任务列表、脚注、删除线等）
- **Mermaid 图表渲染**：渲染视图支持 Mermaid 流程图、时序图、甘特图等图表类型，支持主题颜色同步和语法错误检测
- **KaTeX 数学公式**：渲染视图支持 LaTeX 行内公式（`$...$`）和块级公式（`$$...$$`），使用 KaTeX 本地渲染
- **Prism.js 代码高亮**：渲染视图使用 Prism.js 实现 30+ 语言的语法高亮，替代 Textual 内置高亮
- **MPE 预设主题**：新增 10 套 Markdown Preview Enhanced 风格预设主题（5 深色 + 5 浅色）
- **PlantUML 图表渲染**：渲染视图支持 PlantUML 语法，自动渲染为 SVG 图表（需要网络）
- **Quick Look 预览扩展**：Finder 中选中 .md 文件按空格即可预览渲染效果，无需打开应用
- **命令行工具 mdr**：支持在终端安装/卸载 `mdr` 命令，直接从命令行打开 Markdown 文件
- **渲染内容最大宽度跟随窗口**：新增设置选项，渲染内容宽度可跟随窗口自适应
- **Raw→Rendered 光标同步**：切换渲染/原文模式时自动同步光标位置
- **GitHub Pages 项目主页**：新增项目官网，展示功能特性、主题预览和下载入口

### 变更

- **渲染引擎迁移**：从 Textual (StructuredText) 迁移到 cmark-gfm + WKWebView
- **最低部署目标**：从 macOS 15.0 提升到 macOS 26
- **Bundle ID**：保持 `com.markdownreader.app`（单线发布，回归统一标识）
- **JS/CSS 资源本地化**：Mermaid、KaTeX、Prism.js 及字体文件全部本地打包，无需网络
- **移除 x86_64 支持**：回归 arm64 单架构构建

## [1.0.10] - 2026-06-06

### 变更

- **CI 发布流程重构**：将单一 `release` job 拆分为 `create-release`（仅创建 draft release，等待本地构建上传）和 `ci-build`（可选后备，需手动启用 `use_ci_build`）
- **新增本地发布脚本**：`release-local.sh`，本地构建 → 创建 DMG/ZIP → 上传到 GitHub Release，绕过 CI 环境差异导致的运行时问题
- **CI 签名改为精确签名**：不再使用已弃用的 `codesign --deep`，改为分别签名 `Resources/*.bundle` 和主 app

### 修复

- **CI 构建目录修正**：构建产物路径从 `.build/release/` 改为 `.build/arm64-apple-macosx/release/`，匹配 `--arch arm64` 构建输出
- **CI 签名方式修复**：与 v1.0.9 本地构建签名方式一致，避免递归签名破坏 SwiftUI 颜色目录

## [1.0.9] - 2026-06-06

### 修复

- **Appearance 变化时 NSTextView 文字不可见**：深色/浅色主题切换后原文模式文字颜色可能变为与背景相同，导致内容不可见。修复方式：
  - `applicationDidFinishLaunching` 中提前设置 `NSApp.appearance`，避免 SwiftUI 视图创建后 AppKit 覆盖 textColor
  - `SyntaxHighlightedEditor` 新增 appearance 变化检测，切换时自动重应用文字颜色和语法高亮
  - 显式设置 `textView.backgroundColor = .clear`，防止 AppKit 在 appearance 变化时重置为不透明背景
  - `Color.nsColor` 转换改用 sRGB 色彩空间创建固定颜色，消除 SwiftUI 颜色目录动态解析问题
- **自动更新签名修复**：`codesign --deep`（已弃用）改为精确签名，先签名 `Resources/*.bundle` 再签名主 app，避免递归签名破坏 SwiftUI 颜色目录签名导致 NSColor(SwiftUI.Color) 运行时解析失败
- **CI 构建指定架构**：`swift build -c release` 改为 `swift build -c release --arch arm64`，确保 CI 构建产物架构正确

## [1.0.8] - 2026-06-05

### 修复

- **Bundle.module 资源路径修补**：SPM 生成的 `resource_bundle_accessor.swift` 使用 `Bundle.main.bundleURL` 查找资源 bundle，但 macOS .app 的资源位于 `Contents/Resources/`，导致运行时找不到 Textual 和 swiftui-math 的资源 bundle 而崩溃。修补为 `Bundle.main.resourceURL` 使路径正确解析
- **CI 构建修补**：GitHub Actions release 工作流新增 Bundle.module 路径修补步骤，确保 CI 构建的 .app 也能正确加载依赖资源

## [1.0.7] - 2026-06-05

### 变更

- **查找替换栏布局重构**：改为三列布局（chevron / input / buttons），移除固定宽度约束，输入框自适应宽度
- **原文模式文字颜色**：SyntaxHighlightedEditor 主题切换时同步更新文字颜色（`textView.textColor`）

### 修复

- **语法高亮主题刷新**：切换主题后重新应用语法高亮颜色，修复之前主题切换后代码高亮不更新的问题
- **CI 依赖资源 bundle**：构建 .app 时复制依赖资源 bundle（Textual prism-bundle.js 等），修复代码块语法高亮在分发版中不工作的问题
- **自动更新签名断裂**：`cp -R` 替换应用后重新 ad-hoc 签名，修复 macOS 可能限制 AppKit 功能的问题

## [1.0.6] - 2026-06-05

### 新增

- **查找替换功能**：
  - VSCode 风格浮动查找面板，锚定文档区域右上角，Cmd+F 打开，Esc 关闭
  - 支持大小写敏感（Aa）、全词匹配（W*）、正则搜索（.*）
  - 实时匹配计数和当前位置显示（如 3/15），无匹配时红色提示
  - ▲▼ 按钮和 Cmd+G / Cmd+Shift+G 导航匹配项
  - Raw 模式下 NSTextStorage 背景色高亮所有匹配项，当前匹配高亮加深
  - Rendered 模式下通过行号跳转定位匹配位置
  - 替换当前匹配和全部替换（仅 Raw 模式），文字按钮替代图标更直观
  - ▶/▼ 展开收起替换行
  - 新增 FindReplaceViewModel、FindReplaceBar、TextViewSearchRef 三个组件
  - 新增 12 个查找替换相关本地化键值（简中/繁中/英文）
- **图片渲染**：
  - 渲染视图支持显示本地和远程图片（PNG、JPG、GIF、WebP、SVG）
  - 新增 ImageAttachmentLoader 处理图片加载，支持本地文件和 HTTP/HTTPS URL
  - SVG 图片通过 WKWebView 渲染为位图后显示
  - 链接图片（可点击跳转的图片）通过 URL fragment 编码链接地址实现
  - 图片自动适配宽度，保持纵横比
- **上标下标渲染**：
  - 新增 SupSubMarkupParser，支持 `<sup>`/`<sub>` HTML 标签渲染
  - 新增 MarkdownContentPreprocessor 预处理 Markdown 内容中的上标下标标记
- **代码块语法高亮主题**：
  - ThemeColors 新增 `highlighterTheme` 属性，从主题色派生 Textual 语法高亮配色
  - 23 套预设主题各有匹配的代码高亮色彩，关键字、字符串、注释等 20+ token 类型
  - 深色/浅色主题自动适配代码前景色和背景色

### 修复

- **Dock 点击双窗口 bug**：
  - `applicationShouldHandleReopen` 返回 false 阻止 SwiftUI 自动创建新窗口
  - 根据 reopenLastLocation 设置发送 restoreLastLocation 或 resetToWelcome 通知
- **冷启动恢复位置**：
  - 冷启动时若无待处理文件且 reopenLastLocation 开启，发送 restoreLastLocation 通知恢复上次位置
  - 新增 `restoreLastLocation()` 方法恢复上次打开的目录或文件
- **单文件模式稳定性**：
  - 切换单文件模式时保留 selectedFileURL，避免瞬时 nil 翻转触发 SelectionChangeModifier
  - 单文件模式下不再因 selectedFileURL 变 nil 而取消文档，文档生命周期独立于文件树
  - 文件树展开时选中文件清除逻辑增加路径前缀检查，不误清不在根目录树中的选中

## [1.0.5] - 2026-06-04

### 修复

- **自动更新安装可靠性**：
  - 先关闭更新弹窗再执行安装，避免 SwiftUI sheet 干扰进程退出
  - 使用 `exit(0)` 替代 `NSApplication.terminate()`，防止 `windowShouldClose` 拦截导致应用无法退出、守夜人脚本永远等待
  - 守夜人脚本 stdout/stderr 重定向到日志文件（`$TMPDIR/MarkdownReader-update-<UUID>.log`），避免父进程退出时管道关闭导致子进程收到 SIGPIPE
- **滚动定位可靠性**：
  - `CaptureNSView` 新增 `viewDidMoveToSuperview()` 捕获时机和 `viewDidMoveToWindow()` 延迟重试，确保 NSScrollView 捕获成功
  - `ScrollHelperNSView.scrollToLine` 新增两层重试机制（最多 20 次，间隔 0.1 秒）：NSScrollView 未捕获时重试、文档布局未完成时重试
  - 渲染模式滚动请求超时从 0.5 秒延长至 2.5 秒，等待 StructuredText 完成布局

### 变更

- **Dock 点击行为**：所有窗口关闭后点击 Dock 图标，根据「启动时重新打开上次位置」设置决定恢复上次位置或显示欢迎页，修复点击 Dock 时出现双窗口的 bug
- **冷启动恢复位置**：点击应用图标启动时，若「启动时重新打开上次位置」开启则恢复上次位置，否则显示欢迎页
- **移除 `.handlesExternalEvents(matching:)`**：冷启动时 ContentView.task 通过 UserDefaults 读取文件路径，无需 SwiftUI 为外部事件创建额外窗口，避免双窗口问题
- **README 更新**：DMG 安装包大小描述从「不到 6MB」更新为「不到 10MB」

## [1.0.4] - 2026-06-04

### 新增

- **标题栏复制路径按钮**：DetailView 标题栏新增一键复制文件路径按钮
- **右键菜单复制路径**：文件树中目录和文件的右键菜单均新增「复制路径」选项
- **自定义细滚动条**：新增 `ThinOverlayScroller` 类，渲染 6px 圆角滑块，覆盖非 NSTextView 的 NSScrollView（如文件树列表）
- **OpenPanelHelper 重入保护**：新增 `isPanelShowing` 标志位，防止 WindowGroup 多实例并发触发重复弹窗
- **OverlayScrollerHelper 三级搜索策略**：重写滚动条查找逻辑，支持 superview 链 → 兄弟视图 → 祖先区域三级搜索，解决深层级视图中滚动条样式不生效的问题
- **Package.resolved 纳入版本控制**：锁定依赖版本确保构建可复现

### 变更

- **直接调用 OpenPanelHelper**：SidebarView、DetailView、WelcomeView 改为直接调用 `OpenPanelHelper.show()`，移除 `.openPanel` 通知方式，避免 WindowGroup 多实例重复弹窗
- **DocumentViewModel 幂等加载**：`loadFile(at:)` 新增幂等保护，已加载同一文件且内容非空时跳过重复加载
- **热启动延迟移除**：AppDelegate 中 `DispatchQueue.main.asyncAfter(0.3)` 改为 `DispatchQueue.main.async`，消除不必要的 300ms 延迟
- **移除冗余 synchronize()**：AppDelegate 中 `UserDefaults.standard.synchronize()` 调用移除，UserDefaults 自动定期同步
- **ContentView 清理**：移除 4 处冗余的 `loadFile(at:)` 调用，统一由 `SelectionChangeModifier` 响应 `selectedFileURL` 变化触发加载
- **目录关闭优化**：切换到单文件模式时跳过 `clearDirectory()`，文件树即将被隐藏无需清空
- **WelcomeView 清理**：移除内联 `openPanel()` 方法和 `UniformTypeIdentifiers` 导入，统一使用 `OpenPanelHelper.show()`
- **应用图标更新**：更新全部 10 个 AppIcon 尺寸图片

## [1.0.3] - 2026-06-04

### 新增

- **自动更新功能**：基于 GitHub Releases 实现应用内自动更新检查与安装
  - 启动时自动检查更新（延迟 2 秒，避免影响启动速度）
  - 菜单栏「检查更新…」手动触发更新检查
  - 更新弹窗显示版本号、Release Notes、下载进度
  - 支持自动安装并重启（Sparkle 式体验）和手动安装两种模式
  - 支持「跳过此版本」和「稍后提醒」
  - 新增 UpdateService、UpdateViewModel、UpdateView 三个组件
  - SettingsModel 新增 skippedVersion、lastUpdateCheckTime 设置项
- **复制路径本地化**：新增 titleBarCopyPath、contextMenuCopyPath 本地化键值（简中/繁中/英文）
- **自动更新本地化**：新增 18 个更新相关本地化键值（简中/繁中/英文）

### 变更

- **CI 发布流程**：GitHub Actions release 工作流新增 ZIP 打包，Release 同时上传 DMG 和 ZIP
- **发布说明目录**：发布说明文件从项目根目录移至 `docs/releases/` 目录，CI 路径同步更新

## [1.0.2] - 2026-06-04

### 修复

- **双击 .md 文件无法打开应用**：重写 AppDelegate，改用 `application(_:open:)` 替代 `application(_:openFiles:)`，修复 macOS 15+ 上 SwiftUI WindowGroup 窗口不可见的问题
- **冷启动/热启动文件打开**：新增 UserDefaults 回退机制解决文件打开时序问题；新增 `activateFirstHiddenWindow()` 处理冷启动、热启动和 Dock 点击场景
- **Dock 点击激活**：新增 `applicationShouldHandleReopen` 实现 Dock 点击时激活窗口
- **文件打开幂等保护**：ContentView 中对 openFile/openDirectory 通知添加幂等保护，防止重复触发
- **恢复上次位置**：新增 `restoreLastLocation` 通知机制，确保双击文件启动时跳过恢复上次位置
- **应用图标**：更新全部 AppIcon 尺寸（16–512pt），新增图标生成脚本
- **DMG 打包**：package.sh 优先使用 create-dmg，支持 DMG 卷图标；移除 DMG 的 ad-hoc 签名（避免 Gatekeeper 误拦截）
- **文件关联**：LSHandlerRank 从 Alternate 改为 Default，新增 UTImportedTypeDeclarations 确保 .md 文件正确关联

## [1.0.1] - 2026-06-03

### 新增

- **AppDelegate 文件打开处理**：新增 AppDelegate 处理冷启动/热启动时的文件打开事件，通过 `lastHandledURL` 去重防止 `.onOpenURL` 和 AppDelegate 同时触发导致重复打开
- **文件外部修改检测**：集成 FileSystemWatcher，实时监控当前文件所在目录的变更；未修改文件自动静默刷新，已修改文件显示刷新按钮
- **重新加载功能**：标题栏刷新按钮（文件被外部修改时显示）、侧边栏右键菜单「重新加载」选项，支持从磁盘重新加载文件（丢弃当前未保存修改）
- **重新加载确认弹窗**：有未保存修改时弹出确认对话框，支持「以后不再提醒」选项
- **skipFileModifiedAlert 设置**：允许用户关闭外部修改确认弹窗，直接静默重新加载
- **本地化**：新增 `fileModifiedExternallyTitle/Message/Reload/DontRemind`、`titleBarReload`、`contextMenuReload` 共 7 个本地化键值（简中/繁中/英文）

### 变更

- 双击文件启动应用时，跳过恢复上次打开位置，优先打开用户点击的文件
- 禁用 macOS 窗口标签页功能（隐藏「显示标签页栏」菜单项）
- 保存文件后清除外部修改标记，避免误显示刷新按钮

## [1.0.0] - 2026-06-03

首个正式版本。Markdown Reader 是一款 macOS 原生 Markdown 阅读器，采用 SwiftUI + Textual 构建，提供三栏布局：左侧目录树导航 + 中间 Markdown 渲染 + 右侧大纲导航。

### 新增

- **Markdown 渲染引擎**：基于 [Textual](https://github.com/gonzalezreal/textual) 库实现 Markdown 渲染，支持 GFM 扩展（表格、任务列表、删除线等），代码块语法高亮
- **渲染 / 原文模式**：一键切换渲染视图与原始 Markdown 文本，渲染视图支持原生文本选择
- **文件编辑保存**：支持直接编辑 Markdown 文件，Cmd+S 保存，切换文件时自动保留未保存修改（per-file 内容缓存）
- **Per-file Undo 管理**：每个文件独立维护撤销/重做栈，切换文件时完整保留编辑历史
- **新建文件**：右键菜单或快捷键在当前目录下新建 Markdown 文件
- **文件系统监控**：FileSystemWatcher 实时监听文件变更，外部修改自动刷新内容
- **文件树右键菜单**：目录支持新建文档、新建子目录、重命名、移动到、删除；文件支持重命名、移动到、删除
- **未保存修改保护**：关闭未保存文件时弹出确认对话框，可选保存/放弃/取消
- **空目录显示**：文件树递归展示空目录节点
- **自定义双栏布局**：HStack + DragGesture 两列布局，支持拖拽阈值自动隐藏侧边栏、圆角 Detail 区域
- **Buddy 风格界面**：隐藏标题栏 + 自定义窗口控制按钮（TrafficLightButtons），实现 macOS 原生应用体验
- **大纲导航面板**：OutlineView/OutlineService/OutlineItem，自动解析 Markdown 标题结构（ATX + Setext 风格），层级缩进显示，支持 1-6 级标题，点击快速跳转
- **大纲导航滚动同步**：编辑区滚动时自动高亮当前大纲标题
- **主题色彩系统**：23 套预设主题（15 深色 + 8 浅色：Dracula、Catppuccin、Nord、Tokyo Night、Gruvbox、One Dark Pro 等），支持自定义颜色覆盖（surface / ink / accent / success / danger 五色），对比度滑块精细调节
- **外观模式**：支持浅色 / 深色 / 跟随系统三种外观模式
- **多语言本地化**：LocalizationService/L10n 方案，支持简体中文、繁体中文、英文三语，80+ 本地化键值覆盖全部 UI 文字，自动检测系统语言
- **设置系统**：SettingsModel 基于 @Observable + UserDefaults，支持默认显示模式、启动恢复、隐藏文件过滤、外观模式、字体字号、内容边距等配置
- **设置视图**：左侧边栏 + 右侧内容布局，包含主题模式卡片、配色方案网格、自定义颜色条、对比度滑块、字体排版五个区段
- **默认 Markdown 打开程序**：可通过设置将应用注册为 .md/.markdown 文件的默认打开程序
- **最近打开记录**：记录最近打开的文件和目录
- **Git 状态面板**：底部状态栏显示分支、变更计数，可展开变更文件列表及 commit+push 输入区（仅在 Git 仓库中显示）
- **文件树过滤**：支持隐藏文件、非 Markdown 文件过滤
- **键盘导航**：↑↓ 移动文件树，Enter 打开/展开，Cmd+, 设置、Cmd+O 打开、Cmd+\ 切换侧边栏、Cmd+Shift+E/R 切换渲染/原始模式
- **窗口状态恢复**：启动时恢复上次打开的位置
- **应用图标**：全套 macOS AppIcon 尺寸
- **构建与发布**：build-app.sh 支持代码签名与 DMG 打包，package.sh 一键构建打包，GitHub Actions 自动化发布流程

### 变更

- 渲染库从 MarkdownUI 迁移至 Textual（官方继任者）
- 最低部署目标从 macOS 13.0 升级至 macOS 15.0
- 状态管理从 ObservableObject 迁移至 @Observable，启用 Swift 6 严格并发
- 布局方案从 NavigationSplitView 改为自定义 HStack 两列布局
- 窗口样式改用 `.windowStyle(.hiddenTitleBar)`，新增自定义标题栏替代系统 NSToolbar
- ResizeHandle 从 SwiftUI DragGesture 重构为 NSViewRepresentable + NSView 鼠标事件，修复 macOS 拖拽不可靠问题
- RawMarkdownView 替代 SourceMarkdownView，改进原始 Markdown 展示
- 恢复系统原生滚动条，移除自定义主题滚动条

### 移除

- 移除 cmark-gfm 依赖
- 移除 NavigationSplitView 布局方案
- 移除系统 NSToolbar 标题栏
- 移除 Git 模块独立视图（整合至底部状态栏）
