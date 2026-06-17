import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SumiBoostEditorMetrics {
    static let normalWidth: CGFloat = 204
    static let codeWidth: CGFloat = 392
    static let height: CGFloat = 582
}

@MainActor
final class SumiBoostEditorPanelController: NSObject, NSWindowDelegate {
    private weak var parentWindow: NSWindow?
    private var panel: NSPanel?
    private var session: SumiBoostEditorSession?

    func present(
        boost: SumiBoost,
        tab: Tab,
        profile: Profile?,
        windowState: BrowserWindowState,
        module: SumiBoostsModule
    ) {
        let session = SumiBoostEditorSession(
            boost: boost,
            tab: tab,
            profile: profile,
            windowState: windowState,
            module: module,
            onClose: { [weak self] in
                self?.panel?.close()
            }
        )
        session.onCodeModeChange = { [weak self] isCodeMode in
            self?.resizePanel(forCodeMode: isCodeMode, animated: true)
        }
        self.session = session

        let panel = self.panel ?? makePanel()
        panel.contentViewController = NSHostingController(
            rootView: SumiBoostEditorView(session: session)
        )
        if parentWindow !== windowState.window {
            parentWindow?.removeChildWindow(panel)
            parentWindow = windowState.window
            windowState.window?.addChildWindow(panel, ordered: .above)
        }
        self.panel = panel
        panel.delegate = self
        resizePanel(forCodeMode: false, animated: false)
        centerPanel(over: windowState.window)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        session?.close()
        session = nil
        if let panel {
            parentWindow?.removeChildWindow(panel)
        }
        parentWindow = nil
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SumiBoostEditorMetrics.normalWidth,
                height: SumiBoostEditorMetrics.height
            ),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Boost"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = NSSize(
            width: SumiBoostEditorMetrics.normalWidth,
            height: SumiBoostEditorMetrics.height
        )
        panel.maxSize = NSSize(
            width: SumiBoostEditorMetrics.codeWidth,
            height: SumiBoostEditorMetrics.height
        )
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func resizePanel(forCodeMode isCodeMode: Bool, animated: Bool) {
        guard let panel else { return }
        let contentSize = NSSize(
            width: isCodeMode ? SumiBoostEditorMetrics.codeWidth : SumiBoostEditorMetrics.normalWidth,
            height: SumiBoostEditorMetrics.height
        )
        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        var frame = panel.frame
        let midpoint = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = frameSize
        frame.origin.x = midpoint.x - frameSize.width / 2
        frame.origin.y = midpoint.y - frameSize.height / 2
        panel.setFrame(frame, display: true, animate: animated)
    }

    private func centerPanel(over parent: NSWindow?) {
        guard let panel else { return }
        let referenceFrame = parent?.frame
            ?? parent?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
        let visibleFrame = parent?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? referenceFrame

        var origin = NSPoint(
            x: referenceFrame.midX - panel.frame.width / 2,
            y: referenceFrame.midY - panel.frame.height / 2
        )
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
    }
}

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

    private weak var tab: Tab?
    private weak var profile: Profile?
    private weak var windowState: BrowserWindowState?
    private weak var module: SumiBoostsModule?
    private let onClose: @MainActor () -> Void
    private var didDelete = false

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
        self.tab = tab
        self.profile = profile
        self.windowState = windowState
        self.module = module
        self.onClose = onClose
        self.fontFamilies = [""] + NSFontManager.shared.availableFontFamilies.sorted()
    }

    var isEphemeral: Bool {
        profile?.isEphemeral == true || tab?.isEphemeral == true
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
        module?.stopZapSelection()
        isZapActive = false
        guard !didDelete else { return }
        // If the user made changes, the boost is persisted and active; we must
        // re-sync the atDocumentStart WKUserScript so the final state takes
        // effect on the next navigation, and flush any debounced disk write.
        // If nothing changed, discard the ephemeral draft instead.
        if boost.data.changeWasMade {
            module?.reinstallUserScriptsAfterEdit(profileId: boost.profileId, host: boost.host)
        } else {
            module?.discardUnchangedDraft(boost)
        }
    }

    func dismiss() {
        onClose()
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
        let resolved = Self.primaryDotData(for: position, secondaryDelta: boost.data.secondaryDotAngleDegDelta)
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
        let resolved = Self.secondaryDotData(
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
        let resolved = Self.primaryDotData(for: primary, secondaryDelta: delta)
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
        didDelete = true
        module?.deleteBoost(boost, isEphemeral: isEphemeral)
        onClose()
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
        guard let tab, let windowState else { return }
        let didStart = module?.startZapSelection(
            for: boost,
            tab: tab,
            windowState: windowState,
            isEphemeral: isEphemeral,
            onSelector: { [weak self] updated in
                self?.boost = updated
                self?.isZapActive = false
                self?.statusMessage = nil
            },
            onFinish: { [weak self] in
                self?.isZapActive = false
                self?.statusMessage = nil
            }
        ) ?? false
        isZapActive = didStart
        statusMessage = didStart ? "Select an element" : nil
    }

    func stopZap() {
        module?.stopZapSelection()
        isZapActive = false
        statusMessage = nil
    }

    func previewZap(_ selector: String, isHighlighted: Bool) {
        guard let tab, let windowState else { return }
        module?.previewZapSelector(selector, isHighlighted: isHighlighted, tab: tab, windowState: windowState)
    }

    func exportJSON() {
        guard let module else { return }
        do {
            let data = try module.exportData(for: boost)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "\(boost.data.boostName).sumi-boost.json"
            savePanel.begin { [weak self] response in
                guard response == .OK, let url = savePanel.url else { return }
                do {
                    try data.write(to: url, options: [.atomic])
                } catch {
                    Task { @MainActor [weak self] in
                        self?.statusMessage = error.localizedDescription
                    }
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func importJSON() {
        guard let tab, let module else { return }
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.begin { [weak self] response in
            guard response == .OK,
                  let url = openPanel.url,
                  let data = try? Data(contentsOf: url)
            else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let imported = try module.importBoost(from: data, tab: tab, profile: self.profile)
                    self.boost = imported
                    self.statusMessage = nil
                } catch {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func openInspector() {
        module?.browserManager?.openWebInspector()
    }

    private func update(
        refreshPath: SumiBoostsModule.RefreshPath = .liveState,
        _ mutate: (inout SumiBoostData) -> Void
    ) {
        guard let updated = module?.updateBoost(
            boost,
            isEphemeral: isEphemeral,
            markChanged: true,
            refreshPath: refreshPath,
            mutate: mutate
        ) else {
            return
        }
        boost = updated
    }

    private static func primaryDotData(
        for position: SumiBoostDotPosition,
        secondaryDelta: Double
    ) -> (
        angle: Double,
        distance: Double,
        primary: SumiBoostDotPosition,
        secondary: SumiBoostDotPosition
    ) {
        let center = SumiBoostDotPosition(x: 0.5, y: 0.5)
        let dx = position.x - center.x
        let dy = position.y - center.y
        let rawDistance = sqrt(dx * dx + dy * dy) / 0.42
        let distance = max(0, min(1, rawDistance))
        let angle = normalizedDegrees((atan2(dy, dx) * 180 / .pi) + 100)
        let primary = Self.position(angle: angle, distance: distance)
        let secondary = Self.position(angle: angle + secondaryDelta, distance: distance)
        return (angle, distance, primary, secondary)
    }

    private static func secondaryDotData(
        for position: SumiBoostDotPosition,
        primaryAngle: Double,
        dotDistance: Double
    ) -> (delta: Double, position: SumiBoostDotPosition) {
        let dx = position.x - 0.5
        let dy = position.y - 0.5
        let rawAngle = (atan2(dy, dx) * 180 / .pi) + 100
        let delta = normalizedDegrees(rawAngle - primaryAngle)
        return (delta, Self.position(angle: primaryAngle + delta, distance: dotDistance))
    }

    private static func position(angle: Double, distance: Double) -> SumiBoostDotPosition {
        let radians = (normalizedDegrees(angle) - 100) * .pi / 180
        let radius = max(0, min(1, distance)) * 0.42
        return SumiBoostDotPosition(
            x: max(0.08, min(0.92, 0.5 + cos(radians) * radius)),
            y: max(0.08, min(0.92, 0.5 + sin(radians) * radius))
        )
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

private struct SumiBoostEditorView: View {
    @ObservedObject var session: SumiBoostEditorSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var isBoostMenuPresented = false

    private enum NavigationDirection {
        case forward
        case backward
    }

    private static let modeAnimation = Animation.spring(
        response: 0.3,
        dampingFraction: 0.88,
        blendDuration: 0.08
    )

    var body: some View {
        ZStack {
            if session.isCodeMode {
                codeRoot
                    .id("code")
                    .transition(modeTransition)
            } else {
                boostRoot
                    .id("boost")
                    .transition(modeTransition)
            }
        }
        .frame(
            width: session.isCodeMode ? SumiBoostEditorMetrics.codeWidth : SumiBoostEditorMetrics.normalWidth,
            height: SumiBoostEditorMetrics.height
        )
        .clipped()
        .background(SumiBoostEditorStyle.primaryBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SumiBoostEditorStyle.border(for: colorScheme), lineWidth: 1)
        }
        .animation(Self.modeAnimation, value: session.isCodeMode)
    }

    private var boostRoot: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                SumiBoostColorCanvas(session: session)
                    .frame(width: 166, height: 166)
                    .padding(.top, 6)

                colorControlRow

                SumiBoostFontGrid(session: session)

                HStack(spacing: 8) {
                    SumiBoostActionButton(title: session.sizeLabel) {
                        session.cycleSize()
                    }
                    SumiBoostActionButton(title: session.caseLabel) {
                        session.cycleCase()
                    }
                }

                SumiBoostActionButton(
                    title: "Zap",
                    trailingSystemImage: "bolt",
                    valueText: zapValue,
                    isActive: session.isZapActive
                ) {
                    toggleZap()
                }
                .contextMenu {
                    if session.boost.data.zapSelectors.isEmpty {
                        Text("No elements zapped")
                    } else {
                        ForEach(session.boost.data.zapSelectors, id: \.self) { selector in
                            Button("Remove \(selector)") {
                                session.removeZapSelector(selector)
                            }
                        }
                    }
                }

                SumiBoostActionButton(title: "Code", trailingText: "{ }") {
                    openCodeMode()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: session.dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Close")

            SumiBoostHeaderDragSpacer()

            // The boost name. In the Zen reference this is a plain <p> text
            // element with a small down-arrow background glyph that opens a
            // separate popup on click. A SwiftUI Menu with a custom label
            // truncates to "…" here, so we render plain text + a chevron and
            // surface the actions via a popover instead.
            //
            // fixedSize + layoutPriority: the two drag spacers flanking this
            // button use maxWidth: .infinity and would otherwise starve the
            // label of width, truncating "My Boost" to "…". fixedSize lets the
            // button claim its ideal content width; layoutPriority(1) makes
            // the spacers absorb any shortfall rather than the name.
            Button {
                isBoostMenuPresented.toggle()
            } label: {
                HStack(spacing: 3) {
                    Text(session.boost.data.boostName.isEmpty ? "My Boost" : session.boost.data.boostName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(SumiBoostEditorStyle.primaryText(for: colorScheme))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .popover(isPresented: $isBoostMenuPresented, arrowEdge: .bottom) {
                SumiBoostHeaderMenu(session: session, isPresented: $isBoostMenuPresented)
            }

            SumiBoostHeaderDragSpacer()

            Button(action: session.shuffleBoost) {
                Image(systemName: "die.face.5")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Shuffle Boost Settings")
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(SumiBoostEditorStyle.secondaryBackground(for: colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SumiBoostEditorStyle.border(for: colorScheme))
                .frame(height: 1)
        }
    }

    private var colorControlRow: some View {
        HStack(spacing: 8) {
            SumiBoostIconButton(
                systemImage: "lightbulb",
                isActive: session.boost.data.smartInvert,
                help: "Smart Invert Colors"
            ) {
                session.toggleSmartInvert()
            }

            SumiBoostAdvancedColorButton(session: session)

            SumiBoostIconButton(
                systemImage: "circle.slash",
                isActive: !session.boost.data.enableColorBoost,
                help: "Disable Color Adjustments"
            ) {
                session.toggleColorBoost()
            }
        }
    }

    private var zapValue: String? {
        let count = session.boost.data.zapSelectors.count
        return count == 0 ? nil : "\(count)"
    }

    private var codeRoot: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    closeCodeMode()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(SumiBoostEditorStyle.buttonBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                SumiBoostHeaderDragSpacer()

                Text("Code")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SumiBoostEditorStyle.primaryText(for: colorScheme))

                SumiBoostHeaderDragSpacer()

                Button(action: session.dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(SumiBoostEditorStyle.secondaryBackground(for: colorScheme))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SumiBoostEditorStyle.border(for: colorScheme))
                    .frame(height: 1)
            }

            TextEditor(
                text: Binding(
                    get: { session.boost.data.customCSS },
                    set: { session.setCustomCSS($0) }
                )
            )
            .font(.system(size: 12, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                SumiBoostActionButton(
                    title: "Zap",
                    trailingSystemImage: "bolt",
                    isActive: session.isZapActive
                ) {
                    toggleZap()
                }
                SumiBoostActionButton(title: "Inspector", trailingSystemImage: "scope") {
                    session.openInspector()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(height: 60)
            .background(SumiBoostEditorStyle.secondaryBackground(for: colorScheme))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(SumiBoostEditorStyle.border(for: colorScheme))
                    .frame(height: 1)
            }
        }
    }

    private var modeTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: Self.submenuInsertionTransition,
                removal: Self.rootRemovalTransition
            )
        case .backward:
            return .asymmetric(
                insertion: Self.rootInsertionTransition,
                removal: Self.submenuRemovalTransition
            )
        }
    }

    private static var submenuInsertionTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }

    private static var rootRemovalTransition: AnyTransition {
        .offset(x: -14, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.995, anchor: .leading))
    }

    private static var rootInsertionTransition: AnyTransition {
        .offset(x: -18, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.99, anchor: .leading))
    }

    private static var submenuRemovalTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }

    private func openCodeMode() {
        navigationDirection = .forward
        withAnimation(Self.modeAnimation) {
            session.isCodeMode = true
        }
    }

    private func closeCodeMode() {
        navigationDirection = .backward
        withAnimation(Self.modeAnimation) {
            session.isCodeMode = false
        }
    }

    private func toggleZap() {
        if session.isZapActive {
            session.stopZap()
        } else {
            session.startZap()
        }
    }
}

private struct SumiBoostHeaderDragSpacer: View {
    var body: some View {
        SumiBoostPanelDragRegion()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

private struct SumiBoostHeaderMenu: View {
    @ObservedObject var session: SumiBoostEditorSession
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton("Rename Boost") {
                isPresented = false
                session.promptRename()
            }
            menuButton("Shuffle Boost") {
                isPresented = false
                session.shuffleBoost()
            }
            menuButton("Reset All Edits") {
                isPresented = false
                session.reset()
            }

            Divider().padding(.vertical, 4)

            menuButton("Import Boost...") {
                isPresented = false
                session.importJSON()
            }
            menuButton("Export Boost...") {
                isPresented = false
                session.exportJSON()
            }

            Divider().padding(.vertical, 4)

            menuButton("Delete Boost", role: .destructive) {
                isPresented = false
                session.delete()
            }
        }
        .padding(.vertical, 6)
        .frame(width: 200)
    }

    @ViewBuilder
    private func menuButton(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SumiBoostPanelDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        _ = context
        return SumiBoostPanelDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = nsView
        _ = context
    }
}

private final class SumiBoostPanelDragView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private enum SumiBoostColorPreview {
    /// Mirrors the Zen reference editor (ZenBoostsEditor.mjs `updateDot`):
    /// the dots visualize the *input* hue + saturation picked on the wheel
    /// (saturation comes from the radial distance), with fixed lightness.
    /// They are not a literal preview of the page filter; the advanced
    /// brightness/contrast/saturation sliders drive the page filter on top.
    static func primaryDotColor(for data: SumiBoostData) -> Color {
        hslColor(
            hueDegrees: data.dotAngleDeg,
            saturation: clamped(data.dotDistance, lower: 0.05, upper: 1),
            lightness: 0.55
        )
    }

    static func backgroundDotColor(for data: SumiBoostData) -> Color {
        // Same hue/saturation formula the CSS builder uses for the page
        // background, so the secondary dot tells the truth about the bg color.
        hslColor(
            hueDegrees: data.dotAngleDeg + data.secondaryDotAngleDegDelta,
            saturation: clamped(data.dotDistance, lower: 0.05, upper: 1),
            lightness: 0.2
        )
    }

    private static func hslColor(
        hueDegrees: Double,
        saturation: Double,
        lightness: Double
    ) -> Color {
        let hue = normalizedDegrees(hueDegrees) / 360
        let saturation = clamped(saturation, lower: 0, upper: 1)
        let lightness = clamped(lightness, lower: 0, upper: 1)

        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let huePrime = hue * 6
        let x = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2

        let rgb: (Double, Double, Double)
        switch huePrime {
        case 0..<1:
            rgb = (chroma, x, 0)
        case 1..<2:
            rgb = (x, chroma, 0)
        case 2..<3:
            rgb = (0, chroma, x)
        case 3..<4:
            rgb = (0, x, chroma)
        case 4..<5:
            rgb = (x, 0, chroma)
        default:
            rgb = (chroma, 0, x)
        }

        return Color(
            red: rgb.0 + match,
            green: rgb.1 + match,
            blue: rgb.2 + match,
            opacity: 1
        )
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}

private enum SumiBoostEditorStyle {
    static func primaryBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#171717") : Color(hex: "#FCFCFE")
    }

    static func secondaryBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#1C1C1E") : Color(hex: "#F6F6F8")
    }

    static func buttonBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#262626") : Color(hex: "#EBEBED")
    }

    static func fontBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#262626") : Color.white
    }

    static func primaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#F3F3F3") : Color(hex: "#3A3A3B")
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#B1B1B1") : Color(hex: "#727272")
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#3A3A3A") : Color(hex: "#EDEDEF")
    }
}

