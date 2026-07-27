import Testing
@testable import MarkdownReaderKit

// MARK: - locateRange

@Suite("CriticMarkup.locateRange")
struct CriticMarkupLocateTests {

    @Test("finds a unique substring")
    func uniqueMatch() {
        let source = "The quick brown fox"
        let range = CriticMarkup.locateRange(in: source, selectedText: "brown", nearLine: 1)
        #expect(range != nil)
        #expect(source[range!] == "brown")
    }

    @Test("returns nil when text is absent")
    func absent() {
        #expect(CriticMarkup.locateRange(in: "hello world", selectedText: "zzz", nearLine: 1) == nil)
    }

    @Test("returns nil for empty selection")
    func emptySelection() {
        #expect(CriticMarkup.locateRange(in: "hello", selectedText: "", nearLine: 1) == nil)
    }

    @Test("picks the occurrence nearest to the hint line")
    func nearestLine() {
        // "cat" appears on line 1 and line 4 — nearLine 4 should pick the second.
        let source = "cat one\ntwo\nthree\ncat four"
        let range = CriticMarkup.locateRange(in: source, selectedText: "cat", nearLine: 4)
        #expect(range != nil)
        // The chosen "cat" should be on line 4 (offset after the three newlines)
        let lineOfMatch = source[source.startIndex..<range!.lowerBound].filter { $0 == "\n" }.count + 1
        #expect(lineOfMatch == 4)
    }

    @Test("near line 1 picks the first occurrence")
    func nearestLineFirst() {
        let source = "cat one\ntwo\nthree\ncat four"
        let range = CriticMarkup.locateRange(in: source, selectedText: "cat", nearLine: 1)
        let lineOfMatch = source[source.startIndex..<range!.lowerBound].filter { $0 == "\n" }.count + 1
        #expect(lineOfMatch == 1)
    }
}

// MARK: - apply

@Suite("CriticMarkup.apply")
struct CriticMarkupApplyTests {

    @Test("delete wraps selection in {-- --}")
    func delete() {
        let out = CriticMarkup.apply(.delete, to: "keep this gone", selectedText: "this", nearLine: 1)
        #expect(out == "keep {--this--} gone")
    }

    @Test("highlight wraps selection in {== ==}")
    func highlight() {
        let out = CriticMarkup.apply(.highlight, to: "look here now", selectedText: "here", nearLine: 1)
        #expect(out == "look {==here==} now")
    }

    @Test("comment highlights selection and appends {>> <<}")
    func comment() {
        let out = CriticMarkup.apply(.comment("why?"), to: "fix this part", selectedText: "this", nearLine: 1)
        #expect(out == "fix {==this==}{>>why?<<} part")
    }

    @Test("replace produces a {~~old~>new~~} substitution")
    func replace() {
        let out = CriticMarkup.apply(.replace("that"), to: "use this here", selectedText: "this", nearLine: 1)
        #expect(out == "use {~~this~>that~~} here")
    }

    @Test("insert appends an addition after the selection")
    func insert() {
        let out = CriticMarkup.apply(.insert(" extra"), to: "add here", selectedText: "here", nearLine: 1)
        #expect(out == "add here{++ extra++}")
    }

    @Test("apply returns nil when selection not found")
    func notFound() {
        #expect(CriticMarkup.apply(.delete, to: "abc", selectedText: "xyz", nearLine: 1) == nil)
    }

    @Test("apply targets the occurrence nearest the hint line")
    func nearestLine() {
        let source = "drop me\n\n\ndrop me"
        let out = CriticMarkup.apply(.delete, to: source, selectedText: "drop me", nearLine: 4)
        #expect(out == "drop me\n\n\n{--drop me--}")
    }
}

// MARK: - edit / delete comment

@Suite("CriticMarkup comment editing")
struct CriticMarkupCommentTests {

    @Test("editComment rewrites the comment text in place")
    func edit() {
        let src = "看这里{==重点==}{>>原评论<<}结束"
        let out = CriticMarkup.editComment(in: src, oldComment: "原评论", newComment: "新评论", nearLine: 1)
        #expect(out == "看这里{==重点==}{>>新评论<<}结束")
    }

