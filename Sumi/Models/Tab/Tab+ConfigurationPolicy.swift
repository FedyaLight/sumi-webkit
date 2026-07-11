import WebKit

@MainActor
extension Tab {
    func preparedConfigurationPolicyChangeSet(
        for webViews: [WKWebView]
    ) -> PreparedConfigurationPolicyChangeSet? {
        configurationPolicyTransaction.preparedChangeSet(for: webViews)
    }

    func cancelConfigurationPolicy(for webViews: [WKWebView]) {
        configurationPolicyTransaction.cancel(webViews)
    }
}
