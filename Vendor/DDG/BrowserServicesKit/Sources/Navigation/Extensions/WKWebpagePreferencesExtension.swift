//
//  WKWebpagePreferencesExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import WebKit

#if _WEBPAGE_PREFS_AUTOPLAY_POLICY_ENABLED
extension WKWebpagePreferences {

    enum AutoplayPolicySelector {
        static let autoplayPolicy = NSSelectorFromString("_autoplayPolicy")
        static let setAutoplayPolicy = NSSelectorFromString("_setAutoplayPolicy:")
    }

    @objc dynamic public var autoplayPolicy: UInt /*_WKWebsiteAutoplayPolicy*/ {
        get {
            guard self.responds(to: AutoplayPolicySelector.autoplayPolicy),
                  let method = class_getInstanceMethod(object_getClass(self), AutoplayPolicySelector.autoplayPolicy) else {
                assertionFailure("WKWebView does not respond to selector _autoplayPolicy")
                return _WKWebsiteAutoplayPolicy.default.rawValue
            }
            let imp = method_getImplementation(method)
            typealias AutoplayPolicyType = @convention(c) (WKWebpagePreferences, ObjectiveC.Selector) -> UInt
            let autoplayPolicyGetter = unsafeBitCast(imp, to: AutoplayPolicyType.self)
            let autoplayPolicy = autoplayPolicyGetter(self, AutoplayPolicySelector.autoplayPolicy)
            return autoplayPolicy
        }
        set {
            guard self.responds(to: AutoplayPolicySelector.setAutoplayPolicy),
                  let method = class_getInstanceMethod(object_getClass(self), AutoplayPolicySelector.setAutoplayPolicy) else {
                assertionFailure("WKWebView does not respond to selector _setAutoplayPolicy:")
                return
            }
            let imp = method_getImplementation(method)
            typealias SetAutoplayPolicyType = @convention(c) (WKWebpagePreferences, ObjectiveC.Selector, UInt) -> Void
            let setAutoplayPolicyGetter = unsafeBitCast(imp, to: SetAutoplayPolicyType.self)
            setAutoplayPolicyGetter(self, AutoplayPolicySelector.setAutoplayPolicy, newValue)
        }
    }
}

public enum _WKWebsiteAutoplayPolicy: UInt {
    case `default`
    case allow
    case allowWithoutSound
    case deny

    public init(_ mediaTypes: WKAudiovisualMediaTypes) {
        if mediaTypes == WKAudiovisualMediaTypes.all {
            self = .deny
        } else if mediaTypes.contains(.audio) {
            self = .allowWithoutSound
        } else {
            self = .allow
        }
    }
}
#endif
