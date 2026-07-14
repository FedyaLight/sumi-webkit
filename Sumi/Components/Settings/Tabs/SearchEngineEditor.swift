import SwiftUI

struct SearchEngineEditorDraft: Identifiable, Equatable {
    let id = UUID()
    var engineID: String?
    var name = ""
    var domain = ""
    var searchURLTemplate = ""
    var colorHex = "#666666"
    var tabSearchEnabled = false

    init() {}

    init(engine: SumiSearchEngine) {
        engineID = engine.id
        name = engine.name
        domain = engine.domain
        searchURLTemplate = engine.searchURLTemplate
        colorHex = engine.colorHex
        tabSearchEnabled = engine.tabSearchEnabled
    }
}

struct SearchEngineEditor: View {
    let draft: SearchEngineEditorDraft
    let onSave: (SumiSearchEngine) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var domain: String
    @State private var searchURLTemplate: String
    @State private var color: Color

    init(
        draft: SearchEngineEditorDraft,
        onSave: @escaping (SumiSearchEngine) -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _domain = State(initialValue: draft.domain)
        _searchURLTemplate = State(initialValue: draft.searchURLTemplate)
        _color = State(initialValue: Color(hex: draft.colorHex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.engineID == nil ? "Add Search Engine" : "Edit Search Engine")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("Domain", text: $domain)
                    .help("Optional. If empty, Sumi uses the host from the search URL.")
                TextField("Search URL", text: $searchURLTemplate)
                    .help("Use {query} where the typed search text should go.")
                ColorPicker("Color", selection: $color, supportsOpacity: false)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(input.previewURLString ?? "Enter a valid search URL to preview the result.")
                        .font(.caption)
                        .foregroundStyle(input.previewURLString == nil ? .secondary : .primary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                if let validationMessage = input.validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(input.validationMessage != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var input: SearchEngineEditorInput {
        SearchEngineEditorInput(
            engineID: draft.engineID,
            name: name,
            domain: domain,
            searchURLTemplate: searchURLTemplate,
            colorHex: color.toHexString() ?? draft.colorHex,
            tabSearchEnabled: draft.tabSearchEnabled
        )
    }

    private func save() {
        guard let engine = input.engine(id: draft.engineID ?? UUID().uuidString) else {
            return
        }
        onSave(engine)
        dismiss()
    }
}
