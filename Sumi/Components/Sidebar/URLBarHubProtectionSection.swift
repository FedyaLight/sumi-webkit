import SwiftUI
import WebKit

struct URLBarHubProtectionSection: View {
    let coordinator: SumiProtectionCoordinator
    let currentTab: Tab?
    let webViewProvider: () -> WKWebView?
    let onBack: () -> Void
    let onClose: () -> Void
    let onDidMutate: () -> Void

    @State private var isSiteEnabled = false
    @State private var areSavedRulesEnabled = true
    @State private var savedRules: [String] = []
    @State private var draftRules: [String] = []
    @State private var isActivatingZapper = false
    @State private var errorMessage: String?

    private var plan: SumiProtectionRulePlan {
        coordinator.cachedRulePlan(
            for: currentTab?.url,
            profileId: currentTab?.resolveProfile()?.id
        )
    }

    private var host: String? {
        plan.siteHost ?? currentTab?.url.host?.lowercased()
    }

    private var displayHost: String {
        guard let host else { return "This site" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var normalizedDraftRules: [String] {
        var seen = Set<String>()
        return draftRules.compactMap { rule in
            let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedRule.isEmpty,
                  seen.insert(trimmedRule).inserted
            else {
                return nil
            }
            return trimmedRule
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 14) {
                protectionSection
                Divider()
                elementRulesSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

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
        .onAppear(perform: loadState)
        .accessibilityIdentifier("urlhub-protection-details")
    }

    private var header: some View {
        HStack(spacing: 10) {
            URLBarSiteDataIconButton(
                systemName: "chevron.left",
                help: "Back",
                action: onBack
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Adblock & Protection")
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

    private var protectionSection: some View {
        HStack(spacing: 12) {
            Image(systemName: isSiteEnabled ? "shield.fill" : "shield.slash")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(URLBarHubNativeStyle.primaryText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Protection on this site")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(URLBarHubNativeStyle.primaryText)
                Text(isSiteEnabled ? "Active" : "Off")
                    .font(.system(size: 11.5))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Protection on this site", isOn: siteEnabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(host == nil || plan.requestedLevel == .off)
                .accessibilityIdentifier("urlhub-protection-site-toggle")
        }
        .frame(minHeight: 34)
    }

    private var elementRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Element rules")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(URLBarHubNativeStyle.primaryText)
                Spacer(minLength: 8)
                Text("\(savedRules.count) saved")
                    .font(.system(size: 11.5))
                    .foregroundStyle(URLBarHubNativeStyle.secondaryText)
            }

            HStack(spacing: 10) {
                Button(action: activateElementZapper) {
                    HStack(spacing: 7) {
                        Image(systemName: "eyedropper")
                        Text("Block element")
                        if isActivatingZapper {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(URLBarZoomPopoverButtonStyle(minWidth: 150))
                .disabled(
                    !isSiteEnabled
                        || !areSavedRulesEnabled
                        || isActivatingZapper
                        || currentTab == nil
                )
                .accessibilityIdentifier("urlhub-protection-block-element")

                Toggle("Apply saved rules", isOn: savedRulesEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                    .disabled(!isSiteEnabled)
                    .fixedSize()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            rulesEditor

            HStack(spacing: 8) {
                Button(action: addRule) {
                    Label("Add Rule", systemImage: "plus")
                }

                Spacer(minLength: 8)

                Button("Clear", action: clearRules)
                    .disabled(savedRules.isEmpty && normalizedDraftRules.isEmpty)

                Button("Save", action: saveRules)
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedDraftRules == savedRules)
            }
            .controlSize(.small)
        }
    }

    private var rulesEditor: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if draftRules.isEmpty {
                    Text("No selectors saved for this site.")
                        .font(.system(size: 12))
                        .foregroundStyle(URLBarHubNativeStyle.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                } else {
                    ForEach(draftRules.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            TextField("CSS selector", text: $draftRules[index])
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))

                            Button {
                                draftRules.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete rule")
                            .accessibilityLabel("Delete rule")
                        }
                        .frame(minHeight: 28)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(minHeight: 64, maxHeight: 174)
    }

    private var siteEnabledBinding: Binding<Bool> {
        Binding(
            get: { isSiteEnabled },
            set: { isEnabled in
                guard host != nil else { return }
                isSiteEnabled = isEnabled
                coordinator.setSiteOverride(isEnabled ? .inherit : .disabled, for: currentTab?.url)
                onDidMutate()
            }
        )
    }

    private var savedRulesEnabledBinding: Binding<Bool> {
        Binding(
            get: { areSavedRulesEnabled },
            set: { isEnabled in
                guard let host else { return }
                areSavedRulesEnabled = isEnabled
                SumiAdblockZapperStore.shared.setEnabled(isEnabled, forHost: host)
                applySavedRulesToCurrentWebView()
            }
        )
    }

    private func loadState() {
        guard let host else { return }
        let zapperState = SumiAdblockZapperStore.shared.state(forHost: host)
        isSiteEnabled = plan.sitePolicyAllowsProtection && plan.effectiveLevel != .off
        areSavedRulesEnabled = !zapperState.disabled
        savedRules = zapperState.rules
        draftRules = zapperState.rules
        errorMessage = nil
    }

    private func addRule() {
        draftRules.append("")
    }

    private func saveRules() {
        guard let host else { return }
        SumiAdblockZapperStore.shared.setRules(normalizedDraftRules, forHost: host)
        loadState()
        applySavedRulesToCurrentWebView()
    }

    private func clearRules() {
        guard let host else { return }
        SumiAdblockZapperStore.shared.setRules([], forHost: host)
        loadState()
        applySavedRulesToCurrentWebView()
    }

    private func activateElementZapper() {
        guard let host,
              let webView = webViewProvider()
        else { return }
        isActivatingZapper = true
        errorMessage = nil

        Task { @MainActor in
            let didActivate = await SumiAdblockZapperInjector.activateElementPicker(
                in: webView,
                host: host
            )
            isActivatingZapper = false
            if didActivate {
                onClose()
            } else {
                errorMessage = "Unable to start the element picker."
            }
        }
    }

    private func applySavedRulesToCurrentWebView() {
        guard let host,
              let webView = webViewProvider()
        else { return }
        SumiAdblockZapperInjector.applySavedRules(
            to: webView,
            host: host
        )
    }
}
