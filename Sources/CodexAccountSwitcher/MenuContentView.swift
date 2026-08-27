import SwiftUI

struct MenuContentView: View {
    private static let segmentedQuotaProgressBarHeight: CGFloat = 8

    @EnvironmentObject private var appState: AppState
    var onPreferredHeightChange: (CGFloat) -> Void = { _ in }
    var onAccountSwitchRequested: ((AccountSnapshot) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let setupIssue = appState.setupIssue {
                    setupStateView(setupIssue)
                } else {
                    headerView
                    fleetQuotaView
                    actionSection
                    accountsSection
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PreferredPopoverHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        .onPreferenceChange(PreferredPopoverHeightKey.self) { height in
            guard height > 0 else { return }
            onPreferredHeightChange(height)
        }
    }

    private var headerView: some View {
        PopoverHeaderView(
            activeAccount: appState.activeAccount,
            checkedAt: appState.lastSuccessfulRefreshAt,
            isRefreshing: appState.isRefreshing,
            errorMessage: appState.headerMessage,
            refreshAction: {
                Task { await appState.refreshAll() }
            }
        )
    }

    private var fleetQuotaView: some View {
        let summary = appState.fleetQuotaSummary
        let weeklyPaceSegments = appState.weeklyPaceDemoEnabled
            ? max(summary.weeklyPaceSegmentCount, 6)
            : summary.weeklyPaceSegmentCount
        let weeklyAverageValue = appState.weeklyPaceDemoEnabled
            ? demoWeeklyPaceValue(paceSegments: weeklyPaceSegments)
            : summary.averageWeeklyRemaining
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Text("Combined Quota")
                    .font(.headline)
                Spacer()
                Text("\(summary.freshAccounts)/\(summary.totalAccounts) fresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if summary.staleAccounts > 0 {
                    statusPill(
                        text: "\(summary.staleAccounts) stale",
                        tint: .orange
                    )
                }

                if summary.exhaustedAccounts > 0 {
                    statusPill(
                        text: "\(summary.exhaustedAccounts) exhausted",
                        tint: .red
                    )
                }
            }

            quotaMeter(
                title: "5h average",
                value: summary.averageFiveHourRemaining,
                lowValue: summary.lowestFiveHourRemaining
            )

            quotaMeter(
                title: "Weekly average",
                value: weeklyAverageValue,
                lowValue: summary.lowestWeeklyRemaining,
                progressSegments: 7,
                paceSegments: weeklyPaceSegments
            )

            if appState.weeklyPaceDemoEnabled {
                Text("Weekly pace alert demo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.m)
        .background(Color.codexCardFill, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let candidate = appState.bestAvailableAccount,
               candidate.accountKey != appState.activeAccount?.accountKey {
                Button {
                    requestAccountSwitch(candidate)
                } label: {
                    Label("Switch to \(candidate.primaryLabel)", systemImage: "arrow.left.arrow.right.circle")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.codexAccent)
                .controlSize(.regular)
                .disabled(
                    !appState.isCodexAuthSupported
                        || appState.isRefreshing
                        || appState.isSwitching
                        || appState.isRestarting
                )
                .accessibilityHint("Switches accounts and restarts Codex")
            }

            Toggle(isOn: Binding(
                get: { appState.autoMonitorEnabled },
                set: { enabled in
                    Task { await appState.setAutoMonitor(enabled: enabled) }
                }
            )) {
                Text("Auto Monitor")
            }
            .disabled(appState.isSavingSettings)

            Divider()

            HStack(spacing: Spacing.l) {
                Button("Settings…") {
                    appState.openSettings()
                }

                Spacer()

                Button(appState.isRestarting ? "Restarting…" : "Restart Codex") {
                    Task { await appState.restartCodex() }
                }
                .disabled(appState.isRestarting || appState.isSwitching)

                Button("Quit") {
                    appState.quit()
                }
            }
            .frame(minHeight: 28)
            .padding(.vertical, Spacing.xs)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)

            Divider()
        }
    }

    private var accountsSection: some View {
        let listedAccounts = accountsForList
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Text(appState.activeAccount == nil ? "Accounts" : "Other Accounts")
                    .font(.headline)
                Spacer()
                if !listedAccounts.isEmpty {
                    Text("\(listedAccounts.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if listedAccounts.isEmpty {
                Text(appState.accounts.isEmpty ? "No accounts found." : "No other accounts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(listedAccounts) { account in
                        AccountRow(
                            account: account,
                            isDisabled: !appState.isCodexAuthSupported
                                || appState.isSwitching
                                || appState.isRestarting
                                || account.isActive
                        ) {
                            requestAccountSwitch(account)
                        }
                    }
                }
            }
        }
    }

    private var accountsForList: [AccountSnapshot] {
        guard appState.activeAccount != nil else { return appState.accounts }
        return appState.accounts.filter { !$0.isActive }
    }

    private func requestAccountSwitch(_ account: AccountSnapshot) {
        if let onAccountSwitchRequested {
            onAccountSwitchRequested(account)
        } else {
            Task { await appState.switchToAccount(account) }
        }
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
    }

