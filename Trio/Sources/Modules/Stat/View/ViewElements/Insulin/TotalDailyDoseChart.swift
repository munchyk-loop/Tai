import Charts
import SwiftUI

/// A view that displays a bar chart for Total Daily Dose (TDD) statistics.
///
/// This view presents insulin usage over time, with the ability to adjust the time interval
/// and scroll through historical data.
struct TotalDailyDoseChart: View {
    /// The selected time interval for displaying statistics.
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    /// The list of TDD statistics data.
    let tddStats: [TDDStats]

    /// The current scroll position in the chart.
    @State private var scrollPosition = Date()
    /// The visible calendar-period duration. This is updated only when native snapping lands
    /// on a new major calendar anchor, so month width does not mutate continuously during a drag.
    @State private var visibleDomainLength: TimeInterval = 24 * 3600
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The actual chart plot's width in pixels.
    @State private var chartWidth: CGFloat = 0

    /// Keep the existing call site API while deriving summaries directly from the visible bars.
    init(
        selectedInterval: Binding<Stat.StateModel.StatsTimeInterval>,
        tddStats: [TDDStats],
        state _: Stat.StateModel
    ) {
        _selectedInterval = selectedInterval
        self.tddStats = tddStats
    }

    /// Computes the exact visible date range.
    /// The 3-month view is a static latest-90-day overview; other views follow the scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        if selectedInterval == .total {
            let range = StatChartUtils.latest90DayTDDRange()
            return (range.start, range.end)
        }

        let start = canonicalMajorAnchor(for: scrollPosition) ?? scrollPosition
        return (
            start,
            start.addingTimeInterval(visibleDomainLength - 1)
        )
    }

    /// The hourly/daily bars that are currently visible.
    private var visibleStats: [TDDStats] {
        tddStats.filter { stat in
            stat.date >= visibleDateRange.start && stat.date <= visibleDateRange.end
        }
    }

    /// The bars supplied to the chart. The static 3-month overview is explicitly limited to the latest 90 days.
    private var chartStats: [TDDStats] {
        selectedInterval == .total ? visibleStats : tddStats
    }

    /// Sum of all visible insulin bars.
    private var totalDose: Double {
        visibleStats.reduce(0) { $0 + $1.amount }
    }

    /// Arithmetic mean of visible non-zero insulin bars.
    /// Zero-dose hours/days are intentionally excluded from both numerator and denominator.
    private var averageDose: Double {
        let nonZeroDoses = visibleStats.map(\.amount).filter { $0 > 0 }
        guard !nonZeroDoses.isEmpty else { return 0 }
        return nonZeroDoses.reduce(0, +) / Double(nonZeroDoses.count)
    }

    /// Normalized 30-day insulin amount based on the non-zero daily average.
    private var thirtyDayAverageDose: Double {
        averageDose * 30
    }

    private var averageLabel: String {
        selectedInterval == .day ? "Hourly Average" : "Daily Average"
    }

    private var secondaryLabel: String {
        selectedInterval == .total ? "30-Day Average" : "Total"
    }

    private var secondaryDose: Double {
        selectedInterval == .total ? thirtyDayAverageDose : totalDose
    }

    private var chartTitle: String {
        selectedInterval == .day ? "Total Hourly Dose (U)" : "Total Daily Dose (U)"
    }

    /// Retrieves the TDD statistic for a given date.
    /// - Parameter date: The date for which to retrieve TDD data.
    /// - Returns: The `TDDStats` object if available, otherwise `nil`.
    private func getTDDForDate(_ date: Date) -> TDDStats? {
        chartStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    /// Reset the chart to the canonical current period for the selected interval.
    private func resetChartWindow() {
        let initial = StatChartUtils.getInitialTDDScrollPosition(for: selectedInterval)
        scrollPosition = initial
        visibleDomainLength = StatChartUtils.tddVisibleDomainLength(from: initial, for: selectedInterval)
    }

    /// Quantizes a native scroll-position binding back to the semantic major boundary.
    /// Swift Charts can report a binding a few minutes to either side of midnight even when it has
    /// visually snapped, so test the nearest midnight rather than requiring exact equality.
    private func canonicalMajorAnchor(for date: Date) -> Date? {
        guard selectedInterval != .total else { return nil }

        let calendar = Calendar.current
        let currentDayStart = calendar.startOfDay(for: date)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: currentDayStart) ?? currentDayStart
        let midnightTolerance: TimeInterval = 15 * 60

        let anchor: Date
        if abs(date.timeIntervalSince(currentDayStart)) <= midnightTolerance {
            anchor = currentDayStart
        } else if abs(nextDayStart.timeIntervalSince(date)) <= midnightTolerance {
            anchor = nextDayStart
        } else {
            return nil
        }

        switch selectedInterval {
        case .day:
            return anchor
        case .week:
            return calendar.component(.weekday, from: anchor) == 1 ? anchor : nil
        case .month:
            return calendar.component(.day, from: anchor) == 1 ? anchor : nil
        case .total:
            return nil
        }
    }

    /// Update a variable calendar-period viewport only after native major snapping has completed.
    private func updateVisibleDomainAfterNativeSnap(_ newPosition: Date) {
        guard let anchor = canonicalMajorAnchor(for: newPosition) else { return }
        let newLength = StatChartUtils.tddVisibleDomainLength(from: anchor, for: selectedInterval)

        if abs(newLength - visibleDomainLength) > 1 {
            visibleDomainLength = newLength
        }
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
            resetChartWindow()
        }
        .onChange(of: selectedInterval) {
            selectedDate = nil
            resetChartWindow()
        }
        .onChange(of: scrollPosition) { _, newPosition in
            updateVisibleDomainAfterNativeSnap(newPosition)
        }
    }

    /// A view displaying the average and secondary summary for the exact bars in the visible range.
    private var statsView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                summaryRow(label: averageLabel, value: averageDose)
                summaryRow(label: secondaryLabel, value: secondaryDose)
            }
            .font(.headline)

            Spacer()

            Text(
                StatChartUtils
                    .formatVisibleDateRange(from: visibleDateRange.start, to: visibleDateRange.end, for: selectedInterval)
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// Keeps each value immediately adjacent to its label rather than sharing a variable-width Grid column.
    private func summaryRow(label: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
            Text(value.formatted(.number.precision(.fractionLength(1))))
                + Text("\u{00A0}") + Text("U")
        }
    }

    /// Applies either the native scroll/snap behavior or the static latest-90-day domain.
    @ViewBuilder private var chartsView: some View {
        if selectedInterval == .total {
            let range = StatChartUtils.latest90DayTDDRange()

            baseChart
                .chartXScale(domain: range.start ... range.domainEnd)
                .frame(height: 250)
        } else {
            baseChart
                .chartScrollableAxes(.horizontal)
                .chartScrollPosition(x: $scrollPosition)
                .chartScrollTargetBehavior(
                    .valueAligned(
                        matching: StatChartUtils.tddMinorAlignmentComponents(for: selectedInterval),
                        majorAlignment: .matching(
                            StatChartUtils.tddMajorAlignmentComponents(for: selectedInterval)
                        ),
                        limitBehavior: .always
                    )
                )
                .chartXVisibleDomain(length: visibleDomainLength)
                .frame(height: 250)
        }
    }

    /// A chart displaying raw hourly/daily insulin totals as bars.
    private var baseChart: some View {
        Chart {
            ForEach(chartStats) { stat in
                let isSunday = Calendar.current.component(.weekday, from: stat.date) == 1
                let highlightSunday = (selectedInterval == .month || selectedInterval == .total) && isSunday

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(highlightSunday ? Color.basal : Color.insulin)
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

            // Keep the complete current day/week/month scrollable even before that period has finished.
            // In 3-month mode this simply pins the end of the static latest-90-day domain.
            PointMark(
                x: .value("Current Range End", StatChartUtils.currentTDDPageEnd(for: selectedInterval)),
                y: .value("Boundary", 0)
            )
            .opacity(0)

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
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
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
                        if hour % 6 == 0 {
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .month:
                        let weekday = calendar.component(.weekday, from: date)
                        if weekday == 1 {
                            AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                                .font(.footnote)
                            AxisGridLine()
                        }
                    case .total:
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
    }
}

/// A popover view displaying TDD (Total Daily Dose) for a given time period.
/// Shows the insulin amount in units (U) for an hourly or daily interval, depending on `selectedInterval`.
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
        let padding: CGFloat = 10

        let dateFraction = selectedDate.timeIntervalSince(domain.start) / domainDuration
        let xSelected = dateFraction * chartWidth

        let xLeft = xSelected - (popoverWidth / 2)
        let xRight = xSelected + (popoverWidth / 2)

        var offset: CGFloat = 0

        if xLeft < padding {
            offset = padding - xLeft
        } else if xRight > chartWidth - padding {
            offset = (chartWidth - padding) - xRight
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
        .frame(minWidth: 100, maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { popoverSize = geo.size }
                    .onChange(of: geo.size) { _, newValue in popoverSize = newValue }
            }
        )
        .offset(x: xOffset(), y: 0)
        .opacity(selectedDate >= domain.start && selectedDate <= domain.end ? 1 : 0)
    }
}
