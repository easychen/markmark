# MarkMark 打开请求路由 — 改造方案

> 创建时间：2026-06-27  
> 状态：✅ 主路径已接入；默认窗口延迟到无显式 URL 后创建；命令级 LaunchServices + NSPerformService 回归通过  
> 目标版本：v2.x 后续版本

---

## 1. 问题描述

MarkMark 当前已经支持从 Finder、Dock、菜单、最近打开等多个入口打开文件或目录，但这些入口的路由逻辑分散在 `AppDelegate`、`ContentView`、`WindowRouter` 和 UserDefaults pending 机制中，导致不同入口的产品语义不够统一。

核心问题不是“某个入口打不开”，而是：

| 问题 | 当前表现 | 影响 |
|------|----------|------|
| 外部打开语义不统一 | 双击/打开方式倾向多窗口，Finder Services 倾向复用现有窗口 | 用户难以预测打开结果 |
| Services 只支持文件夹 | `NSSendFileTypes` 仅注册 `public.folder` | 右键文件无法通过 Services 打开 |
| 恢复会话与显式打开耦合 | 冷启动 pending 与 restore 分散在 AppDelegate/ContentView | 容易回归为“显式打开被恢复覆盖” |
| 打开状态机分散 | 冷启动、热启动、无窗口、隐藏窗口、fallback window 多处判断 | 维护成本高，测试困难 |
| AppDelegate 过重 | 同时负责 lifecycle、Services、pending、窗口激活、拖拽 overlay 等 | AppKit adapter 和产品决策混杂 |

---

## 2. 设计目标

### 2.1 产品目标

1. **显式打开永远优先于恢复会话**：只要用户指定了文件或目录，就不应被 `reopenLastLocation` 覆盖。
2. **外部显式打开使用多窗口语义**：不同 URL 新窗口，同 URL 聚焦已有窗口。
3. **App 内导航复用当前窗口**：菜单、欢迎页、最近打开等应用内操作不额外创建窗口。
4. **Finder Services 与其他外部入口一致**：支持文件和文件夹，并按外部显式打开处理。
5. **直接启动 App 才恢复会话**：无显式 URL 时，根据设置恢复上次位置或显示欢迎页。

### 2.2 工程目标

1. 把打开请求状态机收敛到一个深模块中。
2. 降低 `AppDelegate` 的产品决策职责，让它只做 AppKit 入口适配。
3. 让 `ContentView` 只消费明确的窗口内动作或绑定 URL。
4. 为打开路由补充最小可测试 seam，避免只靠 Finder 手测。
5. 保留现有 SwiftUI `WindowGroup(for: URL.self)` 的多窗口/去重能力。

---

## 3. 术语定义

| 术语 | 定义 | 示例 |
|------|------|------|
| Open Request | 一次“想打开某个目标”的请求 | 双击文件、Cmd+O、Dock reopen |
| External Open | 来自 Finder、LaunchServices、Services、拖到 App 图标等 App 外部入口的显式打开 | 双击 `.md`、右键“打开方式” |
| Internal Open | 来自 App 内 UI 的导航式打开 | 打开最近、欢迎页最近文件 |
| Restore Request | 无显式 URL 时恢复上次位置的请求 | 直接双击 App 图标启动 |
| Open Disposition | 对 Open Request 的处理策略 | 新窗口、替换当前窗口、恢复、欢迎页 |
| Pending Open | 冷启动早期暂存、等待 SwiftUI WindowGroup 可用后消费的打开请求 | `pendingOpenFilePath` |
| Usable Window | 可见、可成为 key、非 panel、非 sheet 的内容窗口 | 当前阅读窗口 |

---

## 4. 目标行为矩阵

