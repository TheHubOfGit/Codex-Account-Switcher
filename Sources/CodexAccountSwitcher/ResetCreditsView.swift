import SwiftUI

struct ResetCreditsView: View {
    enum Presentation {
        case header
        case accountRow
    }

    let snapshot: RateLimitResetCreditsSnapshot?
    let presentation: Presentation
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: presentation == .header ? Spacing.s : Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(Color.codexAccent)
                    .accessibilityHidden(true)

                Text("Usage resets")
                    .font(presentation == .header ? .caption.weight(.semibold) : .caption2.weight(.semibold))

                Spacer(minLength: Spacing.s)

                Text(availabilityText)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(snapshot == nil ? .secondary : .primary)
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 2)
                    .background(Color.codexAccent.opacity(0.13), in: Capsule())
            }

            if credits.isEmpty {
                if (snapshot?.availableCount ?? 0) > 0 {
                    Label("Expiry dates unavailable", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(
                    columns: gridColumns,
                    alignment: .leading,
                    spacing: Spacing.xs
                ) {
                    ForEach(credits) { credit in
                        ResetExpiryChip(credit: credit, now: now)
                    }
                }
            }
        }
        .padding(presentation == .header ? Spacing.m : Spacing.s)
        .background(
            Color.codexResetFill,
            in: RoundedRectangle(cornerRadius: presentation == .header ? Radius.card : Radius.small)
        )
        .accessibilityElement(children: .combine)
    }

    private var credits: [RateLimitResetCredit] {
        snapshot?.credits.filter {
            $0.status?.lowercased() == "available" || $0.status == nil
        } ?? []
    }

    private var availabilityText: String {
        guard let snapshot else { return "Unavailable" }
        let count = snapshot.availableCount
        let countText = count == 1 ? "1 available" : "\(count) available"
        return now.timeIntervalSince(snapshot.checkedAt) > 30 * 60
            ? "\(countText) · cached"
            : countText
    }

    private var gridColumns: [GridItem] {
        let count = min(max(credits.count, 1), 4)
        return Array(
            repeating: GridItem(.flexible(minimum: 68), spacing: Spacing.xs),
            count: count
        )
    }
}

private struct ResetExpiryChip: View {
    let credit: RateLimitResetCredit
    let now: Date

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "calendar")
                .font(.caption2)
                .foregroundStyle(expiryColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    "\(ResetCreditsSummary.expiryDate(for: credit)) · "
                        + ResetCreditsSummary.expiryTime(for: credit)
                )
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                Text(ResetCreditsSummary.timeUntilExpiry(for: credit, now: now))
                    .font(.caption2)
                    .foregroundStyle(expiryColor)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: Radius.small))
    }

    private var expiryColor: Color {
        ResetCreditsSummary.isExpiringSoon(credit, now: now) ? .orange : .secondary
    }
}
