import Testing
@testable import MarkdownReaderKit

/// 数学公式识别的回归测试。
///
/// 背景：行内公式正则曾允许跨行配对（dotMatchesLineSeparators），文档里两个不相干的
/// 美元金额（如 "$134/月" 与几行外的 "$0.01/GB-月"）被远距离配成一个"公式"，把中间的
/// 正文连同行内代码占位符一起吞进 KaTeX，页面出现 �CODEINLINE_43� 且整段字体错乱。
struct MarkdownMathTests {

    // MARK: - 美元金额不应被识别为公式

    @Test func currencyPairAcrossLinesIsNotMath() {
        let markdown = """
        实锤案例：76 万行小库跑出 $134/月，全因无索引聚合：

        禁裸 `SELECT COUNT(*)`（SQLite 无行数元数据 = 全表扫描计费）。

        每周全量快照导 R2（IA 档 $0.01/GB-月）。
        """
        let html = MarkdownHTMLService.render(markdown).html
        #expect(!html.contains("language-math"))
        #expect(!html.contains("CODEINLINE"))
        #expect(!html.contains("\u{0000}"))
        #expect(html.contains("$134/月"))
        #expect(html.contains("SELECT COUNT(*)"))
    }

    @Test func currencyPairOnSameLineIsNotMath() {
        // 闭合 $ 后紧跟数字（Pandoc 规则）→ 不是公式
        let markdown = "存储 **$0.20/GB-月，是 D1（$0.75）的 27%**；表格行：3TB ≈ $600/月"
        let html = MarkdownHTMLService.render(markdown).html
        #expect(!html.contains("language-math"))
        #expect(html.contains("$0.20"))
    }

    // MARK: - 合法公式仍应渲染

    @Test func inlineMathStillRenders() {
        let html = MarkdownHTMLService.render("质能方程 $E=mc^2$ 很有名。").html
        #expect(html.contains("language-math inline"))
        #expect(html.contains("E=mc^2"))
    }

    @Test func blockMathStillRenders() {
        let markdown = """
        $$
        e^{-x^2}
        $$
        """
        let html = MarkdownHTMLService.render(markdown).html
        #expect(html.contains("language-math"))
        #expect(html.contains("e^{-x^2}"))
    }

    @Test func inlineMathMustCloseOnSameLine() {
        let markdown = "单价 $5，另一行：\n结尾又出现 $x 但不该配对"
        let html = MarkdownHTMLService.render(markdown).html
        #expect(!html.contains("language-math"))
    }

    // MARK: - 开关

    @Test func mathDisabledLeavesDollarsLiteral() {
        let html = MarkdownHTMLService.render("公式 $E=mc^2$ 与金额 $134/月", mathEnabled: false).html
        #expect(!html.contains("language-math"))
        #expect(html.contains("$134/月"))
    }

    @Test func mathDisabledSkipsBlockMath() {
        let html = MarkdownHTMLService.render("$$\nx+y\n$$", mathEnabled: false).html
        #expect(!html.contains("language-math"))
    }
}