| 入口 | 请求类型 | 目标行为 | 多 URL 行为 | 是否允许恢复覆盖 |
|------|----------|----------|-------------|------------------|
| 拖拽文件/文件夹到 App 图标 | External Open | 不同 URL 新窗口；同 URL 聚焦 | 每个 URL 独立路由 | ❌ |
| Finder 双击已注册文件 | External Open | 不同 URL 新窗口；同 URL 聚焦 | 每个 URL 独立路由 | ❌ |
| 右键文件/文件夹 → 打开方式 | External Open | 不同 URL 新窗口；同 URL 聚焦 | 每个 URL 独立路由 | ❌ |
| 右键文件/文件夹 → Services → 用 MarkMark 打开 | External Open | 不同 URL 新窗口；同 URL 聚焦 | 每个 URL 独立路由 | ❌ |
| Cmd+O 打开 | Internal Open | 当前 key window 替换 | 现有 open panel 单选 | 不适用 |
| 欢迎页最近文件 | Internal Open | 当前窗口替换 | 单个 URL | 不适用 |
| 菜单“打开最近” | Internal Open | 当前 key window 替换；无窗口则新建 | 单个 URL | 不适用 |
| 直接双击 App 图标启动 | Restore Request | 按设置恢复或欢迎页 | 无 URL | ✅ 仅无显式 URL 时 |
| Dock reopen（无可见窗口） | Restore Request | 按设置恢复或欢迎页 | 无 URL | ✅ 仅无显式 URL 时 |

---

## 5. 方案概览

新增 `OpenRequestCoordinator` 作为打开请求路由的深模块，统一处理入口事件和路由决策。

```
Finder / Dock / Services / App Menu
        │
        ▼
AppKit / SwiftUI Adapter
(AppDelegate / ContentView / Menu)
        │
        ▼
OpenRequestCoordinator
        │
        ├── External Open → WindowRouter.openExternalURL(url)
        ├── Internal Open → WindowRouter.replaceActiveWindow(url)
        ├── Restore Request → .restoreLastLocation notification
        └── Welcome Request → .resetToWelcome notification
```

### 5.1 模块职责

| 模块 | 改造后职责 |
|------|------------|
| AppDelegate | 接收 AppKit lifecycle、open URL、Services selector、Dock reopen；转交 coordinator |
| OpenRequestCoordinator | 判断请求类型、pending 策略、恢复优先级、打开动作、watchdog |
| WindowRouter | 封装 `openWindow(value:)`、当前窗口替换通知、可用窗口判断 |
| ContentView | 加载 `openedURL`，响应当前窗口替换、恢复、欢迎页动作 |
| SettingsModel | 继续保存上次打开位置和恢复设置，不参与路由决策 |

---

## 6. 推荐接口

### 6.1 OpenRequestCoordinator

建议 interface 保持小而稳定：

```swift
@MainActor
final class OpenRequestCoordinator {
    func handleExternalOpen(urls: [URL], reason: OpenReason)
    func handleServiceOpen(pasteboard: NSPasteboard)
    func handleLaunchCompleted()
    func handleDockReopen()
}
```

内部私有职责：

- URL 分类：文件 / 目录 / unsupported
- Services pasteboard 解析与过滤
- cold-start pending 写入与消费检测
- watchdog：pending 未消费时主动路由
- restore guard：有 pending 或已显式打开时不恢复
- activation pulse：拉起隐藏窗口
- fallback window：仅作为极端兜底，不作为正常路径

### 6.2 WindowRouter

建议 interface 聚焦窗口分发：

```swift
@MainActor
final class WindowRouter {
    func openExternalURL(_ url: URL)
    func replaceActiveWindow(with url: URL)
    func hasUsableWindow() -> Bool
}
```

语义约定：

| 方法 | 语义 |
|------|------|
| `openExternalURL` | 使用 `openWindow(value:)`，依赖 SwiftUI 值型 WindowGroup 去重 |
| `replaceActiveWindow` | 对 key window 发送 `.openFile` / `.openDirectory`；无窗口时退化为新窗口 |
| `hasUsableWindow` | 只判断内容窗口，不把 sheet/panel 计入 |

---

## 7. 实施步骤

### 阶段 1：固化语义与测试 seam

- [x] 新增 `OpenRequestCoordinator`
- [x] 定义 `OpenReason` 与 coordinator seam
- [x] 为 coordinator 决策补充最小单元测试
- [x] 先验证决策表，再迁移生产路径