    @Test("editComment returns nil when the comment is absent")
    func editMissing() {
        #expect(CriticMarkup.editComment(in: "no comment here", oldComment: "x", newComment: "y", nearLine: 1) == nil)
    }

    @Test("deleteComment of a comment-only mark removes just the comment")
    func deleteCommentOnly() {
        let src = "结论存疑{>>来源？<<}。"
        let out = CriticMarkup.deleteComment(in: src, comment: "来源？", nearLine: 1)
        #expect(out == "结论存疑。")
    }

    @Test("deleteComment unwraps the paired highlight too")
    func deleteUnwrapsHighlight() {
        // 评论是用 {==sel==}{>>c<<} 创建的，删除评论应连同高亮一起还原为原文
        let src = "请改{==这一段==}{>>太啰嗦<<}内容"
        let out = CriticMarkup.deleteComment(in: src, comment: "太啰嗦", nearLine: 1)
        #expect(out == "请改这一段内容")
    }

    @Test("deleteComment targets the occurrence nearest the hint line")
    func deleteNearest() {
        let src = "a{>>dup<<}\n\n\nb{>>dup<<}"
        let out = CriticMarkup.deleteComment(in: src, comment: "dup", nearLine: 4)
        #expect(out == "a{>>dup<<}\n\n\nb")
    }
}

// MARK: - accept / reject / strip

@Suite("CriticMarkup transforms")
struct CriticMarkupTransformTests {

    let sample = "a{++b++}c{--d--}e{~~f~>g~~}h{==i==}j{>>k<<}l"

    @Test("accepting applies all suggested changes")
    func accepting() {
        // additions kept, deletions removed, substitution→new, highlight kept (content), comment removed
        #expect(CriticMarkup.accepting(sample) == "abceghijl")
    }

    @Test("rejecting reverts to the original text")
    func rejecting() {
        // additions removed, deletions kept, substitution→old, highlight kept (content), comment removed
        #expect(CriticMarkup.rejecting(sample) == "acdefhijl")
    }

    @Test("hasMarkup detects presence")
    func hasMarkup() {
        #expect(CriticMarkup.hasMarkup(sample))
        #expect(!CriticMarkup.hasMarkup("plain text only"))
    }
}

// MARK: - export for AI

@Suite("CriticMarkup.exportForAI")
struct CriticMarkupExportTests {

    @Test("includes the marked source verbatim")
    func includesSource() {
        let marked = "Hello {--world--}"
        let out = CriticMarkup.exportForAI(marked)
        #expect(out.contains(marked))
    }

    @Test("includes a guiding prompt that explains CriticMarkup")
    func includesPrompt() {
        let out = CriticMarkup.exportForAI("x")
        #expect(out.contains("CriticMarkup"))
        // mentions the core syntaxes so the AI understands the marks
        #expect(out.contains("{--"))
        #expect(out.contains("{++"))
        #expect(out.contains("{>>"))
    }

    @Test("a custom prompt overrides the default header")
    func customPrompt() {
        let out = CriticMarkup.exportForAI("body", prompt: "MY HEADER")
        #expect(out.contains("MY HEADER"))
        #expect(out.contains("body"))
    }
}

// MARK: - HTML rendering

@Suite("CriticMarkup.renderToHTML")
struct CriticMarkupHTMLTests {

    @Test("addition becomes an <ins> with a critic class")
    func addition() {
        let html = CriticMarkup.renderToHTML("a {++new++} b")
        #expect(html.contains("<ins"))
        #expect(html.contains("critic"))
        #expect(html.contains("new"))
        #expect(!html.contains("{++"))
    }

    @Test("deletion becomes a <del>")
    func deletion() {
        let html = CriticMarkup.renderToHTML("a {--old--} b")
        #expect(html.contains("<del"))
        #expect(!html.contains("--}"))
    }

