import Testing
@testable import CodexAccountSwitcher

struct SegmentedQuotaMeterTests {
    @Test
    func segmentFillUsesRawRemainingProgressAcrossSevenSegments() {
        let state = SegmentedQuotaMeterState(value: 50, segments: 7, paceSegments: 3)

        #expect(state.fillAmount(for: 0) == 1)
        #expect(state.fillAmount(for: 1) == 1)
        #expect(state.fillAmount(for: 2) == 1)
        #expect(abs(state.fillAmount(for: 3) - 0.5) < 0.0001)
        #expect(state.fillAmount(for: 4) == 0)
    }

    @Test
    func segmentFillClampsUnavailableAndOutOfRangeValues() {
        let unavailable = SegmentedQuotaMeterState(value: nil, segments: 7, paceSegments: 2)
        let overFull = SegmentedQuotaMeterState(value: 125, segments: 7, paceSegments: 2)
        let exhausted = SegmentedQuotaMeterState(value: -10, segments: 7, paceSegments: 2)

        #expect(unavailable.fillAmount(for: 0) == 0)
        #expect(overFull.fillAmount(for: 6) == 1)
        #expect(exhausted.fillAmount(for: 0) == 0)
    }

    @Test
    func paceSegmentsClampToAvailableSegments() {
        let state = SegmentedQuotaMeterState(value: 80, segments: 7, paceSegments: 12)

        #expect(state.isPaceSegment(0))
        #expect(state.isPaceSegment(6))
    }
}
