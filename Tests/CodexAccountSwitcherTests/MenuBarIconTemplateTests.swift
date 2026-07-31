import AppKit
import Testing
@testable import CodexAccountSwitcher

struct MenuBarIconTemplateTests {
    @Test
    func meteredIconIsTemplateWhenQuotaDataIsUnavailable() {
        let state = MenuBarQuotaMeterState(activeAccount: nil)

        let image = MenuBarIcon.paceRing(state: state)

        #expect(image.isTemplate == true)
    }

    @Test
    func meteredIconRemainsTemplateWhenQuotaDataIsAvailable() {
        let state = MenuBarQuotaMeterState(remainingPercent: 75, isStale: false)

        let image = MenuBarIcon.paceRing(state: state)

        #expect(image.isTemplate == true)
    }

    @Test
    func meteredIconRemainsTemplateEvenWhenStateIsStale() {
        let state = MenuBarQuotaMeterState(remainingPercent: 5, isStale: true)

        let image = MenuBarIcon.paceRing(state: state)

        #expect(image.isTemplate == true)
    }
}
