import Foundation
import Testing
@testable import MarkMark

@Suite("Markdown link navigation policy")
struct MarkdownLinkNavigationPolicyTests {

    @Test("mr URLs are the only URLs eligible for internal navigation")
    func onlyMRURLsAreInternalNavigationCandidates() throws {
        let local = URL(fileURLWithPath: "/tmp/linked.md")

        #expect(MarkdownLinkNavigationPolicy.internalTargetURL(from: URL(string: "mr:///tmp/linked.md")!) == local.markMarkCanonicalFileURL)
        #expect(MarkdownLinkNavigationPolicy.internalTargetURL(from: URL(string: "mr://host/tmp/linked.md")!) == nil)
        #expect(MarkdownLinkNavigationPolicy.internalTargetURL(from: URL(string: "https://example.com/readme.md")!) == nil)
        #expect(MarkdownLinkNavigationPolicy.internalTargetURL(from: URL(string: "mailto:test@example.com")!) == nil)
        #expect(MarkdownLinkNavigationPolicy.internalTargetURL(from: local) == nil)
    }

    @Test("markdown file inside the current root keeps the root")
    func markdownFileInsideCurrentRootKeepsRoot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("a/current.md")
        let target = root.appendingPathComponent("b/target.md")
        try createFile(source)
        try createFile(target)

        let decision = MarkdownLinkNavigationPolicy.decide(
            sourceFileURL: source,
            currentRootURL: root,
            targetURL: target
        )

        #expect(decision.targetKind == .markdownFile)
        #expect(decision.rootURL == root.markMarkCanonicalFileURL)
        #expect(!decision.requiresConfirmation)
    }

    @Test("directory inside the current root keeps the root")
    func directoryInsideCurrentRootKeepsRoot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("a/current.md")
        let target = root.appendingPathComponent("b", isDirectory: true)
        try createFile(source)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let decision = MarkdownLinkNavigationPolicy.decide(
            sourceFileURL: source,
            currentRootURL: root,
            targetURL: target
        )

        #expect(decision.targetKind == .directory)
        #expect(decision.rootURL == root.markMarkCanonicalFileURL)
        #expect(!decision.requiresConfirmation)
    }

    @Test("relative target outside current root switches to common parent with confirmation")
    func outsideCurrentRootRequiresConfirmationAndCommonParent() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let docs = root.appendingPathComponent("docs", isDirectory: true)
        let source = docs.appendingPathComponent("a/current.md")
        let target = root.appendingPathComponent("README.md")
        try createFile(source)
        try createFile(target)

        let decision = MarkdownLinkNavigationPolicy.decide(
            sourceFileURL: source,
            currentRootURL: docs.appendingPathComponent("a", isDirectory: true),
            targetURL: target
        )

        #expect(decision.targetKind == .markdownFile)
        #expect(decision.rootURL == root.markMarkCanonicalFileURL)
        #expect(decision.requiresConfirmation)
    }

    @Test("single file mode switches to common parent without confirmation")
    func singleFileModeUsesCommonParentWithoutConfirmation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("docs/a/current.md")
        let target = root.appendingPathComponent("docs/b/target.md")
        try createFile(source)
        try createFile(target)

        let decision = MarkdownLinkNavigationPolicy.decide(
            sourceFileURL: source,
            currentRootURL: nil,
            targetURL: target
        )

        #expect(decision.targetKind == .markdownFile)
        #expect(decision.rootURL == root.appendingPathComponent("docs", isDirectory: true).markMarkCanonicalFileURL)
        #expect(!decision.requiresConfirmation)
    }

    @Test("missing and unsupported targets do not navigate")
    func missingAndUnsupportedTargetsDoNotNavigate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("current.md")
        let missing = root.appendingPathComponent("missing.md")
        let unsupported = root.appendingPathComponent("image.png")
        try createFile(source)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: unsupported)

        let missingDecision = MarkdownLinkNavigationPolicy.decide(
            sourceFileURL: source,
            currentRootURL: root,
            targetURL: missing
        )
        let unsupportedDecision = MarkdownLinkNavigationPolicy.decide(
            sourceFileURL: source,
            currentRootURL: root,
            targetURL: unsupported
        )

        #expect(missingDecision.targetKind == .missing)
        #expect(!missingDecision.canNavigate)
        #expect(unsupportedDecision.targetKind == .unsupportedFile)
        #expect(!unsupportedDecision.canNavigate)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkMarkLinkPolicyTests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.markMarkCanonicalFileURL
}

private func createFile(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "# Test".write(to: url, atomically: true, encoding: .utf8)
}