    @Test("substitution becomes a <del> followed by an <ins>")
    func substitution() {
        let html = CriticMarkup.renderToHTML("{~~old~>new~~}")
        #expect(html.contains("<del"))
        #expect(html.contains("<ins"))
        let delIdx = html.range(of: "<del")!.lowerBound
        let insIdx = html.range(of: "<ins")!.lowerBound
        #expect(delIdx < insIdx)
    }

    @Test("highlight becomes a <mark>")
    func highlight() {
        let html = CriticMarkup.renderToHTML("{==important==}")
        #expect(html.contains("<mark"))
        #expect(html.contains("important"))
    }

    @Test("comment becomes a titled span carrying the comment text")
    func comment() {
        let html = CriticMarkup.renderToHTML("{>>look here<<}")
        #expect(html.contains("critic-comment"))
        #expect(html.contains("look here"))
        #expect(!html.contains("<<}"))
    }

    @Test("comment text is attribute-escaped")
    func commentEscaped() {
        let html = CriticMarkup.renderToHTML("{>>a \"quote\" & <tag><<}")
        #expect(!html.contains("\"quote\""))   // quotes escaped inside the title attribute
        #expect(html.contains("&amp;") || html.contains("&quot;"))
    }
}

// MARK: - integration with the markdown→HTML pipeline

@Suite("MarkdownHTMLService CriticMarkup integration")
struct CriticMarkupPipelineTests {

    @Test("a deletion in a paragraph renders as a critic <del>")
    func deletionInParagraph() {
        let result = MarkdownHTMLService.render("This is {--wrong--} text.")
        #expect(result.html.contains("critic"))
        #expect(result.html.contains("<del"))
    }

    @Test("rendering preserves straight quotes (smart typography disabled)")
    func noSmartQuotes() {
        let html = MarkdownHTMLService.render("是为\"第五起\"这。").html
        // 不应出现弯引号；直引号会被 HTML 转义为 &quot;（DOM 里仍显示直引号）
        #expect(!html.contains("\u{201C}"))
        #expect(!html.contains("\u{201D}"))
        #expect(html.contains("&quot;") || html.contains("\""))
    }

    @Test("rendering preserves -- and ... literally")
    func noSmartDashesEllipsis() {
        let html = MarkdownHTMLService.render("a -- b ... c").html
        #expect(html.contains("--"))
        #expect(html.contains("..."))
        #expect(!html.contains("\u{2013}"))   // en dash
        #expect(!html.contains("\u{2026}"))   // ellipsis
    }

    @Test("critic markup inside fenced code is left untouched")
    func codeUntouched() {
        let md = "```\nkeep {--literal--} here\n```"
        let result = MarkdownHTMLService.render(md)
        // Inside code, the literal braces must survive (escaped), not become <del>
        #expect(result.html.contains("{--literal--}"))
    }
}

@Suite("MarkdownHTMLService math blocks")
struct MarkdownMathBlockTests {

    @Test("block math keeps superscript LaTeX intact (no injected <sup>)")
    func blockMathSuperscriptPreserved() {
        // $$...$$ 转成 math 代码块后，块内 LaTeX 的 ^ 不应被上标预处理改写
        let html = MarkdownHTMLService.render("$$e^{-x^2}$$").html
        #expect(html.contains("language-math"))
        #expect(html.contains("e^{-x^2}"))
        #expect(!html.contains("<sup>"))
    }

    @Test("block math keeps tilde LaTeX intact (no injected <sub>)")
    func blockMathTildePreserved() {
        // 块内裸 ~ 不应被下标预处理改写成 <sub>
        let html = MarkdownHTMLService.render("$$a~b~c$$").html
        #expect(html.contains("language-math"))
        #expect(html.contains("a~b~c"))
        #expect(!html.contains("<sub>"))
    }

    @Test("block math keeps highlight markers intact (no injected <mark>)")
    func blockMathHighlightPreserved() {
        // 块内 == 不应被高亮预处理改写成 <mark>
        let html = MarkdownHTMLService.render("$$a==b==c$$").html
        #expect(html.contains("language-math"))
        #expect(!html.contains("<mark>"))
    }

