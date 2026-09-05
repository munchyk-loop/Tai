import Charts
import Foundation
import SwiftUI

struct StatChartUtils {
    /// Returns the time interval length for the visible domain based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: The time interval in seconds.
    static func visibleDomainLength(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> TimeInterval {
        switch selectedInterval {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .total: return 90 * 24 * 3600
        }
    }

    /// Returns the TDD chart's fixed visual window length using calendar-day arithmetic.
    /// Month always displays 31 day slots and 3-month always displays 93 day slots.
    /// Calendar arithmetic keeps midnight boundaries correct across DST changes.
    static func tddVisibleDomainLength(
        from scrollPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> TimeInterval {
        let calendar = Calendar.current
        let dayCount: Int

        switch selectedInterval {
        case .day:
            dayCount = 1
        case .week:
            dayCount = 7
        case .month:
            dayCount = 31
        case .total:
            dayCount = 93
        }

        let end = calendar.date(byAdding: .day, value: dayCount, to: scrollPosition)
        return end?.timeIntervalSince(scrollPosition) ?? TimeInterval(dayCount * 24 * 3600)
    }

    /// Computes the exact visible range for the TDD chart without expanding it to an extra day.
    static func tddVisibleDateRange(
        from scrollPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let length = tddVisibleDomainLength(from: scrollPosition, for: selectedInterval)
        return (scrollPosition, scrollPosition.addingTimeInterval(length - 1))
    }

    /// Returns the canonical initial start of the TDD chart.
    /// Day starts at midnight, week starts Sunday, month starts on the 1st,
    /// and 3-month starts on the 1st two months before the current month.
    static func getInitialTDDScrollPosition(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        switch selectedInterval {
        case .day:
            return today
        case .week:
            return sundayStart(for: today)
        case .month:
            return monthStart(for: today)
        case .total:
            let currentMonthStart = monthStart(for: today)
            return calendar.date(byAdding: .month, value: -2, to: currentMonthStart) ?? currentMonthStart
        }
    }

    /// Fine-grained alignment used after a precise drag.
    /// Day can settle on an hour; longer views can settle on any midnight.
    static func tddMinorAlignmentComponents(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        switch selectedInterval {
        case .day:
            return DateComponents(minute: 0)
        case .week,
             .month,
             .total:
            return DateComponents(hour: 0)
        }
    }

    /// Returns the next/previous canonical range start for a deliberate swipe.
    /// The fixed visual widths remain 1/7/31/93 days, while the snap anchors stay semantic:
    /// midnight, Sunday, month-start, or a three-month jump from a month-start.
    static func tddSwipeTarget(
        from date: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval,
        direction: Int
    ) -> Date {
        let calendar = Calendar.current
        let step = direction >= 0 ? 1 : -1

        switch selectedInterval {
        case .day:
            let start = calendar.startOfDay(for: date)
            return calendar.date(byAdding: .day, value: step, to: start) ?? start
        case .week:
            let start = sundayStart(for: date)
            return calendar.date(byAdding: .day, value: 7 * step, to: start) ?? start
        case .month:
            let start = monthStart(for: date)
            return calendar.date(byAdding: .month, value: step, to: start) ?? start
        case .total:
            let start = monthStart(for: date)
            return calendar.date(byAdding: .month, value: 3 * step, to: start) ?? start
        }
    }

    private static func sundayStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: dayStart) ?? dayStart
    }

