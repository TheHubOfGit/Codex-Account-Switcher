import Foundation

enum AccountSwitchNotificationDecision: Equatable {
    case none
    case notifyExternalSwitch(accountKey: String)
}

enum AccountSwitchNotificationPolicy {
    static func decision(
        previousActive: String?,
        nextActive: String?,
        notifyOnExternalSwitch: Bool,
        suppressNextExternalSwitchNotification: inout Bool,
        pendingAutoMonitorPromptTargetKey: inout String?
    ) -> AccountSwitchNotificationDecision {
        guard notifyOnExternalSwitch,
              let previousActive,
              let nextActive,
              previousActive != nextActive else {
            if suppressNextExternalSwitchNotification {
                suppressNextExternalSwitchNotification = false
            }
            return .none
        }

        if suppressNextExternalSwitchNotification {
            suppressNextExternalSwitchNotification = false
            return .none
        }

        if pendingAutoMonitorPromptTargetKey == nextActive {
            pendingAutoMonitorPromptTargetKey = nil
            return .none
        }

        return .notifyExternalSwitch(accountKey: nextActive)
    }
}
