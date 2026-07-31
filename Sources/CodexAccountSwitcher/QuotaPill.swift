import SwiftUI

/// Compact pill used for displaying a quota window summary inside the popover.
/// One pill per window — used in both the active-account header and the
/// per-account list rows so the typography stays consistent across the popover.
struct QuotaPill: View {
    enum Size {
        case regular
        case compact
    }

    let label: String
    let summary: String
    var size: Size = .regular

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .fontWeight(.medium)
            Text(summary)
        }
        .font(font)
        .foregroundStyle(.primary)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(.quaternary.opacity(0.8), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(summary)")
    }

    private var font: Font {
        switch size {
        case .regular:
            return .caption
        case .compact:
            return .caption2
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .regular:
            return 8
        case .compact:
            return 6
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .regular:
            return 4
        case .compact:
            return 2
        }
    }
}

/// A dense weekly quota indicator that sits beside an account email.
struct InlineWeeklyQuotaBar: View {
    let state: QuotaWindowState

    var body: some View {
        HStack(spacing: Spacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    Capsule()
                        .fill(fillColor)
                        .frame(width: proxy.size.width * fillFraction)
                }
            }
            .frame(width: 42, height: 6)

            Text(state.remainingPercent.map { "\($0)%" } ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .fixedSize()
        .opacity(state.isStale ? 0.7 : 1)
        .help("Weekly \(QuotaSummary.weeklyLimitLeft(for: state))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly quota")
        .accessibilityValue(QuotaSummary.weeklyLimitLeft(for: state))
    }

    private var fillFraction: CGFloat {
        CGFloat(state.remainingPercent ?? 0) / 100
    }

    private var fillColor: Color {
        guard let remaining = state.remainingPercent else {
            return .secondary
        }

        if state.isStale {
            return .secondary
        }

        if remaining <= 10 {
            return .red
        }

        if remaining <= 30 {
            return .orange
        }

        return .green
    }
}

/// Exact weekly reset timing shown beneath each account identity.
struct WeeklyResetCaption: View {
    let state: QuotaWindowState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Label {
                Text(caption(now: context.date))
                    .monospacedDigit()
            } icon: {
                Image(systemName: state.isResetPending(at: context.date) ? "arrow.clockwise" : "clock")
            }
            .font(.caption2)
            .foregroundStyle(
                state.isResetPending(at: context.date) ? Color.orange : Color.secondary
            )
            .help(accessibilityValue(now: context.date))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly quota reset")
            .accessibilityValue(accessibilityValue(now: context.date))
        }
    }

    private func caption(now: Date) -> String {
        guard let resetAt = state.resetAt else {
            return "Reset time unavailable"
        }

        let prefix = state.isResetPending(at: now) ? "Reset due" : "Resets"
        let distance = QuotaSummary.compactResetDistance(resetAt: resetAt, now: now)
        let cachedSuffix = state.isStale(at: now) ? " · cached" : ""
        return "\(prefix) \(formatted(resetAt)) · \(distance)\(cachedSuffix)"
    }

    private func accessibilityValue(now: Date) -> String {
        guard let resetAt = state.resetAt else {
            return "Unavailable"
        }

        let distance = QuotaSummary.compactResetDistance(resetAt: resetAt, now: now)
        let cachedSuffix = state.isStale(at: now) ? ", cached data" : ""
        return "\(resetAt.formatted(date: .complete, time: .shortened)), \(distance)\(cachedSuffix)"
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }
}
