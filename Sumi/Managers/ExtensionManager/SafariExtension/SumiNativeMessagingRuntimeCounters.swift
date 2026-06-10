//
//  SumiNativeMessagingRuntimeCounters.swift
//  Sumi
//
//  Payload-free native messaging runtime counters and signposts.
//  Never logs message bodies or credentials.
//

import Foundation

struct SumiNativeMessagingRuntimeSnapshot: Sendable, Equatable, Codable {
    let delegateSendMessageInvokedCount: Int
    let delegateConnectInvokedCount: Int
    let sendMessageCount: Int
    let connectCount: Int
    let portOpenCount: Int
    let portCloseCount: Int
    let liveRelayPortSessions: Int
    let liveAdapterPortSessions: Int
    let desktopTransportStartCount: Int
    let desktopTransportStopCount: Int
    let liveDesktopTransports: Int
    let coalescedDiagnosticEmits: Int
    let popupOpenCount: Int
    let popupCloseCount: Int
    let contextUnloadCount: Int
    let repeatedIdenticalErrorCount: Int
}

@MainActor
enum SumiNativeMessagingRuntimeCounters {
    private static var delegateSendMessageInvokedCount = 0
    private static var delegateConnectInvokedCount = 0
    private static var sendMessageCount = 0
    private static var connectCount = 0
    private static var portOpenCount = 0
    private static var portCloseCount = 0
    private static var liveRelayPortSessions = 0
    private static var liveAdapterPortSessions = 0
    private static var desktopTransportStartCount = 0
    private static var desktopTransportStopCount = 0
    private static var liveDesktopTransports = 0
    private static var coalescedDiagnosticEmits = 0
    private static var popupOpenCount = 0
    private static var popupCloseCount = 0
    private static var contextUnloadCount = 0
    private static var repeatedIdenticalErrorCount = 0

    static func recordDelegateSendMessageInvoked() {
        delegateSendMessageInvokedCount += 1
        PerformanceTrace.emitEvent("nativeMessaging.delegate.sendMessage")
    }

    static func recordDelegateConnectInvoked() {
        delegateConnectInvokedCount += 1
        PerformanceTrace.emitEvent("nativeMessaging.delegate.connect")
    }

    static func recordSendMessage(applicationIdentifier: String?) {
        sendMessageCount += 1
        PerformanceTrace.emitEvent("nativeMessaging.sendMessage")
        logVerbose {
            "send count=\(sendMessageCount) appId=\(applicationIdentifier ?? "(nil)")"
        }
    }

    static func recordConnect(applicationIdentifier: String?) {
        connectCount += 1
        PerformanceTrace.emitEvent("nativeMessaging.connect")
        logVerbose {
            "connect count=\(connectCount) appId=\(applicationIdentifier ?? "(nil)")"
        }
    }

    static func recordPortOpened() {
        portOpenCount += 1
        liveRelayPortSessions += 1
        PerformanceTrace.emitEvent("nativeMessaging.portOpen")
    }

    static func recordPortClosed() {
        portCloseCount += 1
        liveRelayPortSessions = max(0, liveRelayPortSessions - 1)
        PerformanceTrace.emitEvent("nativeMessaging.portClose")
    }

    static func recordAdapterPortSessionOpened() {
        liveAdapterPortSessions += 1
        PerformanceTrace.emitEvent("nativeMessaging.adapterPortOpen")
    }

    static func recordAdapterPortSessionClosed() {
        liveAdapterPortSessions = max(0, liveAdapterPortSessions - 1)
        PerformanceTrace.emitEvent("nativeMessaging.adapterPortClose")
    }

    static func recordDesktopTransportStarted() {
        desktopTransportStartCount += 1
        liveDesktopTransports += 1
        PerformanceTrace.emitEvent("nativeMessaging.desktopTransportStart")
    }

    static func recordDesktopTransportStopped() {
        desktopTransportStopCount += 1
        liveDesktopTransports = max(0, liveDesktopTransports - 1)
        PerformanceTrace.emitEvent("nativeMessaging.desktopTransportStop")
    }

    static func recordCoalescedDiagnosticEmit(repeatCount: Int) {
        coalescedDiagnosticEmits += 1
        repeatedIdenticalErrorCount += max(0, repeatCount - 1)
        PerformanceTrace.emitEvent("nativeMessaging.diagnosticCoalesced")
    }

    static func recordPopupOpened(extensionId: String) {
        popupOpenCount += 1
        PerformanceTrace.emitEvent("nativeMessaging.popupOpen")
        logVerbose { "popup open ext=\(extensionId) count=\(popupOpenCount)" }
    }

