//
//  DateExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public extension Date {

    /// Returns the date exactly one week ago.
    static var weekAgo: Date {
        guard let date = Calendar.current.date(byAdding: .weekOfMonth, value: -1, to: Date()) else {
            fatalError("Unable to calculate a week ago date.")
        }
        return date
    }

    /// Returns the date exactly one month ago.
    static var monthAgo: Date {
        guard let date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else {
            fatalError("Unable to calculate a month ago date.")
        }
        return date
    }

    /// Returns the date a specific number of days ago from this date instance.
    func daysAgo(_ days: Int) -> Date {
        guard let date = Calendar.current.date(byAdding: .day, value: -days, to: self) else {
            fatalError("Unable to calculate \(days) days ago date from this instance.")
        }
        return date
    }
}
