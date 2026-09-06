import Foundation

/// One actual hourly or daily insulin total; never a smoothed value.
struct TDDStats: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let amount: Double
}

/// Calendar ranges and summaries shared by the insulin chart and its header.
enum TDDChartData {
    typealias Interval = Stat.StateModel.StatsTimeInterval

    struct Summary {
        let average: Double
        let total: Double
        let monthlyAverage: Double
    }

    static func initialPosition(for interval: Interval, now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch interval {
        case .day:
            return today
        case .week:
            // Sunday is the week boundary regardless of the user's locale.
            return calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: today), to: today)!
        case .month:
            return calendar.dateInterval(of: .month, for: today)!.start
        case .total:
            let monthStart = calendar.dateInterval(of: .month, for: today)!.start
            return calendar.date(byAdding: .month, value: -2, to: monthStart)!
        }
    }

    static func minorAlignment(for interval: Interval) -> DateComponents {
        interval == .day ? DateComponents(minute: 0, second: 0) : DateComponents(hour: 0, minute: 0, second: 0)
    }

    static func majorAlignment(for interval: Interval) -> DateComponents {
        switch interval {
        case .day: return DateComponents(hour: 0, minute: 0, second: 0)
        case .week: return DateComponents(hour: 0, minute: 0, second: 0, weekday: 1)
        case .month, .total: return DateComponents(day: 1, hour: 0, minute: 0, second: 0)
        }
    }

    /// Snap summaries to the nearest bar boundary. Swift Charts can report a fractional
    /// offset around a native snap target; flooring would incorrectly select the prior day.
    static func visibleRange(from position: Date, for interval: Interval, calendar: Calendar = .current) -> Range<Date> {
        let unit: Calendar.Component = interval == .day ? .hour : .day
        let bucket = calendar.dateInterval(of: unit, for: position)!
        let start = position.timeIntervalSince(bucket.start) < bucket.duration / 2 ? bucket.start : bucket.end
        return start ..< endDate(from: start, for: interval, calendar: calendar)
    }

    static func endDate(from start: Date, for interval: Interval, calendar: Calendar = .current) -> Date {
        switch interval {
        case .day: return calendar.date(byAdding: .day, value: 1, to: start)!
        case .week: return calendar.date(byAdding: .day, value: 7, to: start)!
        case .month: return calendar.date(byAdding: .day, value: 31, to: start)!
        case .total: return calendar.date(byAdding: .month, value: 3, to: start)!
        }
    }

    /// Explicit scale bounds leave enough room to show the entire current calendar page.
    /// This avoids invisible chart marks and preserves snapping at both ends of the history.
    static func scrollDomain(
        for stats: [TDDStats], interval: Interval, now: Date = .now, calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let initial = initialPosition(for: interval, now: now, calendar: calendar)
        let first = min(stats.map(\.date).min() ?? initial, initial)
        let lower = initialPosition(for: interval == .total ? .month : interval, now: first, calendar: calendar)
        let last = max(stats.map(\.date).max() ?? now, now)
        let latestPage = initialPosition(for: interval, now: last, calendar: calendar)
        return lower ... endDate(from: latestPage, for: interval, calendar: calendar)
    }

    static func summary(of stats: [TDDStats], in range: Range<Date>, calendar: Calendar = .current) -> Summary {
        let visible = stats.filter { range.contains($0.date) }
        let total = visible.reduce(0) { $0 + $1.amount }
        let positive = visible.filter { $0.amount > 0 }
        let positiveTotal = positive.reduce(0) { $0 + $1.amount }
        let months = Dictionary(grouping: positive) { calendar.dateInterval(of: .month, for: $0.date)!.start }
        // Each month contributes only the bars in view, including partially visible months.
        return Summary(
            average: positive.isEmpty ? 0 : positiveTotal / Double(positive.count),
            total: total,
            monthlyAverage: months.isEmpty ? 0 : positiveTotal / Double(months.count)
        )
    }

    static func highlightsSunday(_ date: Date, for interval: Interval, calendar: Calendar = .current) -> Bool {
        (interval == .month || interval == .total) && calendar.component(.weekday, from: date) == 1
    }

    static func rangeLabel(
        for range: Range<Date>, interval: Interval, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let start = range.lowerBound
        // Upper bounds are exclusive: a Sunday-to-Sunday week is labelled Sunday–Saturday.
        let last = range.upperBound.addingTimeInterval(-1)
        let monthStart = calendar.dateInterval(of: .month, for: start)!.start
        func formatted(_ date: Date, _ style: Date.FormatStyle) -> String {
            var style = style.locale(locale)
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }
        if interval == .month, start == monthStart {
            return formatted(start, .dateTime.month(.wide))
        }
        if interval == .day, start == calendar.startOfDay(for: start) {
            return formatted(start, .dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        if interval == .day {
            let style = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
            return formatted(start, style) + "–" + formatted(range.upperBound, style)
        }
        let style = calendar.component(.year, from: start) == calendar.component(.year, from: last)
            ? Date.FormatStyle.dateTime.month(.abbreviated).day()
            : Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        return formatted(start, style) + "–" + formatted(last, style)
    }
}
