import Testing
@testable import MarkdownReaderKit

// MARK: - 选区边界修正（格式安全）

@Suite("CriticMarkup format-safe boundaries")
struct CriticMarkupBoundaryTests {

    @Test("selection straddling bold into plain text absorbs the whole bold run")
    func boldStraddle() {
        // 源码 **bold** plain，渲染文本 "bold plain"，选中 "ld pla"（跨粗体边界）
        let out = CriticMarkup.apply(.highlight, to: "**bold** plain end", selectedText: "ld pla", nearLine: 1)
        #expect(out == "{==**bold** pla==}in end")
    }

    @Test("straddled bold still renders as bold inside the highlight")
    func boldStraddleRenders() {
        let out = CriticMarkup.apply(.highlight, to: "**bold** plain end", selectedText: "ld pla", nearLine: 1)!
        let html = MarkdownHTMLService.render(out).html
        #expect(html.contains("<strong>bold</strong>"))
        #expect(!html.contains("**"))
        #expect(!html.contains("{=="))
    }

    @Test("selection straddling inline code absorbs the whole code span")
    func inlineCodeStraddle() {
        // 渲染文本 "run code now"，选中 "de now"（跨行内代码右边界）
        let out = CriticMarkup.apply(.highlight, to: "run `code` now ok", selectedText: "de now", nearLine: 1)
        #expect(out == "run {==`code` now==} ok")
    }

    @Test("selection straddling an existing annotation absorbs it whole")
    func existingAnnotationStraddle() {
        // 已有 {==高亮==} 的文档上再选跨边界内容：整个旧标注并入，不产生交错嵌套
        let source = "前{==高亮==}后文"
        let out = CriticMarkup.apply(.delete, to: source, selectedText: "亮后", nearLine: 1)
        #expect(out == "前{--{==高亮==}后--}文")
    }

    @Test("fully inside a bold run stays untouched")
    func insideBoldUnchanged() {
        let out = CriticMarkup.apply(.highlight, to: "前**粗体内容**后", selectedText: "体内", nearLine: 1)
        #expect(out == "前**粗{==体内==}容**后")
    }

    @Test("expansion never crosses a table pipe")
    func noPipeCrossing() {
        // 表格单元格里的粗体：边界修正在单元格内进行，不把含 | 的误匹配 span 并入
        let source = "| a**b** | c**d** |"
        let out = CriticMarkup.apply(.highlight, to: source, selectedText: "ab", nearLine: 1)
        #expect(out == "| {==a**b**==} | c**d** |")
    }
}

// MARK: - 跨块选区分段标注

@Suite("CriticMarkup cross-block fragments")
struct CriticMarkupFragmentTests {

    @Test("selection across two table cells highlights each cell separately")
    func crossCellHighlight() {
        // 跨单元格选区：selection.toString() 在单元格间产生 \t
        let source = "| 甲甲 | 乙乙 |\n| --- | --- |\n| 丙丙 | 丁丁 |"
        let out = CriticMarkup.apply(.highlight, to: source, selectedText: "丙丙\t丁丁", nearLine: 3)
        #expect(out == "| 甲甲 | 乙乙 |\n| --- | --- |\n| {==丙丙==} | {==丁丁==} |")
    }

    @Test("cross-cell annotated table still renders as a table")
    func crossCellRenders() {
        let source = "| 甲甲 | 乙乙 |\n| --- | --- |\n| 丙丙 | 丁丁 |"
        let out = CriticMarkup.apply(.highlight, to: source, selectedText: "丙丙\t丁丁", nearLine: 3)!
        let html = MarkdownHTMLService.render(out).html
        #expect(html.contains("<table"))
        #expect(!html.contains("{=="))
    }

    @Test("comment across cells attaches the comment to the last fragment")
    func crossCellComment() {
        let source = "| 甲甲 | 乙乙 |"
        let result = CriticMarkup.applyDetailed(.comment("疑问"), to: source, selectedText: "甲甲\t乙乙", nearLine: 1)!
        #expect(result.source == "| {==甲甲==} | {==乙乙==}{>>疑问<<} |")
        #expect(result.annotations.map(\.kind) == [.highlight, .comment])
    }

    @Test("selection across paragraphs wraps each paragraph separately")
    func crossParagraphHighlight() {
        let source = "第一段结尾内容\n\n开头内容第二段"
        let out = CriticMarkup.apply(.highlight, to: source, selectedText: "结尾内容\n开头内容", nearLine: 1)
        #expect(out == "第一段{==结尾内容==}\n\n{==开头内容==}第二段")
    }

    @Test("replace across paragraphs deletes leading fragments and substitutes the last")
    func crossParagraphReplace() {
        let source = "旧文甲乙\n\n旧文丙丁"
        let result = CriticMarkup.applyDetailed(.replace("新文"), to: source, selectedText: "甲乙\n旧文丙丁", nearLine: 1)!
        #expect(result.source == "旧文{--甲乙--}\n\n{~~旧文丙丁~>新文~~}")
        #expect(result.annotations.map(\.kind) == [.deletion, .substitution])
    }

    @Test("soft line break within one paragraph stays a single annotation")
    func softBreakStaysSingle() {
        // 同段软换行：不拆段（selection.toString 的换行来自源码软换行）
        let out = CriticMarkup.apply(.highlight, to: "第一行\n第二行结尾", selectedText: "第一行第二行", nearLine: 1)
        #expect(out == "{==第一行\n第二行==}结尾")
    }

    @Test("fails as a whole when any fragment cannot be located")
    func fragmentFailureIsAtomic() {
        let source = "| 甲甲 | 乙乙 |"
        #expect(CriticMarkup.apply(.highlight, to: source, selectedText: "甲甲\t不存在", nearLine: 1) == nil)
        #expect(source.contains("{==") == false)
    }
}