    private static func monthStart(for date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    /// Returns the end boundary of the current canonical TDD window.
    /// An invisible mark at this date lets Swift Charts display the complete current period,
    /// even when future hours/days in that period do not have insulin data yet.
    static func currentTDDPageEnd(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let start = getInitialTDDScrollPosition(for: selectedInterval)
        let length = tddVisibleDomainLength(from: start, for: selectedInterval)
        return start.addingTimeInterval(length)
    }

    /// Computes the visible date range based on the current scroll position and selected duration.
    /// - Parameters:
    ///   - scrollPosition: The current scroll position in the chart.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A tuple containing the start and end dates of the visible range.
    static func visibleDateRange(
        from scrollPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current

        if selectedInterval == .day {
            // For day view, don't modify the scroll position
            let end = scrollPosition.addingTimeInterval(visibleDomainLength(for: selectedInterval) - 1)
            return (scrollPosition, end)
        } else {
            // For week and longer intervals, align to day boundaries consistently with meal data grouping
            // Use the same logic as meal data grouping: calendar.startOfDay()
            let startOfDay = calendar.startOfDay(for: scrollPosition)
            let intervalLength = visibleDomainLength(for: selectedInterval)

            // Calculate end date by adding the interval length and aligning to day boundary
            let endDate = startOfDay.addingTimeInterval(intervalLength)
            let endOfDay = calendar.startOfDay(for: endDate)

            // Ensure we include the full end day by going to the end of that day
            let alignedEnd = (calendar.date(byAdding: .day, value: 1, to: endOfDay) ?? endOfDay).addingTimeInterval(-1)

            return (startOfDay, alignedEnd)
        }
    }

    /// Returns the appropriate date format style based on the selected time interval.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: A Date.FormatStyle configured for the current time interval.
    static func dateFormat(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date.FormatStyle {
        switch selectedInterval {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .total: return .dateTime.month(.abbreviated)
        }
    }

    /// Returns DateComponents for aligning dates based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: DateComponents configured for the appropriate alignment.
    static func alignmentComponents(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        switch selectedInterval {
        case .day: return DateComponents(hour: 0)
        case .week:
            let calendar = Calendar.current
            return DateComponents(weekday: calendar.firstWeekday)
        case .month,
             .total: return DateComponents(day: 1)
        }
    }

    /// Returns the initial scroll position date based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: A Date representing the initial scroll position.
    static func getInitialScrollPosition(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let baseDate: Date
        switch selectedInterval {
        case .day:
            baseDate = today
        case .week:
            baseDate = calendar.date(byAdding: .day, value: -6, to: today)!
        case .month:
            baseDate = calendar.date(byAdding: .day, value: -29, to: today)!
        case .total:
            baseDate = calendar.date(byAdding: .day, value: -89, to: today)!
        }

        return calendar.date(byAdding: .second, value: 1, to: baseDate)!
    }

    /// Checks if two dates belong to the same time unit based on the selected duration.
    /// - Parameters:
    ///   - date1: The first date.
    ///   - date2: The second date.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A Boolean indicating whether the two dates are in the same time unit.
    static func isSameTimeUnit(
        _ date1: Date,
        _ date2: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Bool {
        let calendar = Calendar.current
        switch selectedInterval {
        case .day:
            return calendar.isDate(date1, equalTo: date2, toGranularity: .hour)
        default:
            return calendar.isDate(date1, inSameDayAs: date2)
        }
    }

    /// Formats the visible date range into a human-readable string.
    /// - Parameters:
    ///   - start: The start date of the range.
    ///   - end: The end date of the range.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A formatted string representing the visible date range.
    static func formatVisibleDateRange(
        from start: Date,
        to end: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> String {
        let calendar = Calendar.current

        // If not .day, we just return "startText - endText", e.g. "Jan 1 - Jan 8"
        guard selectedInterval == .day else {
            let formatDate: (Date) -> String = { date in
                date.formatted(.dateTime.day().month())
            }
            let startText = formatDate(start)
            let endText = formatDate(end)
            return "\(startText) - \(endText)"
        }

        // For .day mode, we figure out if we are near the boundaries for a "full day" (00:00 - 23:59)
        let dayStart = calendar.startOfDay(for: start)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // Allow +/- 15 minutes from midnight as buffer, so slow scrolling doesn't break the "full day"
        let tolerance: TimeInterval = 60 * 15

        let isStartNearMidnight = abs(start.timeIntervalSince(dayStart)) < tolerance
        let isEndNearNextMidnight = abs(end.timeIntervalSince(nextDayStart)) < tolerance

        let formatDay: (Date) -> String = { date in
            date.formatted(.dateTime.day().month(.abbreviated))
        }

        if isStartNearMidnight, isEndNearNextMidnight {
            // Full day: show just start as "Mon, Jan 1"
            return dayStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        } else {
            // Partial day: show start and end
            let startText = formatDay(start)
            let endText = formatDay(end)
            return "\(startText) - \(endText)"
        }
    }

    /// A helper function to create a `VStack` for each statistic.
    ///
    /// - Parameters:
    ///   - title: The title of the statistic.
    ///   - value: The formatted value to display.
    /// - Returns: A `VStack` containing the title and value.
    static func statView(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(value)
        }
    }

    /// Computes the median value of an array of integers.
    ///
    /// - Parameter array: An array of integers.
    /// - Returns: The median value as a `Double`. Returns `0` if the array is empty.
    static func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    /// Computes the median value of an array of doubles.
    ///
    /// - Parameter array: An array of `Double` values.
    /// - Returns: The median value. Returns `0` if the array is empty.
    static func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    /// Creates a legend item view for use in a chart legend.
    ///
    /// - Parameters:
    ///   - label: The text label for the legend item.
    ///   - color: The color associated with the legend item.
    /// - Returns: A SwiftUI view displaying a colored symbol and a label.
    @ViewBuilder static func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill").foregroundStyle(color)
            Text(label).foregroundStyle(Color.secondary)
        }.font(.caption)
    }
}
