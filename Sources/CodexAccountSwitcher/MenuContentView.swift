import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let setupIssue = appState.setupIssue {
                setupStateView(setupIssue)
            } else {
                headerView
                fleetQuotaView
                actionSection
                Divider()
                accountsSection
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appState.activeAccount?.primaryLabel ?? "No active account")
                .font(.headline)

            if let active = appState.activeAccount {
                if let secondary = active.secondaryLabel {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    quotaBadge(title: "5h", summary: QuotaSummary.fiveHourLimitLeft(for: active.fiveHour))
                    quotaBadge(title: "Week", summary: QuotaSummary.weeklyLimitLeft(for: active.weekly))
                }

                Text("Auto Monitor: \(appState.autoMonitorEnabled ? "On" : "Off")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastRefresh = active.lastRefresh {
                    Text("Last refresh \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Quota unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let lastError = appState.lastErrorMessage {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fleetQuotaView: some View {
        let summary = appState.fleetQuotaSummary

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Combined Quota")
                    .font(.headline)
                Spacer()
                Text("\(summary.freshAccounts)/\(summary.totalAccounts) fresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Text("Strength")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 50)
            }

            quotaMeterWithStrength(
                title: "5h average",
                value: summary.averageFiveHourRemaining,
                lowValue: summary.lowestFiveHourRemaining,
                strengthValue: summary.averageFiveHourStrength
            )
            quotaMeterWithStrength(
                title: "Weekly average",
                value: summary.averageWeeklyRemaining,
                lowValue: summary.lowestWeeklyRemaining,
                strengthValue: summary.averageWeeklyStrength
            )

            if summary.exhaustedAccounts > 0 || summary.staleAccounts > 0 {
                Text("\(summary.exhaustedAccounts) exhausted / \(summary.staleAccounts) stale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(appState.isRefreshing ? "Refreshing…" : "Refresh Quota") {
                Task { await appState.refreshAll() }
            }
            .disabled(appState.isRefreshing || appState.isSwitching)

            Button("Switch to Lowest Eligible") {
                Task { await appState.switchToBestAvailable() }
            }
            .disabled(appState.isRefreshing || appState.isSwitching || appState.bestAvailableAccount == nil)

            Button("Restart Codex") {
                Task { await appState.restartCodex() }
            }
            .disabled(appState.isSwitching)

            Toggle(isOn: Binding(
                get: { appState.autoMonitorEnabled },
                set: { enabled in
                    Task { await appState.setAutoMonitor(enabled: enabled) }
                }
            )) {
                Text("Auto Monitor")
            }
            .disabled(appState.isSavingSettings)

            HStack(spacing: 12) {
                Button("Settings…") {
                    appState.openSettings()
                }

                Button("Quit") {
                    appState.quit()
                }
            }
            .buttonStyle(.link)
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts")
                .font(.headline)

            if appState.accounts.isEmpty {
                Text("No accounts found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.accounts) { account in
                    Button {
                        Task { await appState.switchToAccount(account) }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: account.isActive ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(account.isActive ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(account.primaryLabel)
                                        .fontWeight(account.isActive ? .semibold : .regular)
                                    Spacer()
                                    Text(account.planLabel)
                                        .foregroundStyle(.secondary)
                                }

                                if let secondary = account.secondaryLabel {
                                    Text(secondary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 10) {
                                    Text("5h \(QuotaSummary.fiveHourLimitLeft(for: account.fiveHour))")
                                    Text("Week \(QuotaSummary.weeklyLimitLeft(for: account.weekly))")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isSwitching)
                }
            }
        }
    }

    private func quotaBadge(title: String, state: QuotaWindowState) -> some View {
        quotaBadge(title: title, summary: quotaSummary(for: state))
    }

    private func quotaBadge(title: String, summary: String) -> some View {
        Text("\(title) \(summary)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.8), in: Capsule())
    }

    private func quotaMeterWithStrength(title: String, value: Int?, lowValue: Int?, strengthValue: Int?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(quotaAverageSummary(value: value, lowValue: lowValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(value ?? 0), total: 100)
                    .tint(quotaTint(for: value))
            }
            .frame(maxWidth: .infinity)

            strengthGauge(value: strengthValue)
        }
    }

    private func quotaSummary(for state: QuotaWindowState) -> String {
        QuotaSummary.limitLeft(for: state)
    }

    private func quotaAverageSummary(value: Int?, lowValue: Int?) -> String {
        guard let value else {
            return "Unavailable"
        }

        if let lowValue {
            return "\(value)% avg / \(lowValue)% low"
        }

        return "\(value)% avg"
    }

    private func strengthGauge(value: Int?) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(Double(value ?? 0) / 100))
                .stroke(
                    quotaTint(for: value),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(value.map(String.init) ?? "--")
                .font(.caption2.monospacedDigit())
                .fontWeight(.semibold)
        }
        .frame(width: 38, height: 38)
        .frame(width: 50)
    }

    private func quotaTint(for value: Int?) -> Color {
        guard let value else {
            return .secondary
        }

        if value <= 10 {
            return .red
        }

        if value <= 30 {
            return .orange
        }

        return .green
    }

    private func setupStateView(_ issue: SetupIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(issue.title)
                .font(.headline)
            Text(issue.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Retry") {
                    Task { await appState.refreshAll(showNotifications: false) }
                }

                Button("Quit") {
                    appState.quit()
                }
                .buttonStyle(.link)
            }
        }
    }
}
