import SwiftUI
import SumiDomain

/// UI rendering for profile emoji / default-dot icons.
/// Lives in Components so Models stay Foundation-only.
struct SumiProfileIconView: View {
    let icon: String
    var font: Font = .body

    var body: some View {
        if SumiProfileIcon.usesDefaultIcon(icon) {
            Circle()
                .fill(.primary)
                .frame(
                    width: SumiProfileIcon.defaultDotDiameter,
                    height: SumiProfileIcon.defaultDotDiameter
                )
        } else {
            Text(SumiProfileIcon.storedValue(icon))
                .font(font)
        }
    }
}
