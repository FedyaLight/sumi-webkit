import SwiftUI

struct SumiBoostFontGrid: View {
    @ObservedObject var session: SumiBoostEditorSession
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(session.commonFontFamilies, id: \.self) { family in
                    Button {
                        toggleFont(family)
                    } label: {
                        Text("Aa")
                            .font(.custom(family, size: 14))
                            .fontWeight(fontWeight(for: family))
                            .foregroundStyle(SumiBoostEditorStyle.primaryText(for: colorScheme))
                            .frame(width: 25, height: 24)
                            .background(
                                session.boost.data.fontFamily == family
                                    ? Color.primary.opacity(0.12)
                                    : Color.clear
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(family)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle()
                .fill(SumiBoostEditorStyle.border(for: colorScheme))
                .frame(height: 1)
                .padding(.horizontal, 12)

            Picker(
                "Font",
                selection: Binding(
                    get: { session.boost.data.fontFamily },
                    set: { session.setFontFamily($0) }
                )
            ) {
                Text("Default").tag("")
                ForEach(session.fontFamilies.filter { !$0.isEmpty }, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .frame(height: 30)
        }
        .frame(height: 126)
        .background(SumiBoostEditorStyle.fontBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 8, y: 3)
    }

    private func toggleFont(_ family: String) {
        session.setFontFamily(session.boost.data.fontFamily == family ? "" : family)
    }

    private func fontWeight(for family: String) -> Font.Weight {
        switch family {
        case "Impact", "Arial Black":
            return .bold
        default:
            return .regular
        }
    }
}