    @Test("inline math still renders alongside block math")
    func inlineMathStillWorks() {
        let html = MarkdownHTMLService.render("Energy $E = mc^2$ done.").html
        #expect(html.contains("language-math"))
        #expect(html.contains("E = mc^2"))
    }
}

@Suite("CriticMarkup combined highlight+comment")
struct CriticMarkupCombinedTests {
    @Test("highlight immediately followed by a comment renders both")
    func highlightThenComment() {
        let html = CriticMarkup.renderToHTML("请改{==这一段==}{>>太啰嗦<<}内容")
        #expect(html.contains("critic-mark"))
        #expect(html.contains("critic-comment"))
        #expect(html.contains("太啰嗦"))
        #expect(html.contains("这一段"))
    }
    @Test("full pipeline keeps the comment bubble for a saved comment")
    func pipelineCombined() {
        let r = MarkdownHTMLService.render("结论存疑{==这里==}{>>请补充来源<<}。")
        #expect(r.html.contains("critic-comment"))
        #expect(r.html.contains("请补充来源"))
    }
}

// MARK: - 选区与源码一致（渲染关闭智能排版，引号/破折号等逐字保留）

@Suite("CriticMarkup locate with quotes (smart typography off)")
struct CriticMarkupQuoteLocateTests {

    @Test("locates text containing straight quotes exactly")
    func locateStraightQuotes() {
        let source = "不是为死的那个人停的。是为\"第五起\"这三个字。"
        let selected = "是为\"第五起\"这三个字"
        let out = CriticMarkup.apply(.highlight, to: source, selectedText: selected, nearLine: 1)
        #expect(out == "不是为死的那个人停的。{==是为\"第五起\"这三个字==}。")
    }

    @Test("single-span bold still located exactly (content is a substring)")
    func singleSpanExact() {
        // **粗体** 的内容「粗体」本身是源码子串，精确匹配即可命中
        let out = CriticMarkup.apply(.highlight, to: "前**粗体**后", selectedText: "粗体", nearLine: 1)
        #expect(out == "前**{==粗体==}**后")
    }
}

// MARK: - 容错定位（选区跨行内标记 / 软换行）

@Suite("CriticMarkup tolerant locate")
struct CriticMarkupTolerantLocateTests {

    @Test("locates a selection that crosses an inline-emphasis boundary")
    func crossesEmphasis() {
        // 渲染视图里看到 "bc"，但源码是 a**b**c —— "bc" 不是子串，需容错。
        // 容错命中 "b**c" 后边界修正把被撕裂的 **b** 整体并入，避免 {-- 插进 ** 配对中间
        let out = CriticMarkup.apply(.delete, to: "a**b**c", selectedText: "bc", nearLine: 1)
        #expect(out == "a{--**b**c--}")
    }

    @Test("locates across a soft line break (newline in source)")
    func crossesSoftBreak() {
        // 选区视觉文本 "第一行第二行"（软换行处的空白被忽略），源码中间是 \n
        let out = CriticMarkup.apply(.highlight, to: "第一行\n第二行结尾", selectedText: "第一行第二行", nearLine: 1)
        #expect(out == "{==第一行\n第二行==}结尾")
    }

    @Test("tolerant match picks the occurrence nearest the hint line")
    func tolerantNearestLine() {
        let source = "x**a**y\n\n\nx**a**y"
        // 选 "xay"（跨 ** 边界），近第 4 行应选第二处
        let out = CriticMarkup.apply(.highlight, to: source, selectedText: "xay", nearLine: 4)
        #expect(out == "x**a**y\n\n\n{==x**a**y==}")
    }

    @Test("does not fuzzy-match selections that are too short")
    func tooShortNoFuzzy() {
        // 单字符选区不做容错，避免乱命中
        #expect(CriticMarkup.locateRange(in: "a**b**c", selectedText: "x", nearLine: 1) == nil)
    }

    @Test("returns nil when even tolerant match fails")
    func tolerantFails() {
        #expect(CriticMarkup.apply(.delete, to: "完全无关的内容", selectedText: "zzzqqq", nearLine: 1) == nil)
    }
}
