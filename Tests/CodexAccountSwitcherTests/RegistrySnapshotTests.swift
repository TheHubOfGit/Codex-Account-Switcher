import Foundation
import Testing
@testable import CodexAccountSwitcher

struct RegistrySnapshotTests {
    @Test
    func classifiesSinglePrimaryWeeklyWindowByDuration() throws {
        let data = Data(
            """
            {
              "active_account_key": "acct-1",
              "auto_switch": {"enabled": false, "threshold_5h_percent": 10, "threshold_weekly_percent": 5},
              "api": {"usage": true},
              "accounts": [{
                "account_key": "acct-1",
                "email": "weekly@example.com",
                "alias": "",
                "account_name": null,
                "plan": "team",
                "last_usage": {
                  "primary": {"used_percent": 43, "window_minutes": 10080, "resets_at": 1785273696},
                  "secondary": null
                },
                "last_usage_at": 1785000000
              }]
            }
            """.utf8
        )

        let account = try #require(
            RegistrySnapshot.decode(from: data).accountSnapshots().first
        )
        #expect(account.fiveHour.remainingPercent == nil)
        #expect(account.weekly.remainingPercent == 57)
    }

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
    func keepsOldUsageFreshOnlyAfterSuccessfulRefresh() throws {
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
        let accounts = snapshot.accountSnapshots(
            now: Date(timeIntervalSince1970: 1778987900),
            usageCheckedAtByAccountKey: [
                "acct-1": Date(timeIntervalSince1970: 1778987890)
            ]
        )

        #expect(!accounts[0].isUsageStale(at: Date(timeIntervalSince1970: 1778987900)))
        #expect(accounts[0].fiveHour.remainingPercent == 50)
    }

    @Test
    func partialRefreshKeepsOnlyFailedAccountStale() throws {
        let data = Data(
            """
            {
              "active_account_key": "acct-1",
              "auto_switch": {"enabled": false, "threshold_5h_percent": 10, "threshold_weekly_percent": 5},
              "api": {"usage": true},
              "accounts": [
                {
                  "account_key": "acct-1",
                  "email": "fresh@example.com",
                  "alias": "",
                  "account_name": null,
                  "plan": "team",
                  "last_usage": {"primary": {"used_percent": 10}, "secondary": {"used_percent": 20}},
                  "last_usage_at": 1000
                },
                {
                  "account_key": "acct-2",
                  "email": "failed@example.com",
                  "alias": "",
                  "account_name": null,
                  "plan": "team",
                  "last_usage": {"primary": {"used_percent": 30}, "secondary": {"used_percent": 40}},
                  "last_usage_at": 1000
                }
              ]
            }
            """.utf8
        )

        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = try RegistrySnapshot.decode(from: data)
        let accounts = snapshot.accountSnapshots(
            now: now,
            usageCheckedAtByAccountKey: ["acct-1": now]
        )
        let fresh = try #require(accounts.first { $0.email == "fresh@example.com" })
        let failed = try #require(accounts.first { $0.email == "failed@example.com" })

        #expect(!fresh.isUsageStale(at: now))
        #expect(failed.isUsageStale(at: now))
    }

    @Test
    func marksOldSnapshotAsStale() throws {
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
                  "last_usage_at": 1778987890
                }
              ]
            }
            """.utf8
        )

        let snapshot = try RegistrySnapshot.decode(from: data)
        let accounts = snapshot.accountSnapshots(now: Date(timeIntervalSince1970: 1778990000))

        #expect(accounts[0].isUsageStale(at: Date(timeIntervalSince1970: 1778990000)))
        #expect(accounts[0].fiveHour.remainingPercent == 50)
    }

    @Test
    func freshnessChangesAsClockAdvancesWithoutReloading() throws {
        let data = Data(
            """
            {
              "active_account_key": "acct-1",
              "auto_switch": {"enabled": false, "threshold_5h_percent": 10, "threshold_weekly_percent": 5},
              "api": {"usage": true},
              "accounts": [{
                "account_key": "acct-1",
                "email": "one@example.com",
                "alias": "",
                "account_name": null,
                "plan": "plus",
                "last_usage": {"primary": {"used_percent": 20}, "secondary": {"used_percent": 30}, "plan_type": "plus"},
                "last_usage_at": 1000
              }]
            }
            """.utf8
        )
        let snapshot = try RegistrySnapshot.decode(from: data)
        let accounts = snapshot.accountSnapshots(
            now: Date(timeIntervalSince1970: 1_010),
            usageCheckedAtByAccountKey: [
                "acct-1": Date(timeIntervalSince1970: 1_000)
            ]
        )

        #expect(!accounts[0].isUsageStale(at: Date(timeIntervalSince1970: 2_799)))
        #expect(accounts[0].isUsageStale(at: Date(timeIntervalSince1970: 2_801)))
    }
}
