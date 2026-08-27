import SwiftUI

/// Compact pill primitive for displaying a quota window summary inside the
/// popover when a text-first presentation is appropriate.
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

/// A dense quota indicator that sits beside an account identity.
///
/// The label is intentionally short (for example, "5h" or "Week") so both
/// windows can be shown together without turning account rows into a second
/// dashboard.
struct InlineQuotaBar: View {
    let label: String
    let state: QuotaWindowState

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))

                    Capsule()
                        .fill(fillColor)
                        .frame(width: proxy.size.width * fillFraction)
                }
            }
            .frame(width: 30, height: 6)

            Text(state.remainingPercent.map { "\($0)%" } ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .fixedSize()
        .opacity(state.isStale ? 0.7 : 1)
        .help("\(label) \(summary)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) quota")
        .accessibilityValue(summary)
    }

    private var summary: String {
        switch label {
        case "5h":
            return QuotaSummary.fiveHourLimitLeft(for: state)
        default:
            return QuotaSummary.weeklyLimitLeft(for: state)
        }
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

/// Backwards-compatible weekly spelling for call sites that only show the
/// weekly window.
struct InlineWeeklyQuotaBar: View {
    let state: QuotaWindowState

    var body: some View {
        InlineQuotaBar(label: "Week", state: state)
    }
}

/// Exact reset timing shown beneath each account identity.
struct QuotaResetCaption: View {
    enum Window {
        case fiveHour
        case weekly

        var label: String {
            switch self {
            case .fiveHour:
                return "5h"
            case .weekly:
                return "Weekly"
            }
        }
    }

    let state: QuotaWindowState
    let window: Window

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
            .accessibilityLabel("\(window.label) quota reset")
            .accessibilityValue(accessibilityValue(now: context.date))
        }
    }

    private func caption(now: Date) -> String {
        guard let resetAt = state.resetAt else {
            return "Reset time unavailable"
        }

        let prefix = state.isResetPending(at: now)
            ? "\(window.label) reset due"
            : "\(window.label) resets"
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

struct FiveHourResetCaption: View {
    let state: QuotaWindowState

    var body: some View {
        QuotaResetCaption(state: state, window: .fiveHour)
    }
}

struct WeeklyResetCaption: View {
    let state: QuotaWindowState

    var body: some View {
        QuotaResetCaption(state: state, window: .weekly)
    }
}
