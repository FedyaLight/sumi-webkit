import AppKit
import SwiftUI

@MainActor
enum BrowserNativeModalKind {
    case browsingData
    case basicAuth(BasicAuthSheetSession)
    case notice(BrowserNoticeSheetModel)
}

@MainActor
final class BrowserNativeModalPresentation: Identifiable {
    let id = UUID()
    let windowID: UUID
    let kind: BrowserNativeModalKind
    let source: SidebarTransientPresentationSource?
    let transientSessionToken: SidebarTransientSessionToken?
    let onDismiss: (() -> Void)?
    weak var window: NSWindow?

    init(
        windowID: UUID,
        window: NSWindow?,
        kind: BrowserNativeModalKind,
        source: SidebarTransientPresentationSource?,
        transientSessionToken: SidebarTransientSessionToken?,
        onDismiss: (() -> Void)? = nil
    ) {
        self.windowID = windowID
        self.window = window
        self.kind = kind
        self.source = source
        self.transientSessionToken = transientSessionToken
        self.onDismiss = onDismiss
    }
}

struct BrowserNoticeSheetModel {
    let title: String
    let subtitle: String?
    let message: String

    init(
        title: String,
        subtitle: String? = nil,
        message: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.message = message
    }
}

struct BrowserNoticeSheet: View {
    let notice: BrowserNoticeSheetModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(notice.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                if let subtitle = notice.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(notice.message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("OK") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 430, alignment: .leading)
    }
}
