import Foundation

struct MenuBarQuotaMeterState: Equatable {
    let remainingPercent: Int?
    let isStale: Bool

    init(activeAccount: AccountSnapshot?) {
        self.init(
            remainingPercent: activeAccount?.fiveHour.remainingPercent,
            isStale: activeAccount?.fiveHour.isStale ?? false
        )
    }

    init(remainingPercent: Int?, isStale: Bool) {
        self.remainingPercent = remainingPercent
        self.isStale = isStale
    }

    var fillFraction: Double {
        guard let remainingPercent else {
            return 0
        }

        return min(max(Double(remainingPercent) / 100, 0), 1)
    }

    var accessibilityDescription: String {
        guard let remainingPercent else {
            return "5 hour limit unavailable"
        }

        let staleDetail = isStale ? ", stale" : ""
        return "5 hour limit \(remainingPercent) percent left\(staleDetail)"
    }
}
