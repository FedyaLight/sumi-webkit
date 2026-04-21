import AppKit
import SwiftUI

enum SidebarDragSourceExclusionZone {
    case leadingStrip(CGFloat)
    case trailingStrip(CGFloat)
    case topLeadingSquare(size: CGFloat, inset: CGFloat = 0)
    case topTrailingSquare(size: CGFloat, inset: CGFloat = 0)

    func contains(_ point: CGPoint, in bounds: CGRect) -> Bool {
        switch self {
        case .leadingStrip(let width):
            return CGRect(x: 0, y: 0, width: width, height: bounds.height).contains(point)
        case .trailingStrip(let width):
            return CGRect(
                x: max(bounds.width - width, 0),
                y: 0,
                width: min(width, bounds.width),
                height: bounds.height
            ).contains(point)
        case .topLeadingSquare(let size, let inset):
            return CGRect(
                x: inset,
                y: max(bounds.height - size - inset, 0),
                width: size,
                height: size
            ).contains(point)
        case .topTrailingSquare(let size, let inset):
            return CGRect(
                x: max(bounds.width - size - inset, 0),
                y: max(bounds.height - size - inset, 0),
                width: size,
                height: size
            ).contains(point)
        }
    }
}

struct SidebarDragSourceConfiguration {
    let item: SumiDragItem
    let sourceZone: DropZoneID
    let previewKind: SidebarDragPreviewKind
    let previewIcon: Image?
    let chromeTemplateSystemImageName: String?
    let pinnedConfig: PinnedTabsConfiguration
    let itemCount: Int
    let previewPresentationState: ShortcutPresentationState?
    let folderGlyphPresentation: SumiFolderGlyphPresentationState?
    let folderGlyphPalette: SumiFolderGlyphPalette?
    let exclusionZones: [SidebarDragSourceExclusionZone]
    let onActivate: (() -> Void)?
    let isEnabled: Bool

    init(
        item: SumiDragItem,
        sourceZone: DropZoneID,
        previewKind: SidebarDragPreviewKind,
        previewIcon: Image? = nil,
        chromeTemplateSystemImageName: String? = nil,
        pinnedConfig: PinnedTabsConfiguration = .large,
        itemCount: Int = 1,
        previewPresentationState: ShortcutPresentationState? = nil,
        folderGlyphPresentation: SumiFolderGlyphPresentationState? = nil,
        folderGlyphPalette: SumiFolderGlyphPalette? = nil,
        exclusionZones: [SidebarDragSourceExclusionZone] = [],
        onActivate: (() -> Void)? = nil,
        isEnabled: Bool = true
    ) {
        self.item = item
        self.sourceZone = sourceZone
        self.previewKind = previewKind
        self.previewIcon = previewIcon
        self.chromeTemplateSystemImageName = chromeTemplateSystemImageName
        self.pinnedConfig = pinnedConfig
        self.itemCount = itemCount
        self.previewPresentationState = previewPresentationState
        self.folderGlyphPresentation = folderGlyphPresentation
        self.folderGlyphPalette = folderGlyphPalette
        self.exclusionZones = exclusionZones
        self.onActivate = onActivate
        self.isEnabled = isEnabled
    }
}

struct SidebarDragSourceBridge: NSViewRepresentable {
    let configuration: SidebarDragSourceConfiguration

    func makeNSView(context: Context) -> SidebarDragSourceView {
        let view = SidebarDragSourceView()
        view.coordinator = context.coordinator
        view.update(configuration: configuration)
        return view
    }

    func updateNSView(_ nsView: SidebarDragSourceView, context: Context) {
        context.coordinator.configuration = configuration
        nsView.coordinator = context.coordinator
        nsView.update(configuration: configuration)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration)
    }

    static func dismantleNSView(_ nsView: SidebarDragSourceView, coordinator: Coordinator) {
        nsView.setTransientInteractionEnabled(false)
    }

    final class Coordinator: NSObject {
        var configuration: SidebarDragSourceConfiguration

        init(configuration: SidebarDragSourceConfiguration) {
            self.configuration = configuration
        }
    }
}

extension View {
    func sidebarDragSource(
        _ configuration: SidebarDragSourceConfiguration
    ) -> some View {
        overlay {
            SidebarDragSourceBridge(configuration: configuration)
        }
    }
}

