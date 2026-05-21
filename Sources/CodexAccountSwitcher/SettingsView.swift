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

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { appState.backgroundRefreshEnabled },
                    set: { appState.setBackgroundRefresh(enabled: $0) }
                )) {
                    Text("Enable Background Refresh")
                }

                Picker(
                    "Refresh every",
                    selection: Binding(
                        get: { appState.backgroundRefreshIntervalMinutes },
                        set: { appState.setBackgroundRefreshInterval(minutes: $0) }
                    )
                ) {
                    ForEach(AppState.backgroundRefreshIntervalOptions, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!appState.backgroundRefreshEnabled)

                Text("Runs the same quota refresh as the manual button, so fresh and stale accounts can both update when codex-auth returns newer usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { appState.quotaPrimerEnabled },
                    set: { appState.setQuotaPrimer(enabled: $0) }
                )) {
                    Text("Enable Scheduled Quota Primer")
                }

                Picker(
                    "Check every",
                    selection: Binding(
                        get: { appState.quotaPrimerIntervalMinutes },
                        set: { appState.setQuotaPrimerInterval(minutes: $0) }
                    )
                ) {
                    ForEach(AppState.quotaPrimerIntervalOptions, id: \.self) { minutes in
                        Text(quotaPrimerIntervalLabel(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!appState.quotaPrimerEnabled)

                HStack(spacing: 12) {
                    Button(appState.isPrimingQuota ? "Priming…" : "Prime Accounts Now") {
                        Task { await appState.runManualQuotaPrimerNow() }
                    }
                    .disabled(!appState.quotaPrimerEnabled || appState.isPrimingQuota || appState.isRefreshing || appState.isSwitching)
                }

                if let message = appState.lastQuotaPrimerStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(appState.isPrimingQuota ? .blue : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("The manual button primes every usable account now. Scheduled runs only prime accounts with missing quota data or a reset time that has passed. Each primer uses isolated stored auth and consumes real Codex usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    private func quotaPrimerIntervalLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        }

        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}
