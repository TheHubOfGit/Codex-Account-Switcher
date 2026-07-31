import AppKit
import Testing
@testable import CodexAccountSwitcher

struct AppDelegateLifecycleTests {
    @Test
    func appDelegateHandlesReopenEvents() {
        let selector = #selector(NSApplicationDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:))

        #expect(AppDelegate.instancesRespond(to: selector))
    }
}