struct SidebarDragPreviewSession {
    let descriptor: SumiNativeDragPreviewDescriptor
    let previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset]
    let previewModel: SidebarDragPreviewModel
    let primaryAsset: SidebarDragPreviewAsset
}

@MainActor
enum SidebarDragPreviewSessionFactory {
    static func make(
        configuration: SidebarDragSourceConfiguration,
        sourceSize: CGSize,
        sourceOffsetFromBottomLeading point: CGPoint
    ) -> SidebarDragPreviewSession? {
        let descriptor = SumiNativeDragPreviewDescriptor(
            item: configuration.item,
            previewIcon: configuration.previewIcon,
            sourceZone: configuration.sourceZone,
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: point,
            pinnedConfig: configuration.pinnedConfig,
            itemCount: configuration.itemCount,
            folderGlyphPresentation: configuration.folderGlyphPresentation,
            folderGlyphPalette: configuration.folderGlyphPalette
        )
        let previewAssets = buildPreviewAssets(
            descriptor: descriptor,
            previewKind: configuration.previewKind
        )
        guard let primaryAsset = previewAssets[configuration.previewKind] else { return nil }

        let model = SidebarDragPreviewModel(
            item: configuration.item,
            sourceZone: configuration.sourceZone,
            baseKind: configuration.previewKind,
            previewIcon: configuration.previewIcon,
            chromeTemplateSystemImageName: configuration.chromeTemplateSystemImageName,
            sourceSize: sourceSize,
            normalizedTopLeadingAnchor: SidebarDragPreviewModel.normalizedTopLeadingAnchor(
                fromBottomLeading: point,
                in: sourceSize
            ),
            pinnedConfig: configuration.pinnedConfig,
            itemCount: configuration.itemCount,
            shortcutPresentationState: configuration.previewPresentationState,
            folderGlyphPresentation: configuration.folderGlyphPresentation,
            folderGlyphPalette: configuration.folderGlyphPalette
        )

        return SidebarDragPreviewSession(
            descriptor: descriptor,
            previewAssets: previewAssets,
            previewModel: model,
            primaryAsset: primaryAsset
        )
    }

    private static func buildPreviewAssets(
        descriptor: SumiNativeDragPreviewDescriptor,
        previewKind: SidebarDragPreviewKind
    ) -> [SidebarDragPreviewKind: SidebarDragPreviewAsset] {
        let factory = SumiNativeDragImageFactory.shared
        var assets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]

        func insert(_ kind: SidebarDragPreviewKind) {
            let style = kind.nativeStyle
            let size = factory.size(for: style, descriptor: descriptor)
            assets[kind] = SidebarDragPreviewAsset(
                image: factory.image(for: style, descriptor: descriptor, sourceView: nil),
                size: size,
                anchorOffset: factory.offset(for: style, descriptor: descriptor)
            )
        }

        insert(previewKind)

        if descriptor.item.kind == .tab {
            insert(.essentialsTile)
            if previewKind != .row {
                insert(.row)
            }
        }

        return assets
    }
}

@MainActor
final class SidebarDragSourceView: NSView, NSDraggingSource, SidebarTransientInteractionDisarmable {
    weak var coordinator: SidebarDragSourceBridge.Coordinator?
    var configuration = SidebarDragSourceConfiguration(
        item: SumiDragItem(tabId: UUID(), title: ""),
        sourceZone: .essentials,
        previewKind: .row
    )
    private(set) var isInteractive: Bool = true

    private let dragThreshold: CGFloat = 3
    private var mouseDownEvent: NSEvent?
    private var mouseDownPoint: CGPoint?
    private var didStartDrag = false

    override var acceptsFirstResponder: Bool {
        true
    }