    static func recordPopupClosed(extensionId: String) {
        popupCloseCount += 1
        PerformanceTrace.emitEvent("nativeMessaging.popupClose")
        logVerbose { "popup close ext=\(extensionId) count=\(popupCloseCount)" }
    }

    static func recordContextUnload(extensionId: String) {
        contextUnloadCount += 1
        PerformanceTrace.emitEvent("nativeMessaging.contextUnload")
        logVerbose { "context unload ext=\(extensionId) count=\(contextUnloadCount)" }
    }

    static func snapshot() -> SumiNativeMessagingRuntimeSnapshot {
        SumiNativeMessagingRuntimeSnapshot(
            delegateSendMessageInvokedCount: delegateSendMessageInvokedCount,
            delegateConnectInvokedCount: delegateConnectInvokedCount,
            sendMessageCount: sendMessageCount,
            connectCount: connectCount,
            portOpenCount: portOpenCount,
            portCloseCount: portCloseCount,
            liveRelayPortSessions: liveRelayPortSessions,
            liveAdapterPortSessions: liveAdapterPortSessions,
            desktopTransportStartCount: desktopTransportStartCount,
            desktopTransportStopCount: desktopTransportStopCount,
            liveDesktopTransports: liveDesktopTransports,
            coalescedDiagnosticEmits: coalescedDiagnosticEmits,
            popupOpenCount: popupOpenCount,
            popupCloseCount: popupCloseCount,
            contextUnloadCount: contextUnloadCount,
            repeatedIdenticalErrorCount: repeatedIdenticalErrorCount
        )
    }

    static func logSnapshotIfVerbose(context: String) {
        logPerformanceReportIfVerbose(context: context)
    }

    #if DEBUG
    struct PerformanceReport: Codable, Equatable, Sendable {
        let generatedAt: Date
        let context: String
        let counters: SumiNativeMessagingRuntimeSnapshot
        let hasActivePortSessions: Bool
        let hasActiveDesktopTransports: Bool
    }

    static func buildPerformanceReport(context: String) -> PerformanceReport {
        let counters = snapshot()
        return PerformanceReport(
            generatedAt: Date(),
            context: context,
            counters: counters,
            hasActivePortSessions: counters.liveRelayPortSessions > 0
                || counters.liveAdapterPortSessions > 0,
            hasActiveDesktopTransports: counters.liveDesktopTransports > 0
        )
    }
    #endif

    static func logPerformanceReportIfVerbose(context: String) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            #if DEBUG
                let report = buildPerformanceReport(context: context)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                guard let data = try? encoder.encode(report),
                      let json = String(data: data, encoding: .utf8)
                else {
                    RuntimeDiagnostics.debug(category: "SafariNativeMessagingMetrics") {
                        "performanceReport encode failed context=\(context)"
                    }
                    return
                }
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingMetrics") {
                    "performanceReport \(json)"
                }
            #else
                let snap = snapshot()
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingMetrics") {
                    """
                    context=\(context) \
                    delegateSend=\(snap.delegateSendMessageInvokedCount) \
                    delegateConnect=\(snap.delegateConnectInvokedCount) \
                    send=\(snap.sendMessageCount) \
                    connect=\(snap.connectCount) \
                    portsOpen=\(snap.portOpenCount) \
                    portsClose=\(snap.portCloseCount) \
                    liveRelayPorts=\(snap.liveRelayPortSessions) \
                    liveAdapterPorts=\(snap.liveAdapterPortSessions) \
                    desktopStart=\(snap.desktopTransportStartCount) \
                    desktopStop=\(snap.desktopTransportStopCount) \
                    liveDesktop=\(snap.liveDesktopTransports) \
                    coalesced=\(snap.coalescedDiagnosticEmits) \
                    repeatErrors=\(snap.repeatedIdenticalErrorCount) \
                    popupOpen=\(snap.popupOpenCount) \
                    popupClose=\(snap.popupCloseCount) \
                    contextUnload=\(snap.contextUnloadCount)
                    """
                }
            #endif
        #else
            _ = context
        #endif
    }

    #if DEBUG
    static func resetForTesting() {
        delegateSendMessageInvokedCount = 0
        delegateConnectInvokedCount = 0
        sendMessageCount = 0
        connectCount = 0
        portOpenCount = 0
        portCloseCount = 0
        liveRelayPortSessions = 0
        liveAdapterPortSessions = 0
        desktopTransportStartCount = 0
        desktopTransportStopCount = 0
        liveDesktopTransports = 0
        coalescedDiagnosticEmits = 0
        popupOpenCount = 0
        popupCloseCount = 0
        contextUnloadCount = 0
        repeatedIdenticalErrorCount = 0
    }
    #endif

    private static func logVerbose(_ message: @escaping () -> String) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "SafariNativeMessagingMetrics") {
                message()
            }
        #endif
    }
}
