import Foundation
import Testing
@testable import MarkMark

@MainActor
@Suite("Chrome state memory")
struct ChromeStateMemoryTests {

    @Test("settings persist remembered sidebar and outline visibility")
    func settingsPersistRememberedChromeVisibility() throws {
        let suiteName = "MarkMarkTests.ChromeState.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsModel(defaults: defaults)
        #expect(!settings.rememberedSidebarVisible)
        #expect(!settings.rememberedOutlineVisible)

        settings.rememberedSidebarVisible = true
        settings.rememberedOutlineVisible = true

        let reloaded = SettingsModel(defaults: defaults)
        #expect(reloaded.rememberedSidebarVisible)
        #expect(reloaded.rememberedOutlineVisible)
    }

    @Test("settings persist the selected file within directory mode")
    func settingsPersistDirectoryModeSelectedFile() throws {
        let suiteName = "MarkMarkTests.DirectorySelectedFile.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = try makeTemporaryChromeStateDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("notes", isDirectory: true)
            .appendingPathComponent("current.md")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Current".write(to: target, atomically: true, encoding: .utf8)

        let settings = SettingsModel(defaults: defaults)
        settings.rememberOpenedDirectory(root)
        settings.rememberDirectorySelectedFile(target, rootDirectory: root)

        let reloaded = SettingsModel(defaults: defaults)
        #expect(reloaded.lastOpenedDirectory == root.markMarkCanonicalFileURL)
        #expect(reloaded.lastOpenedFile == nil)
        #expect(reloaded.restorableDirectorySelectedFile(for: root) == target.markMarkCanonicalFileURL)
    }

    @Test("directory mode selected file restore ignores outside or missing targets")
    func directoryModeSelectedFileRestoreIgnoresInvalidTargets() throws {
        let suiteName = "MarkMarkTests.InvalidDirectorySelectedFile.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = try makeTemporaryChromeStateDirectory()
        let outsideRoot = try makeTemporaryChromeStateDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let inside = root.appendingPathComponent("inside.md")
        let outside = outsideRoot.appendingPathComponent("outside.md")
        try "# Inside".write(to: inside, atomically: true, encoding: .utf8)
        try "# Outside".write(to: outside, atomically: true, encoding: .utf8)

        let settings = SettingsModel(defaults: defaults)
        settings.rememberOpenedDirectory(root)
        settings.rememberDirectorySelectedFile(outside, rootDirectory: root)
        #expect(settings.restorableDirectorySelectedFile(for: root) == nil)

        settings.rememberDirectorySelectedFile(inside, rootDirectory: root)
        try FileManager.default.removeItem(at: inside)

        let reloaded = SettingsModel(defaults: defaults)
        #expect(reloaded.restorableDirectorySelectedFile(for: root) == nil)
    }

    @Test("opening directory can restore remembered hidden sidebar")
    func openingDirectoryCanRestoreHiddenSidebar() {
        let viewModel = AppViewModel()
        viewModel.isSidebarVisible = true

        viewModel.openDirectory(URL(fileURLWithPath: "/tmp/docs", isDirectory: true), sidebarVisible: false)

        #expect(viewModel.rootDirectory == URL(fileURLWithPath: "/tmp/docs", isDirectory: true))
        #expect(!viewModel.isSingleFileMode)
        #expect(!viewModel.isSidebarVisible)
    }

    @Test("opening single file can restore remembered visible sidebar")
    func openingSingleFileCanRestoreVisibleSidebar() {
        let viewModel = AppViewModel()

        viewModel.openSingleFile(URL(fileURLWithPath: "/tmp/note.md"), sidebarVisible: true)

        #expect(viewModel.isSingleFileMode)
        #expect(viewModel.singleFileURL == URL(fileURLWithPath: "/tmp/note.md"))
        #expect(viewModel.isSidebarVisible)
    }

    @Test("remembered outline visibility closes annotation panel")
    func rememberedOutlineVisibilityClosesAnnotationPanel() {
        let viewModel = AppViewModel()
        viewModel.isAnnotationPanelVisible = true

        viewModel.applyRememberedChromeState(sidebarVisible: false, outlineVisible: true)

        #expect(viewModel.isOutlineVisible)
        #expect(!viewModel.isAnnotationPanelVisible)
    }
}

private func makeTemporaryChromeStateDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkMarkChromeStateTests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.markMarkCanonicalFileURL
}
