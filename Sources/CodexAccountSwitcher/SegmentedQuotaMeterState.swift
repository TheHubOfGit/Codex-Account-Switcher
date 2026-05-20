import Foundation

struct SegmentedQuotaMeterState: Equatable {
    let value: Int?
    let segments: Int
    let paceSegments: Int

    var segmentCount: Int {
        max(segments, 0)
    }

    func fillAmount(for index: Int) -> Double {
        guard segmentCount > 0 else {
            return 0
        }

        let progress = min(max(Double(value ?? 0) / 100, 0), 1)
        let segmentStart = Double(index) / Double(segmentCount)
        let segmentEnd = Double(index + 1) / Double(segmentCount)

        if progress >= segmentEnd {
            return 1
        }

        if progress <= segmentStart {
            return 0
        }

        return (progress - segmentStart) * Double(segmentCount)
    }

    func isPaceSegment(_ index: Int) -> Bool {
        index >= 0 && index < min(max(paceSegments, 0), segmentCount)
    }
}
