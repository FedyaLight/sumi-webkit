import AppKit
import SwiftUI

// MARK: - Right-click menu entries

// The right-click-only AppKit menu is attached by the enclosing strip/grid as
// the *outermost* layer, above the reorder drag gesture. Nesting it under the
// container-level reorder `.simultaneousGesture` (as an inner overlay on the
// button) lets that gesture shadow the AppKit host, so `rightMouseDown` never
// reaches it — which is why pinned surfaces lost their context menu. Building
// the entries here (rather than inside the button) lets each surface own the
// overlay placement while sharing the menu contents.

@available(macOS 15.5, *)
@MainActor
func extensionActionMenuEntries(
    for ext: BrowserExtensionToolbarDisplayRecord,
    layout: ExtensionActionLayout,
    presentation: ExtensionActionPresentationContext
) -> [SidebarContextMenuEntry] {
    var entries: [SidebarContextMenuEntry] = [
        .action(
            SidebarContextMenuAction(
                title: "Manage Extensions",
                systemImage: "gearshape",
                classification: .presentationOnly,
                action: {
                    presentation.openExtensionsSettings()
                }
            )
        ),
    ]

    switch layout {
    case .hubTiles:
        entries.append(
            .action(
                SidebarContextMenuAction(
                    title: "Pin to Toolbar",
                    systemImage: "pin",
                    classification: .presentationOnly,
                    action: {
                        presentation.pinToToolbar(extensionId: ext.id)
                    }
                )
            )
        )
    case .compactStrip, .sidebarGrid:
        entries.append(
            .action(
                SidebarContextMenuAction(
                    title: "Unpin from Toolbar",
                    systemImage: "pin.slash",
                    classification: .presentationOnly,
                    action: {
                        presentation.unpinFromToolbar(extensionId: ext.id)
                    }
                )
            )
        )
    }

    if ext.hasOptionsPage {
        entries.append(
            .action(
                SidebarContextMenuAction(
                    title: "Options",
                    systemImage: "slider.horizontal.3",
                    classification: .presentationOnly,
                    action: {
                        Task { @MainActor in
                            await presentation.openOptionsPage(for: ext)
                        }
                    }
                )
            )
        )
    }

    return entries
}

/// Whether the extension's action is actionable for the focused tab. Shared by
/// the button's disabled styling and the surface's tap gate, so a click on a
/// dimmed icon stays inert now that activation is delivered by the reorder
/// gesture rather than a `Button` with `.disabled`.
@available(macOS 15.5, *)
@MainActor
func extensionActionIsEnabled(
    _ ext: BrowserExtensionToolbarDisplayRecord,
    browserContext: ExtensionActionBrowserContext
) -> Bool {
    guard let tab = browserContext.currentTab(),
          browserContext.windowState.currentTabId == tab.id,
          let target = browserContext.extensionsModule.actionPresentationTarget(
              extensionID: ext.id,
              tab: tab,
              window: browserContext.windowState
          ),
          let snapshot = browserContext.extensionsModule
              .actionPresentationSnapshot(for: target)
    else {
        return true
    }
    return snapshot.isEnabled != false
}

@available(macOS 15.5, *)
struct ExtensionActionButton: View {
    let ext: BrowserExtensionToolbarDisplayRecord
    var layout: ExtensionActionLayout = .compactStrip
    var profileId: UUID?
    let browserContext: ExtensionActionBrowserContext
    /// Press state, owned by the enclosing reorder surface. The button used to
    /// track this with its own `DragGesture(minimumDistance: 0)`, which was a
    /// third claimant on a press the reorder gesture already tracks.
    var isPressed: Bool = false
    /// Assistive-technology activation. The pointer path runs through the
    /// enclosing reorder gesture, which VoiceOver cannot drive, so the same
    /// action is published here as an accessibility action.
    var onActivate: () -> Void = {}
    private let iconCache: ExtensionIconCache
    @StateObject private var actionModel: BrowserExtensionActionButtonModel
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @State private var isHovering: Bool = false

    init(
        ext: BrowserExtensionToolbarDisplayRecord,
        layout: ExtensionActionLayout = .compactStrip,
        profileId: UUID? = nil,
        browserContext: ExtensionActionBrowserContext,
        isPressed: Bool = false,
        onActivate: @escaping () -> Void = {}
    ) {
        self.ext = ext
        self.layout = layout
        self.profileId = profileId
        self.browserContext = browserContext
        self.isPressed = isPressed
        self.onActivate = onActivate
        let surfaceStore = browserContext.extensionsModule.surfaceStore
        iconCache = surfaceStore.iconCache
        _actionModel = StateObject(
            wrappedValue: BrowserExtensionActionButtonModel(
                changes: surfaceStore.actionPresentationChanges,
                query: { target in
                    guard browserContext.windowState === target.window,
                          browserContext.currentTab() === target.tab
                    else { return nil }
                    return browserContext.extensionsModule
                        .actionPresentationSnapshot(for: target)
                }
            )
        )
    }

