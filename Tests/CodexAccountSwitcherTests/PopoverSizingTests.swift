import Testing
@testable import CodexAccountSwitcher

struct PopoverSizingTests {
    @Test
    func growsToFitContentWhenScreenHasRoom() {
        #expect(
            PopoverSizing.height(contentHeight: 742.2, availableScreenHeight: 900)
                == 743
        )
    }

    @Test
    func capsHeightToUsableScreen() {
        #expect(
            PopoverSizing.height(contentHeight: 1_200, availableScreenHeight: 800)
                == 784
        )
    }

    @Test
    func keepsSparseContentUsable() {
        #expect(
            PopoverSizing.height(contentHeight: 200, availableScreenHeight: 900)
                == PopoverSizing.minimumHeight
        )
    }
}
