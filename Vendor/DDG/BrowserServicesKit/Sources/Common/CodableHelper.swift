import Foundation

public struct CodableHelper {
    public static func decode<T: Decodable>(from object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

public typealias DecodableHelper = CodableHelper
