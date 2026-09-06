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

    /// Computes the visible date range based on the scroll position and selected duration.
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

    // MARK: - Insulin (TDD) chart: calendar-aligned, page-like scrolling

    /// The width of the insulin chart's visible window, in seconds.
    ///
    /// Each mode shows exactly one calendar period, so that a snapped window lines up with
    /// real calendar boundaries: midnight-to-midnight, Sunday-to-Saturday, 31 days from the
    /// 1st of a month, and three whole months.
    static func insulinVisibleDomainLength(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> TimeInterval {
        switch selectedInterval {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 31 * 24 * 3600
        case .total: return 92 * 24 * 3600
        }
    }

    /// The components a slow, precise drag settles on.
    ///
    /// These are deliberately fine-grained so the user can park the chart on a custom range,
    /// e.g. a Wednesday-to-Tuesday week, instead of always being forced onto a period boundary.
    static func insulinMinorAlignment(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        switch selectedInterval {
        case .day:
            // Settle on whole hours.
            return DateComponents(minute: 0, second: 0)
        default:
            // Settle on whole days.
            return DateComponents(hour: 0, minute: 0, second: 0)
        }
    }

    /// The components a *swipe* snaps to, i.e. one whole period per swipe.
    ///
    /// `Charts` uses this as the "major" alignment: a swipe jumps to the next or previous
    /// matching value depending on direction, which is what produces page-like paging.
    ///
    /// - Important: minutes and seconds are pinned to zero. `DateComponents(day: 1)` on its own
    ///   matches *any* time on the 1st of the month, which lets the chart settle at an arbitrary
    ///   time of day and makes the window look like it never quite snapped.
    static func insulinMajorAlignment(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        var components = DateComponents(hour: 0, minute: 0, second: 0)

        switch selectedInterval {
        case .day:
            break // midnight, i.e. a whole day
        case .week:
            components.weekday = Calendar.current.firstWeekday // start of the week
        case .month,
             .total:
            components.day = 1 // first of the month
        }

        return components
    }

    /// The number of whole days the insulin chart shows at once.
    static func insulinVisibleDayCount(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Int {
        switch selectedInterval {
        case .day: return 1
        case .week: return 7
        case .month: return 31
        case .total: return 92
        }
    }

    /// The half-open date range `[start, end)` currently visible in the insulin chart.
    ///
    /// The end is advanced by whole calendar days rather than by a fixed number of seconds.
    /// Across a daylight-saving change a day is 23 or 25 hours long, so a seconds-based window
    /// drifts by an hour and can pull an extra day's bar into the totals.
    static func insulinVisibleDateRange(
        from scrollPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayCount = insulinVisibleDayCount(for: selectedInterval)
        let end = calendar.date(byAdding: .day, value: dayCount, to: scrollPosition)
            ?? scrollPosition.addingTimeInterval(insulinVisibleDomainLength(for: selectedInterval))
        return (scrollPosition, end)
    }

    /// The start of the calendar period containing `date` for the given mode.
    static func insulinPeriodStart(
        containing date: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Date {
        let calendar = Calendar.current

        switch selectedInterval {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month,
             .total:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    /// The scroll position the insulin chart opens on: the start of the current period,
    /// so the chart is snapped from the very first frame.
    static func insulinInitialScrollPosition(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let periodStart = insulinPeriodStart(containing: now, for: selectedInterval)

        guard selectedInterval == .total else { return periodStart }

        // Three-month view: show the current month plus the two preceding ones.
        return calendar.date(byAdding: .month, value: -2, to: periodStart) ?? periodStart
    }

    /// The full scrollable extent of the insulin chart.
    ///
    /// The lower bound is snapped back to a period boundary and the upper bound is the end of
    /// the initial window, so every page the user can reach lands on a calendar boundary.
    /// Defining the domain explicitly also removes the need for invisible padding marks.
    static func insulinScrollDomain(
        for selectedInterval: Stat.StateModel.StatsTimeInterval,
        dates: [Date]
    ) -> ClosedRange<Date> {
        let upperBound = insulinInitialScrollPosition(for: selectedInterval)
            .addingTimeInterval(insulinVisibleDomainLength(for: selectedInterval))

        guard let earliest = dates.min() else {
            return upperBound.addingTimeInterval(-insulinVisibleDomainLength(for: selectedInterval)) ... upperBound
        }

        let lowerBound = min(insulinPeriodStart(containing: earliest, for: selectedInterval), upperBound)
        return lowerBound ... upperBound
    }

    /// Formats the header's date range for the insulin chart.
    ///
    /// When the window is snapped to a whole period the period's own name is shown (a weekday and
    /// date for a day, a full month name for a month). Any other, precision-scrolled range falls
    /// back to explicit start and end dates, e.g. "Feb 2 - Mar 4".
    static func formatInsulinDateRange(
        from start: Date,
        to end: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> String {
        let calendar = Calendar.current
        // `end` is exclusive; the last instant actually on screen belongs to the previous second.
        let lastVisible = end.addingTimeInterval(-1)

        let shortDate: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
        let range = "\(shortDate(start)) - \(shortDate(lastVisible))"

        let isMidnight = calendar.dateComponents([.hour, .minute, .second], from: start) == DateComponents(
            hour: 0,
            minute: 0,
            second: 0
        )

        switch selectedInterval {
        case .day:
            guard isMidnight else { return range }
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

        case .week:
            return range

        case .month:
            // Snapped to a whole month: show the month's name on its own, e.g. "February".
            guard isMidnight, calendar.component(.day, from: start) == 1 else { return range }

            let isCurrentYear = calendar.component(.year, from: start) == calendar.component(.year, from: Date())
            return isCurrentYear
                ? start.formatted(.dateTime.month(.wide))
                : start.formatted(.dateTime.month(.wide).year())

        case .total:
            guard isMidnight, calendar.component(.day, from: start) == 1 else { return range }

            // The window is a whole number of days, so it overscans a little way into a fourth
            // month. Name the three months it is anchored to, the same way the month view is
            // labelled "February" while a few days of March are still on screen.
            let month: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated)) }
            let lastMonth = calendar.date(byAdding: .month, value: 2, to: start) ?? lastVisible
            return "\(month(start)) - \(month(lastMonth))"
        }
    }

    /// A helper function to create a `VStack` for each statistic.
    ///
    /// - Parameters:
    ///   - title: The title of the statistic.
    ///   - value: The formatted value to display.
    /// - Returns: A `VStack` with the title and value.
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
