import Charts
import Foundation
import SwiftUI

/// Scroll behaviour for the insulin chart: a flick turns whole pages, a drag settles where
/// it was released, and neither coasts.
///
/// Charts ships two behaviours and neither does both. `.valueAligned` keeps the scroll view's
/// momentum and only snaps once it has glided to a stop, so a swipe reads as a drag that
/// happens to land tidily. `.paging` never coasts but only knows page boundaries, so a custom
/// range such as Wednesday-to-Tuesday becomes unreachable.
///
/// This is the same decision the Health app makes in UIKit's
/// `scrollViewWillEndDragging(_:withVelocity:targetContentOffset:)`: look at how fast the
/// finger was moving, then overwrite where the scroll is about to land.
///
/// - Note: Offsets are converted to dates arithmetically from the domain and the scroll
///   content's width. An earlier version read `proxy.value(atX: target.rect.origin.x)`, which
///   mixes a scroll-content offset into an API that works in plot-area coordinates; the
///   resulting targets were meaningless and the chart barely scrolled at all.
struct InsulinPagingScrollBehavior: ChartScrollTargetBehavior {
    /// The chart's full scrollable date range.
    let domain: ClosedRange<Date>
    /// The window start as the gesture ends, before any momentum is applied.
    let releaseStart: Date
    /// The mode being displayed.
    let interval: Stat.StateModel.StatsTimeInterval

    /// Points per second at which a gesture stops being a drag and becomes a flick.
    /// Tune this single value if flicks feel too eager or too reluctant.
    private var flickThreshold: CGFloat { 250 }

    /// How many whole periods a flick covers. A firmer flick travels further, but always in
    /// whole periods, so the chart never comes to rest mid-period.
    private func periodCount(forSpeed speed: CGFloat) -> Int {
        switch speed {
        case ..<900: return 1
        case ..<1800: return 2
        default: return 3
        }
    }

    func updateTarget(_ target: inout ScrollTarget, context: ChartScrollTargetBehaviorContext) {
        let contentWidth = context.contentSize.width
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard contentWidth > 0, span > 0 else { return }

        func date(atOffset x: CGFloat) -> Date {
            domain.lowerBound.addingTimeInterval(Double(x / contentWidth) * span)
        }
        func offset(for date: Date) -> CGFloat {
            CGFloat(date.timeIntervalSince(domain.lowerBound) / span) * contentWidth
        }

        let speed = abs(context.velocity.dx)
        let destination: Date

        if speed < flickThreshold {
            // A drag. Settle on the bar under the finger. Derived from the target rather than
            // from `releaseStart` so the common case depends only on values Charts hands us;
            // at this speed the momentum built into the target is negligible.
            destination = StatChartUtils.insulinSnapToBar(date(atOffset: target.rect.origin.x), for: interval)
        } else {
            // A flick. Move whole periods from the page the gesture started on, discarding
            // however far the momentum would have carried the chart.
            let anchor = StatChartUtils.insulinPeriodStart(containing: releaseStart, for: interval)
            let forward = target.rect.origin.x > offset(for: releaseStart)
            var steps = periodCount(forSpeed: speed)

            // Travelling backwards from a mid-period position, the boundary we have already
            // passed is the first stop, so it costs nothing.
            if !forward, anchor != releaseStart {
                steps -= 1
            }

            destination = StatChartUtils.insulinPage(
                from: anchor,
                steps: forward ? steps : -steps,
                for: interval
            )
        }

        let clamped = min(max(destination, domain.lowerBound), domain.upperBound)
        target.rect.origin.x = offset(for: clamped)
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

    /// The components a slow, precise drag settles on.
    ///
    /// Fine-grained on purpose, so the chart can be parked on a custom range such as a
    /// Wednesday-to-Tuesday week instead of always being forced onto a period boundary.
    static func insulinMinorAlignment(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        switch selectedInterval {
        case .day:
            return DateComponents(minute: 0, second: 0) // whole hours
        default:
            return DateComponents(hour: 0, minute: 0, second: 0) // whole days
        }
    }

    /// The components a swipe snaps to: one whole period.
    ///
    /// - Important: minutes and seconds are pinned to zero. `DateComponents(day: 1)` on its
    ///   own matches *any* instant on the 1st of the month, and `DateComponents(weekday: 1)`
    ///   matches any instant on a Sunday, so without pinning the time the chart settles at an
    ///   arbitrary hour and the window never looks snapped.
    static func insulinMajorAlignment(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        var components = DateComponents(hour: 0, minute: 0, second: 0)

        switch selectedInterval {
        case .day:
            break // midnight, i.e. a whole day
        case .week:
            components.weekday = Calendar.current.firstWeekday
        case .month,
             .total:
            components.day = 1
        }

        return components
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

    /// Moves `steps` whole periods from a period boundary, using calendar arithmetic so a
    /// month step lands on the 1st of the next month rather than 31 days later.
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
