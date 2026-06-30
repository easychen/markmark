import SwiftUI
import MarkdownReaderKit

/// Compact icon-only titlebar button with a hover background.
///
/// macOS plain buttons are visually too silent in MarkMark's custom titlebar.
/// This component keeps the existing flat look, but adds hover/pressed/disabled
/// feedback for the small controls near the traffic lights.
struct TitleBarIconButton: View {
    let systemName: String
    let helpText: String
    var isEnabled: Bool = true
    var foregroundColor: Color?
    var action: () -> Void

    @Environment(\.themeColors) private var themeColors
    @State private var isHovering = false

    private var iconColor: Color {
        guard isEnabled else { return themeColors.fgMuted.opacity(0.45) }
        if let foregroundColor { return foregroundColor }
        return isHovering ? themeColors.ink : themeColors.fgSecondary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(background)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
        .overlay(alignment: .bottom) {
            if isHovering && !helpText.isEmpty {
                tooltip
                    .offset(y: 30)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .zIndex(isHovering ? 1000 : 0)
        .animation(.easeOut(duration: 0.08), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var background: some View {
        if isEnabled && isHovering {
            RoundedRectangle(cornerRadius: 6)
                .fill(themeColors.bgMuted)
        }
    }

    private var tooltip: some View {
        let parts = parsedHelpText

        return HStack(spacing: 8) {
            Text(parts.title)
                .font(.system(size: 11))
                .foregroundStyle(themeColors.ink)

            if !parts.shortcutCombinations.isEmpty {
                shortcutCombinations(parts.shortcutCombinations)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(themeColors.bgElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(themeColors.border, lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
    }

    private var parsedHelpText: TooltipHelpText {
        TooltipHelpText.parse(helpText)
    }

    private func shortcutCombinations(_ combinations: [[String]]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(combinations.enumerated()), id: \.offset) { index, keys in
                if index > 0 {
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundStyle(themeColors.fgMuted)
                }

                Text(keys.joined())
                    .font(.system(size: 11))
                    .foregroundStyle(themeColors.fgMuted)
            }
        }
    }
}

struct TitleBarIconMenu<MenuContent: View>: View {
    let systemName: String
    let helpText: String
    var foregroundColor: Color?
    var content: () -> MenuContent

    @Environment(\.themeColors) private var themeColors
    @State private var isHovering = false

    init(
        systemName: String,
        helpText: String,
        foregroundColor: Color? = nil,
        @ViewBuilder content: @escaping () -> MenuContent
    ) {
        self.systemName = systemName
        self.helpText = helpText
        self.foregroundColor = foregroundColor
        self.content = content
    }

    private var iconColor: Color {
        if let foregroundColor { return foregroundColor }
        return isHovering ? themeColors.ink : themeColors.fgSecondary
    }

    private var accessibilityTitle: String {
        TooltipHelpText.parse(helpText).title
    }

    var body: some View {
        Menu(content: content) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 3)
        .frame(height: 24)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(background)
        .accessibilityLabel(accessibilityTitle)
        .zIndex(isHovering ? 1000 : 0)
        .animation(.easeOut(duration: 0.08), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var background: some View {
        if isHovering {
            RoundedRectangle(cornerRadius: 6)
                .fill(themeColors.bgMuted)
        }
    }
}

private struct TooltipHelpText {
    let title: String
    let shortcutCombinations: [[String]]

    static func parse(_ rawValue: String) -> TooltipHelpText {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = ""
        var combinations: [[String]] = []
        var index = trimmed.startIndex

        while index < trimmed.endIndex {
            let character = trimmed[index]
            let closingParenthesis: Character?

            switch character {
            case "(":
                closingParenthesis = ")"
            case "（":
                closingParenthesis = "）"
            default:
                closingParenthesis = nil
            }

            guard let closingParenthesis else {
                title.append(character)
                index = trimmed.index(after: index)
                continue
            }

            let contentStart = trimmed.index(after: index)
            guard let contentEnd = trimmed[contentStart...].firstIndex(of: closingParenthesis) else {
                title.append(character)
                index = contentStart
                continue
            }

            let parenthesizedContent = String(trimmed[contentStart..<contentEnd])
            if let shortcut = parseShortcutCombination(from: parenthesizedContent) {
                combinations.append(shortcut)
            } else {
                title += String(trimmed[index...contentEnd])
            }

            index = trimmed.index(after: contentEnd)
        }

        let normalizedTitle = normalizeTitle(title)

        guard !normalizedTitle.isEmpty else {
            return TooltipHelpText(title: trimmed, shortcutCombinations: [])
        }

        return TooltipHelpText(title: normalizedTitle, shortcutCombinations: combinations)
    }

    private static func normalizeTitle(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseShortcutCombination(from value: String) -> [String]? {
        var currentRun: [String] = []
        var runs: [[String]] = []

        for character in value {
            if isShortcutCharacter(character) {
                currentRun.append(String(character))
            } else {
                if !currentRun.isEmpty {
                    runs.append(currentRun)
                    currentRun.removeAll()
                }
            }
        }

        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        return runs
            .filter { $0.contains(where: isModifierKey) }
            .max { $0.count < $1.count }
    }

    private static func isShortcutCharacter(_ character: Character) -> Bool {
        if isModifierKey(String(character)) {
            return true
        }
        if character.isLetter || character.isNumber {
            return true
        }

        return "\\[]{}.,;'-=`~+/".contains(character)
    }

    private static func isModifierKey(_ value: String) -> Bool {
        ["⌘", "⇧", "⌥", "⌃"].contains(value)
    }
}
