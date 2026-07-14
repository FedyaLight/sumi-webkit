import AppKit

enum URLBarHubScreenshotCaptureTarget: Int, CaseIterable {
    case visiblePage
    case selectedArea

    var title: LocalizedStringResource {
        switch self {
        case .visiblePage:
            return "Visible Page"
        case .selectedArea:
            return "Selected Area"
        }
    }
}

enum URLBarHubScreenshotDestination: Int, CaseIterable {
    case askEveryTime
    case downloads

    var title: LocalizedStringResource {
        switch self {
        case .askEveryTime:
            return "Ask Every Time"
        case .downloads:
            return "Downloads"
        }
    }
}

struct URLBarHubScreenshotOptions: Equatable {
    var target: URLBarHubScreenshotCaptureTarget
    var destination: URLBarHubScreenshotDestination
    var scale: URLBarHubScreenshotQuality
}

@MainActor
enum URLBarHubScreenshotSettingsPresenter {
    static func present(
        initial: URLBarHubScreenshotOptions,
        window: NSWindow?,
        themeContext: ResolvedThemeContext? = nil,
        completion: @escaping @MainActor (URLBarHubScreenshotOptions?) -> Void
    ) {
        let targetItems = URLBarHubScreenshotCaptureTarget.allCases
        let destinationItems = URLBarHubScreenshotDestination.allCases
        let scaleItems = URLBarHubScreenshotQuality.allCases

        let targetPopup = popup(
            items: targetItems,
            selected: initial.target,
            title: \.title
        )
        let destinationPopup = popup(
            items: destinationItems,
            selected: initial.destination,
            title: \.title
        )
        let scalePopup = popup(
            items: scaleItems,
            selected: initial.scale,
            title: \.menuTitle
        )

        let alert = NSAlert()
        alert.messageText = String(localized: "Screenshot Settings")
        alert.accessoryView = makeAccessoryView(rows: [
            ("Capture", targetPopup, "screenshot-settings-capture"),
            ("Save To", destinationPopup, "screenshot-settings-destination"),
            ("Scale", scalePopup, "screenshot-settings-scale"),
        ])
        let captureButton = alert.addButton(withTitle: String(localized: "Capture"))
        captureButton.keyEquivalent = "\r"
        captureButton.setAccessibilityIdentifier("screenshot-settings-confirm")

        let cancelButton = alert.addButton(withTitle: String(localized: "Cancel"))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityIdentifier("screenshot-settings-cancel")

        alert.sumiApplyNativeSurfaceAppearance(themeContext: themeContext)
        run(alert, window: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }

            completion(URLBarHubScreenshotOptions(
                target: selectedItem(
                    in: targetItems,
                    popup: targetPopup,
                    fallback: initial.target
                ),
                destination: selectedItem(
                    in: destinationItems,
                    popup: destinationPopup,
                    fallback: initial.destination
                ),
                scale: selectedItem(
                    in: scaleItems,
                    popup: scalePopup,
                    fallback: initial.scale
                )
            ))
        }
    }

    private static func popup<Item: Equatable>(
        items: [Item],
        selected: Item,
        title: (Item) -> LocalizedStringResource
    ) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        items.forEach { popup.addItem(withTitle: String(localized: title($0))) }
        if let selectedIndex = items.firstIndex(of: selected) {
            popup.selectItem(at: selectedIndex)
        }
        return popup
    }

    private static func selectedItem<Item>(
        in items: [Item],
        popup: NSPopUpButton,
        fallback: Item
    ) -> Item {
        let selectedIndex = popup.indexOfSelectedItem
        guard items.indices.contains(selectedIndex) else { return fallback }
        return items[selectedIndex]
    }

    private static func makeAccessoryView(
        rows: [(title: LocalizedStringResource, control: NSView, identifier: String)]
    ) -> NSView {
        let rowHeight: CGFloat = 26
        let rowSpacing: CGFloat = 8
        let labelWidth: CGFloat = 78
        let controlSpacing: CGFloat = 10
        let width: CGFloat = 320
        let height = CGFloat(rows.count) * rowHeight + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        for (index, row) in rows.enumerated() {
            let title = String(localized: row.title)
            let control = row.control
            let y = height - rowHeight - CGFloat(index) * (rowHeight + rowSpacing)
            let label = NSTextField(labelWithString: title)
            label.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 20)
            label.alignment = .right
            label.setAccessibilityIdentifier("\(row.identifier)-label")
            control.setAccessibilityIdentifier(row.identifier)
            control.setAccessibilityTitle(title)

            control.frame = NSRect(
                x: labelWidth + controlSpacing,
                y: y,
                width: width - labelWidth - controlSpacing,
                height: rowHeight
            )

            container.addSubview(label)
            container.addSubview(control)
        }

        return container
    }

    private static func run(
        _ alert: NSAlert,
        window: NSWindow?,
        completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void
    ) {
        if let window {
            alert.beginSheetModal(for: window) { response in
                Task { @MainActor in
                    completion(response)
                }
            }
        } else {
            completion(alert.runModal())
        }
    }
}