private struct SumiBoostColorCanvas: View {
    @ObservedObject var session: SumiBoostEditorSession
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                .red,
                                .orange,
                                .yellow,
                                .green,
                                .cyan,
                                .blue,
                                .purple,
                                .pink,
                                .red,
                            ]),
                            center: .center,
                            angle: .degrees(-100)
                        )
                    )
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(SumiBoostEditorStyle.primaryBackground(for: colorScheme).opacity(0.86))
                            .padding(8)
                            .overlay {
                                SumiBoostDottedOverlay(
                                    color: colorScheme == .dark
                                        ? Color.white.opacity(0.12)
                                        : Color(hex: "#DCE4DE").opacity(0.9)
                                )
                                .padding(8)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                    }
                    .saturation(session.boost.data.enableColorBoost && !session.isMonochromeMode ? 1 : 0)
                    .opacity(session.boost.data.enableColorBoost ? 1 : 0.55)

                Circle()
                    .stroke(Color.gray.opacity(0.28), lineWidth: 1)
                    .frame(
                        width: max(12, CGFloat(session.boost.data.dotDistance) * proxy.size.width * 0.84),
                        height: max(12, CGFloat(session.boost.data.dotDistance) * proxy.size.height * 0.84)
                    )

                Button(action: session.toggleMonochromeMode) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(session.isMonochromeMode ? monochromeIconForeground : SumiBoostEditorStyle.primaryText(for: colorScheme))
                        .frame(width: 24, height: 24)
                        .background(monochromeButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                }
                .buttonStyle(.plain)
                .position(x: proxy.size.width / 2, y: 24)
                .help("Monochrome")

                SumiBoostColorDot(color: session.backgroundDotColor, isPrimary: false)
                    .position(point(for: session.boost.data.secondaryDotPos, in: proxy.size))
                    .gesture(dotDrag(in: proxy, setter: session.setSecondaryDot))
                    .help("Background Color")

                SumiBoostColorDot(color: session.primaryDotColor, isPrimary: true)
                    .position(point(for: session.boost.data.dotPos, in: proxy.size))
                    .gesture(dotDrag(in: proxy, setter: session.setPrimaryDot))
                    .help("Boost Color")
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(dotDrag(in: proxy, setter: session.setPrimaryDot))
        }
    }

    /// Monochrome (sparkles) toggle button styling. Mirrors the Zen
    /// magic-theme button (`light-dark(white, #3a3a3a)` inactive, inverted when
    /// active) so the icon is always legible against its background in both
    /// light and dark schemes — never white-on-white.
    private var monochromeButtonBackground: Color {
        if session.isMonochromeMode {
            return colorScheme == .dark ? Color.white : Color(hex: "#3a3a3a")
        }
        return colorScheme == .dark ? Color(hex: "#3a3a3a") : Color.white
    }

    private var monochromeIconForeground: Color {
        // When active the background is inverted, so the icon takes the
        // opposite tone to stay readable.
        colorScheme == .dark ? Color(hex: "#3a3a3a") : Color.white
    }

    private func point(for dotPosition: SumiBoostDotPosition, in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(dotPosition.x) * size.width,
            y: CGFloat(dotPosition.y) * size.height
        )
    }

    private func dotDrag(
        in proxy: GeometryProxy,
        setter: @escaping (SumiBoostDotPosition) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let frame = proxy.frame(in: .global)
                let x = (value.location.x - frame.minX) / max(frame.width, 1)
                let y = (value.location.y - frame.minY) / max(frame.height, 1)
                setter(
                    SumiBoostDotPosition(
                        x: Double(max(0.08, min(0.92, x))),
                        y: Double(max(0.08, min(0.92, y)))
                    )
                )
            }
    }
}

