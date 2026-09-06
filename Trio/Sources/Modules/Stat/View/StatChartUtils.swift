import Charts
import Foundation
import SwiftUI

/// A scroll behaviour for the insulin chart that pages by whole calendar periods.
///
/// `.valueAligned` projects the scroll's momentum and then snaps wherever that projection
/// lands, so a firm swipe can coast across several periods and settle on an arbitrary day.
/// That is momentum scrolling with alignment, not paging.
///
/// This behaviour separates the two gestures the chart needs:
///
/// * A **flick** moves exactly one period from the page currently on screen, regardless of
///   how hard it was thrown. One swipe, one day/week/month.
/// * A **slow drag** keeps the projected destination and merely rounds it onto a whole bar,
///   so a custom range such as Wednesday-to-Tuesday stays reachable.
///
/// Direction is taken from the projected destination rather than the sign of `velocity`,
/// which keeps it correct regardless of the scroll view's coordinate conventions.
struct InsulinPagingScrollBehavior: ChartScrollTargetBehavior {
    /// The period boundary the chart is currently anchored to.
    let currentStart: Date
    /// The mode being displayed.
    let interval: Stat.StateModel.StatsTimeInterval

    /// Point-per-second speed above which a gesture counts as a flick rather than a drag.
    private let flickVelocityThreshold: CGFloat = 250

    func updateTarget(_ target: inout ScrollTarget, context: ChartScrollTargetBehaviorContext) {
        let proxy = context.chartProxy

        // Where the scroll view's own momentum would have put us.
        guard let projected: Date = proxy.value(atX: target.rect.origin.x) else { return }

        let destination: Date

        if abs(context.velocity.dx) > flickVelocityThreshold {
            // A flick. Move to the adjacent period boundary, ignoring how far the momentum
            // would have carried the chart.
            let anchor = StatChartUtils.insulinPeriodStart(containing: currentStart, for: interval)

            if projected > currentStart {
                // Forwards is always the next boundary after the current position.
                destination = StatChartUtils.insulinPage(from: anchor, steps: 1, for: interval)
            } else if anchor == currentStart {
                // Already snapped, so step back a whole period.
                destination = StatChartUtils.insulinPage(from: anchor, steps: -1, for: interval)
            } else {
                // Mid-period after a precision scroll: fall back onto the boundary behind us.
                destination = anchor
            }
        } else {
            // A deliberate drag. Respect where the user let go, rounded to a whole bar.
            destination = StatChartUtils.insulinSnapToBar(projected, for: interval)
        }

        guard let x = proxy.position(forX: destination) else { return }
        target.rect.origin.x = x
    }
}

