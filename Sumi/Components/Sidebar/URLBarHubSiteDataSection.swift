import SwiftUI

struct URLBarSiteDataDetailsView: View {
    @ObservedObject var model: URLBarSiteDataDetailsViewModel

    let currentTab: Tab?
    let profile: Profile?
    let onBack: () -> Void
    let onClose: () -> Void
    let onDidMutate: () -> Void

    @State private var pendingDeletionEntry: SumiSiteDataEntry?

    private var displayHost: String {
        let host = currentTab?.url.host ?? currentTab?.url.absoluteString ?? "This site"
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var loadKey: String {
        [
            profile?.id.uuidString ?? "none",
            currentTab?.id.uuidString ?? "none",
            currentTab?.url.host ?? currentTab?.url.absoluteString ?? "none",
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            content

            if let entry = pendingDeletionEntry {
                URLBarSiteDataDeleteConfirmationView(
                    domain: entry.domain,
                    onCancel: {
                        pendingDeletionEntry = nil
                    },
                    onDelete: {
                        delete(entry)
                    }
                )
                .transition(
                    .scale(scale: 0.98, anchor: .center)
                        .combined(with: .opacity)
                )
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: pendingDeletionEntry?.id)
        .task(id: loadKey) {
            await model.load(url: currentTab?.url, profile: profile)
        }
        .onReceive(SumiSiteDataPolicyStore.shared.changesPublisher) { _ in
            Task {
                await model.load(url: currentTab?.url, profile: profile)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 18) {
                intro
                entriesSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 8)

            HStack {
                Spacer(minLength: 0)
                Button("Done", action: onClose)
                    .buttonStyle(URLBarZoomPopoverButtonStyle(minWidth: 76))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            URLBarSiteDataIconButton(
                systemName: "chevron.left",
                help: "Back",
                action: onBack
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Cookies & Site Data")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(URLBarHubNativeStyle.primaryText)
                    .lineLimit(1)
                URLBarFadingText(
                    displayHost,
                    font: .system(size: 12, weight: .medium),
                    color: URLBarHubNativeStyle.secondaryText
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            URLBarSiteDataIconButton(
                systemName: "xmark",
                help: "Close",
                action: onClose
            )
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Site data stored on this device")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
            Text("Sites can store preferences, session data, and cached files on your device. This data is available to the site and its subdomains.")
                .font(.system(size: 13))
                .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data from this site")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)

            if model.isLoading && model.entries.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading site data...")
                        .font(.system(size: 12))
                        .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            } else if model.entries.isEmpty {
                Text("No site data is stored for \(displayHost).")
                    .font(.system(size: 12.5))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        URLBarSiteDataEntryRow(
                            entry: entry,
                            summary: model.summary(for: entry),
                            policyState: model.policyState(for: entry),
                            isDeleting: model.deletingHosts.contains(entry.domain),
                            onDelete: {
                                pendingDeletionEntry = entry
                            },
                            onToggleBlockStorage: {
                                let state = model.policyState(for: entry)
                                Task {
                                    await model.setBlockStorage(
                                        !state.blockStorage,
                                        for: entry,
                                        url: currentTab?.url,
                                        profile: profile
                                    )
                                    onDidMutate()
                                }
                            },
                            onToggleDeleteOnClose: {
                                let state = model.policyState(for: entry)
                                Task {
                                    await model.setDeleteWhenAllWindowsClosed(
                                        !state.deleteWhenAllWindowsClosed,
                                        for: entry,
                                        url: currentTab?.url,
                                        profile: profile
                                    )
                                    onDidMutate()
                                }
                            }
                        )

                        if entry.id != model.entries.last?.id {
                            Divider()
                                .padding(.leading, 38)
                        }
                    }
                }
            }
        }
    }

    private func delete(_ entry: SumiSiteDataEntry) {
        pendingDeletionEntry = nil
        Task {
            await model.delete(
                entry: entry,
                url: currentTab?.url,
                profile: profile
            )
            onDidMutate()
        }
    }
}
struct URLBarSiteDataDeleteConfirmationView: View {
    let domain: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black
                .opacity(colorScheme == .dark ? 0.28 : 0.12)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(URLBarHubNativeStyle.destructiveBackground)
                    .clipShape(Circle())

                VStack(spacing: 6) {
                    Text("Delete cookies and site data?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(URLBarHubNativeStyle.primaryText)
                        .multilineTextAlignment(.center)
                    Text("This will delete cookies and site data for \(domain).")
                        .font(.system(size: 12.5))
                        .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(URLBarSiteDataConfirmationButtonStyle(role: .secondary))

                    Button("Delete", action: onDelete)
                        .buttonStyle(URLBarSiteDataConfirmationButtonStyle(role: .destructive))
                }
            }
            .padding(18)
            .frame(maxWidth: 330)
            .background(URLBarHubNativeStyle.backgroundFallback)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(URLBarHubNativeStyle.separator, lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, x: 0, y: 8)
            .padding(16)
        }
    }
}