private struct SumiBoostDottedOverlay: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 4
            var x: CGFloat = 2
            while x < size.width {
                var y: CGFloat = 2
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.9, height: 0.9)),
                        with: .color(color)
                    )
                    y += spacing
                }
                x += spacing
            }
        }
    }
}

private struct SumiBoostColorDot: View {
    let color: Color
    let isPrimary: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: isPrimary ? 32 : 28, height: isPrimary ? 32 : 28)
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
    }
}

private struct SumiBoostIconButton: View {
    let systemImage: String
    var isActive: Bool = false
    let help: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var background: Color {
        isActive
            ? SumiBoostEditorStyle.primaryText(for: colorScheme)
            : SumiBoostEditorStyle.buttonBackground(for: colorScheme)
    }

    private var foreground: Color {
        isActive
            ? SumiBoostEditorStyle.primaryBackground(for: colorScheme)
            : SumiBoostEditorStyle.primaryText(for: colorScheme)
    }
}

private struct SumiBoostAdvancedColorButton: View {
    @ObservedObject var session: SumiBoostEditorSession
    @State private var isPresented = false

    var body: some View {
        SumiBoostIconButton(
            systemImage: "slider.horizontal.3",
            isActive: isPresented,
            help: "Advanced Color Controls"
        ) {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SumiBoostAdvancedColorPopover(session: session)
        }
    }
}