### 阶段 2：迁移 AppDelegate 路由逻辑

- [x] `application(_:open:)` 接入 coordinator
- [x] pending UserDefaults 读写收敛到 `PendingOpenStoring`
- [x] cold-start watchdog 改为通过 coordinator 重新路由
- [x] Services pasteboard 解析迁入 coordinator
- [ ] 继续瘦身旧 `routeURLsToApp` fallback helper（当前仍作为 AppDelegate router adapter 的兜底实现保留）

### 阶段 3：收敛 WindowRouter 语义

- [x] App 内“打开最近”改为 coordinator internal-open 语义
- [x] 保留 `openWindow(value:)` 注册逻辑
- [x] 当前窗口替换继续通过 key-window active receive 限定
- [ ] 后续可把 `NotificationOpenRequestRouter` 与 `WindowRouter` 的职责进一步合并命名

### 阶段 4：补齐 Finder Services

- [x] `Info.plist` Services 支持文件和文件夹
- [x] Services 入口接受 file URL pasteboard
- [x] Services 使用 external open 语义，不再特殊复用当前窗口
- [ ] unsupported URL 目前安全过滤；如需用户提示可后续补 UI

### 阶段 5：回归验证

- [x] 冷启动打开 `.md`（`scripts/open-request-regression.sh` 通过 LaunchServices `open <file> -a <app>` 验证）
- [x] 热启动打开不同 `.md`（脚本验证不同 URL 增加一个目标窗口）
- [x] 重复打开同一 URL 不新增窗口（脚本验证 A→B 后重复 A/B 窗口数不再增长）
- [x] 拖文件到 App 图标 / 右键“打开方式”的底层 LaunchServices 路径（脚本用指定 app bundle 的 LaunchServices open 覆盖）
- [x] 拖文件夹到 App 图标的底层 LaunchServices 路径（脚本验证 cold explicit folder 只留下目标目录窗口，并更新 lastOpenedDirectory）
- [x] 拖文件/文件夹到已打开窗口：窗口拖拽 overlay 走 `WindowRouter.openWindow(for:)` 外部多窗口语义，新窗口会前置
- [x] 右键 Services 打开文件（脚本用 `NSPerformService("用 MarkMark 打开", pasteboard)` 验证）
- [x] 右键 Services 打开文件夹（脚本用 `NSPerformService("用 MarkMark 打开", pasteboard)` 验证）
- [ ] 直接双击 App 图标恢复上次位置（coordinator 单测覆盖；真实 Finder/Dock 点击建议发布前抽查）
- [x] 自动化验证：有 pending external open 时不触发恢复
- [x] 自动化验证：启动后延迟到达的显式 open 会压过 restore，不会先恢复旧 A 再打开 B
- [x] 自动化验证：显式 URL 启动不再先创建默认 nil 窗口再关闭

> 命令级回归说明：`open -a <本地 debug app> <file>` 在 ad-hoc debug bundle 下存在 LaunchServices 注册/进程生命周期不稳定；当前仅将其作为辅助信号。最终验收仍以 Finder 双击、打开方式、拖 App 图标、Services 的真实手工回归为准。

---

## 8. 需求条目

| 编号 | 需求 | 优先级 | 状态 | 说明 |
|------|------|--------|------|------|
| FO-07 | 外部显式打开统一多窗口 | P1 | ✅ | 主路径已接入；脚本验证不同 URL 增窗、同 URL 不增窗 |
| FO-08 | App 内打开复用当前窗口 | P1 | ✅ | Cmd+O、打开最近、欢迎页最近文件替换当前 key window；无窗口退化为外部路径 |
| FO-09 | Services 支持文件和文件夹 | P1 | ✅ | Info.plist + `NSPerformService` 脚本验证文件/文件夹 |
| FO-10 | 恢复会话不覆盖显式打开 | P0 | ✅ | pending/external URL 存在时禁止 restoreLastLocation 覆盖；脚本覆盖延迟显式 open 压过 restore |
| FO-11 | 打开请求路由可测试 | P1 | ✅ | coordinator 决策通过单元测试覆盖，减少 Finder 手测依赖 |

