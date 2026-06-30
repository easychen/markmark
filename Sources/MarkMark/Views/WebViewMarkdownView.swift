import SwiftUI
import MarkdownReaderKit
import WebKit

/// 暴露底层 WKWebView 的句柄，供 PDF 导出等场景复用当前已渲染的页面。
final class WebViewHandle {
    weak var webView: WKWebView?
}

/// WKWebView 预热：App 启动时创建隐藏 WebView 提前拉起 Web 内容进程与 JS 引擎，
/// 并共享 WKProcessPool，使首次打开文件时跳过冷启动（替代旧 WebPage 预热）。
@MainActor
enum WebViewWarmer {
    private static var warmWebView: WKWebView?

    static func warmUp() {
        guard warmWebView == nil else { return }
        let configuration = WKWebViewConfiguration()
        let handler = MarkdownURLSchemeHandler(baseURL: nil)
        configuration.setURLSchemeHandler(handler, forURLScheme: "mr")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let html = """
        <!DOCTYPE html><html><head>
        <link rel="stylesheet" href="mr:///css/markdown.css">
        <link rel="stylesheet" href="mr:///css/katex.min.css">
        <script src="mr:///js/mermaid.min.js"></script>
        <script src="mr:///js/katex.min.js"></script>
        <script src="mr:///js/prism-core.min.js"></script>
        <script src="mr:///js/prism-autoloader.min.js"></script>
        <script>Prism.plugins.autoloader.languages_path = 'mr:///js/';</script>
        <script src="mr:///js/markdown-reader.js"></script>
        </head><body><div class="markdown-preview"><div id="mr-content"></div></div></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "about:blank")!)
        warmWebView = webView
    }
}

/// 渲染视图中用户发起的 CriticMarkup 标注动作。
/// 由 markdown-reader.js 选词工具条通过 `criticAction` message handler 投递。
struct CriticActionPayload {
    let op: String          // "delete" | "highlight" | "comment" | "replace" | "insert"
    let text: String        // 选中的纯文本
    let line: Int           // 选区所在块的 data-line（用于在源码中定位）
    let payload: String?    // 评论内容 / 替换后的新文本
}

/// macOS 15 兼容的 Markdown 渲染视图：以 NSViewRepresentable 封装 WKWebView。
///
/// v2.x 早期使用 SwiftUI 的 `WebView`/`WebPage`（仅 macOS 26+）。本实现迁移回经典
/// `WKWebView`，通过 `evaluateJavaScript` 调用 MR.* 接口，并用 `WKScriptMessageHandler`
/// 接收滚动同步与 CriticMarkup 标注消息。
struct WebViewMarkdownView: NSViewRepresentable {
    let content: String
    let fileURL: URL?
    var contentPadding: CGFloat = 20
    var maxContentWidthFollowsWindow: Bool = false
    var scrollToLine: Int?
    let themeCSS: String
    var isDark: Bool = true
    var searchQuery: String = ""
    var searchCaseSensitive: Bool = false
    var searchWholeWord: Bool = false
    var searchCurrentIndex: Int = -1
    var isFindBarVisible: Bool = false
    var onVisibleHeadingChanged: ((MarkdownHTMLService.HeadingInfo?) -> Void)?
    var onVisibleLineChanged: ((Int) -> Void)?
    /// 返回是否成功定位并写入；失败时渲染层会闪一个「无法定位选区」提示。
    var onCriticAction: ((CriticActionPayload) -> Bool)?
    /// 用户点击 Markdown 中的相对本地链接时，渲染层将 `mr:///...` 还原为本地文件 URL 后上报。
    var onLocalLinkActivated: ((URL) -> Void)?
    /// CriticMarkup 选词工具条的本地化文案（键：delete/highlight/comment/replace/confirm/cancel/edit/commentHint/replaceHint/notFound）
    var criticLabels: [String: String] = [:]

    /// 由父视图持有，使 PDF 导出可拿到当前 WKWebView。
    let handle: WebViewHandle

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator

        let configuration = WKWebViewConfiguration()
        let handler = MarkdownURLSchemeHandler(baseURL: fileURL?.deletingLastPathComponent())
        configuration.setURLSchemeHandler(handler, forURLScheme: "mr")

        let contentController = configuration.userContentController
        let proxy = WeakScriptMessageHandler(target: coordinator)
        contentController.add(proxy, name: "scrollSync")
        contentController.add(proxy, name: "criticAction")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.allowsMagnification = true
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        // 透明背景，渲染前透出底层主题色（等价于旧 .webViewContentBackground(.hidden)）
        webView.setValue(false, forKey: "drawsBackground")

        handle.webView = webView
        coordinator.webView = webView
        coordinator.loadFullHTML()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.handle.webView = webView
        coordinator.syncFromParent()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.scrollSyncTimer?.invalidate()
        let ucc = webView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: "scrollSync")
        ucc.removeScriptMessageHandler(forName: "criticAction")
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebViewMarkdownView
        weak var webView: WKWebView?
        var handle: WebViewHandle { parent.handle }

        private var isLoaded = false
        private var lastLoadedContent = ""
        private var lastLoadedURL: URL?
        private var lastThemeCSS = ""
        private var lastPadding: CGFloat = -1
        private var lastMaxWidth = false
        private var lastScrollToLine: Int?
        private var pendingScrollToLine: Int?
        private var lastSearchSignature = ""
        var scrollSyncTimer: Timer?

        init(parent: WebViewMarkdownView) {
            self.parent = parent
        }

        // MARK: Loading

        func loadFullHTML() {
            guard let webView else { return }
            let baseURL = parent.fileURL?.deletingLastPathComponent()
            let html = MarkdownHTMLService.buildFullHTML(
                content: parent.content,
                themeCSS: parent.themeCSS,
                contentPadding: parent.contentPadding,
                maxContentWidthFollowsWindow: parent.maxContentWidthFollowsWindow,
                baseURL: baseURL,
                isDark: parent.isDark
            )
            isLoaded = false
            pendingScrollToLine = parent.scrollToLine
            let effectiveBaseURL = baseURL ?? URL(string: "about:blank")!
            webView.loadHTMLString(html, baseURL: effectiveBaseURL)

            lastLoadedContent = parent.content
            lastLoadedURL = parent.fileURL
            lastThemeCSS = parent.themeCSS
            lastPadding = parent.contentPadding
            lastMaxWidth = parent.maxContentWidthFollowsWindow
            lastScrollToLine = parent.scrollToLine
            lastSearchSignature = searchSignature()
        }

        /// 在 updateNSView 中按需将父视图的最新状态同步到页面。
        func syncFromParent() {
            guard webView != nil else { return }

            // 文件切换：整页重载
            if parent.fileURL != lastLoadedURL {
                loadFullHTML()
                return
            }

            // 内容变化：局部替换（保留滚动与性能）
            if parent.content != lastLoadedContent {
                lastLoadedContent = parent.content
                replaceContent(parent.content)
            }

            if parent.themeCSS != lastThemeCSS {
                lastThemeCSS = parent.themeCSS
                updateThemeCSS(parent.themeCSS)
            }

            if parent.contentPadding != lastPadding {
                lastPadding = parent.contentPadding
                eval("document.documentElement.style.setProperty('--content-padding', '\(parent.contentPadding)px')")
            }

            if parent.maxContentWidthFollowsWindow != lastMaxWidth {
                lastMaxWidth = parent.maxContentWidthFollowsWindow
                let value = parent.maxContentWidthFollowsWindow ? "none" : "980px"
                eval("document.documentElement.style.setProperty('--content-max-width', '\(value)')")
            }

            if parent.scrollToLine != lastScrollToLine {
                lastScrollToLine = parent.scrollToLine
                if let line = parent.scrollToLine {
                    if isLoaded {
                        scrollToLineNumber(line)
                    } else {
                        pendingScrollToLine = line
                    }
                }
            }

            let sig = searchSignature()
            if sig != lastSearchSignature {
                lastSearchSignature = sig
                updateSearchHighlight()
            }
        }

        private func searchSignature() -> String {
            "\(parent.isFindBarVisible)|\(parent.searchQuery)|\(parent.searchCaseSensitive)|\(parent.searchWholeWord)|\(parent.searchCurrentIndex)"
        }

        // MARK: JS helpers

        private func eval(_ js: String) {
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        private func replaceContent(_ content: String) {
            let baseURL = parent.fileURL?.deletingLastPathComponent()
            let renderResult = MarkdownHTMLService.render(content, baseURL: baseURL)
            let escaped = Self.escapeForJSString(renderResult.html)
            eval("MR.replaceContent('\(escaped)')")
        }

        private func updateThemeCSS(_ themeCSS: String) {
            let escaped = Self.escapeForJSString(themeCSS)
            eval("document.getElementById('mr-theme-style').textContent = '\(escaped)'; MR.rerenderMermaid && MR.rerenderMermaid(); MR.rerenderPlantUML && MR.rerenderPlantUML();")
        }

        private func scrollToLineNumber(_ line: Int) {
            eval("MR.scrollToLine(\(line))")
        }

        private func pushCriticLabels() {
            guard !parent.criticLabels.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: parent.criticLabels),
                  let json = String(data: data, encoding: .utf8) else { return }
            eval("MR.setCriticLabels && MR.setCriticLabels(\(json))")
        }

        private func updateSearchHighlight() {
            guard parent.isFindBarVisible else {
                eval("MR.clearSearchHighlight && MR.clearSearchHighlight()")
                return
            }
            let escapedQuery = parent.searchQuery
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            eval("MR.highlightSearch('\(escapedQuery)', \(parent.searchCaseSensitive), \(parent.searchWholeWord), \(parent.searchCurrentIndex))")
        }

        static func escapeForJSString(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "'", with: "\\'")
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            pushCriticLabels()
            if let line = pendingScrollToLine {
                pendingScrollToLine = nil
                // 给 JS 渲染（KaTeX/Mermaid/Prism）留出布局时间
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.scrollToLineNumber(line)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let isMainFrameLinkClick = navigationAction.navigationType == .linkActivated
                && (navigationAction.targetFrame?.isMainFrame ?? true)

            if url.scheme == "mr" {
                if isMainFrameLinkClick,
                   let targetURL = MarkdownLinkNavigationPolicy.internalTargetURL(from: url) {
                    parent.onLocalLinkActivated?(targetURL)
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }

            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }

            if isSameDocumentAnchor(url) {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "file" {
                if isMainFrameLinkClick {
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        private func isSameDocumentAnchor(_ url: URL) -> Bool {
            guard url.fragment != nil else { return false }

            if url.scheme == "about" {
                return true
            }

            guard url.scheme == "file",
                  let baseURL = parent.fileURL?.deletingLastPathComponent() else {
                return false
            }

            return URL(fileURLWithPath: url.path).markMarkCanonicalFileURL == baseURL.markMarkCanonicalFileURL
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "scrollSync":
                handleScrollSync(message.body)
            case "criticAction":
                handleCriticAction(message.body)
            default:
                break
            }
        }

        private func handleScrollSync(_ body: Any) {
            guard let dict = body as? [String: Any] else { return }
            if let line = dict["line"] as? Int {
                parent.onVisibleLineChanged?(line)
            }
            if let heading = dict["heading"] as? [String: Any],
               let id = heading["id"] as? String,
               let level = heading["level"] as? Int,
               let title = heading["title"] as? String,
               let lineNumber = heading["lineNumber"] as? Int {
                parent.onVisibleHeadingChanged?(
                    MarkdownHTMLService.HeadingInfo(id: id, level: level, title: title, lineNumber: lineNumber)
                )
            } else {
                parent.onVisibleHeadingChanged?(nil)
            }
        }

        private func handleCriticAction(_ body: Any) {
            guard let dict = body as? [String: Any],
                  let op = dict["op"] as? String,
                  let text = dict["text"] as? String else { return }
            let line = (dict["line"] as? Int) ?? 0
            let extra = dict["payload"] as? String
            let ok = parent.onCriticAction?(CriticActionPayload(op: op, text: text, line: line, payload: extra)) ?? true
            if !ok {
                // 容错匹配仍定位失败：渲染层闪一个提示，避免「静默无反应」
                eval("MR.flashCriticError && MR.flashCriticError()")
            }
        }
    }
}

/// 弱引用代理，避免 WKUserContentController 强持有 Coordinator 造成循环引用。
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(target: any WKScriptMessageHandler) {
        self.target = target
        super.init()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