struct URLBarSiteDataConfirmationButtonStyle: ButtonStyle {
    enum Role {
        case secondary
        case destructive
    }

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private var foregroundColor: Color {
        switch role {
        case .secondary:
            return URLBarHubNativeStyle.primaryText
        case .destructive:
            return .white
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch role {
        case .secondary:
            return isPressed || isHovering
                ? URLBarHubNativeStyle.hoveredControlBackground
                : URLBarHubNativeStyle.controlBackground
        case .destructive:
            let base = URLBarHubNativeStyle.destructiveBackground
            return isPressed || isHovering ? base.opacity(0.88) : base
        }
    }
}

struct URLBarSiteDataEntryRow: View {
    let entry: SumiSiteDataEntry
    let summary: String
    let policyState: SumiSiteDataPolicyState
    let isDeleting: Bool
    let onDelete: () -> Void
    let onToggleBlockStorage: () -> Void
    let onToggleDeleteOnClose: () -> Void

    @State private var isTitleHovered = false
    @State private var isDeleteHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                titleArea

                Button(action: onDelete) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isDeleteHovered ? URLBarHubNativeStyle.hoveredControlBackground : Color.clear)

                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                .disabled(isDeleting)
                .help("Delete data for \(entry.domain)")
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isDeleteHovered = hovering
                    }
                }
            }

            VStack(spacing: 6) {
                URLBarSiteDataActionButton(
                    title: policyState.blockStorage
                        ? "Allow saving data"
                        : "Block saving data",
                    systemName: policyState.blockStorage ? "checkmark.circle" : "nosign",
                    action: onToggleBlockStorage
                )
                URLBarSiteDataActionButton(
                    title: policyState.deleteWhenAllWindowsClosed
                        ? "Keep after all windows close"
                        : "Delete when all windows close",
                    systemName: policyState.deleteWhenAllWindowsClosed ? "checkmark.circle" : "clock.arrow.circlepath",
                    action: onToggleDeleteOnClose
                )
            }
            .disabled(isDeleting)
        }
        .padding(.vertical, 9)
    }

    private var titleArea: some View {
        HStack(spacing: 10) {
            URLBarSiteDataFavicon(domain: entry.domain)

            VStack(alignment: .leading, spacing: 2) {
                URLBarFadingText(
                    entry.domain,
                    font: .system(size: 13, weight: .medium),
                    color: URLBarHubNativeStyle.primaryText
                )
                URLBarFadingText(
                    summary,
                    font: .system(size: 11.5),
                    color: URLBarHubNativeStyle.secondaryText
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTitleHovered ? URLBarHubNativeStyle.hoveredControlBackground : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isTitleHovered = hovering
            }
        }
    }
}

struct URLBarSiteDataActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 14, height: 14)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(URLBarHubNativeStyle.primaryText)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .background(isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct URLBarSiteDataFavicon: View {
    let domain: String

    var body: some View {
        Group {
            if let image = cachedFavicon {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @MainActor
    private var cachedFavicon: Image? {
        let normalizedDomain = domain.normalizedWebsiteDataDomain
        guard !normalizedDomain.isEmpty else { return nil }

        if let url = URL(string: "https://\(normalizedDomain)"),
           let key = SumiFaviconResolver.cacheKey(for: url),
           let image = Tab.getCachedFavicon(for: key) {
            return image
        }

        if let url = URL(string: "https://\(normalizedDomain)"),
           let image = TabFaviconStore.getCachedImage(
            forDocumentURL: url,
            partition: .regular(nil),
            context: .historyBookmarkRow
           ) {
            return Image(nsImage: image)
        }

        return nil
    }
}

struct URLBarSiteDataIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
                .frame(width: 34, height: 34)
                .background(isHovered ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
