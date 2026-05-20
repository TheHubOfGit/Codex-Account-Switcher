import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, NotificationManaging {
    private enum Action {
        static let autoSwitchCategory = "AUTO_SWITCH_PROMPT"
        static let switchAndRestart = "SWITCH_AND_RESTART"
    }

    private let center: UNUserNotificationCenter
    private var actions: [String: () async -> Void] = [:]

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
        configureCategories()
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("CodexAccountSwitcher notification authorization failed: %@", error.localizedDescription)
            } else {
                NSLog("CodexAccountSwitcher notification authorization granted: %@", String(granted))
            }
        }
        center.getNotificationSettings { settings in
            NSLog(
                "CodexAccountSwitcher notification settings authorization=%ld alert=%ld sound=%ld",
                settings.authorizationStatus.rawValue,
                settings.alertSetting.rawValue,
                settings.soundSetting.rawValue
            )
        }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let requestID = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                NSLog("CodexAccountSwitcher notification add failed: %@", error.localizedDescription)
            } else {
                NSLog("CodexAccountSwitcher notification added: %@", requestID)
            }
        }
    }

    func promptForAutoSwitch(from currentAccount: AccountSnapshot, to candidate: AccountSnapshot, onConfirm: @escaping () async -> Void) {
        let requestID = UUID().uuidString
        actions[requestID] = onConfirm

        let content = UNMutableNotificationContent()
        content.title = "Switch Codex account?"
        content.body = "\(currentAccount.primaryLabel) is at its quota threshold. Switch to \(candidate.primaryLabel) and restart Codex?"
        content.sound = .default
        content.categoryIdentifier = Action.autoSwitchCategory
        content.userInfo = ["requestID": requestID]

        let request = UNNotificationRequest(
            identifier: requestID,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                NSLog("CodexAccountSwitcher auto-switch notification add failed: %@", error.localizedDescription)
            } else {
                NSLog("CodexAccountSwitcher auto-switch notification added: %@", requestID)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == Action.switchAndRestart,
              let requestID = response.notification.request.content.userInfo["requestID"] as? String else {
            completionHandler()
            return
        }

        Task { @MainActor in
            let action = actions.removeValue(forKey: requestID)
            await action?()
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .list])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    private func configureCategories() {
        let switchAction = UNNotificationAction(
            identifier: Action.switchAndRestart,
            title: "Switch and Restart",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: Action.autoSwitchCategory,
            actions: [switchAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }
}
