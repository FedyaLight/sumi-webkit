import Foundation

struct BrowserNotificationAction {
    let label: String
    let handler: @MainActor () -> Void
}

enum BrowserNotificationControlKind {
    case systemImage(String)
    case text(String)
}

struct BrowserNotificationControl: Identifiable {
    let id: String
    let kind: BrowserNotificationControlKind
    let accessibilityLabel: String
    let handler: @MainActor () -> Void
    let dismissesOnActivate: Bool
    let isDisabled: Bool

    init(
        id: String,
        kind: BrowserNotificationControlKind,
        accessibilityLabel: String,
        dismissesOnActivate: Bool = false,
        isDisabled: Bool = false,
        handler: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel
        self.dismissesOnActivate = dismissesOnActivate
        self.isDisabled = isDisabled
        self.handler = handler
    }
}

struct BrowserNotification: Identifiable {
    let id: UUID
    let messageKey: String
    let title: String
    let subtitle: String?
    let duration: TimeInterval
    let action: BrowserNotificationAction?
    let controls: [BrowserNotificationControl]?
    let icon: String?

    init(
        id: UUID = UUID(),
        messageKey: String,
        title: String,
        subtitle: String? = nil,
        duration: TimeInterval = 2.0,
        action: BrowserNotificationAction? = nil,
        controls: [BrowserNotificationControl]? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.messageKey = messageKey
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
        self.action = action
        self.controls = controls
        self.icon = icon
    }

    /// Preserves all content while substituting the presentation id (used by dedup updates in the center).
    func withID(_ id: UUID) -> BrowserNotification {
        BrowserNotification(
            id: id,
            messageKey: messageKey,
            title: title,
            subtitle: subtitle,
            duration: duration,
            action: action,
            controls: controls,
            icon: icon
        )
    }
}

extension BrowserNotification {
    static func copyURL(undo: BrowserNotificationAction? = nil) -> Self {
        Self(
            messageKey: "copy-url",
            title: "Copied Current URL",
            duration: undo == nil ? 2.0 : 3.0,
            action: undo,
            icon: "checkmark.circle.fill"
        )
    }

    static func spaceRenamed(name: String) -> Self {
        Self(
            messageKey: "space-renamed",
            title: "Renamed space to “\(name)”",
            icon: "square.and.pencil"
        )
    }

    static func backgroundTabOpened(openAction: BrowserNotificationAction) -> Self {
        Self(
            messageKey: "background-tab-opened",
            title: "Opened tab in background",
            duration: 3.0,
            action: openAction,
            icon: "arrow.up.forward.square"
        )
    }

    static func splitViewLimit(maximumPanes: Int) -> Self {
        Self(
            messageKey: "split-view-limit",
            title: "Split view is full",
            subtitle: "Maximum \(maximumPanes) panes per split",
            icon: "rectangle.split.2x1"
        )
    }

    static func tabUnloaded(count: Int) -> Self {
        Self(
            messageKey: "tab-unloaded",
            title: "\(count) tab\(count == 1 ? "" : "s") unloaded",
            subtitle: "Click the tab to reload it",
            duration: 2.0,
            icon: "moon.zzz"
        )
    }

    static func splitViewUnloaded(tabCount: Int) -> Self {
        Self(
            messageKey: "split-view-unloaded",
            title: "\(tabCount)-tab Split View unloaded",
            subtitle: "Click the Split View to reload it",
            duration: 2.0,
            icon: "rectangle.split.2x1"
        )
    }

    static func tabClosure(
        count: Int,
        undoShortcut: String?,
        action: BrowserNotificationAction?
    ) -> Self {
        let subtitle: String?
        if let undoShortcut {
            subtitle = "Press \(undoShortcut) to reopen"
        } else {
            subtitle = "Use History to reopen"
        }

        return Self(
            messageKey: "tab-closed",
            title: "\(count) tab\(count == 1 ? "" : "s") closed",
            subtitle: subtitle,
            duration: 3.0,
            action: action,
            icon: "arrow.uturn.backward"
        )
    }

    static func splitViewClosure(
        tabCount: Int,
        undoShortcut: String?,
        action: BrowserNotificationAction?
    ) -> Self {
        let subtitle = undoShortcut.map { "Press \($0) to reopen" }
            ?? "Use History to reopen"
        return Self(
            messageKey: "split-view-closed",
            title: "\(tabCount)-tab Split View closed",
            subtitle: subtitle,
            duration: 3.0,
            action: action,
            icon: "rectangle.split.2x1"
        )
    }

    static func profileSwitch(profileName: String) -> Self {
        Self(
            messageKey: "profile-switch",
            title: "Switched to \(profileName)",
            icon: "person.2"
        )
    }

    static func zoom(
        percentage: String,
        isAtMinimum: Bool,
        isAtMaximum: Bool,
        zoomOut: @escaping @MainActor () -> Void,
        resetZoom: @escaping @MainActor () -> Void,
        zoomIn: @escaping @MainActor () -> Void
    ) -> Self {
        Self(
            messageKey: "zoom",
            title: "Zoom",
            duration: 2.0,
            controls: [
                BrowserNotificationControl(
                    id: "zoom-out",
                    kind: .systemImage("minus"),
                    accessibilityLabel: "Zoom out",
                    isDisabled: isAtMinimum,
                    handler: zoomOut
                ),
                BrowserNotificationControl(
                    id: "zoom-percentage-\(percentage)",
                    kind: .text(percentage),
                    accessibilityLabel: "Reset zoom to 100%",
                    handler: resetZoom
                ),
                BrowserNotificationControl(
                    id: "zoom-in",
                    kind: .systemImage("plus"),
                    accessibilityLabel: "Zoom in",
                    isDisabled: isAtMaximum,
                    handler: zoomIn
                )
            ],
            icon: "magnifyingglass"
        )
    }
}
