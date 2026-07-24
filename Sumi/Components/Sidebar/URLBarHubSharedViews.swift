import SwiftUI

/// Single-line URL-bar hub label.
struct URLBarTitleLabel: View {
    let text: String
    let font: Font
    let color: Color

    init(_ text: String, font: Font, color: Color) {
        self.text = text
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }
}
