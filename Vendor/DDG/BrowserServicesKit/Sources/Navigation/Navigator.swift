//
//  Navigator.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import Common
import Foundation
import WebKit

@MainActor
public struct Navigator {

    let webView: WKWebView
    let distributedNavigationDelegate: DistributedNavigationDelegate
    let currentNavigation: Navigation?
    let expectedNavigations: UnsafeMutablePointer<[ExpectedNavigation]>?

    init(webView: WKWebView, distributedNavigationDelegate: DistributedNavigationDelegate, currentNavigation: Navigation?, expectedNavigations: UnsafeMutablePointer<[ExpectedNavigation]>? = nil) {
        self.webView = webView
        self.distributedNavigationDelegate = distributedNavigationDelegate
        self.currentNavigation = currentNavigation
        self.expectedNavigations = expectedNavigations
    }

    init?(webView: WKWebView) {
        guard let distributedNavigationDelegate = webView.navigationDelegate as? DistributedNavigationDelegate else {
            assertionFailure("webView.navigationDelegate is not DistributedNavigationDelegate")
            return nil
        }
        self.init(webView: webView, distributedNavigationDelegate: distributedNavigationDelegate, currentNavigation: nil, expectedNavigations: nil)
    }

    @discardableResult
    public func go(to item: WKBackForwardListItem, withExpectedNavigationType expectedNavigationType: NavigationType? = .redirect(.developer)) -> ExpectedNavigation? {
        webView.go(to: item)?
            .expectedNavigation(with: expectedNavigationType, distributedNavigationDelegate: distributedNavigationDelegate, currentNavigation: currentNavigation)
            .appending(to: expectedNavigations)
    }

}

@MainActor
public final class ExpectedNavigation {

    internal let navigation: Navigation

    internal init(navigation: Navigation) {
        self.navigation = navigation
    }

    public var navigationResponders: ResponderChain {
        get { // swiftlint:disable:this implicit_getter
            navigation.navigationResponders
        }
        _modify {
            yield &navigation.navigationResponders
        }
    }

    fileprivate func appending(to expectedNavigations: UnsafeMutablePointer<[ExpectedNavigation]>?) -> Self {
        expectedNavigations?.pointee.append(self)
        return self
    }

}
extension ExpectedNavigation: NavigationProtocol {}
extension ExpectedNavigation: CustomDebugStringConvertible {
    public nonisolated var debugDescription: String {
        guard Thread.isMainThread else {
            assertionFailure("Accessing ExpectedNavigation from background thread")
            return "<ExpectedNavigation ?>"
        }
        return MainActor.assumeMainThread {
            "<ExpectedNavigation \(navigation.identity) \(navigation.navigationActions.last != nil ? "from_redirected: #\(navigation.navigationActions.last!.identifier)" : "")>"
        }
    }
}

extension WKNavigation {

    @MainActor
    func expectedNavigation(with expectedNavigationType: NavigationType?, distributedNavigationDelegate: DistributedNavigationDelegate, currentNavigation: Navigation?) -> ExpectedNavigation {
        let navigation = Navigation(identity: NavigationIdentity(self), responders: distributedNavigationDelegate.responders, state: .expected(expectedNavigationType), redirectHistory: currentNavigation?.navigationActions, isCurrent: false)
        navigation.associate(with: self)
        return ExpectedNavigation(navigation: navigation)
    }

}

extension WKWebView {

    public func navigator() -> Navigator? {
        Navigator(webView: self)
    }

    public func navigator(distributedNavigationDelegate: DistributedNavigationDelegate, redirectedNavigation: Navigation?, expectedNavigations: UnsafeMutablePointer<[ExpectedNavigation]>? = nil) -> Navigator {
        Navigator(webView: self, distributedNavigationDelegate: distributedNavigationDelegate, currentNavigation: redirectedNavigation, expectedNavigations: expectedNavigations)
    }

}
