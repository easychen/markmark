import SwiftUI

/// 窗口拖动区域 — 将整个区域标记为可拖动窗口的标题栏
/// 配合 .windowStyle(.hiddenTitleBar) 使用，扩展系统默认的窄拖动区域
/// 到自定义 titlebar 的完整高度（与下方横线对齐）
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        let view = WindowDragNSView()
        return view
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

/// 支持窗口拖动的 NSView
/// mouseDown 时调用 NSWindow.performDrag(with:) 启动窗口拖动
final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }

        if event.clickCount == 2 {
            if !window.styleMask.contains(.fullScreen) {
                window.zoom(nil)
            }
            return
        }

        window.performDrag(with: event)
    }
}
