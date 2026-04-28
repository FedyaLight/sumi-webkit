import Foundation
import UserScript
import WebKit

@MainActor
final class SumiWebNotificationUserScript: NSObject, UserScript, UserScriptMessaging, WKScriptMessageHandlerWithReply {
    private let context: String
    let broker: UserScriptMessageBroker
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = true
    let messageNames: [String]

    init(tab: Tab) {
        self.context = "sumiWebNotifications_\(tab.id.uuidString)"
        self.broker = UserScriptMessageBroker(context: context, requiresRunInPageContentWorld: true)
        self.messageNames = [context]
        self.source = Self.makeSource(context: context)
        super.init()
        registerSubfeature(delegate: SumiWebNotificationSubfeature(tab: tab))
    }

    private static func makeSource(context: String) -> String {
        """
        (function() {
            if (window.__sumiWebNotificationsInstalled) { return; }
            window.__sumiWebNotificationsInstalled = true;

            const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(context)"];
            if (!handler) { return; }

            const originalNotification = window.Notification;
            const originalPermissions = navigator.permissions;
            const originalPermissionsQuery = originalPermissions && typeof originalPermissions.query === "function"
                ? originalPermissions.query.bind(originalPermissions)
                : null;
            let permissionCache = "default";
            const activeNotifications = new Map();

            function makeId(prefix) {
                if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
                    return prefix + "-" + crypto.randomUUID();
                }
                return prefix + "-" + Date.now() + "-" + Math.random().toString(36).slice(2);
            }

            function normalizePermission(value) {
                if (value === "granted" || value === "denied" || value === "default") {
                    return value;
                }
                return "default";
            }

            function permissionsAPIState(value) {
                value = normalizePermission(value);
                return value === "default" ? "prompt" : value;
            }

            function post(method, params) {
                return handler.postMessage({
                    context: "\(context)",
                    featureName: "webNotifications",
                    method: method,
                    id: params && params.id ? params.id : makeId(method),
                    params: params || {}
                });
            }

            function normalizeOptions(options) {
                options = options || {};
                return {
                    body: options.body == null ? "" : String(options.body),
                    icon: options.icon == null ? "" : String(options.icon),
                    image: options.image == null ? "" : String(options.image),
                    tag: options.tag == null ? "" : String(options.tag),
                    silent: !!options.silent
                };
            }

            function fire(target, type) {
                const event = typeof Event === "function" ? new Event(type) : { type: type };
                if (target.__listeners && target.__listeners[type]) {
                    target.__listeners[type].slice().forEach(function(listener) {
                        try { listener.call(target, event); } catch (error) { setTimeout(function() { throw error; }); }
                    });
                }
                const handlerName = "on" + type;
                if (typeof target[handlerName] === "function") {
                    try { target[handlerName].call(target, event); } catch (error) { setTimeout(function() { throw error; }); }
                }
            }

            function refreshPermission() {
                return post("getPermission", { id: makeId("permission") }).then(function(result) {
                    permissionCache = normalizePermission(result && result.permission);
                    return permissionCache;
                }, function() {
                    permissionCache = "default";
                    return permissionCache;
                });
            }

            function SumiNotification(title, options) {
                if (!(this instanceof SumiNotification)) {
                    throw new TypeError("Failed to construct 'Notification': Please use the 'new' operator.");
                }

                this.title = title == null ? "" : String(title);
                this.body = options && options.body != null ? String(options.body) : "";
                this.tag = options && options.tag != null ? String(options.tag) : "";
                this.icon = options && options.icon != null ? String(options.icon) : "";
                this.onclick = null;
                this.onclose = null;
                this.onerror = null;
                this.onshow = null;
                this.__listeners = {};

                const notification = this;
                const id = makeId("notification");
                activeNotifications.set(id, notification);
                post("showNotification", {
                    id: id,
                    title: notification.title,
                    options: normalizeOptions(options)
                }).then(function(result) {
                    permissionCache = normalizePermission(result && result.permission);
                    if (result && result.delivered) {
                        notification.__sumiIdentifier = result.identifier || "";
                        fire(notification, "show");
                    } else {
                        fire(notification, "error");
                    }
                }, function() {
                    fire(notification, "error");
                });
            }

            SumiNotification.prototype.addEventListener = function(type, listener) {
                if (typeof listener !== "function") { return; }
                type = String(type);
                this.__listeners[type] = this.__listeners[type] || [];
                this.__listeners[type].push(listener);
            };
            SumiNotification.prototype.removeEventListener = function(type, listener) {
                type = String(type);
                const listeners = this.__listeners[type] || [];
                this.__listeners[type] = listeners.filter(function(candidate) { return candidate !== listener; });
            };
            SumiNotification.prototype.dispatchEvent = function(event) {
                if (!event || !event.type) { return true; }
                fire(this, String(event.type));
                return true;
            };
            SumiNotification.prototype.close = function() {
                if (this.__sumiIdentifier) {
                    post("closeNotification", { id: makeId("close"), identifier: this.__sumiIdentifier }).catch(function() {});
                }
                fire(this, "close");
            };

            Object.defineProperty(SumiNotification, "permission", {
                configurable: true,
                enumerable: true,
                get: function() { return permissionCache; }
            });

            SumiNotification.requestPermission = function(callback) {
                return post("requestPermission", { id: makeId("request") }).then(function(result) {
                    permissionCache = normalizePermission(result && result.permission);
                    if (typeof callback === "function") {
                        callback(permissionCache);
                    }
                    return permissionCache;
                }, function() {
                    permissionCache = "denied";
                    if (typeof callback === "function") {
                        callback(permissionCache);
                    }
                    return permissionCache;
                });
            };

            Object.defineProperty(SumiNotification, "name", { value: "Notification" });
            if (originalNotification && originalNotification.maxActions != null) {
                SumiNotification.maxActions = originalNotification.maxActions;
            } else {
                SumiNotification.maxActions = 0;
            }

            window.Notification = SumiNotification;

            if (originalPermissionsQuery) {
                try {
                    navigator.permissions.query = function(descriptor) {
                        if (descriptor && descriptor.name === "notifications") {
                            return refreshPermission().then(function(permission) {
                                return {
                                    name: "notifications",
                                    state: permissionsAPIState(permission),
                                    onchange: null,
                                    addEventListener: function() {},
                                    removeEventListener: function() {},
                                    dispatchEvent: function() { return true; }
                                };
                            });
                        }
                        return originalPermissionsQuery(descriptor);
                    };
                } catch (_) {
                    try {
                        Object.defineProperty(navigator.permissions, "query", {
                            configurable: true,
                            value: function(descriptor) {
                                if (descriptor && descriptor.name === "notifications") {
                                    return refreshPermission().then(function(permission) {
                                        return {
                                            name: "notifications",
                                            state: permissionsAPIState(permission),
                                            onchange: null,
                                            addEventListener: function() {},
                                            removeEventListener: function() {},
                                            dispatchEvent: function() { return true; }
                                        };
                                    });
                                }
                                return originalPermissionsQuery(descriptor);
                            }
                        });
                    } catch (_) {}
                }
            }

            refreshPermission();
        })();
        """
    }