    private func quotaMeter(
        title: String,
        value: Int?,
        lowValue: Int?,
        progressSegments: Int? = nil,
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

        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(quotaAverageSummary(value: value, lowValue: lowValue))
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
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: setupIssueIconName(for: issue))
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 28, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(issue.title)
                        .font(.headline)
                    Text(issue.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: Spacing.m) {
                Button {
                    Task { await appState.refreshAll(showNotifications: false) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.codexAccent)
                .controlSize(.regular)

                Spacer()

                Button("Quit") {
                    appState.quit()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func setupIssueIconName(for issue: SetupIssue) -> String {
        switch issue {
        case .missingCodexAuth:
            return "terminal"
        case .missingRegistry:
            return "questionmark.folder"
        case .unreadableRegistry:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct PreferredPopoverHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


/// Header for the popover — renders the active account identity, two quota
/// pills, a last-refresh caption, and an optional error callout.
private struct PopoverHeaderView: View {
    let activeAccount: AccountSnapshot?
    let checkedAt: Date?
    let isRefreshing: Bool
    let errorMessage: String?
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(activeAccount?.primaryLabel ?? "No active account")
                    .font(.headline)
                    .lineLimit(1)
                    .layoutPriority(1)

                if let active = activeAccount, active.secondaryLabel == nil {
                    quotaIndicators(for: active)
                }

                Spacer()

                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(isRefreshing ? .degrees(360) : .zero)
                        .animation(
                            isRefreshing
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: isRefreshing
                        )
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help(isRefreshing ? "Refreshing quota" : "Refresh quota")
                .accessibilityLabel(isRefreshing ? "Refreshing quota" : "Refresh quota")
            }

            if let active = activeAccount {
                if let secondary = active.secondaryLabel {
                    HStack(spacing: Spacing.s) {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)

                        quotaIndicators(for: active)

                        Spacer(minLength: 0)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    FiveHourResetCaption(state: active.fiveHour)
                    WeeklyResetCaption(state: active.weekly)
                }

                ResetCreditsView(snapshot: active.resetCredits, presentation: .header)

                if let checkedAt {
                    Text("Checked \(checkedAt, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let lastRefresh = active.lastRefresh {
                    Text("Cached usage from \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Quota unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func quotaIndicators(for account: AccountSnapshot) -> some View {
        HStack(spacing: Spacing.s) {
            InlineQuotaBar(label: "5h", state: account.fiveHour)
            InlineQuotaBar(label: "Week", state: account.weekly)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}


/// Single account row in the popover list. Owns its own hover state so the
/// background tint updates as the cursor enters / leaves the row.
private struct AccountRow: View {
    let account: AccountSnapshot
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.s) {
                        Text(account.primaryLabel)
                            .fontWeight(account.isActive ? .semibold : .regular)
                            .lineLimit(1)
                            .layoutPriority(1)

                        if account.isUsageStale {
                            Label("Stale", systemImage: "clock.badge.exclamationmark")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, Spacing.s)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                        } else if account.hasResetPending() {
                            Label("Reset due", systemImage: "arrow.clockwise")
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, Spacing.s)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                        }

                        Spacer(minLength: 0)

                        PlanPill(label: account.planLabel)

                        if account.isActive {
                            ActivePill()
                        }
                    }

                    HStack(spacing: Spacing.s) {
                        if let secondary = account.secondaryLabel {
                            Text(secondary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }

                        quotaIndicators(for: account)

                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        FiveHourResetCaption(state: account.fiveHour)
                        WeeklyResetCaption(state: account.weekly)
                    }

                    ResetCreditsView(snapshot: account.resetCredits, presentation: .accountRow)
                }
            }
            .padding(.vertical, Spacing.s)
            .padding(.horizontal, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.medium)
                    .fill(Color.codexAccountFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.medium)
                            .fill(rowInteractionFill)
                    }
            }
            .contentShape(.rect(cornerRadius: Radius.medium))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(account.isActive ? "Current account" : "Switches accounts and restarts Codex")
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var rowInteractionFill: Color {
        if account.isActive {
            return Color.codexActiveFill
        }

        if isHovered && !isDisabled {
            return Color.codexHoverFill
        }

        return .clear
    }

    private var accessibilitySummary: String {
        var parts = [account.primaryLabel, account.planLabel]
        if account.isActive { parts.append("active") }
        if account.isUsageStale { parts.append("quota data stale") }
        if account.hasResetPending() { parts.append("quota reset due") }
        parts.append("5-hour \(QuotaSummary.fiveHourLimitLeft(for: account.fiveHour))")
        parts.append("weekly \(QuotaSummary.weeklyLimitLeft(for: account.weekly))")
        parts.append("usage limit resets \(ResetCreditsSummary.availability(for: account.resetCredits))")
        parts.append(contentsOf: ResetCreditsSummary.expiryLines(for: account.resetCredits))
        return parts.joined(separator: ", ")
    }

    private func quotaIndicators(for account: AccountSnapshot) -> some View {
        HStack(spacing: Spacing.s) {
            InlineQuotaBar(label: "5h", state: account.fiveHour)
            InlineQuotaBar(label: "Week", state: account.weekly)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Trailing "Active" pill shown on the active account row.
private struct ActivePill: View {
    var body: some View {
        Text("Active")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
            .background(Color.codexAccent.opacity(0.15), in: Capsule())
    }
}

/// Outlined plan capsule (e.g. "Plus", "Pro", "Unknown").
private struct PlanPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
            .overlay(
                Capsule()
                    .strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5)
            )
    }
}
