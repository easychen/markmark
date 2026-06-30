import Testing
import Foundation
@testable import MarkMark

@Suite("Launch completion routing state")
struct LaunchCompletionRoutingStateTests {

    @Test("direct intent waits for content window ready")
    func directIntentWaitsForContentWindowReady() {
        var state = LaunchCompletionRoutingState()

        state.markDidFinishLaunching()
        state.markUntitledLaunchRequest()

        #expect(state.decision == .wait)
    }

    @Test("content window ready waits for launch intent")
    func contentWindowReadyWaitsForLaunchIntent() {
        var state = LaunchCompletionRoutingState()

        state.markDidFinishLaunching()
        state.markContentWindowReady()

        #expect(state.decision == .wait)
    }

    @Test("direct intent plus finish plus content ready restores or welcomes")
    func directIntentRoutesAfterFinishAndContentReady() {
        var state = LaunchCompletionRoutingState()

        state.markUntitledLaunchRequest()
        state.markDidFinishLaunching()
        state.markContentWindowReady()

        #expect(state.decision == .routeDirectLaunch)
    }

    @Test("explicit URL routes target instead of restoring")
    func explicitURLRoutesTarget() {
        var state = LaunchCompletionRoutingState()
        let target = URL(fileURLWithPath: "/tmp/target.md")

        state.markUntitledLaunchRequest()
        state.markExplicitURL(target)
        state.markDidFinishLaunching()
        state.markContentWindowReady()

        #expect(state.decision == .routeExplicitURL(target.markMarkCanonicalFileURL))
    }

    @Test("explicit intent without URL suppresses restore")
    func explicitIntentWithoutURLSuppressesRestore() {
        var state = LaunchCompletionRoutingState()

        state.markUntitledLaunchRequest()
        state.markExplicitIntentWithoutURL()
        state.markDidFinishLaunching()
        state.markContentWindowReady()

        #expect(state.decision == .suppressRestore)
    }

    @Test("pending store URL beats direct restore")
    func pendingStoreURLBeatsDirectRestore() {
        var state = LaunchCompletionRoutingState()
        let pending = URL(fileURLWithPath: "/tmp/pending.md")

        state.markUntitledLaunchRequest()
        state.updatePendingStoreURL(pending)
        state.markDidFinishLaunching()
        state.markContentWindowReady()

        #expect(state.decision == .routeExplicitURL(pending.markMarkCanonicalFileURL))
    }

    @Test("routed state does not produce another decision")
    func routedStateWaits() {
        var state = LaunchCompletionRoutingState()

        state.markUntitledLaunchRequest()
        state.markDidFinishLaunching()
        state.markContentWindowReady()
        state.markDidBecomeActive()
        state.markRouted()

        #expect(state.decision == .wait)
    }
}
