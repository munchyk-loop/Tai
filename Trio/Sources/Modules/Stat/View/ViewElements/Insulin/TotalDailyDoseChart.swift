import Charts
import SwiftUI

/// A view that displays a bar chart for Total Daily Dose (TDD) statistics.
///
/// The chart pages one whole calendar period per swipe, while a slow, deliberate drag can
/// still settle on a custom range. Header figures describe the settled window only, so they
/// do not churn while a scroll is in flight.
struct TotalDailyDoseChart: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    /// The list of TDD statistics data.
    let tddStats: [TDDStats]
    /// The state model containing cached statistics data.
    let state: Stat.StateModel

    /// The live scroll position. Continuous, and updated on every frame of a scroll.
    @State private var scrollPosition = Date()
    /// The settled window start, rounded onto a whole bar. Everything in the header reads
    /// from this rather than from `scrollPosition`.
    @State private var committedStart = Date()
    /// Debounce that holds header updates back until scrolling actually stops.
    @State private var settleTask: Task<Void, Never>?
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The actual chart plot's width in pixel
    @State private var chartWidth: CGFloat = 0

    /// The half-open range `[start, end)` of the settled window.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.insulinVisibleDateRange(from: committedStart, for: selectedInterval)
    }

    /// The full extent the chart can be scrolled across.
    private var scrollDomain: ClosedRange<Date> {
        StatChartUtils.insulinScrollDomain(for: selectedInterval, dates: tddStats.map(\.date))
    }

    /// Retrieves the TDD statistic for a given date.
    private func getTDDForDate(_ date: Date) -> TDDStats? {
        tddStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// Commits the settled window once scrolling has paused.
    private func scheduleCommit(for rawPosition: Date) {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            committedStart = StatChartUtils.insulinNormalizedStart(rawPosition, for: selectedInterval)
        }
    }

    /// Jumps straight to the start of the current period, without waiting for the debounce.
    private func resetToCurrentPeriod() {
        settleTask?.cancel()
        selectedDate = nil
        let start = StatChartUtils.insulinInitialScrollPosition(for: selectedInterval)
        scrollPosition = start
        committedStart = start
    }

    // MARK: - Header values

    /// Every non-empty dose bucket inside the settled window.
    ///
    /// Buckets with no insulin are dropped so empty hours and days never drag the averages
    /// down. They contribute nothing to a sum either, so one list backs the average and
    /// the total alike.
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
    /// Scaling the daily average keeps this consistent with excluding empty days, and keeps
    /// the figure stable when the window covers only part of a month.
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

    private var averageTitle: String {
        selectedInterval == .day
            ? String(localized: "Hourly Average:")
            : String(localized: "Daily Average:")
    }

    private var secondaryTitle: String {
        selectedInterval == .total
            ? String(localized: "Monthly Average:")
            : String(localized: "Total:")
    }

    private var secondaryValue: Double {
        selectedInterval == .total ? monthlyAverage : visibleTotal
    }

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
        .onAppear { resetToCurrentPeriod() }
        .onChange(of: selectedInterval) { resetToCurrentPeriod() }
        .onChange(of: scrollPosition) { _, newValue in scheduleCommit(for: newValue) }
        .onDisappear { settleTask?.cancel() }
    }

    /// A view displaying the statistics summary for the settled window.
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
    /// Only Sundays, and only in the month and three-month views, where the accent makes
    /// the week divisions easy to pick out.
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
                        if day == 1 { // Show start of every month
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
        // An explicit domain keeps every reachable page on a calendar boundary, and removes
        // the need for invisible padding marks to stretch the plotted range.
        .chartXScale(domain: scrollDomain)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollPosition)
        .chartXVisibleDomain(length: StatChartUtils.insulinVisibleDomainLength(for: selectedInterval))
        .chartScrollTargetBehavior(
            InsulinPagingScrollBehavior(
                currentStart: StatChartUtils.insulinNormalizedStart(scrollPosition, for: selectedInterval),
                interval: selectedInterval
            )
        )
        // Selection is deliberately behind a long press. `chartXSelection` also reacts to a
        // plain drag, which fights the scroll gesture: the popover kept firing when the user
        // was only trying to scroll. Requiring a hold first leaves ordinary drags to the
        // scroll view, and matches the "tap and hold a bar" hint under the chart.
        .chartGesture { proxy in
            LongPressGesture(minimumDuration: 0.2)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { phase in
                    guard case let .second(_, drag?) = phase else { return }
                    guard let date: Date = proxy.value(atX: drag.location.x) else { return }
                    // Lock the popover onto the bar under the finger rather than tracking a
                    // continuous position between bars.
                    withAnimation(.easeInOut(duration: 0.1)) {
                        selectedDate = StatChartUtils.insulinSnapToBar(date, for: selectedInterval)
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut) { selectedDate = nil }
                }
        }
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
