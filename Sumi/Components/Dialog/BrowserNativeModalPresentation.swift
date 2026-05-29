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
    let icon: String
    let title: String
    let subtitle: String?
    let message: String

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        message: String
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.message = message
    }
}

struct BrowserNoticeSheet: View {
    let notice: BrowserNoticeSheetModel
    let onDismiss: () -> Void

    var body: some View {
        StandardDialog(
            header: {
                DialogHeader(
                    icon: notice.icon,
                    title: notice.title,
                    subtitle: notice.subtitle
                )
            },
            content: {
                Text(notice.message)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            },
            footer: {
                DialogFooter(rightButtons: [
                    DialogButton(
                        text: "OK",
                        variant: .primary,
                        keyboardShortcut: .return,
                        action: onDismiss
                    )
                ])
            }
        )
        .padding(20)
    }
}
