import SwiftUI

struct SumiTabTitleLabel: View {
    let title: String
    var font: Font = .system(size: 13, weight: .medium)
    var textColor: Color = .primary
    var reservedTrailingWidth: CGFloat = 0
    var animated: Bool = true
    var height: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sumiSettings) private var sumiSettings

    var body: some View {
        Text(title)
            .font(font)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.trailing, reservedTrailingWidth)
            .frame(
                maxWidth: .infinity,
                minHeight: height,
                maxHeight: height,
                alignment: .leading
            )
            .contentTransition(.opacity)
            .animation(titleAnimation, value: title)
            .accessibilityLabel(title)
    }

    private var titleAnimation: Animation? {
        guard animated, !reduceMotion, !sumiSettings.shouldReduceChromeMotion else {
            return nil
        }
        return .easeInOut(duration: 0.2)
    }
}
