import Foundation
import Testing
@testable import MarkMark

@MainActor
@Suite("Navigation history")
struct NavigationHistoryModelTests {

    @Test("recording locations builds back stack and clears forward stack")
    func recordingBuildsBackStackAndClearsForwardStack() {
        let history = NavigationHistoryModel()
        let first = snapshot(root: "/tmp/docs", selected: "/tmp/docs/a.md")
        let second = snapshot(root: "/tmp/docs", selected: "/tmp/docs/b.md")
        let third = snapshot(root: "/tmp/docs", selected: "/tmp/docs/c.md")

        history.record(first)
        history.record(second)

        #expect(history.canGoBack)
        #expect(!history.canGoForward)
        #expect(history.goBack() == first)
        #expect(!history.canGoBack)
        #expect(history.canGoForward)

        history.record(third)

        #expect(history.canGoBack)
        #expect(!history.canGoForward)
        #expect(history.backTarget == first)
    }

    @Test("back and forward preserve active directory without changing selected file")
    func backForwardPreserveActiveDirectoryState() {
        let history = NavigationHistoryModel()
        let fileState = snapshot(
            root: "/tmp/docs",
            selected: "/tmp/docs/current.md",
            active: "/tmp/docs/current.md"
        )
        let revealedDirectoryState = snapshot(
            root: "/tmp/docs",
            selected: "/tmp/docs/current.md",
            active: "/tmp/docs/reference"
        )

        history.record(fileState)
        history.record(revealedDirectoryState)

        #expect(history.goBack() == fileState)
        #expect(history.goForward() == revealedDirectoryState)
    }

    @Test("single file snapshots round trip")
    func singleFileSnapshotsRoundTrip() {
        let history = NavigationHistoryModel()
        let singleFile = NavigationHistorySnapshot(
            isSingleFileMode: true,
            rootDirectory: nil,
            singleFileURL: URL(fileURLWithPath: "/tmp/current.md"),
            selectedFileURL: URL(fileURLWithPath: "/tmp/current.md"),
            activeNodeURL: URL(fileURLWithPath: "/tmp/current.md")
        )
        let directoryFile = snapshot(root: "/tmp/docs", selected: "/tmp/docs/target.md")

        history.record(singleFile)
        history.record(directoryFile)

        let previous = history.goBack()

        #expect(previous == singleFile)
        #expect(previous?.isSingleFileMode == true)
        #expect(previous?.rootDirectory == nil)
    }
}

private func snapshot(
    root: String,
    selected: String? = nil,
    active: String? = nil
) -> NavigationHistorySnapshot {
    NavigationHistorySnapshot(
        isSingleFileMode: false,
        rootDirectory: URL(fileURLWithPath: root, isDirectory: true),
        singleFileURL: nil,
        selectedFileURL: selected.map { URL(fileURLWithPath: $0) },
        activeNodeURL: active.map { URL(fileURLWithPath: $0) }
    )
}
