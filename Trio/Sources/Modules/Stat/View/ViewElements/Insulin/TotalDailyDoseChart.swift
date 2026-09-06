import Charts
import SwiftUI

/// A view that displays a bar chart for Total Daily Dose (TDD) statistics.
///
/// This view presents insulin usage over time. The chart pages one calendar period at a time
/// when swiped, while a slow, precise drag can settle on a custom range.
struct TotalDailyDoseChart: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    /// The list of TDD statistics data.
    let tddStats: [TDDStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The actual chart plot's width in pixel
    @State private var chartWidth: CGFloat = 0

    /// The half-open range `[start, end)` currently on screen.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.insulinVisibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// The full extent the chart can be scrolled across.
    private var scrollDomain: ClosedRange<Date> {
        StatChartUtils.insulinScrollDomain(for: selectedInterval, dates: tddStats.map(\.date))
    }

    /// Retrieves the TDD statistic for a given date.
    /// - Parameter date: The date for which to retrieve TDD data.
    /// - Returns: The `TDDStats` object if available, otherwise `nil`.
    private func getTDDForDate(_ date: Date) -> TDDStats? {
        tddStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    // MARK: - Header values

    /// Every non-empty dose bucket inside the visible window.
    ///
    /// Buckets with no insulin are dropped so that empty hours and days never drag the
    /// averages down. They contribute nothing to a sum either, so the same list backs
    /// both the average and the total.
    private var visibleDoses: [Double] {
        let range = visibleDateRange
        return tddStats
            .filter { $0.date >= range.start && $0.date < range.end }
            .map(\.amount)
            .filter { $0 > 0 }
    }

    /// The total insulin across every bar in view.
    private var visibleTotal: Double {
        visibleDoses.reduce(0, +)
    }

    /// The average dose per non-empty bar: hourly in `Day` mode, daily everywhere else.
    private var visibleAverage: Double {
        guard !visibleDoses.isEmpty else { return 0 }
        return visibleTotal / Double(visibleDoses.count)
    }

    /// The insulin a typical calendar month in view would total at the current daily average.
    ///
    /// Scaling the daily average keeps this consistent with the rule that empty days are
    /// excluded, and keeps the number stable when the window is precision-scrolled so that
    /// it only covers part of a month.
    private var monthlyAverage: Double {
        let calendar = Calendar.current
        let range = visibleDateRange

        var monthLengths: [Int] = []
        var cursor = calendar.dateInterval(of: .month, for: range.start)?.start ?? range.start

        while cursor < range.end {
            if let length = calendar.range(of: .day, in: .month, for: cursor)?.count {
                monthLengths.append(length)
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        let averageMonthLength = monthLengths.isEmpty
            ? 30.0
            : Double(monthLengths.reduce(0, +)) / Double(monthLengths.count)

        return visibleAverage * averageMonthLength
    }

    /// The label for the average shown in the header.
    private var averageTitle: String {
        selectedInterval == .day
            ? String(localized: "Hourly Average:")
            : String(localized: "Daily Average:")
    }

    /// The label for the second header value.
    private var secondaryTitle: String {
        selectedInterval == .total
            ? String(localized: "Monthly Average:")
            : String(localized: "Total:")
    }

    /// The second header value: a monthly average in the three-month view, a total elsewhere.
    private var secondaryValue: Double {
        selectedInterval == .total ? monthlyAverage : visibleTotal
    }

    /// The caption above the chart.
    private var chartTitle: String {
        selectedInterval == .day
            ? String(localized: "Total Hourly Dose (U)")
            : String(localized: "Total Daily Dose (U)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text(chartTitle)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chartsView
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { chartWidth = geo.size.width }
                                .onChange(of: geo.size.width) { _, newValue in chartWidth = newValue }
                        }
                    )
            }
        }
        .onAppear {
            scrollPosition = StatChartUtils.insulinInitialScrollPosition(for: selectedInterval)
        }
        .onChange(of: selectedInterval) {
            selectedDate = nil
            scrollPosition = StatChartUtils.insulinInitialScrollPosition(for: selectedInterval)
        }
    }

    /// A view displaying the statistics summary for the visible range.
    private var statsView: some View {
        HStack(alignment: .top) {
            Grid(alignment: .leading) {
                GridRow {
                    Text(averageTitle)
                    Text(visibleAverage.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                GridRow {
                    Text(secondaryTitle)
                    Text(secondaryValue.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
            }
            .font(.headline)

            Spacer()

            Text(
                StatChartUtils.formatInsulinDateRange(
                    from: visibleDateRange.start,
                    to: visibleDateRange.end,
                    for: selectedInterval
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// Whether a bar should be tinted to mark the start of a week.
    ///
    /// Only Sundays are tinted, and only in the month and three-month views, where the
    /// accent makes the week divisions easy to pick out.
    private func isWeekDivider(_ date: Date) -> Bool {
        guard selectedInterval == .month || selectedInterval == .total else { return false }
        return Calendar.current.component(.weekday, from: date) == 1
    }

    /// A view displaying the bar chart for TDD statistics.
    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(isWeekDivider(stat.date) ? Color.basal : Color.insulin)
                .annotation(position: .top) {
                    if selectedInterval == .week {
                        Text(stat.amount.formatted(.number.precision(.fractionLength(1))))
                            .font(.footnote)
                            .foregroundColor(Color.primary)
                    }
                }
                .opacity(
                    selectedDate.map { date in
                        StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval) ? 1 : 0.3
                    } ?? 1
                )
            }

            // Selection popover outside of the ForEach loop!
            if let selectedDate,
               let selectedTDD = getTDDForDate(selectedDate)
            {
                RuleMark(
                    x: .value("Selected Date", selectedDate)
                )
                .foregroundStyle(Color.insulin.opacity(0.5))
                .annotation(
                    position: .top,
                    spacing: 0,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    TDDSelectionPopover(
                        selectedDate: selectedDate,
                        tdd: selectedTDD,
                        selectedInterval: selectedInterval,
                        domain: visibleDateRange,
                        chartWidth: chartWidth
                    )
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                if let amount = value.as(Double.self) {
                    AxisValueLabel {
                        Text(amount.formatted(.number.precision(.fractionLength(0))))
                            .font(.footnote)
                    }
                    AxisGridLine()
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: selectedInterval == .day ? .hour : .day)) { value in
                if let date = value.as(Date.self) {
                    let calendar = Calendar.current
                    let day = calendar.component(.day, from: date)
                    let hour = calendar.component(.hour, from: date)

                    switch selectedInterval {
                    case .day:
                        if hour % 6 == 0 { // Show only every 6 hours
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .month:
                        let weekday = calendar.component(.weekday, from: date)
                        if weekday == calendar.firstWeekday { // Only show the first day of the week
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .total:
                        // Show start of every month
                        if day == 1 {
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    default:
                        AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                            .font(.footnote)
                        AxisGridLine()
                    }
                }
            }
        }
        // An explicit domain means every reachable page lands on a calendar boundary, and
        // removes the need for invisible padding marks to stretch the plotted range.
        .chartXScale(domain: scrollDomain)
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollPosition(x: $scrollPosition)
        .chartXVisibleDomain(length: StatChartUtils.insulinVisibleDomainLength(for: selectedInterval))
        // `majorAlignment` is what Charts uses on a swipe: it jumps to the next or previous
        // matching value, which gives the paging feel. `matching` is where a slow, precise drag
        // settles, so a custom range such as Wed-Tue stays reachable. `.always` is essential --
        // the default `.automatic` only limits scrolling on views that are compact along the
        // scroll axis, so on a full-width chart a flick would otherwise fly past several periods.
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: StatChartUtils.insulinMinorAlignment(for: selectedInterval),
                majorAlignment: .matching(StatChartUtils.insulinMajorAlignment(for: selectedInterval)),
                limitBehavior: .always
            )
        )
        .frame(height: 250)
    }
}

/// A popover view displaying TDD (Total Daily Dose) for a given time period.
/// Shows the insulin amount in units (U) for an hourly or daily interval, depending on `selectedInterval`.
///
/// - Parameters:
///   - date: The reference date for determining the displayed time range.
///   - tdd: The TDDStats containing insulin usage data.
///   - selectedInterval: The selected time interval (hourly or daily).
private struct TDDSelectionPopover: View {
    let selectedDate: Date
    let tdd: TDDStats
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    let domain: (start: Date, end: Date)
    let chartWidth: CGFloat

    @State private var popoverSize: CGSize = .zero

    @Environment(\.colorScheme) var colorScheme

    private var timeText: String {
        if selectedInterval == .day {
            let hour = Calendar.current.component(.hour, from: selectedDate)
            return selectedDate.formatted(.dateTime.month().day().weekday()) + "\n" + "\(hour):00-\(hour + 1):00"
        } else {
            return selectedDate.formatted(.dateTime.month().day().weekday())
        }
    }

    private func xOffset() -> CGFloat {
        // If the selected date is outside the visible domain, hide the popover
        guard selectedDate >= domain.start && selectedDate <= domain.end else { return 0 }

        let domainDuration = domain.end.timeIntervalSince(domain.start)
        guard domainDuration > 0, chartWidth > 0 else { return 0 }

        let popoverWidth = popoverSize.width
        let padding: CGFloat = 10 // Padding from screen edges

        // Convert dates to pixel'd x-position
        let dateFraction = selectedDate.timeIntervalSince(domain.start) / domainDuration
        let x_selected = dateFraction * chartWidth

        // Calculate popover edges
        let x_left = x_selected - (popoverWidth / 2)
        let x_right = x_selected + (popoverWidth / 2)

        var offset: CGFloat = 0

        // Ensure the popover stays within screen bounds
        if x_left < padding {
            // Popover would extend past left edge, shift it right
            offset = padding - x_left
        } else if x_right > chartWidth - padding {
            // Popover would extend past right edge, shift it left
            offset = (chartWidth - padding) - x_right
        }

        return offset
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(.subheadline)
                .bold()
                .foregroundStyle(Color.secondary)

            Divider()

            HStack {
                Text(tdd.amount.formatted(.number.precision(.fractionLength(1))))
                Text("U").foregroundStyle(Color.secondary)
            }
            .font(.headline)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.bgDarkBlue.opacity(0.9) : Color.white.opacity(0.95))
                .shadow(color: Color.secondary, radius: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue, lineWidth: 2)
                )
        }
        .frame(minWidth: 100, maxWidth: .infinity) // Ensures proper width
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { popoverSize = geo.size }
                    .onChange(of: geo.size) { _, newValue in popoverSize = newValue }
            }
        )
        // Apply calculated xOffset to keep within bounds
        .offset(x: xOffset(), y: 0)
        // Hide popover if selected date is outside visible domain
        .opacity(selectedDate >= domain.start && selectedDate <= domain.end ? 1 : 0)
    }
}
