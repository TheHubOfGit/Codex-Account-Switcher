import Foundation
import Testing
@testable import CodexAccountSwitcher

struct RegistrySnapshotTests {
    @Test
    func decodesRealisticRegistryShapeAndMarksActiveAccount() throws {
        let data = Data(
            """
            {
              "active_account_key": "acct-2",
              "auto_switch": {
                "enabled": true,
                "threshold_5h_percent": 12,
                "threshold_weekly_percent": 8
              },
              "api": {
                "usage": true
              },
              "accounts": [
                {
                  "account_key": "acct-1",
                  "email": "one@example.com",
                  "alias": "",
                  "account_name": "One",
                  "plan": "team",
                  "last_usage": {
                    "primary": {
                      "used_percent": 70,
                      "window_minutes": 300,
                      "resets_at": 1779005309
                    },
                    "secondary": {
                      "used_percent": 40,
                      "window_minutes": 10080,
                      "resets_at": 1779592109
                    },
                    "plan_type": "team"
                  },
                  "last_usage_at": 1778987846
                },
                {
                  "account_key": "acct-2",
                  "email": "two@example.com",
                  "alias": "Work",
                  "account_name": null,
                  "plan": "team",
                  "last_usage": {
                    "primary": {
                      "used_percent": 10,
                      "window_minutes": 300,
                      "resets_at": 1779005309
                    },
                    "secondary": {
                      "used_percent": 5,
                      "window_minutes": 10080,
                      "resets_at": 1779592109
                    },
                    "plan_type": "team"
                  },
                  "last_usage_at": 1778987846
                }
              ]
            }
            """.utf8
        )

        let snapshot = try RegistrySnapshot.decode(from: data)
        let accounts = snapshot.accountSnapshots(now: Date(timeIntervalSince1970: 1778987900))

        #expect(snapshot.activeAccountKey == "acct-2")
        #expect(snapshot.autoSwitch.enabled)
        #expect(snapshot.autoSwitch.threshold5hPercent == 12)
        #expect(accounts.count == 2)
        #expect(accounts[0].accountKey == "acct-2")
        #expect(accounts[0].isActive)
        #expect(accounts[0].primaryLabel == "Work")
        #expect(accounts[0].secondaryLabel == "two@example.com")
        #expect(accounts[0].fiveHour.remainingPercent == 90)
        #expect(accounts[0].weekly.remainingPercent == 95)
    }

    @Test
    func marksMissingOrOldUsageAsStale() throws {
        let data = Data(
            """
            {
              "active_account_key": "acct-1",
              "auto_switch": {
                "enabled": false,
                "threshold_5h_percent": 10,
                "threshold_weekly_percent": 5
              },
              "api": {
                "usage": false
              },
              "accounts": [
                {
                  "account_key": "acct-1",
                  "email": "stale@example.com",
                  "alias": "",
                  "account_name": null,
                  "plan": "team",
                  "last_usage": {
                    "primary": {
                      "used_percent": 50,
                      "window_minutes": 300,
                      "resets_at": 1779005309
                    },
                    "secondary": {
                      "used_percent": 20,
                      "window_minutes": 10080,
                      "resets_at": 1779592109
                    },
                    "plan_type": "team"
                  },
                  "last_usage_at": 1778980000
                }
              ]
            }
            """.utf8
        )

        let snapshot = try RegistrySnapshot.decode(from: data)
        let accounts = snapshot.accountSnapshots(now: Date(timeIntervalSince1970: 1778987900))

        #expect(accounts[0].isUsageStale)
        #expect(accounts[0].fiveHour.remainingPercent == 50)
    }
}
