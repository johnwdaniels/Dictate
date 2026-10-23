import Foundation

struct InsightSample {
    var date: Date
    var wordCount: Int
    var durationSeconds: Double
    var appName: String
    var bundleID: String
}

enum InsightRange: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case all = "All"

    var id: String { rawValue }
}

struct InsightBucket: Identifiable {
    var id: Int
    var label: String
    var words: Int
}

struct InsightAppUse: Identifiable {
    var id: String
    var name: String
    var bundleID: String
    var words: Int
}

struct InsightSummary {
    var words: Int
    var timeSavedSeconds: Double
    var buckets: [InsightBucket]
    var apps: [InsightAppUse]
}

enum InsightsMath {
    /// Ordinary typing speed used for "compared to typing".
    static let typingWordsPerMinute = 40.0

    static func timeSavedSeconds(words: Int, durationSeconds: Double) -> Double {
        let typing = Double(words) / typingWordsPerMinute * 60
        return max(0, typing - max(0, durationSeconds))
    }

    static func timeSavedLabel(seconds: Double) -> (value: String, unit: String) {
        if seconds >= 3600 {
            let hours = seconds / 3600
            if abs(hours - 1) < 0.05 {
                return ("1", "hour")
            }
            let shown = hours >= 10 ? String(format: "%.0f", hours) : String(format: "%.1f", hours)
            return (shown, "hours")
        }
        if seconds >= 60 {
            let minutes = max(1, Int((seconds / 60).rounded()))
            return ("\(minutes)", minutes == 1 ? "minute" : "minutes")
        }
        let whole = Int(seconds.rounded())
        return ("\(whole)", whole == 1 ? "second" : "seconds")
    }

    static func summarize(
        _ samples: [InsightSample],
        range: InsightRange,
        now: Date,
        calendar: Calendar = .current
    ) -> InsightSummary {
        let filtered = samples.filter { includes($0.date, range: range, now: now, calendar: calendar) }
        let words = filtered.reduce(0) { $0 + max(0, $1.wordCount) }
        let duration = filtered.reduce(0.0) { $0 + max(0, $1.durationSeconds) }
        return InsightSummary(
            words: words,
            timeSavedSeconds: timeSavedSeconds(words: words, durationSeconds: duration),
            buckets: buckets(for: filtered, range: range, now: now, calendar: calendar),
            apps: apps(in: filtered)
        )
    }

    private static func includes(_ date: Date, range: InsightRange, now: Date, calendar: Calendar) -> Bool {
        switch range {
        case .day:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .year:
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
        case .all:
            return true
        }
    }

    private static func buckets(
        for samples: [InsightSample],
        range: InsightRange,
        now: Date,
        calendar: Calendar
    ) -> [InsightBucket] {
        switch range {
        case .day:
            let start = calendar.startOfDay(for: now)
            return (0..<24).map { hour in
                let slot = calendar.date(byAdding: .hour, value: hour, to: start) ?? start
                return InsightBucket(
                    id: hour,
                    label: hour % 6 == 0 ? hourLabel(slot, calendar: calendar) : "",
                    words: words(in: samples, same: { calendar.isDate($0, equalTo: slot, toGranularity: .hour) })
                )
            }
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return (0..<7).map { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
                return InsightBucket(
                    id: offset,
                    label: dayLabel(day, calendar: calendar),
                    words: words(in: samples, same: { calendar.isDate($0, inSameDayAs: day) })
                )
            }
        case .month:
            let dayCount = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            return (0..<dayCount).map { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                let number = offset + 1
                return InsightBucket(
                    id: offset,
                    label: number == 1 || number % 10 == 0 ? "\(number)" : "",
                    words: words(in: samples, same: { calendar.isDate($0, inSameDayAs: day) })
                )
            }
        case .year:
            let year = calendar.component(.year, from: now)
            return (1...12).map { month in
                var parts = DateComponents()
                parts.year = year
                parts.month = month
                parts.day = 1
                let date = calendar.date(from: parts) ?? now
                return InsightBucket(
                    id: month,
                    label: monthLabel(date, calendar: calendar),
                    words: words(in: samples, same: { calendar.isDate($0, equalTo: date, toGranularity: .month) })
                )
            }
        case .all:
            let dates = samples.map(\.date)
            let first = dates.min() ?? now
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: first)) ?? first
            let end = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            var buckets: [InsightBucket] = []
            var cursor = start
            var index = 0
            while cursor <= end && index < 240 {
                buckets.append(InsightBucket(
                    id: index,
                    label: monthLabel(cursor, calendar: calendar),
                    words: words(in: samples, same: { calendar.isDate($0, equalTo: cursor, toGranularity: .month) })
                ))
                guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
                index += 1
            }
            return buckets
        }
    }

    private static func words(in samples: [InsightSample], same: (Date) -> Bool) -> Int {
        samples.reduce(0) { total, sample in
            same(sample.date) ? total + max(0, sample.wordCount) : total
        }
    }

    private static func apps(in samples: [InsightSample]) -> [InsightAppUse] {
        var grouped: [String: InsightAppUse] = [:]
        for sample in samples {
            let name = sample.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let bundleID = sample.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = bundleID.isEmpty ? name.lowercased() : bundleID
            if var existing = grouped[key] {
                existing.words += max(0, sample.wordCount)
                grouped[key] = existing
            } else {
                grouped[key] = InsightAppUse(id: key, name: name, bundleID: bundleID, words: max(0, sample.wordCount))
            }
        }
        return grouped.values.sorted { lhs, rhs in
            if lhs.words == rhs.words { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.words > rhs.words
        }
    }

    private static func hourLabel(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let shown = hour % 12 == 0 ? 12 : hour % 12
        return "\(shown)\(hour < 12 ? "a" : "p")"
    }

    private static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let index = calendar.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }

    private static func monthLabel(_ date: Date, calendar: Calendar) -> String {
        let symbols = calendar.shortMonthSymbols
        let index = calendar.component(.month, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}
