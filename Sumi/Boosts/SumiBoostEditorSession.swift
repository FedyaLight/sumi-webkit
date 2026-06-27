import AppKit
import SwiftUI

@MainActor
final class SumiBoostEditorSession: ObservableObject {
    @Published private(set) var boost: SumiBoost
    @Published var isCodeMode = false {
        didSet {
            guard oldValue != isCodeMode else { return }
            onCodeModeChange?(isCodeMode)
        }
    }
    @Published var statusMessage: String?
    @Published var isZapActive = false
    var onCodeModeChange: ((Bool) -> Void)?

    private let actions: SumiBoostEditorSessionActions

    /// Full list of available font families, captured once at session build.
    /// This is a (relatively) expensive system call + sort; caching it avoids
    /// re-enumerating all installed fonts on every SwiftUI body evaluation
    /// (which happens on every editor tick — dot drag, slider, etc.).
    let fontFamilies: [String]

    init(
        boost: SumiBoost,
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState,
        module: SumiBoostsModule,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.boost = boost
        self.actions = SumiBoostEditorSessionActions(
            tab: tab,
            profile: profile,
            windowState: windowState,
            module: module,
            onClose: onClose
        )
        self.fontFamilies = [""] + NSFontManager.shared.availableFontFamilies.sorted()
    }

    var isEphemeral: Bool {
        actions.isEphemeral
    }

    var hostTitle: String {
        boost.host
    }

    var sizeLabel: String {
        abs(boost.data.sizeOverride - 1) < 0.01
            ? "Size"
            : "\(Int((boost.data.sizeOverride * 100).rounded()))%"
    }

    var caseLabel: String {
        switch boost.data.textCaseOverride {
        case .none: return "Case"
        case .uppercase: return "Upper"
        case .lowercase: return "Lower"
        case .capitalize: return "Title"
        }
    }

    var commonFontFamilies: [String] {
        let preferred = [
            "Arial",
            "Times New Roman",
            "Courier New",
            "Georgia",
            "Comic Sans MS",
            "Verdana",
            "Trebuchet MS",
            "Impact",
            "Palatino",
            "Tahoma",
            "Helvetica",
            "Garamond",
            "Century Gothic",
            "Arial Black",
            "Papyrus",
        ]
        return preferred
    }

    var isMonochromeMode: Bool {
        boost.data.enableColorBoost && boost.data.saturation <= 0.02
    }

    var primaryDotColor: Color {
        if isMonochromeMode {
            return Color(nsColor: NSColor(white: 0.88, alpha: 1))
        }
        return SumiBoostColorPreview.primaryDotColor(for: boost.data)
    }

    var backgroundDotColor: Color {
        if isMonochromeMode {
            return Color(nsColor: NSColor(white: 0.32, alpha: 1))
        }
        return SumiBoostColorPreview.backgroundDotColor(for: boost.data)
    }

    func close() {
        actions.close(boost: boost)
        isZapActive = false
    }

    func dismiss() {
        actions.dismiss()
    }

    func rename(_ name: String) {
        update { data in
            data.boostName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "My Boost"
                : name
        }
    }

    func promptRename() {
        let alert = NSAlert()
        alert.messageText = "Rename Boost"
        alert.informativeText = hostTitle
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = boost.data.boostName
        alert.accessoryView = textField
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        rename(textField.stringValue)
    }

    func setPrimaryDot(position: SumiBoostDotPosition) {
        let resolved = SumiBoostEditorDotGeometry.primaryDotData(
            for: position,
            secondaryDelta: boost.data.secondaryDotAngleDegDelta
        )
        update { data in
            data.dotAngleDeg = resolved.angle
            data.dotDistance = resolved.distance
            data.dotPos = resolved.primary
            data.secondaryDotPos = resolved.secondary
            data.enableColorBoost = true
            data.autoTheme = false
        }
    }

    func setSecondaryDot(position: SumiBoostDotPosition) {
        let resolved = SumiBoostEditorDotGeometry.secondaryDotData(
            for: position,
            primaryAngle: boost.data.dotAngleDeg,
            dotDistance: boost.data.dotDistance
        )
        update { data in
            data.secondaryDotAngleDegDelta = resolved.delta
            data.secondaryDotPos = resolved.position
            data.enableColorBoost = true
            data.autoTheme = false
        }
    }

    func setColorBoostEnabled(_ isEnabled: Bool) {
        update { data in
            data.enableColorBoost = isEnabled
        }
    }

