import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var weeklyThreshold = 5
    @State private var showsPrimerConfirmation = false

    var body: some View {
        Form {
            monitoringSection
            backgroundRefreshSection
            quotaPrimerSection
            diagnosticsSection
#if DEBUG
            developerSection
#endif
        }
        .formStyle(.grouped)
        .onAppear {
            weeklyThreshold = appState.monitorWeeklyThreshold
        }
        .confirmationDialog(
            "Prime all accounts?",
            isPresented: $showsPrimerConfirmation,
            titleVisibility: .visible
        ) {
            Button("Prime All Accounts") {
                Task { await appState.primeAllAccounts() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sends one isolated minimal Codex request from each account. The active account and Codex app remain untouched. Each request consumes real quota.")
        }
    }

    // MARK: - Monitoring

    private var monitoringSection: some View {
        Section("Monitoring") {
            Toggle(isOn: Binding(
                get: { appState.autoMonitorEnabled },
                set: { enabled in
                    Task { await appState.setAutoMonitor(enabled: enabled) }
                }
            )) {
                Text("Ask Before Switching")
            }
            .disabled(appState.isSavingSettings)
            .accessibilityLabel("Ask before switching accounts")

            if appState.externalAutoSwitchEnabled {
                Label(
                    "codex-auth automatic switching is also enabled. Turn it off to avoid competing switches.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)

                Button("Turn Off Automatic Service") {
                    Task { await appState.disableExternalAutoSwitch() }
                }
            }

            Stepper(value: $weeklyThreshold, in: 1...100) {
                LabeledContent("Weekly threshold") {
                    Text("\(weeklyThreshold)% remaining")
                        .monospacedDigit()
                }
            }

            Button("Save Monitoring Thresholds") {
                Task {
                    await appState.saveThresholds(
                        fiveHour: appState.monitorFiveHourThreshold,
                        weekly: weeklyThreshold
                    )
                }
            }
            .disabled(
                appState.isSavingSettings
                    || weeklyThreshold == appState.monitorWeeklyThreshold
            )
        }
    }

    // MARK: - Background Refresh

    @ViewBuilder
    private var backgroundRefreshSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.backgroundRefreshEnabled },
                set: { appState.setBackgroundRefresh(enabled: $0) }
            )) {
                Text("Background Refresh")
            }
            .accessibilityLabel("Refresh quota in the background")

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
            .accessibilityLabel("Background refresh interval")
        } header: {
            Text("Background Refresh")
        } footer: {
            Text("Runs the same quota refresh as the manual button, so fresh and stale accounts can both update when codex-auth returns newer usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Quota Primer

    @ViewBuilder
    private var quotaPrimerSection: some View {
        Section {
            Button {
                showsPrimerConfirmation = true
            } label: {
                Label(
                    appState.isPrimingQuota ? "Priming All Accounts…" : "Prime All Accounts…",
                    systemImage: "bolt.fill"
                )
            }
            .disabled(
                !appState.isCodexAuthSupported
                    || appState.activeAccount == nil
                    || appState.accounts.isEmpty
                    || appState.isPrimingQuota
                    || appState.isRefreshing
                    || appState.isSwitching
            )

            if let message = appState.lastQuotaPrimerStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(appState.isPrimingQuota ? .blue : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Quota Primer")
        } footer: {
            Text("Sends one verified isolated message from every stored account without switching the active account or restarting Codex. Scheduled priming remains disabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Diagnostics

    @ViewBuilder
    private var diagnosticsSection: some View {
        Section {
            LabeledContent("codex-auth") {
                Text(appState.codexAuthVersionLabel ?? "Checking…")
                    .foregroundStyle(appState.isCodexAuthSupported ? Color.secondary : Color.orange)
            }

            if !appState.isCodexAuthSupported {
                Text("Install version 0.2.10 or newer, then refresh status. Cached accounts remain visible, but switching is disabled.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            LabeledContent("Usage Mode") {
                HStack(spacing: Spacing.s) {
                    Circle()
                        .fill(usageModeColor)
                        .frame(width: 8, height: 8)
                    Text(appState.usageModeLabel)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("Automatic Service") {
                Text(appState.externalAutoSwitchEnabled ? "Enabled" : "Off")
                    .foregroundStyle(appState.externalAutoSwitchEnabled ? .orange : .secondary)
            }

            HStack {
                Spacer()
                Button {
                    Task { await appState.refreshAll(showNotifications: false) }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            if let error = appState.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            usageModeFooter
        }
    }

    @ViewBuilder
    private var usageModeFooter: some View {
        if appState.usageModeLabel == UsageMode.local.displayName {
            Text("Quota freshness may lag because codex-auth is using local rollout data instead of the API-backed refresh mode.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if appState.usageModeLabel == UsageMode.api.displayName {
            Text("API-backed refresh is controlled by codex-auth. It sends stored access tokens to OpenAI endpoints; codex-auth warns this can carry account-policy risk. This app does not change the mode silently.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("The quota refresh source is not yet known.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var usageModeColor: Color {
        if appState.usageModeLabel == UsageMode.api.displayName {
            return .green
        }

        if appState.usageModeLabel == UsageMode.local.displayName {
            return .orange
        }

        return .secondary
    }

    // MARK: - Developer

    @ViewBuilder
    private var developerSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.weeklyPaceDemoEnabled },
                set: { appState.setWeeklyPaceDemo(enabled: $0) }
            )) {
                Text("Demo Weekly Pace Alert")
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Temporarily shows the weekly average bar and strength gauge in the exceed-pace alert state without changing account data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func quotaPrimerIntervalLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) minutes"
        }

        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}
