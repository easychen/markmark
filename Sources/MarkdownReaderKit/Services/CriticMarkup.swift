import Foundation

/// CriticMarkup 支持：在 Markdown 源码中表达审阅意见（增/删/改/评论/高亮），
/// 既能在渲染视图中样式化显示，也能一键复制给 AI 进行修订。
///
/// 语法参考 <http://criticmarkup.com>：
/// - 增加 Addition:     `{++ ... ++}`
/// - 删除 Deletion:     `{-- ... --}`
/// - 替换 Substitution: `{~~ old ~> new ~~}`
/// - 评论 Comment:      `{>> ... <<}`
/// - 高亮 Highlight:    `{== ... ==}`
public enum CriticMarkup {

    /// 一次标注动作。
    public enum Operation: Equatable {
        case delete
        case highlight
        case comment(String)   // 高亮选区并附加评论
        case replace(String)   // 用新文本替换选区
        case insert(String)    // 在选区之后插入新文本
    }

    // MARK: - 定位

    /// 在 `source` 中定位 `selectedText`，在多处出现时选取最接近 `nearLine`（1 基）的一处。
    /// 找不到或选区为空返回 nil。
    ///
    /// 两级策略（应对「渲染视图选区文本 ≠ 源码」的问题）：
    /// 1. **精确匹配**：渲染层已关闭智能排版（`.disableSmartOpts`），多数纯文本/单一行内格式
    ///    （如 `**粗**` 的内容是源码子串）能直接命中。
    /// 2. **容错匹配**：选区跨越行内标记（`a**b**c` 选 "bc"）或软换行时，渲染纯文本不再是
    ///    源码子串。此时把选区逐字符之间允许夹杂少量 Markdown 噪声（`* _ ~ \` \ ` 及空白）后再匹配。
    ///    边界可能多包/少包一两个标记符，但能定位到位（参考 Hypothesis 的「精确失败→容错」策略）。
    public static func locateRange(in source: String, selectedText: String, nearLine: Int) -> Range<String.Index>? {
        guard !selectedText.isEmpty else { return nil }

        // 第一级：精确
        if let r = nearestRange(among: exactRanges(of: selectedText, in: source), in: source, nearLine: nearLine) {
            return r
        }
        // 第二级：标记/空白容错
        return nearestRange(among: tolerantRanges(of: selectedText, in: source), in: source, nearLine: nearLine)
    }

    /// 在 `source` 中查找 `needle` 的所有（非重叠）精确出现。
    private static func exactRanges(of needle: String, in source: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = source.startIndex
        while searchStart < source.endIndex,
              let r = source.range(of: needle, range: searchStart..<source.endIndex) {
            ranges.append(r)
            searchStart = r.upperBound > r.lowerBound ? r.upperBound : source.index(after: r.lowerBound)
        }
        return ranges
    }

