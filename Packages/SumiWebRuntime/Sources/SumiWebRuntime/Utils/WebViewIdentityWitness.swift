import WebKit

/// A non-owning proof that an `ObjectIdentifier` still names the same live
/// object. State machines use this instead of retaining an object or trusting
/// an address after the original lifetime has ended.
public final class WeakIdentityWitness<Object: AnyObject> {
    public let identifier: ObjectIdentifier
    public private(set) weak var value: Object?

    public init(_ object: Object) {
        identifier = ObjectIdentifier(object)
        value = object
    }

    public func resolve() -> Object? {
        guard let value, ObjectIdentifier(value) == identifier else {
            return nil
        }
        return value
    }

    public func matches(_ object: Object) -> Bool {
        resolve() === object
    }
}

public typealias WebViewIdentityWitness = WeakIdentityWitness<WKWebView>