    func shouldCaptureInteraction(
        at point: NSPoint,
        eventType: NSEvent.EventType?
    ) -> Bool {
        let configuration = resolvedConfiguration
        guard isInteractive, configuration.isEnabled, bounds.contains(point) else {
            return false
        }

        guard Self.handlesInteraction(for: eventType) else {
            return false
        }

        return !configuration.exclusionZones.contains { $0.contains(point, in: bounds) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        shouldCaptureInteraction(
            at: point,
            eventType: (NSApp.currentEvent ?? window?.currentEvent)?.type
        ) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive, resolvedConfiguration.isEnabled else { return }
        window?.makeFirstResponder(self)
        mouseDownEvent = event
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInteractive, resolvedConfiguration.isEnabled, !didStartDrag, let mouseDownPoint else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        guard distance >= dragThreshold else { return }
        startDrag(with: mouseDownEvent ?? event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractive, resolvedConfiguration.isEnabled else { return }
        if !didStartDrag {
            resolvedConfiguration.onActivate?()
        }
        resetMouseState()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        SidebarDragState.shared.resetInteractionState()
        resetMouseState()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        movedTo screenPoint: NSPoint
    ) {
        guard didStartDrag,
              let location = currentGlobalLocation(fromScreenPoint: screenPoint) else { return }
        updateInternalDragState(at: location)
    }

    private var resolvedConfiguration: SidebarDragSourceConfiguration {
        coordinator?.configuration ?? configuration
    }

    func update(configuration: SidebarDragSourceConfiguration) {
        self.configuration = configuration
        setTransientInteractionEnabled(configuration.isEnabled)
    }

    func setTransientInteractionEnabled(_ isEnabled: Bool) {
        guard isInteractive != isEnabled else { return }

        if !isEnabled,
           didStartDrag,
           !shouldPreserveSharedDragStateOnTeardown {
            SidebarDragState.shared.resetInteractionState()
        }

        isInteractive = isEnabled
        resetMouseState()
    }

    private func startDrag(with event: NSEvent) {
        guard isInteractive, resolvedConfiguration.isEnabled else { return }
        let configuration = resolvedConfiguration
        let point = convert(event.locationInWindow, from: nil)
        guard let previewSession = SidebarDragPreviewSessionFactory.make(
            configuration: configuration,
            sourceSize: bounds.size,
            sourceOffsetFromBottomLeading: point
        ) else { return }

        didStartDrag = true
        let dragLocation = currentGlobalLocation(for: point)
        SidebarDragState.shared.beginInternalDragSession(
            itemId: configuration.item.tabId,
            location: dragLocation,
            previewKind: configuration.previewKind,
            previewAssets: previewSession.previewAssets,
            previewModel: previewSession.previewModel
        )
        updateInternalDragState(at: dragLocation)

        let dragItem = NSDraggingItem(pasteboardWriter: configuration.item.pasteboardItem())
        let frame = NSRect(
            x: point.x - previewSession.primaryAsset.anchorOffset.x,
            y: point.y - previewSession.primaryAsset.anchorOffset.y,
            width: previewSession.primaryAsset.size.width,
            height: previewSession.primaryAsset.size.height
        )
        dragItem.setDraggingFrame(frame, contents: transparentImage(size: previewSession.primaryAsset.size))

        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func currentGlobalLocation(for localPoint: CGPoint) -> CGPoint {
        guard let window else { return localPoint }
        let pointInWindow = convert(localPoint, to: nil)
        let windowHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGPoint(x: pointInWindow.x, y: windowHeight - pointInWindow.y)
    }

    private func currentGlobalLocation(fromScreenPoint screenPoint: NSPoint) -> CGPoint? {
        guard let window else { return nil }
        let pointInWindow = window.convertPoint(fromScreen: screenPoint)
        let windowHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGPoint(x: pointInWindow.x, y: windowHeight - pointInWindow.y)
    }

    private func updateInternalDragState(at location: CGPoint) {
        let state = SidebarDragState.shared
        SidebarDropResolver.updateState(
            location: location,
            state: state,
            draggedItem: resolvedConfiguration.item
        )
    }

    private var shouldPreserveSharedDragStateOnTeardown: Bool {
        guard didStartDrag else { return false }

        let state = SidebarDragState.shared
        return state.isDragging
            && state.isInternalDragSession
            && state.activeDragItemId == resolvedConfiguration.item.tabId
    }

    private func transparentImage(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private static func handlesInteraction(for eventType: NSEvent.EventType?) -> Bool {
        guard let eventType else { return false }
        return switch eventType {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            true
        default:
            false
        }
    }

    private func resetMouseState() {
        mouseDownEvent = nil
        mouseDownPoint = nil
        didStartDrag = false
    }
}