    /// 容错查找：把选区中的非空白字符依次匹配，字符之间允许夹杂 ≤8 个 Markdown 噪声/空白字符
    /// （含 CriticMarkup 定界符 `={}<>+-^`，使跨已有标注边界的选区也能定位）。
    private static func tolerantRanges(of selectedText: String, in source: String) -> [Range<String.Index>] {
        let tokens = selectedText.filter { !$0.isWhitespace }
        // 太短不做容错（避免在长文里乱命中）；太长跳过（避免正则开销过大）
        guard tokens.count >= 2, tokens.count <= 200 else { return [] }
        let separator = "[\\s*_~`\\\\={}<>+^-]{0,8}"
        let pattern = tokens.map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: separator)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { Range($0.range, in: source) }
    }

    /// 在候选区间里选取起点行号最接近 `nearLine` 的一处。
    private static func nearestRange(among ranges: [Range<String.Index>], in source: String, nearLine: Int) -> Range<String.Index>? {
        guard !ranges.isEmpty else { return nil }
        var best = ranges[0]
        var bestDistance = Int.max
        for r in ranges {
            let line = source[source.startIndex..<r.lowerBound].reduce(into: 1) { acc, ch in
                if ch == "\n" { acc += 1 }
            }
            let distance = abs(line - nearLine)
            if distance < bestDistance {
                bestDistance = distance
                best = r
            }
        }
        return best
    }

    // MARK: - 选区边界修正（格式安全）

    /// 行内格式 span 模式（优先级从高到低，先命中者占位）。
    /// `allowsNewline`：span 内容允许含换行（仅已有 CriticMarkup 标注——它们是不可分割的整体）。
    private static let inlineSpanPatterns: [(pattern: String, allowsNewline: Bool)] = [
        (#"\{~~[\s\S]*?~>[\s\S]*?~~\}"#, true),                    // 已有标注：替换
        (#"\{\+\+[\s\S]*?\+\+\}"#, true),                          // 已有标注：新增
        (#"\{--[\s\S]*?--\}"#, true),                              // 已有标注：删除
        (#"\{==[\s\S]*?==\}(?:\{>>[\s\S]*?<<\})?"#, true),         // 已有标注：高亮（含紧邻评论）
        (#"\{>>[\s\S]*?<<\}"#, true),                              // 已有标注：评论
        ("(?<!`)(`+)(?!`)(.+?)(?<!`)\\1(?!`)", false),             // 行内代码
        (#"\*\*(?!\s).+?(?<!\s)\*\*"#, false),                     // 粗体 **
        (#"__(?!\s).+?(?<!\s)__"#, false),                         // 粗体 __
        (#"~~(?!\s).+?(?<!\s)~~"#, false),                         // 删除线
        (#"==(?!\s).+?(?<!\s)=="#, false),                         // 高亮 ==
        (#"!?\[[^\[\]\n]*\]\([^()\n]*\)"#, false),                 // 链接 / 图片
        (#"(?<![\w*])\*(?![\s*])[^*\n]+?(?<![\s\\])\*(?!\*)"#, false),  // 斜体 *
        (#"(?<![\w_])_(?![\s_])[^_\n]+?(?<!\s)_(?![\w_])"#, false),     // 斜体 _
        (#"(?<!\^)\^(?![\s^])[^\^\n]+?\^"#, false),                // 上标
        (#"(?<!~)~(?![\s~])[^~\n]+?~(?!~)"#, false),               // 下标
    ]

    /// 把定位到的选区修正为「行内格式安全」的范围：与选区边界部分重叠的行内格式 span
    /// （行内代码、粗/斜体、删除线、高亮、链接、上下标、已有标注）整体并入选区。
    /// 否则 `{==` 等标记会插进 `**…**` 之类配对符号中间，撕裂行内格式导致整页渲染错乱
    /// （容错定位的边界就可能落在标记符内部）。含 `|` 的 span 一律不并入——表格单元格
    /// 边界不可跨越。
    static func formatSafeRange(_ range: Range<String.Index>, in source: String) -> Range<String.Index> {
        guard !range.isEmpty else { return range }

        // 扫描区域：选区首行行首 → 末行行尾
        var scanStart = source.startIndex
        if let nl = source[..<range.lowerBound].lastIndex(of: "\n") {
            scanStart = source.index(after: nl)
        }
        var scanEnd = source.endIndex
        if let nl = source[range.upperBound...].firstIndex(of: "\n") {
            scanEnd = nl
        }

        // 收集 span：按优先级，跳过与已收集重叠者。
        // `swallowsContained`：行内代码即使完全包住选区也要整体并入——标记落在反引号
        // 内部会被代码保护原样展示（`{==` 变成字面文本），标注完全失效。
        // 其他 span（粗斜体 / 已有标注等）完全包住选区时无需处理，内部插标记是安全的。
        var spans: [(range: Range<String.Index>, swallowsContained: Bool)] = []
        let nsRegion = NSRange(scanStart..<scanEnd, in: source)
        for entry in inlineSpanPatterns {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern) else { continue }
            let isInlineCode = entry.pattern.hasPrefix("(?<!`)")
            for m in regex.matches(in: source, options: [.withTransparentBounds], range: nsRegion) {
                guard let r = Range(m.range, in: source) else { continue }
                let text = source[r]
                if text.contains("|") { continue }
                if !entry.allowsNewline && text.contains("\n") { continue }
                if spans.contains(where: { $0.range.overlaps(r) }) { continue }
                spans.append((r, isInlineCode))
            }
        }

        // 迭代扩张，直到没有 span 被选区边界撕裂
        var result = range
        var changed = true
        while changed {
            changed = false
            for span in spans {
                let r = span.range
                guard r.overlaps(result), r != result else { continue }
                let spanInsideSelection = r.lowerBound >= result.lowerBound && r.upperBound <= result.upperBound
                let selectionInsideSpan = result.lowerBound >= r.lowerBound && result.upperBound <= r.upperBound
                let torn = !spanInsideSelection && !selectionInsideSpan
                if torn || (selectionInsideSpan && span.swallowsContained) {
                    result = min(r.lowerBound, result.lowerBound)..<max(r.upperBound, result.upperBound)
                    changed = true
                }
            }
        }
        return result
    }

    // MARK: - 应用标注

    /// 实际写入的一条标注（字段与 `parseAnnotations` 的解析结果对齐，供会话记录配对）。
    public struct AppliedAnnotation: Equatable, Sendable {
        public let kind: Annotation.Kind
        public let text: String
        public let payload: String?

        public init(kind: Annotation.Kind, text: String, payload: String?) {
            self.kind = kind
            self.text = text
            self.payload = payload
        }
    }

    /// `applyDetailed` 的结果：更新后的源码 + 实际写入的标注列表（按文档中出现顺序）。
    /// 边界修正 / 跨块分段后，实际包裹的文本可能与原选区不同，调用方应以此为准记录会话标注。
    public struct ApplyResult {
        public let source: String
        public let annotations: [AppliedAnnotation]
    }

    /// 在源码中定位选区并写入对应 CriticMarkup。找不到选区时返回 nil。
    public static func apply(_ op: Operation, to source: String, selectedText: String, nearLine: Int) -> String? {
        applyDetailed(op, to: source, selectedText: selectedText, nearLine: nearLine)?.source
    }

    /// 同 `apply`，并返回实际写入的标注明细。
    ///
    /// 两条路径：
    /// 1. **整段定位**（绝大多数选区）：定位后经 `formatSafeRange` 修正边界再包裹；
    ///    若命中范围跨越空行（跨段落），改走分段路径避免标记跨块撕裂渲染。
    /// 2. **分段定位**（跨表格单元格 / 跨段落、列表项）：渲染视图的 `selection.toString()`
    ///    在块边界产生 `\t` / `\n`，按其拆成片段逐一定位、分别包裹；
    ///    评论 / 替换 / 插入的语义落在最后一个片段上，任一片段定位失败则整体失败。
    public static func applyDetailed(_ op: Operation, to source: String, selectedText: String, nearLine: Int) -> ApplyResult? {
        if let raw = locateRange(in: source, selectedText: selectedText, nearLine: nearLine) {
            let range = formatSafeRange(raw, in: source)
            if !containsBlankLine(source[range]) {
                return wrapSingle(op, source: source, range: range)
            }
            // 整段命中但跨段落：优先分段；分段失败退回整段（浏览器对跨段标记多数能恢复）
            return applyFragments(op, to: source, selectedText: selectedText, nearLine: nearLine)
                ?? wrapSingle(op, source: source, range: range)
        }
        return applyFragments(op, to: source, selectedText: selectedText, nearLine: nearLine)
    }

    private static func containsBlankLine(_ text: Substring) -> Bool {
        text.range(of: #"\n[ \t]*\n"#, options: .regularExpression) != nil
    }

    /// 单一范围包裹（整段路径）。
    private static func wrapSingle(_ op: Operation, source: String, range: Range<String.Index>) -> ApplyResult {
        let selected = String(source[range])
        var result = source
        result.replaceSubrange(range, with: replacement(for: op, selected: selected))
        let annotations: [AppliedAnnotation]
        switch op {
        case .delete:           annotations = [AppliedAnnotation(kind: .deletion, text: selected, payload: nil)]
        case .highlight:        annotations = [AppliedAnnotation(kind: .highlight, text: selected, payload: nil)]
        case .comment(let c):   annotations = [AppliedAnnotation(kind: .comment, text: selected, payload: collapseBlankLines(c))]
        case .replace(let new): annotations = [AppliedAnnotation(kind: .substitution, text: selected, payload: new)]
        case .insert(let new):  annotations = [AppliedAnnotation(kind: .addition, text: new, payload: nil)]
        }
        return ApplyResult(source: result, annotations: annotations)
    }

    /// 分段路径：按 `\t` / 换行把选区拆成片段，顺序定位（每段从上一段之后搜起）并分别包裹。
    private static func applyFragments(_ op: Operation, to source: String, selectedText: String, nearLine: Int) -> ApplyResult? {
        let fragments = selectedText
            .split(whereSeparator: { $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !fragments.isEmpty else { return nil }

        // 顺序定位：首段按 nearLine 选最近，后续各段必须出现在前一段之后
        var ranges: [Range<String.Index>] = []
        var searchFrom = source.startIndex
        for (i, fragment) in fragments.enumerated() {
            let located: Range<String.Index>? = (i == 0)
                ? locateRange(in: source, selectedText: fragment, nearLine: nearLine)
                : firstRange(of: fragment, in: source, from: searchFrom)
            guard let raw = located, raw.lowerBound >= searchFrom else { return nil }
            let r = formatSafeRange(raw, in: source)
            guard r.lowerBound >= searchFrom else { return nil }   // 修正后侵入上一段 → 放弃
            ranges.append(r)
            searchFrom = r.upperBound
        }

        // 从 source 原样拼接（避免边替换边失效的索引问题）
        var pieces: [String] = []
        var annotations: [AppliedAnnotation] = []
        var cursor = source.startIndex
        for (i, r) in ranges.enumerated() {
            pieces.append(String(source[cursor..<r.lowerBound]))
            let (wrapped, anns) = fragmentReplacement(op, fragment: String(source[r]), isLast: i == ranges.count - 1)
            pieces.append(wrapped)
            annotations.append(contentsOf: anns)
            cursor = r.upperBound
        }
        pieces.append(String(source[cursor...]))
        return ApplyResult(source: pieces.joined(), annotations: annotations)
    }

    /// 片段包裹规则：评论 / 替换 / 插入的核心语义落在最后一个片段；
    /// 其余片段按操作退化为高亮（评论）或删除（替换）。
    private static func fragmentReplacement(_ op: Operation, fragment: String, isLast: Bool) -> (String, [AppliedAnnotation]) {
        switch op {
        case .delete:
            return ("{--\(fragment)--}", [AppliedAnnotation(kind: .deletion, text: fragment, payload: nil)])
        case .highlight:
            return ("{==\(fragment)==}", [AppliedAnnotation(kind: .highlight, text: fragment, payload: nil)])
        case .comment(let c):
            guard isLast else {
                return ("{==\(fragment)==}", [AppliedAnnotation(kind: .highlight, text: fragment, payload: nil)])
            }
            let collapsed = collapseBlankLines(c)
            return ("{==\(fragment)==}{>>\(collapsed)<<}",
                    [AppliedAnnotation(kind: .comment, text: fragment, payload: collapsed)])
        case .replace(let new):
            guard isLast else {
                return ("{--\(fragment)--}", [AppliedAnnotation(kind: .deletion, text: fragment, payload: nil)])
            }
            return ("{~~\(fragment)~>\(new)~~}",
                    [AppliedAnnotation(kind: .substitution, text: fragment, payload: new)])
        case .insert(let new):
            guard isLast else { return (fragment, []) }
            return ("\(fragment){++\(new)++}", [AppliedAnnotation(kind: .addition, text: new, payload: nil)])
        }
    }

    /// `start` 之后（含）第一处出现：先精确、后容错。
    private static func firstRange(of needle: String, in source: String, from start: String.Index) -> Range<String.Index>? {
        if let r = source.range(of: needle, range: start..<source.endIndex) { return r }
        return tolerantRanges(of: needle, in: source).first(where: { $0.lowerBound >= start })
    }

    private static func replacement(for op: Operation, selected: String) -> String {
        switch op {
        case .delete:
            return "{--\(selected)--}"
        case .highlight:
            return "{==\(selected)==}"
        case .comment(let c):
            return "{==\(selected)==}{>>\(collapseBlankLines(c))<<}"
        case .replace(let new):
            return "{~~\(selected)~>\(new)~~}"
        case .insert(let new):
            return "\(selected){++\(new)++}"
        }
    }

    // MARK: - 编辑 / 删除评论

    /// 编辑已有评论：定位最接近 `nearLine` 的 `{>>oldComment<<}` 并替换其内容。
    public static func editComment(in source: String, oldComment: String, newComment: String, nearLine: Int) -> String? {
        let marker = "{>>\(oldComment)<<}"
        guard let range = locateRange(in: source, selectedText: marker, nearLine: nearLine) else { return nil }
        var result = source
        result.replaceSubrange(range, with: "{>>\(collapseBlankLines(newComment))<<}")
        return result
    }

    /// 折叠评论中的连续空行：连续 2+ 换行 → 单个换行，并去掉首尾空白（issue #6）。
    /// 连续空行会让 cmark 把行内的 `{>>...<<}` 拆到不同段落，破坏标注配对与渲染。
    /// 这是对 JS 端清洗的 Swift 兜底，确保任何调用路径都不会写入破坏性的评论。
    static func collapseBlankLines(_ s: String) -> String {
        let collapsed = s.replacingOccurrences(
            of: "[ \\t]*\\r?\\n(?:[ \\t]*\\r?\\n)+",
            with: "\n",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 删除已有评论：定位 `{>>comment<<}` 并移除；
    /// 若其紧邻前缀是配对的 `{==X==}` 高亮（评论创建时一并添加），则连同高亮还原为原文 `X`。
    public static func deleteComment(in source: String, comment: String, nearLine: Int) -> String? {
        let marker = "{>>\(comment)<<}"
        guard let range = locateRange(in: source, selectedText: marker, nearLine: nearLine) else { return nil }
        var result = source

        let before = result[result.startIndex..<range.lowerBound]
        if let hl = before.range(of: #"\{==[\s\S]*?==\}$"#, options: .regularExpression) {
            // {==X==}{>>comment<<} → X
            let highlight = String(result[hl])
            let inner = String(highlight.dropFirst(3).dropLast(3))   // 去掉 {== 与 ==}
            result.replaceSubrange(hl.lowerBound..<range.upperBound, with: inner)
        } else {
            result.replaceSubrange(range, with: "")
        }
        return result
    }

    // MARK: - 接受 / 拒绝 / 检测

    /// 接受全部修改：增→保留、删→移除、替换→新文本、高亮→保留内容、评论→移除。
    public static func accepting(_ text: String) -> String {
        var s = text
        s = regexReplace(s, #"\{~~([\s\S]*?)~>([\s\S]*?)~~\}"#, template: "$2")
        s = regexReplace(s, #"\{\+\+([\s\S]*?)\+\+\}"#, template: "$1")
        s = regexReplace(s, #"\{--([\s\S]*?)--\}"#, template: "")
        s = regexReplace(s, #"\{==([\s\S]*?)==\}"#, template: "$1")
        s = regexReplace(s, #"\{>>([\s\S]*?)<<\}"#, template: "")
        return s
    }

    /// 拒绝全部修改，恢复原文：增→移除、删→保留、替换→旧文本、高亮→保留内容、评论→移除。
    public static func rejecting(_ text: String) -> String {
        var s = text
        s = regexReplace(s, #"\{~~([\s\S]*?)~>([\s\S]*?)~~\}"#, template: "$1")
        s = regexReplace(s, #"\{\+\+([\s\S]*?)\+\+\}"#, template: "")
        s = regexReplace(s, #"\{--([\s\S]*?)--\}"#, template: "$1")
        s = regexReplace(s, #"\{==([\s\S]*?)==\}"#, template: "$1")
        s = regexReplace(s, #"\{>>([\s\S]*?)<<\}"#, template: "")
        return s
    }

    /// 文本中是否包含任何 CriticMarkup 标注。
    public static func hasMarkup(_ text: String) -> Bool {
        for pattern in [#"\{\+\+[\s\S]*?\+\+\}"#, #"\{--[\s\S]*?--\}"#,
                        #"\{~~[\s\S]*?~~\}"#, #"\{==[\s\S]*?==\}"#, #"\{>>[\s\S]*?<<\}"#] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - 标注解析

    /// 文档中一处已存在的 CriticMarkup 标注。
    /// `range` 基于解析时的源码，内容变化后即失效，需重新解析。
    public struct Annotation: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case addition       // {++ ++}
            case deletion       // {-- --}
            case substitution   // {~~ ~> ~~}
            case highlight      // {== ==}
            case comment        // {>> <<}（含「高亮+评论」合并形态）
        }
        public let kind: Kind
        /// 标注主体文本（高亮/删除/新增的内容、替换的旧文本、纯评论的评论内容）
        public let text: String
        /// 替换的新文本 / 高亮所附的评论内容
        public let payload: String?
        /// 标注起始处行号（1 基）
        public let line: Int
        /// 整个标记（含定界符）在源码中的范围
        public let range: Range<String.Index>

        public init(kind: Kind, text: String, payload: String?, line: Int, range: Range<String.Index>) {
            self.kind = kind
            self.text = text
            self.payload = payload
            self.line = line
            self.range = range
        }
    }

    /// 解析文档中的全部 CriticMarkup 标注，按出现顺序返回。
    /// 评论工作流产物 `{==X==}{>>C<<}`（紧邻）合并为一条 comment 标注（text=X, payload=C）。
    public static func parseAnnotations(in source: String) -> [Annotation] {
        struct RawMatch {
            let kind: Annotation.Kind
            let range: Range<String.Index>
            let text: String
            let payload: String?
        }
        let patterns: [(Annotation.Kind, String)] = [
            (.substitution, #"\{~~([\s\S]*?)~>([\s\S]*?)~~\}"#),
            (.addition, #"\{\+\+([\s\S]*?)\+\+\}"#),
            (.deletion, #"\{--([\s\S]*?)--\}"#),
            (.highlight, #"\{==([\s\S]*?)==\}"#),
            (.comment, #"\{>>([\s\S]*?)<<\}"#),
        ]
        let ns = source as NSString
        let full = NSRange(location: 0, length: ns.length)
        var raws: [RawMatch] = []
        for (kind, pattern) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in regex.matches(in: source, range: full) {
                guard let r = Range(m.range, in: source),
                      let g1 = Range(m.range(at: 1), in: source) else { continue }
                var payload: String?
                if kind == .substitution, m.numberOfRanges > 2,
                   let g2 = Range(m.range(at: 2), in: source) {
                    payload = String(source[g2])
                }
                raws.append(RawMatch(kind: kind, range: r, text: String(source[g1]), payload: payload))
            }
        }
        raws.sort { $0.range.lowerBound < $1.range.lowerBound }

        var result: [Annotation] = []
        var lastEnd = source.startIndex
        var i = 0
        while i < raws.count {
            let cur = raws[i]
            // 跳过与已接受标注重叠的匹配（如删除标记内部嵌着评论语法）
            if cur.range.lowerBound < lastEnd { i += 1; continue }
            // {==X==}{>>C<<} 合并为一条评论标注
            if cur.kind == .highlight, i + 1 < raws.count {
                let next = raws[i + 1]
                if next.kind == .comment, next.range.lowerBound == cur.range.upperBound {
                    let merged = cur.range.lowerBound..<next.range.upperBound
                    result.append(Annotation(
                        kind: .comment, text: cur.text, payload: next.text,
                        line: lineNumber(of: cur.range.lowerBound, in: source), range: merged
                    ))
                    lastEnd = merged.upperBound
                    i += 2
                    continue
                }
            }
            result.append(Annotation(
                kind: cur.kind, text: cur.text, payload: cur.payload,
                line: lineNumber(of: cur.range.lowerBound, in: source), range: cur.range
            ))
            lastEnd = cur.range.upperBound
            i += 1
        }
        return result
    }

    private static func lineNumber(of index: String.Index, in source: String) -> Int {
        source[source.startIndex..<index].reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
    }

    // MARK: - 片段提取

    /// 围绕标注提取的可读片段（用于「只复制改动部分」给 AI）。
    public struct Fragment: Equatable, Sendable {
        /// 标注位置之前最近的 ATX 标题行（如 "## 第三章"），无则 nil
        public let heading: String?
        /// 片段文本（含标注标记；截断处带省略号）
        public let text: String
        /// 片段在源码中的起始偏移（用于排序）
        public let position: Int
    }

    /// 提取标注所在片段：默认整段；段落超 `maxLength` 时以标注为中心逐句扩展；
    /// 核心句仍超限时按字符截断（标注本身始终完整保留）。同段多条标注合并为一个片段。
    public static func fragments(
        for annotations: [Annotation],
        in source: String,
        maxLength: Int = 400
    ) -> [Fragment] {
        var groups: [(paragraph: Range<String.Index>, anns: [Annotation])] = []
        for ann in annotations.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            let para = paragraphRange(around: ann.range, in: source)
            if let last = groups.last, last.paragraph == para {
                groups[groups.count - 1].anns.append(ann)
            } else {
                groups.append((para, [ann]))
            }
        }

        var result: [Fragment] = []
        for group in groups {
            let heading = nearestHeading(before: group.paragraph.lowerBound, in: source)
            let paragraph = source[group.paragraph]
            if paragraph.count <= maxLength {
                result.append(Fragment(
                    heading: heading,
                    text: String(paragraph).trimmingCharacters(in: .whitespacesAndNewlines),
                    position: source.distance(from: source.startIndex, to: group.paragraph.lowerBound)
                ))
            } else {
                // 段落超限：每条标注单独按句/字提取
                for ann in group.anns {
                    let text = clippedFragment(for: ann, paragraph: group.paragraph, in: source, maxLength: maxLength)
                    result.append(Fragment(
                        heading: heading,
                        text: text,
                        position: source.distance(from: source.startIndex, to: ann.range.lowerBound)
                    ))
                }
            }
        }
        return result
    }

    /// 拼接片段为最终导出文本：片段之间用 `[...]` 标示省略，标题线索仅在变化时输出。
    public static func exportFragments(_ fragments: [Fragment], intro: String? = nil) -> String {
        var blocks: [String] = []
        var lastHeading: String?
        for frag in fragments.sorted(by: { $0.position < $1.position }) {
            var block = ""
            if let h = frag.heading, h != lastHeading {
                block += h + "\n\n"
                lastHeading = h
            }
            block += frag.text
            blocks.append(block)
        }
        let body = blocks.joined(separator: "\n\n[...]\n\n")
        if let intro, !intro.isEmpty {
            return intro + "\n\n" + body + "\n"
        }
        return body + "\n"
    }

    /// 标注所在段落范围（以空行为界）。
    private static func paragraphRange(around range: Range<String.Index>, in source: String) -> Range<String.Index> {
        var start = source.startIndex
        if let r = source.range(of: "\n\n", options: .backwards, range: source.startIndex..<range.lowerBound) {
            start = r.upperBound
        }
        var end = source.endIndex
        if let r = source.range(of: "\n\n", range: range.upperBound..<source.endIndex) {
            end = r.lowerBound
        }
        return start..<end
    }

    /// `index` 之前最近的 ATX 标题行（如 "## 章节"）。
    private static func nearestHeading(before index: String.Index, in source: String) -> String? {
        var result: String?
        for lineSub in source[source.startIndex..<index].split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = lineSub.drop(while: { $0 == " " })
            guard trimmed.first == "#" else { continue }
            let hashes = trimmed.prefix(while: { $0 == "#" })
            if hashes.count <= 6, trimmed.dropFirst(hashes.count).first == " " {
                result = String(trimmed)
            }
        }
        return result
    }

    /// 句子级/字符级降级提取：以标注为中心，先取核心句，再逐句向两侧扩展；
    /// 核心句仍超限时按字符截断。截断处补省略号。
    private static func clippedFragment(
        for ann: Annotation,
        paragraph: Range<String.Index>,
        in source: String,
        maxLength: Int
    ) -> String {
        let enders: Set<Character> = ["。", "！", "？", "；", "!", "?", ";", "\n", "."]

        // 核心句边界：从标注两端向外扫到最近的句末符
        var coreStart = paragraph.lowerBound
        var idx = ann.range.lowerBound
        while idx > paragraph.lowerBound {
            let prev = source.index(before: idx)
            if enders.contains(source[prev]) { coreStart = idx; break }
            idx = prev
        }
        var coreEnd = paragraph.upperBound
        idx = ann.range.upperBound
        while idx < paragraph.upperBound {
            if enders.contains(source[idx]) { coreEnd = source.index(after: idx); break }
            idx = source.index(after: idx)
        }

        var fragStart = coreStart
        var fragEnd = coreEnd
        let coreLength = source.distance(from: coreStart, to: coreEnd)

        if coreLength > maxLength {
            // 核心句过长：以标注为中心按字符截断（标注本身完整保留）
            let annLength = source.distance(from: ann.range.lowerBound, to: ann.range.upperBound)
            let budget = max(0, maxLength - annLength) / 2
            fragStart = source.index(ann.range.lowerBound, offsetBy: -budget, limitedBy: paragraph.lowerBound) ?? paragraph.lowerBound
            fragEnd = source.index(ann.range.upperBound, offsetBy: budget, limitedBy: paragraph.upperBound) ?? paragraph.upperBound
        } else {
            // 逐句向两侧交替扩展，直到接近上限
            var length = coreLength
            var canPrev = fragStart > paragraph.lowerBound
            var canNext = fragEnd < paragraph.upperBound
            while (canPrev || canNext) && length < maxLength {
                if canPrev {
                    // 上一句起点：跳过紧邻的句末符，再扫到更前一个句末符之后
                    var s = source.index(before: fragStart)
                    while s > paragraph.lowerBound, enders.contains(source[s]) {
                        s = source.index(before: s)
                    }
                    var newStart = paragraph.lowerBound
                    var j = s
                    while j > paragraph.lowerBound {
                        let prev = source.index(before: j)
                        if enders.contains(source[prev]) { newStart = j; break }
                        j = prev
                    }
                    let grow = source.distance(from: newStart, to: fragStart)
                    if length + grow <= maxLength {
                        fragStart = newStart
                        length += grow
                        canPrev = fragStart > paragraph.lowerBound
                    } else {
                        canPrev = false
                    }
                }
                if canNext, length < maxLength {
                    var newEnd = paragraph.upperBound
                    var j = fragEnd
                    while j < paragraph.upperBound {
                        if enders.contains(source[j]) { newEnd = source.index(after: j); break }
                        j = source.index(after: j)
                    }
                    let grow = source.distance(from: fragEnd, to: newEnd)
                    if grow > 0, length + grow <= maxLength {
                        fragEnd = newEnd
                        length += grow
                        canNext = fragEnd < paragraph.upperBound
                    } else {
                        canNext = false
                    }
                }
            }
        }

        var text = String(source[fragStart..<fragEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        if fragStart > paragraph.lowerBound { text = "……" + text }
        if fragEnd < paragraph.upperBound { text += "……" }
        return text
    }

    // MARK: - 导出给 AI

    /// 默认引导提示词（兜底，正常路径使用设置中的可自定义模板）：
    /// 说明内容包含 CriticMarkup 标注及各标记的含义。
    public static let defaultAIPrompt = """
    下面的内容中包含使用 CriticMarkup 语法的审阅标注，标记含义如下：
    - {++ 新增内容 ++}        建议新增
    - {-- 删除内容 --}        建议删除
    - {~~ 旧内容 ~> 新内容 ~~} 建议替换为新内容
    - {>> 评论 <<}            我的评论/疑问
    - {== 高亮内容 ==}        我重点关注的部分

    ---

    {{MarkMark:content}}
    """

    /// 提示词模板中的正文占位符（带 MarkMark 前缀避免与正文内容冲突）
    public static let contentPlaceholder = "{{MarkMark:content}}"

    /// 生成可直接粘贴给 AI 的内容。
    /// 模板含 `{{MarkMark:content}}` 占位符时替换为正文；否则模板在前、正文在后。
    public static func exportForAI(_ markedSource: String, prompt: String? = nil) -> String {
        let header = prompt ?? defaultAIPrompt
        if header.contains(contentPlaceholder) {
            return header.replacingOccurrences(of: contentPlaceholder, with: markedSource)
        }
        return header + "\n\n" + markedSource + "\n"
    }

    // MARK: - 渲染为 HTML

    /// 将 CriticMarkup 标注转换为带样式 class 的 HTML 片段。
    /// 在 Markdown 解析前调用，使内部 Markdown 仍可正常渲染。
    public static func renderToHTML(_ text: String) -> String {
        var s = text
        // 顺序：先替换（含 ~> ），再增、删、高亮，最后评论（需转义 title）
        s = regexReplace(s, #"\{~~([\s\S]*?)~>([\s\S]*?)~~\}"#,
                         template: "<del class=\"critic critic-del\">$1</del><ins class=\"critic critic-add\">$2</ins>")
        s = regexReplace(s, #"\{\+\+([\s\S]*?)\+\+\}"#,
                         template: "<ins class=\"critic critic-add\">$1</ins>")
        s = regexReplace(s, #"\{--([\s\S]*?)--\}"#,
                         template: "<del class=\"critic critic-del\">$1</del>")
        s = regexReplace(s, #"\{==([\s\S]*?)==\}"#,
                         template: "<mark class=\"critic critic-mark\">$1</mark>")
        s = renderComments(s)
        return s
    }

    private static func renderComments(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{>>([\s\S]*?)<<\}"#) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let commentRange = Range(match.range(at: 1), in: result) else { continue }
            let comment = attributeEscaped(String(result[commentRange]))
            let replacement = "<span class=\"critic critic-comment\" title=\"\(comment)\" data-comment=\"\(comment)\">\u{1F4AC}</span>"
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    // MARK: - 工具

    private static func regexReplace(_ text: String, _ pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func attributeEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
