import Testing
@testable import CodexAccountSwitcher

struct AccountSwitchNotificationPolicyTests {
    @Test
    func suppressesExternalSwitchNoticeWhileApprovalPromptIsPendingForTarget() {
        var suppressNext = false
        var pendingPromptTargetKey: String? = "acct-2"

        let decision = AccountSwitchNotificationPolicy.decision(
            previousActive: "acct-1",
            nextActive: "acct-2",
            notifyOnExternalSwitch: true,
            suppressNextExternalSwitchNotification: &suppressNext,
            pendingAutoMonitorPromptTargetKey: &pendingPromptTargetKey
        )

        #expect(decision == .none)
        #expect(!suppressNext)
        #expect(pendingPromptTargetKey == nil)
    }

    @Test
    func notifiesForUnpromptedExternalSwitch() {
        var suppressNext = false
        var pendingPromptTargetKey: String?

        let decision = AccountSwitchNotificationPolicy.decision(
            previousActive: "acct-1",
            nextActive: "acct-2",
            notifyOnExternalSwitch: true,
            suppressNextExternalSwitchNotification: &suppressNext,
            pendingAutoMonitorPromptTargetKey: &pendingPromptTargetKey
        )

        #expect(decision == .notifyExternalSwitch(accountKey: "acct-2"))
        #expect(!suppressNext)
        #expect(pendingPromptTargetKey == nil)
    }

    @Test
    func consumesManualSwitchSuppressionWithoutNotifying() {
        var suppressNext = true
        var pendingPromptTargetKey: String?

        let decision = AccountSwitchNotificationPolicy.decision(
            previousActive: "acct-1",
            nextActive: "acct-2",
            notifyOnExternalSwitch: true,
            suppressNextExternalSwitchNotification: &suppressNext,
            pendingAutoMonitorPromptTargetKey: &pendingPromptTargetKey
        )

        #expect(decision == .none)
        #expect(!suppressNext)
    }
}