    @MainActor
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        let action = broker.messageHandlerFor(message)
        do {
            let json = try await broker.execute(action: action, original: message)
            return (json, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}

@MainActor
private final class SumiWebNotificationSubfeature: NSObject, Subfeature {
    let featureName = "webNotifications"
    let messageOriginPolicy: MessageOriginPolicy = .all
    weak var broker: UserScriptMessageBroker?
    weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
        super.init()
    }

    func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        switch methodName {
        case "getPermission", "requestPermission", "showNotification", "closeNotification":
            return { [weak self] params, original in
                try await self?.handle(method: methodName, params: params, original: original)
            }
        default:
            return nil
        }
    }

    private func handle(method: String, params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let tab,
              let browserManager = tab.browserManager,
              let tabContext = tab.webNotificationTabContext(for: original.webView)
        else {
            return SumiJSONValue.object([
                "permission": .string(SumiWebNotificationPermissionState.denied.rawValue),
                "permissionsAPIState": .string("denied"),
                "delivered": .bool(false),
                "reason": .string("notification-context-unavailable")
            ])
        }

        let payload = SumiWebNotificationMessagePayload.decode(from: params)
        let request = SumiWebNotificationRequest(id: payload.id, frame: original.frameInfo)

        switch method {
        case "getPermission":
            let state = await browserManager.notificationPermissionBridge.currentWebsitePermissionState(
                request: request,
                tabContext: tabContext
            )
            return permissionResponse(state: state, reason: "permission-state")

        case "requestPermission":
            let state = await browserManager.notificationPermissionBridge.requestWebsitePermission(
                request: request,
                tabContext: tabContext
            )
            return permissionResponse(state: state, reason: "request-permission")

        case "showNotification":
            let result = await browserManager.notificationPermissionBridge.postWebsiteNotification(
                request: request,
                tabContext: tabContext,
                title: payload.title,
                body: payload.body,
                iconURL: payload.iconURL,
                imageURL: payload.imageURL,
                tag: payload.tag,
                isSilent: payload.isSilent,
                webView: original.webView,
                pageValidator: { [weak tab] in
                    tab?.currentPermissionPageId() == tabContext.pageId
                }
            )
            return postResponse(result)

        case "closeNotification":
            if let identifier = payload.identifier {
                await browserManager.notificationPermissionBridge.closeNotification(identifier: identifier)
            }
            return SumiJSONValue.object(["accepted": .bool(true)])

        default:
            return nil
        }
    }

