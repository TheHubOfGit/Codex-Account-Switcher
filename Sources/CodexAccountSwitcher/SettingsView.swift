import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var fiveHourThreshold = 10
    @State private var weeklyThreshold = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Codex Account Switcher")
                .font(.title2)
                .fontWeight(.semibold)

            Toggle(isOn: Binding(
                get: { appState.autoMonitorEnabled },
                set: { enabled in
                    Task { await appState.setAutoMonitor(enabled: enabled) }
                }
            )) {
                Text("Enable Auto Monitor")
            }

            Toggle(isOn: Binding(
                get: { appState.weeklyPaceDemoEnabled },
                set: { appState.setWeeklyPaceDemo(enabled: $0) }
            )) {
                Text("Demo Weekly Pace Alert")
            }

            Text("Temporarily shows the weekly average bar and strength gauge in the exceed-pace alert state without changing account data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Stepper(value: $fiveHourThreshold, in: 1...100) {
                    Text("5h threshold: \(fiveHourThreshold)% remaining")
                }

                Stepper(value: $weeklyThreshold, in: 1...100) {
                    Text("Weekly threshold: \(weeklyThreshold)% remaining")
                }
            }

            HStack(spacing: 12) {
                Button(appState.isSavingSettings ? "Saving…" : "Save Thresholds") {
                    Task {
                        await appState.saveThresholds(fiveHour: fiveHourThreshold, weekly: weeklyThreshold)
                    }
                }
                .disabled(appState.isSavingSettings)

                Button("Refresh Status") {
                    Task { await appState.refreshAll(showNotifications: false) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Usage Mode: \(appState.usageModeLabel)")
                    .font(.headline)

                if appState.usageModeLabel == UsageMode.local.displayName {
                    Text("Quota freshness may lag because codex-auth is using local rollout data instead of the API-backed refresh mode.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("codex-auth is providing the quota cache used by this app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = appState.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            if let currentFive = appState.authStatus.threshold5hPercent {
                fiveHourThreshold = currentFive
            }

            if let currentWeekly = appState.authStatus.thresholdWeeklyPercent {
                weeklyThreshold = currentWeekly
            }
        }
    }
}
