import CoreGraphics

enum PopoverSizing {
    static let width: CGFloat = 400
    static let minimumHeight: CGFloat = 420
    static let screenMargin: CGFloat = 16

    static func height(contentHeight: CGFloat, availableScreenHeight: CGFloat) -> CGFloat {
        let maximumHeight = max(
            minimumHeight,
            availableScreenHeight - screenMargin
        )
        return min(max(ceil(contentHeight), minimumHeight), maximumHeight)
    }
}
