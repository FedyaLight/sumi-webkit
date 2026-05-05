//
//  CalendarExtension.swift
//

import Foundation

extension Calendar {
    public func numberOfDaysBetween(_ from: Date, and to: Date) -> Int? {
        let numberOfDays = dateComponents([.day], from: from, to: to)
        return numberOfDays.day
    }
}