enum StatChartUtils {
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
    static func insulinVisibleDomainLength(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> TimeInterval {
        TimeInterval(insulinVisibleDayCount(for: selectedInterval)) * 24 * 3600
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

    /// Rounds a raw scroll position onto a whole bar boundary.
    ///
    /// `chartScrollPosition` reports a continuous value, so even a perfectly settled chart
    /// hands back something like `00:00:00.37`. Comparing that against bar dates directly
    /// drops the first bar out of the visible window, and comparing it against midnight
    /// makes a snapped window look unsnapped. Everything the header shows is derived from
    /// this normalized value rather than the raw one.
    static func insulinNormalizedStart(
        _ rawPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Date {
        let calendar = Calendar.current

        guard selectedInterval == .day else {
            // Nearest midnight: shifting by half a day turns truncation into rounding.
            return calendar.startOfDay(for: rawPosition.addingTimeInterval(12 * 3600))
        }

        // Nearest whole hour, by the same trick.
        let shifted = rawPosition.addingTimeInterval(30 * 60)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: shifted)
        return calendar.date(from: components) ?? rawPosition
    }

    /// The half-open date range `[start, end)` on screen, in whole calendar days.
    ///
    /// Advancing by calendar days rather than a fixed number of seconds keeps the window
    /// exactly one period wide across a daylight-saving change.
    static func insulinVisibleDateRange(
        from normalizedStart: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayCount = insulinVisibleDayCount(for: selectedInterval)
        let end = calendar.date(byAdding: .day, value: dayCount, to: normalizedStart)
            ?? normalizedStart.addingTimeInterval(insulinVisibleDomainLength(for: selectedInterval))
        return (normalizedStart, end)
    }

    /// The start of the calendar period containing `date`.
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

    /// Moves `steps` whole periods from a period boundary.
    ///
    /// Calendar arithmetic, so a month step lands on the 1st of the next month rather than
    /// 31 days later, and a week step lands on the same weekday.
    static func insulinPage(
        from periodStart: Date,
        steps: Int,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Date {
        let calendar = Calendar.current

        switch selectedInterval {
        case .day:
            return calendar.date(byAdding: .day, value: steps, to: periodStart) ?? periodStart
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: steps, to: periodStart) ?? periodStart
        case .month,
             .total:
            return calendar.date(byAdding: .month, value: steps, to: periodStart) ?? periodStart
        }
    }

    /// Snaps a date onto the bar that contains it: the hour in `Day` mode, the day otherwise.
    static func insulinSnapToBar(
        _ date: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Date {
        let calendar = Calendar.current

        guard selectedInterval == .day else { return calendar.startOfDay(for: date) }

        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: components) ?? date
    }

    /// The midpoint of the bar starting at `barStart`.
    ///
    /// A `BarMark` binned by hour or day occupies the whole interval and is drawn centred in
    /// it, so a `RuleMark` placed at the bar's start date lands on its leading edge rather
    /// than through its middle. Stepping a whole calendar unit keeps this correct across a
    /// daylight-saving change, where a day is 23 or 25 hours long.
    static func insulinBarCenter(
        _ barStart: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Date {
        let calendar = Calendar.current
        let unit: Calendar.Component = selectedInterval == .day ? .hour : .day

        guard let nextBar = calendar.date(byAdding: unit, value: 1, to: barStart) else { return barStart }
        return barStart.addingTimeInterval(nextBar.timeIntervalSince(barStart) / 2)
    }

    /// The scroll position the chart opens on: the start of the current period.
    static func insulinInitialScrollPosition(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let calendar = Calendar.current
        let periodStart = insulinPeriodStart(containing: Date(), for: selectedInterval)

        guard selectedInterval == .total else { return periodStart }

        // Three-month view: the current month plus the two preceding ones.
        return calendar.date(byAdding: .month, value: -2, to: periodStart) ?? periodStart
    }

    /// The full scrollable extent, with the lower bound snapped back to a period boundary
    /// so every reachable page lands on a calendar boundary.
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

    /// Whether `normalizedStart` sits exactly on a period boundary, i.e. the window is snapped.
    static func insulinIsSnapped(
        _ normalizedStart: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Bool {
        normalizedStart == insulinPeriodStart(containing: normalizedStart, for: selectedInterval)
    }

    /// Formats the header's date range.
    ///
    /// A window snapped to a whole period is named after that period; any other,
    /// precision-scrolled range falls back to explicit start and end dates.
    static func formatInsulinDateRange(
        from start: Date,
        to end: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> String {
        let calendar = Calendar.current
        // `end` is exclusive; the last instant on screen belongs to the previous second.
        let lastVisible = end.addingTimeInterval(-1)

        let shortDate: (Date) -> String = { $0.formatted(.dateTime.month(.abbreviated).day()) }
        let range = "\(shortDate(start)) - \(shortDate(lastVisible))"

        guard insulinIsSnapped(start, for: selectedInterval) else { return range }

        switch selectedInterval {
        case .day:
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

        case .week:
            return range

        case .month:
            let isCurrentYear = calendar.component(.year, from: start) == calendar.component(.year, from: Date())
            return isCurrentYear
                ? start.formatted(.dateTime.month(.wide))
                : start.formatted(.dateTime.month(.wide).year())

        case .total:
            // The window overscans a little into a fourth month; name the three it is
            // anchored to, as the month view is labelled "February" with March still showing.
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