---

## 9. 测试策略

项目已有 `MarkMarkTests` 测试 target。本改造的自动化重点是 coordinator / router / pasteboard 等 seam；AppKit、Finder、Dock 和 Services 的真实系统行为仍需要发布前手工抽查。

### 9.1 推荐测试 seam

最高优先级 seam：`OpenRequestCoordinator`，其次是 Services pasteboard 解析和 `WindowRouter` 的 internal/external 分发。

测试不应关心内部是否使用 UserDefaults、NotificationCenter 或 DispatchQueue；只验证输入请求最终产生的 disposition。

### 9.2 测试用例

| 场景 | 输入 | 期望 |
|------|------|------|
| 外部打开文件 | file URL + external reason | `openExternalURL` |
| 外部打开目录 | directory URL + external reason | `openExternalURL` |
| 内部打开最近 | URL + internal reason | `replaceActiveWindow` |
| 无 URL 直接启动，开启恢复 | launch completed + reopen enabled | `restoreLastLocation` |
| 无 URL 直接启动，关闭恢复 | launch completed + reopen disabled | `resetToWelcome` |
| pending external 存在 | launch completed + pending URL | 不发送 restore |
| Services 文件 | pasteboard file URL | external open |
| Services 文件夹 | pasteboard folder URL | external open |
| unsupported URL | unsupported target | 不更新 last opened，不崩溃 |

### 9.3 手工回归

Finder/LaunchServices 行为仍需手工验证，因为 SwiftUI `WindowGroup`、macOS Services、隐藏窗口激活属于系统集成行为。

建议沿用 `docs/double-click-open-investigation.md` 中的场景表，并扩展 Services 与多窗口场景。

---

## 10. 风险与应对

| 风险 | 影响 | 应对 |
|------|------|------|
| SwiftUI `WindowGroup` 冷启动时序不稳定 | 显式打开可能被初始窗口吞掉或延迟 | 保留 pending + watchdog，但收敛到 coordinator |
| Services 冷启动不自动创建窗口 | Finder Services 请求可能无接收者 | coordinator 等待 WindowRouter 注册，必要时 fallback |
| 多窗口通知误广播 | 内部打开影响多个窗口 | 继续使用 key-window 限定的 active receive |
| Services 支持文件后入口变宽 | 可能接收到 unsupported 文件 | coordinator 做预览能力过滤或安全错误提示 |
| 抽模块引入行为回归 | 旧路径依赖隐含时序 | 先补决策测试，再分阶段迁移 |

---

## 11. 非目标范围

- 不实现真正多进程多实例。
- 不重做非 Markdown 文件预览能力。
- 不改变当前 `SettingsModel.shared` 的全局设置模型。
- 不改造 WKWebView 渲染层。
- 不引入文件锁、协同编辑或跨进程状态同步。
- 不改变 Quick Look 扩展行为。

---

## 12. 验收标准

1. 外部显式打开入口语义一致：不同 URL 新窗口，同 URL 聚焦。
2. App 内打开入口语义一致：当前窗口替换。
3. 直接启动 App 时，只有没有显式 URL 才恢复上次位置。
4. Finder Services 支持文件和文件夹。
5. 冷启动/热启动/无窗口场景均不丢失显式打开请求。
6. coordinator 决策有自动化测试覆盖。
7. `AppDelegate` 中不再直接承载打开请求状态机。

---

## 13. 与既有文档的关系

- `docs/double-click-open-investigation.md`：记录历史问题和已验证的 SwiftUI WindowGroup 冷启动事实，本方案继承其中的 pending/watchdog 经验。
- `docs/requirements.md`：本方案补充 FO-07 ~ FO-11，作为文件打开能力的后续需求。
- `docs/architecture.md`：实施后应同步更新 App 层、WindowRouter、OpenRequestCoordinator 的模块关系。
