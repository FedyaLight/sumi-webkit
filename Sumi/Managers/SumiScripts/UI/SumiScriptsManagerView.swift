//
//  SumiScriptsManagerView.swift
//  Sumi
//
//  Dashboard view for managing all installed userscripts.
//  Integrated into Sumi Settings.
//
//  Battery/CPU Optimized:
//  - Strictly opaque.
//  - Minimalist layout.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SumiScriptsManagerView: View {
    @ObservedObject var manager: SumiScriptsManager
    @State private var searchText = ""
    @State private var installURLString = ""
    @State private var exportIncludeSiteRules = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            installSection
            behaviorSection
            backupSection

            runtimeErrorsSection

            Divider()

            if manager.allScripts.isEmpty {
                emptyStateView
            } else {
                scriptsList
            }
        }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Userscripts Manager")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Native Greasemonkey-compatible script host.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }

    @ViewBuilder
    private var runtimeErrorsSection: some View {
        if !manager.runtimeErrors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Runtime errors")
                        .font(.headline)
                    Spacer()
                    Button("Clear log") {
                        manager.clearRuntimeErrors()
                    }
                    .buttonStyle(.bordered)
                }
                Text("Errors and unhandled promise rejections from userscripts (similar to Chrome’s extension error page).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(manager.runtimeErrors) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.scriptFilename)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(entry.kind)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if !entry.message.isEmpty {
                                    Text(entry.message)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                if !entry.location.isEmpty {
                                    Text(entry.location)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                                if !entry.stack.isEmpty {
                                    Text(entry.stack)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                        .lineLimit(8)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            .padding(.vertical, 4)
        }
    }

    private var installSection: some View {
        HStack(spacing: 8) {
            TextField("Install from .user.js URL", text: $installURLString)
                .textFieldStyle(.roundedBorder)

            Button("Install") {
                guard let url = URL(string: installURLString) else { return }
                Task { @MainActor in
                    if await manager.installScript(from: url) {
                        installURLString = ""
                    }
                }
            }
            .disabled(URL(string: installURLString) == nil)

            Button("Update All") {
                manager.updateAllScripts()
            }
            .disabled(manager.allScripts.isEmpty)
        }
    }

    private var behaviorSection: some View {
        GroupBox("Run mode and updates") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Script run mode", selection: Binding(
                    get: { manager.runMode },
                    set: { manager.runMode = $0 }
                )) {
                    Text("Match on all sites (default)").tag(UserScriptRunMode.alwaysMatch)
                    Text("Only allowed sites (no @match until you allow on a site)").tag(UserScriptRunMode.strictOrigin)
                }
                .pickerStyle(.radioGroup)

                Text("Strict mode: the popover switch is the allowlist for that site only. “All sites” mode: switch off on a page disables the script there only (still runs on other sites).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Defer loading script bodies until first inject (saves RAM with large scripts)", isOn: Binding(
                    get: { manager.lazyScriptBodyEnabled },
                    set: { manager.lazyScriptBodyEnabled = $0 }
                ))

                Picker("Auto-update installed scripts", selection: Binding(
                    get: { manager.autoUpdateInterval },
                    set: { manager.autoUpdateInterval = $0 }
                )) {
                    Text("Off").tag("off")
                    Text("When SumiScripts enables").tag("startup")
                    Text("Every hour").tag("hourly")
                    Text("Every day").tag("daily")
                }
                .pickerStyle(.segmented)
            }
            .padding(4)
        }
    }

    private var backupSection: some View {
        GroupBox("Backup") {
            HStack(spacing: 16) {
                Toggle("Include site allow/deny in export", isOn: $exportIncludeSiteRules)
                Spacer()
                Button("Export…") {
                    exportBackup()
                }
                .disabled(!manager.isEnabled || manager.allScripts.isEmpty)
                Button("Import…") {
                    importBackup()
                }
                .disabled(!manager.isEnabled)
            }
            .padding(4)
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "SumiScripts-backup.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try manager.exportBackup(to: url, includeOriginRules: exportIncludeSiteRules)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let n = try manager.importBackup(from: url)
            let alert = NSAlert()
            alert.messageText = "Import finished"
            alert.informativeText = "Imported \(n) file(s). Reload if scripts do not appear."
            alert.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "curlybraces.square")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundColor(.secondary.opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No Userscripts Installed")
                    .font(.headline)
                Text("Scripts dropped into the UserScripts folder will appear here automatically.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Open Scripts Folder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: manager.scriptsDirectory.path)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var scriptsList: some View {
        VStack(spacing: 12) {
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search scripts...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Button("Reload All") {
                    manager.reloadScripts()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredScripts) { script in
                        ScriptManagerRow(manager: manager, script: script)
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private var filteredScripts: [SumiInstalledUserScript] {
        if searchText.isEmpty {
            return manager.allScripts
        }
        return manager.allScripts.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.filename.localizedCaseInsensitiveContains(searchText)
        }
    }
}

private struct ScriptManagerRow: View {
    @ObservedObject var manager: SumiScriptsManager
    let script: SumiInstalledUserScript
    
    @State private var isEnabled: Bool

    init(manager: SumiScriptsManager, script: SumiInstalledUserScript) {
        self.manager = manager
        self.script = script
        _isEnabled = State(initialValue: script.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(script.name)
                            .font(.headline)
                        
                        if let version = script.metadata.version {
                            Text("v\(version)")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    if let desc = script.metadata.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text(script.filename)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 4)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle("", isOn: $isEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .labelsHidden()
                        .onChange(of: isEnabled) { _, newValue in
                            manager.setScriptEnabled(newValue, filename: script.filename)
                        }
                    
                    HStack(spacing: 12) {
                        Button {
                            NSWorkspace.shared.open(manager.scriptsDirectory.appendingPathComponent(script.filename))
                        } label: {
                            Image(systemName: "pencil.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Edit Source File")

                        Button {
                            // Reveal in Finder
                            NSWorkspace.shared.activateFileViewerSelecting([manager.scriptsDirectory.appendingPathComponent(script.filename)])
                        } label: {
                            Image(systemName: "folder.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")

                        Button(role: .destructive) {
                            manager.deleteScript(filename: script.filename)
                        } label: {
                            Image(systemName: "trash.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Delete Script")
                    }
                    .font(.title3)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Stats / Info Badge
            HStack(spacing: 16) {
                InfoBadge(icon: "clock", text: "\(script.metadata.runAt.rawValue)")
                InfoBadge(icon: "target", text: "\(script.metadata.matches.count + script.metadata.includes.count) rules")
                if !script.metadata.resources.isEmpty {
                    InfoBadge(icon: "archivebox", text: "\(script.metadata.resources.count) resources")
                }
                if !script.metadata.requires.isEmpty {
                    InfoBadge(icon: "link", text: "\(script.metadata.requires.count) requires")
                }
                if !script.metadata.connects.isEmpty {
                    InfoBadge(icon: "network", text: "\(script.metadata.connects.count) connects")
                }
                Spacer()
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
    }
}

private struct InfoBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 9))
        .foregroundColor(.secondary)
    }
}