    func toggleColorBoost() {
        setColorBoostEnabled(!boost.data.enableColorBoost)
    }

    func setSmartInvert(_ isEnabled: Bool) {
        update { data in
            data.smartInvert = isEnabled
        }
    }

    func toggleSmartInvert() {
        setSmartInvert(!boost.data.smartInvert)
    }

    func toggleMonochromeMode() {
        update { data in
            data.enableColorBoost = true
            data.autoTheme = false
            data.saturation = data.saturation <= 0.02 ? 0.5 : 0
        }
    }

    func setBrightness(_ value: Double) {
        update { $0.brightness = value }
    }

    func setSaturation(_ value: Double) {
        update { $0.saturation = value }
    }

    func setContrast(_ value: Double) {
        update { $0.contrast = value }
    }

    func setFontFamily(_ fontFamily: String) {
        update { data in
            data.fontFamily = fontFamily
        }
    }

    func cycleSize() {
        let sizes: [Double] = [1.0, 1.1, 1.25, 1.5, 0.9]
        let current = boost.data.sizeOverride
        let index = sizes.firstIndex { abs($0 - current) < 0.01 } ?? 0
        // Only the page zoom changes, so use the cheap zoom-only refresh path
        // and skip the CSS injection that applyLiveBoostState would otherwise do.
        update(refreshPath: .zoomOnly) { data in
            data.sizeOverride = sizes[(index + 1) % sizes.count]
        }
    }

    func cycleCase() {
        update { data in
            data.textCaseOverride = data.textCaseOverride.next
        }
    }

    func shuffleBoost() {
        let primary = SumiBoostDotPosition(
            x: Double.random(in: 0.2...0.84),
            y: Double.random(in: 0.18...0.82)
        )
        let delta = Double.random(in: 42...160)
        let resolved = SumiBoostEditorDotGeometry.primaryDotData(
            for: primary,
            secondaryDelta: delta
        )
        let available = Set(NSFontManager.shared.availableFontFamilies)
        let fontCandidates = commonFontFamilies.filter { available.contains($0) }
        let randomFont = fontCandidates.randomElement() ?? ""
        update { data in
            data.enableColorBoost = true
            data.autoTheme = false
            data.dotAngleDeg = resolved.angle
            data.dotDistance = resolved.distance
            data.dotPos = resolved.primary
            data.secondaryDotAngleDegDelta = delta
            data.secondaryDotPos = resolved.secondary
            data.brightness = Double.random(in: 0.34...0.72)
            data.contrast = Double.random(in: 0.62...0.95)
            data.saturation = Double.random(in: 0.42...0.9)
            data.fontFamily = randomFont
        }
    }

    func reset() {
        let name = boost.data.boostName
        update { data in
            data = .empty(named: name)
            data.changeWasMade = true
        }
    }

    func delete() {
        actions.delete(boost: boost)
    }

    func setCustomCSS(_ css: String) {
        update { data in
            data.customCSS = css
        }
    }

    func removeZapSelector(_ selector: String) {
        update { data in
            data.zapSelectors.removeAll { $0 == selector }
        }
    }

    func startZap() {
        let didStart = actions.startZap(
            boost: boost,
            onSelector: { [weak self] updated in
                self?.boost = updated
                self?.isZapActive = false
                self?.statusMessage = nil
            },
            onFinish: { [weak self] in
                self?.isZapActive = false
                self?.statusMessage = nil
            }
        )
        isZapActive = didStart
        statusMessage = didStart ? "Select an element" : nil
    }

    func stopZap() {
        actions.stopZap()
        isZapActive = false
        statusMessage = nil
    }

    func previewZap(_ selector: String, isHighlighted: Bool) {
        actions.previewZap(selector, isHighlighted: isHighlighted)
    }

    func exportJSON() {
        actions.exportJSON(boost: boost) { [weak self] message in
            self?.statusMessage = message
        }
    }

    func importJSON() {
        actions.importJSON(
            onImported: { [weak self] imported in
                self?.boost = imported
                self?.statusMessage = nil
            },
            onError: { [weak self] message in
                self?.statusMessage = message
            }
        )
    }

    func openInspector() {
        actions.openInspector()
    }

    private func update(
        refreshPath: SumiBoostsModule.RefreshPath = .liveState,
        _ mutate: (inout SumiBoostData) -> Void
    ) {
        guard let updated = actions.update(
            boost: boost,
            refreshPath: refreshPath,
            mutate
        ) else {
            return
        }
        boost = updated
    }
}