    var body: some View {
        // Deliberately not a `Button`: the enclosing strip/grid owns a
        // `minimumDistance: 0` reorder gesture that needs the primary mouse and
        // delivers activation through its tap branch. A button here would be a
        // second claimant on the same press. Enablement is enforced at that tap
        // gate via `extensionActionIsEnabled`.
        buttonLabel
            .help(actionTitle)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(actionTitle)
            .accessibilityIdentifier("extension-action-\(ext.id)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onActivate() }
            .opacity(actionState.isEnabled == false ? 0.55 : 1)
            .sidebarHover($isHovering)
            .task(id: actionPresentationTarget) {
                actionModel.setTarget(actionPresentationTarget)
            }
            .onDisappear {
                actionModel.setTarget(nil)
            }
    }

    private var buttonLabel: some View {
        Group {
            switch layout {
            case .compactStrip:
                iconView(tint: .white)
                    .frame(width: 16, height: 16)
                    .padding(6)
                    .background(isHovering ? .white.opacity(0.1) : .clear)
                    .background(
                        ActionAnchorView(
                            extensionId: ext.id,
                            extensionsModule: browserContext.extensionsModule
                        )
                        .allowsHitTesting(false)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .topTrailing) {
                        actionBadgeView
                    }
            case .sidebarGrid:
                iconView(tint: URLBarHubNativeStyle.primaryText)
                    .frame(width: 16, height: 16)
                    .padding(5)
                    .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
                    .background(sidebarGridBackgroundFill)
                    .background(
                        ActionAnchorView(
                            extensionId: ext.id,
                            extensionsModule: browserContext.extensionsModule
                        )
                        .allowsHitTesting(false)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if let badgeText = visibleBadgeText {
                            actionBadge(badgeText)
                                .padding(2)
                        }
                    }
            case .hubTiles:
                iconView(tint: URLBarHubNativeStyle.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(hubBackgroundFill)
                    .background(
                        ActionAnchorView(
                            extensionId: ext.id,
                            extensionsModule: browserContext.extensionsModule
                        )
                        .allowsHitTesting(false)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(URLBarHubNativeStyle.separator, lineWidth: 0.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if let badgeText = visibleBadgeText {
                            actionBadge(badgeText)
                                .padding(3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .scaleEffect(hubButtonScale)
            }
        }
    }

    @ViewBuilder
    private func iconView(tint: Color) -> some View {
        if let actionIcon = actionState.icon {
            Image(nsImage: actionIcon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else if let iconPath = ext.iconPath,
                  let nsImage = iconCache.image(
                      extensionId: ext.id,
                      iconPath: iconPath
                  ) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private var actionBadgeView: some View {
        if let badgeText = visibleBadgeText {
            actionBadge(badgeText)
                .offset(x: 4, y: -4)
        }
    }

    private func actionBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 3)
            .frame(minWidth: 10, minHeight: 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(actionState.hasUnreadBadgeText ? 0.95 : 0.78))
            )
    }

    private var actionState: BrowserExtensionActionButtonSnapshot {
        actionModel.snapshot(for: actionPresentationTarget)
    }

    private var actionPresentationTarget: ExtensionActionPresentationTarget? {
        guard let tab = browserContext.currentTab(),
              browserContext.windowState.currentTabId == tab.id
        else { return nil }
        return browserContext.extensionsModule.actionPresentationTarget(
            extensionID: ext.id,
            tab: tab,
            window: browserContext.windowState
        )
    }

    private var actionTitle: String {
        guard let label = actionState.label?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            label.isEmpty == false
        else {
            return ext.name
        }
        return label
    }

    private var visibleBadgeText: String? {
        guard let badgeText = actionState.badgeText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            badgeText.isEmpty == false
        else {
            return nil
        }
        return String(badgeText.prefix(4))
    }

    private var hubBackgroundFill: Color {
        isHovering ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground
    }

    private var sidebarGridBackgroundFill: Color {
        isHovering ? tokens.pinnedHoverBackground : tokens.pinnedIdleBackground
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var hubButtonScale: CGFloat {
        if isPressed && isHovering {
            return 0.97
        }
        if isHovering {
            return 1.03
        }
        return 1
    }
}
@available(macOS 15.5, *)
private struct ActionAnchorView: NSViewRepresentable {
    let extensionId: String
    let extensionsModule: SumiExtensionsModule

    func makeNSView(context: Context) -> NSView {
        let view = ActionAnchorHostView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? ActionAnchorHostView else { return }
        configure(nsView)
    }

    private func configure(_ view: ActionAnchorHostView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.extensionId = extensionId
        view.extensionsModule = extensionsModule
        view.registerAnchor()
    }
}

@available(macOS 15.5, *)
private final class ActionAnchorHostView: NSView {
    var extensionId: String?
    weak var extensionsModule: SumiExtensionsModule?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerAnchor()
    }

    func registerAnchor() {
        guard let extensionId, let extensionsModule else { return }
        extensionsModule.setActionAnchorIfLoaded(
            for: extensionId,
            anchorView: self
        )
    }
}
