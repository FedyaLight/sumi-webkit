import SwiftUI

struct URLBarFadingText: View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask(
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 18)
                }
            )
    }
}
