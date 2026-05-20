import SwiftUI

struct MenuContentView: View {
    private static let segmentedQuotaProgressBarHeight: CGFloat = 8

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
        let weeklyPaceSegments = appState.weeklyPaceDemoEnabled
            ? max(summary.weeklyPaceSegmentCount, 6)
            : summary.weeklyPaceSegmentCount
        let weeklyAverageValue = appState.weeklyPaceDemoEnabled
            ? demoWeeklyPaceValue(paceSegments: weeklyPaceSegments)
            : summary.averageWeeklyRemaining
        let weeklyStrengthValue = appState.weeklyPaceDemoEnabled
            ? demoWeeklyPaceValue(paceSegments: weeklyPaceSegments)
            : summary.averageWeeklyStrength

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
                value: weeklyAverageValue,
                lowValue: summary.lowestWeeklyRemaining,
                strengthValue: weeklyStrengthValue,
                progressSegments: 7,
                strengthSegments: 7,
                paceSegments: weeklyPaceSegments
            )

            if appState.weeklyPaceDemoEnabled {
                Text("Weekly pace alert demo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    private func quotaMeterWithStrength(
        title: String,
        value: Int?,
        lowValue: Int?,
        strengthValue: Int?,
        progressSegments: Int? = nil,
        strengthSegments: Int? = nil,
        paceSegments: Int = 0
    ) -> some View {
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

                quotaProgressBar(value: value, segments: progressSegments, paceSegments: paceSegments)
            }
            .frame(maxWidth: .infinity)

            strengthGauge(value: strengthValue, segments: strengthSegments, paceSegments: paceSegments)
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

    private func demoWeeklyPaceValue(paceSegments: Int) -> Int {
        let pacePercent = Int((Double(max(paceSegments, 1)) / 7 * 100).rounded(.down))
        return max(1, pacePercent - 8)
    }

    @ViewBuilder
    private func quotaProgressBar(value: Int?, segments: Int? = nil, paceSegments: Int = 0) -> some View {
        if let segments, segments > 1 {
            segmentedProgressBar(value: value, segments: segments, paceSegments: paceSegments)
        } else {
            ProgressView(value: Double(value ?? 0), total: 100)
                .tint(quotaTint(for: value))
        }
    }

    private func segmentedProgressBar(value: Int?, segments: Int, paceSegments: Int) -> some View {
        let state = SegmentedQuotaMeterState(value: value, segments: segments, paceSegments: paceSegments)
        let isPaceAlert = isInPaceAlertZone(value: value, segments: segments, paceSegments: paceSegments)

        return HStack(spacing: 2) {
            ForEach(0..<state.segmentCount, id: \.self) { index in
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.18))

                        Capsule()
                            .fill(segmentedQuotaFillColor(
                                isPaceSegment: state.isPaceSegment(index),
                                isPaceAlert: isPaceAlert,
                                value: value
                            ))
                            .frame(width: proxy.size.width * state.fillAmount(for: index))
                    }
                }
            }
        }
        .frame(height: Self.segmentedQuotaProgressBarHeight)
    }

    private func strengthGauge(value: Int?, segments: Int? = nil, paceSegments: Int = 0) -> some View {
        let isPaceAlert = isInPaceAlertZone(value: value, segments: segments, paceSegments: paceSegments)

        return ZStack {
            if isPaceAlert {
                Circle()
                    .fill(Color(red: 0.95, green: 0.72, blue: 0.16))
                    .padding(6)
            }

            if let segments, segments > 1 {
                segmentedGaugeRing(value: value, segments: segments, paceSegments: paceSegments)
            } else {
                Circle()
                    .stroke(.quaternary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(Double(value ?? 0) / 100))
                    .stroke(
                        quotaTint(for: value),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Text(value.map(String.init) ?? "--")
                .font(.caption2.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(isPaceAlert ? .black : .primary)
        }
        .frame(width: 38, height: 38)
        .frame(width: 50)
    }

    private func isInPaceAlertZone(value: Int?, segments: Int?, paceSegments: Int) -> Bool {
        guard let value,
              let segments,
              segments > 1,
              paceSegments > 0 else {
            return false
        }

        return Double(value) / 100 <= Double(paceSegments) / Double(segments)
    }

    private func segmentedGaugeRing(value: Int?, segments: Int, paceSegments: Int) -> some View {
        let state = SegmentedQuotaMeterState(value: value, segments: segments, paceSegments: paceSegments)
        let isPaceAlert = isInPaceAlertZone(value: value, segments: segments, paceSegments: paceSegments)
        let gap = 0.035
        let segmentSpan = 1 / Double(segments)
        let visibleSpan = max(0, segmentSpan - gap)

        return ZStack {
            ForEach(0..<segments, id: \.self) { index in
                let start = (Double(index) * segmentSpan) + (gap / 2)
                let end = start + visibleSpan

                Circle()
                    .trim(from: start, to: end)
                    .stroke(
                        Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )

                Circle()
                    .trim(
                        from: start,
                        to: start + (visibleSpan * state.fillAmount(for: index))
                    )
                    .stroke(
                        segmentedQuotaFillColor(
                            isPaceSegment: state.isPaceSegment(index),
                            isPaceAlert: isPaceAlert,
                            value: value
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
            }
        }
        .rotationEffect(.degrees(-90))
    }

    private func segmentedQuotaFillColor(isPaceSegment: Bool, isPaceAlert: Bool, value: Int?) -> Color {
        if isPaceAlert {
            return isPaceSegment ? Color(red: 0.78, green: 0.56, blue: 0.10) : quotaTint(for: value)
        }

        return isPaceSegment ? .green : Color(red: 0.78, green: 0.56, blue: 0.10)
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
