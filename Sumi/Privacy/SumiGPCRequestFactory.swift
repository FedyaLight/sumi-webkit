import Foundation

/// Computes the `Sec-GPC: 1` header rewrite for outgoing navigation requests,
/// following the DuckDuckGo approach: add the header to eligible top-level
/// requests that don't already carry it, and never touch anything else.
///
/// Kept as a pure value type so the eligibility rules can be unit tested without
/// standing up WebKit or a navigation delegate chain.
struct SumiGPCRequestFactory {
    enum Constants {
        static let secGPCHeaderField = "Sec-GPC"
        static let secGPCHeaderValue = "1"
    }

    /// Returns a copy of `request` with `Sec-GPC: 1` added, or `nil` if no
    /// rewrite is needed (GPC disabled, the request is already tagged, or the
    /// request isn't eligible). Callers should treat a non-nil result as "cancel
    /// the original navigation and reload with this request instead."
    func requestAddingGPCHeaderIfNeeded(
        to request: URLRequest,
        isGPCEnabled: Bool
    ) -> URLRequest? {
        guard isGPCEnabled, isEligible(request) else { return nil }
        guard request.value(forHTTPHeaderField: Constants.secGPCHeaderField) == nil else { return nil }

        var rewritten = request
        rewritten.setValue(Constants.secGPCHeaderValue, forHTTPHeaderField: Constants.secGPCHeaderField)
        return rewritten
    }

    /// Only main-frame, plain GET, http(s) requests are eligible. This avoids
    /// ever touching POSTs/form submissions (which would corrupt the submitted
    /// body semantics on reload) and non-web schemes.
    private func isEligible(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }

        let method = (request.httpMethod ?? "GET").uppercased()
        return method == "GET"
    }
}
