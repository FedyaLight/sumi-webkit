import AppKit

@MainActor
final class SumiSearchEngineEditorAlert: NSObject, NSTextFieldDelegate {
    private let originalEngine: SumiSearchEngine?
    private let alert = NSAlert()
    private let nameField = NSTextField()
    private let domainField = NSTextField()
    private let templateField = NSTextField()
    private let tabSearchCheckbox = NSButton(
        checkboxWithTitle: String(localized: "Enable for Tab Search"),
        target: nil,
        action: nil
    )

    init(engine: SumiSearchEngine?) {
        originalEngine = engine
        super.init()
        nameField.stringValue = engine?.name ?? ""
        domainField.stringValue = engine?.domain ?? ""
        templateField.stringValue = engine?.searchURLTemplate ?? ""
        tabSearchCheckbox.state = engine?.tabSearchEnabled == true ? .on : .off
        nameField.delegate = self
        domainField.delegate = self
        templateField.delegate = self
    }

    func beginSheetModal(
        for window: NSWindow,
        completion: @escaping (SumiSearchEngine?) -> Void
    ) {
        alert.messageText = originalEngine == nil
            ? String(localized: "Add Search Engine")
            : String(localized: "Edit Search Engine")
        alert.informativeText = String(
            localized: "Use {query} in the search URL where the typed text should appear."
        )
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.accessoryView = makeAccessoryView()
        updateSaveAvailability()
        alert.beginSheetModal(for: window) { [self] response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            completion(input.engine(id: originalEngine?.id ?? UUID().uuidString))
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        updateSaveAvailability()
    }

    private var input: SearchEngineEditorInput {
        SearchEngineEditorInput(
            engineID: originalEngine?.id,
            name: nameField.stringValue,
            domain: domainField.stringValue,
            searchURLTemplate: templateField.stringValue,
            colorHex: originalEngine?.colorHex ?? "#666666",
            tabSearchEnabled: tabSearchCheckbox.state == .on
        )
    }

    private func updateSaveAvailability() {
        alert.buttons.first?.isEnabled = input.validationMessage == nil
    }

    private func makeAccessoryView() -> NSView {
        nameField.placeholderString = String(localized: "Example: DuckDuckGo")
        domainField.placeholderString = String(localized: "Optional: duckduckgo.com")
        templateField.placeholderString = "https://duckduckgo.com/?q={query}"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "Name:")), nameField],
            [NSTextField(labelWithString: String(localized: "Domain:")), domainField],
            [NSTextField(labelWithString: String(localized: "Search URL:")), templateField],
            [NSTextField(labelWithString: ""), tabSearchCheckbox],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 130))
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            grid.topAnchor.constraint(equalTo: container.topAnchor),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])
        return container
    }
}
