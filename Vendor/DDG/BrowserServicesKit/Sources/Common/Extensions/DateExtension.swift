import Foundation

public extension Date {
    static var weekAgo: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    static var monthAgo: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    }
}
