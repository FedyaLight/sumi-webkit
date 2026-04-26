//
//  SumiScriptsPopupView.swift
//  Sumi
//
//  A minimalist, high-performance, opaque SwiftUI popup for managing
//  userscripts on the current page.
//
//  Designed for zero battery impact:
//  - No transparency or background blurs.
//  - Minimalist layouts with LazyVStack.
//  - Opaque solid colors.
//

import AppKit
import SwiftUI
import WebKit

@MainActor
struct SumiScriptsPopupView: View {
    @ObservedObject var manager: SumiScriptsManager
    let currentURL: URL?
    let webView: WKWebView?

    /// Popover lists are per-site; need a stable HTTP(S) host key (same as `UserScriptOriginPolicy`).
    private var popoverSiteURL: URL? {
        guard let url = currentURL else { return nil }
        guard UserScriptOriginPolicy.originKey(from: url).isEmpty == false else { return nil }
        return url
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()

            if !manager.isEnabled {
                disabledStateView
            } else if let url = popoverSiteURL {
                siteScriptsListView(for: url)
            } else {
                noHostURLStateView
            }

            Divider()
            
            footerView
        }
        .frame(width: 320)
        .background(FloatingChromeSurfaceFill(.panel))
    }

    // MARK: - Components

    private var headerView: some View {
        HStack {
            Text("SumiScripts")
                .font(.headline)
            Spacer()
            Text("Enabled")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(FloatingChromeSurfaceFill(.elevated))
    }

    private var disabledStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "power.circle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Manager is Disabled")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Enable to run userscripts on this page.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Scripts Found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(emptyStateDetailCaption)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateDetailCaption: String {
        switch manager.runMode {
        case .strictOrigin:
            return "Turn a script on below to allow it on this site, or change run mode in SumiScripts settings."
        case .alwaysMatch:
            return "No enabled userscripts match this page."
        }
    }

    private var noHostURLStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Page URL")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Open an http(s) page to manage scripts for that site.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private func siteScriptsListView(for url: URL) -> some View {
        let rows = manager.popoverScripts(for: url)
        return Group {
            if rows.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                        Section(header: sectionHeader("Scripts — this site")) {
                            ForEach(rows) { script in
                                ScriptRow(
                                    manager: manager,
                                    script: script,
                                    webView: webView,
                                    currentURL: url
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
    }

    private var footerView: some View {
        HStack {
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: manager.scriptsDirectory.path)
            }) {
                Label("Open Scripts Folder", systemImage: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(4)

            Spacer()

            Button(action: {
                manager.reloadScripts()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Reload Scripts from Disk")
        }
        .padding(10)
        .background(FloatingChromeSurfaceFill(.elevated))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FloatingChromeSurfaceFill(.panel))
    }

}

// MARK: - Subviews

struct ScriptRow: View {
    @ObservedObject var manager: SumiScriptsManager
    let script: SumiInstalledUserScript
    let webView: WKWebView?
    let currentURL: URL?

    init(
        manager: SumiScriptsManager,
        script: SumiInstalledUserScript,
        webView: WKWebView?,
        currentURL: URL? = nil
    ) {
        self.manager = manager
        self.script = script
        self.webView = webView
        self.currentURL = currentURL
    }

    /// strict: switch = allow on this host only. always: switch = run here (`@match` + not site-off); global enable is separate from “off on this site”.
    private var scriptToggleIsOn: Bool {
        guard let url = currentURL else {
            return script.isEnabled
        }
        switch manager.runMode {
        case .strictOrigin:
            guard script.isEnabled else { return false }
            return manager.isOriginAllowed(filename: script.filename, for: url)
        case .alwaysMatch:
            guard script.isEnabled else { return false }
            return !manager.isOriginDenied(filename: script.filename, for: url)
        }
    }

    private var scriptToggleBinding: Binding<Bool> {
        Binding(
            get: { scriptToggleIsOn },
            set: { newValue in
                guard let url = currentURL else {
                    manager.setScriptEnabled(newValue, filename: script.filename)
                    return
                }
                switch manager.runMode {
                case .strictOrigin:
                    if newValue {
                        if script.isEnabled == false {
                            manager.setScriptEnabled(true, filename: script.filename)
                        }
                        manager.setOriginDeny(false, filename: script.filename, for: url)
                        manager.setOriginAllow(true, filename: script.filename, for: url)
                    } else {
                        manager.setOriginAllow(false, filename: script.filename, for: url)
                        manager.setOriginDeny(false, filename: script.filename, for: url)
                    }
                case .alwaysMatch:
                    if newValue {
                        if script.isEnabled == false {
                            manager.setScriptEnabled(true, filename: script.filename)
                        }
                        manager.setOriginDeny(false, filename: script.filename, for: url)
                    } else {
                        manager.setOriginDeny(true, filename: script.filename, for: url)
                    }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.name)
                        .font(.system(size: 13, weight: .medium))
                    if let version = script.metadata.version {
                        Text("v\(version)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    if currentURL != nil, script.isEnabled == false {
                        switch manager.runMode {
                        case .strictOrigin:
                            Text("Off globally — enable here to allow on this site.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        case .alwaysMatch:
                            Text("Off globally — enable here to run on this page.")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: scriptToggleBinding)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
                    .scaleEffect(0.8)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(FloatingChromeSurfaceFill(.elevated))

            // Menu Commands for this script
            if !script.menuCommands.isEmpty {
                ForEach(Array(script.menuCommands.keys).sorted(), id: \.self) { caption in
                    Button(action: {
                        executeCommand(caption)
                    }) {
                        HStack {
                            Text(caption)
                                .font(.system(size: 12))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                        .background(FloatingChromeSurfaceFill(.elevated))
                    }
                    .buttonStyle(.plain)
                    .dividerOver()
                }
            }
        }
    }

    private func executeCommand(_ caption: String) {
        guard let commandId = script.menuCommands[caption],
              let webView = webView else { return }

        manager.executeMenuCommand(script: script, commandId: commandId, webView: webView)
    }

}

// MARK: - View Modifiers

struct DividerOver: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Divider().padding(.leading, 24)
            content
        }
    }
}

extension View {
    func dividerOver() -> some View {
        modifier(DividerOver())
    }
}