private struct SumiBoostAdvancedColorPopover: View {
    @ObservedObject var session: SumiBoostEditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            slider(
                title: "Contrast",
                value: session.boost.data.contrast,
                range: 0.05...0.9,
                action: session.setContrast
            )
            slider(
                title: "Brightness",
                value: session.boost.data.brightness,
                range: 0...1,
                action: session.setBrightness
            )
            slider(
                title: "Original Saturation",
                value: session.boost.data.saturation,
                range: 0...1,
                action: session.setSaturation
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 224)
    }

    private func slider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        action: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Slider(
                value: Binding(
                    get: { value },
                    set: { action($0) }
                ),
                in: range
            )
        }
    }
}

private struct SumiBoostFontGrid: View {
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

private struct SumiBoostActionButton: View {
    let title: String
    var trailingSystemImage: String?
    var trailingText: String?
    var valueText: String?
    var isActive = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Group {
                if valueText == nil && trailingSystemImage == nil && trailingText == nil {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let valueText {
                            Text(valueText)
                                .font(.system(size: 13, weight: .semibold))
                        } else if let trailingSystemImage {
                            Image(systemName: trailingSystemImage)
                                .font(.system(size: 16, weight: .medium))
                        } else if let trailingText {
                            Text(trailingText)
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        }
                    }
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        isActive
            ? SumiBoostEditorStyle.primaryText(for: colorScheme)
            : SumiBoostEditorStyle.buttonBackground(for: colorScheme)
    }

    private var foreground: Color {
        isActive
            ? SumiBoostEditorStyle.primaryBackground(for: colorScheme)
            : SumiBoostEditorStyle.primaryText(for: colorScheme)
    }
}

private struct SumiBoostZapSelectorRow: View {
    let selector: String
    let onHover: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(selector)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Remove", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover(perform: onHover)
    }
}
