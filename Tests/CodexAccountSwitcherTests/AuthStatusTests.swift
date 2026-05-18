import Foundation
import Testing
@testable import CodexAccountSwitcher

struct AuthStatusTests {
    @Test
    func parsesStatusOutput() {
        let status = AuthStatus.parse(
            """
            auto-switch: ON
            service: running
            thresholds: 5h<10%, weekly<5%
            usage: api
            account: api
            """
        )

        #expect(status.autoSwitchEnabled)
        #expect(status.serviceStatus == "running")
        #expect(status.threshold5hPercent == 10)
        #expect(status.thresholdWeeklyPercent == 5)
        #expect(status.usageMode == .api)
        #expect(status.accountMode == "api")
    }
}