    private func permissionResponse(
        state: SumiWebNotificationPermissionState,
        reason: String
    ) -> SumiJSONValue {
        SumiJSONValue.object([
            "permission": .string(state.rawValue),
            "permissionsAPIState": .string(state.permissionsAPIState),
            "reason": .string(reason)
        ])
    }

    private func postResponse(_ result: SumiNotificationPostResult) -> SumiJSONValue {
        SumiJSONValue.object([
            "delivered": .bool(result.delivered),
            "permission": .string(result.permission.rawValue),
            "permissionsAPIState": .string(result.permission.permissionsAPIState),
            "reason": .string(result.reason),
            "identifier": .string(result.identifier?.rawValue ?? "")
        ])
    }
}

private struct SumiWebNotificationMessagePayload {
    let id: String
    let title: String
    let body: String
    let iconURL: URL?
    let imageURL: URL?
    let tag: String?
    let isSilent: Bool
    let identifier: SumiNotificationIdentifier?

    static func decode(from params: Any) -> SumiWebNotificationMessagePayload {
        let dictionary = params as? [String: Any] ?? [:]
        let options = dictionary["options"] as? [String: Any] ?? [:]
        let id = dictionary["id"] as? String ?? UUID().uuidString
        let title = dictionary["title"] as? String ?? ""
        let body = options["body"] as? String ?? dictionary["body"] as? String ?? ""
        return SumiWebNotificationMessagePayload(
            id: id,
            title: title,
            body: body,
            iconURL: url(options["icon"] as? String),
            imageURL: url(options["image"] as? String),
            tag: nonEmpty(options["tag"] as? String),
            isSilent: options["silent"] as? Bool ?? false,
            identifier: nonEmpty(dictionary["identifier"] as? String).map {
                SumiNotificationIdentifier(rawValue: $0)
            }
        )
    }

    private static func url(_ value: String?) -> URL? {
        guard let value = nonEmpty(value) else { return nil }
        return URL(string: value)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Tab {
    func webNotificationTabContext(for webView: WKWebView?) -> SumiWebNotificationTabContext? {
        guard let profile = resolveProfile() else { return nil }

        let tabId = id.uuidString.lowercased()
        let pageGeneration = String(extensionRuntimeDocumentSequence)
        let committedURL = extensionRuntimeCommittedMainDocumentURL
        return SumiWebNotificationTabContext(
            tabId: tabId,
            pageId: "\(tabId):\(pageGeneration)",
            profilePartitionId: profile.id.uuidString.lowercased(),
            isEphemeralProfile: profile.isEphemeral,
            committedURL: committedURL,
            visibleURL: webView?.url ?? url,
            mainFrameURL: committedURL ?? webView?.url ?? url,
            isActiveTab: isCurrentTab,
            isVisibleTab: primaryWindowId != nil,
            navigationOrPageGeneration: pageGeneration
        )
    }
}
