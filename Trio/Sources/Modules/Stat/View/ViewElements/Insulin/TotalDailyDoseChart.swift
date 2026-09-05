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

    /// The last native scroll position after scrolling has fully settled.
    @State private var settledScrollPosition: Date
    /// The currently selected date in the chart.
    @State private var selectedDate: Date?
    /// The actual chart plot's width in pixels.
    @State private var chartWidth: CGFloat = 0

    /// Keep the existing call site API while deriving summaries directly from the settled visible bars.
    init(
        selectedInterval: Binding<Stat.StateModel.StatsTimeInterval>,
        tddStats: [TDDStats],
        state _: Stat.StateModel
    ) {
        _selectedInterval = selectedInterval
        self.tddStats = tddStats
        _settledScrollPosition = State(
            initialValue: StatChartUtils.getInitialTDDScrollPosition(for: selectedInterval.wrappedValue)
        )
    }

    /// Computes the exact settled visible date range.
    /// The 3-month view is a static latest-90-day overview; scrolling views use calendar-aware periods.
    private var visibleDateRange: (start: Date, end: Date) {
        if selectedInterval == .total {
            let range = StatChartUtils.latest90DayTDDRange()
            return (range.start, range.end)
        }

        return StatChartUtils.tddVisibleDateRange(
            from: settledScrollPosition,
            for: selectedInterval
        )
    }

    /// The bars supplied to the chart. The static 3-month overview is explicitly limited to the latest 90 days.
    private var chartStats: [TDDStats] {
        guard selectedInterval == .total else { return tddStats }
        let range = StatChartUtils.latest90DayTDDRange()
        return tddStats.filter { $0.date >= range.start && $0.date <= range.end }
    }

    /// Computes both visible summary values in one pass.
    /// These values are based on the settled page, so they do not churn during drag/deceleration.
    private var visibleSummary: (average: Double, total: Double) {
        let range = visibleDateRange
        var total = 0.0
        var nonZeroTotal = 0.0
        var nonZeroCount = 0

        for stat in tddStats where stat.date >= range.start && stat.date <= range.end {
            total += stat.amount
            if stat.amount > 0 {
                nonZeroTotal += stat.amount
                nonZeroCount += 1
            }
        }

        let average = nonZeroCount > 0 ? nonZeroTotal / Double(nonZeroCount) : 0
        return (average, total)
    }

    private var averageLabel: String {
        selectedInterval == .day ? "Hourly Average" : "Daily Average"
    }

    private var secondaryLabel: String {
        selectedInterval == .total ? "30-Day Average" : "Total"
    }

    private var chartTitle: String {
        selectedInterval == .day ? "Total Hourly Dose (U)" : "Total Daily Dose (U)"
    }

    /// Month pages use the full month name. Other intervals retain their existing range formatting.
    private var visibleRangeLabel: String {
        if selectedInterval == .month {
            return settledScrollPosition.formatted(.dateTime.month(.wide))
        }

        return StatChartUtils.formatVisibleDateRange(
            from: visibleDateRange.start,
            to: visibleDateRange.end,
            for: selectedInterval
        )
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
        settledScrollPosition = StatChartUtils.getInitialTDDScrollPosition(for: selectedInterval)
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
    }

    /// A view displaying the average and secondary summary for the exact bars in the settled visible range.
    private var statsView: some View {
        let summary = visibleSummary
        let secondaryDose = selectedInterval == .total ? summary.average * 30 : summary.total

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                summaryRow(label: averageLabel, value: summary.average)
                summaryRow(label: secondaryLabel, value: secondaryDose)
            }
            .font(.headline)

            Spacer()

            Text(visibleRangeLabel)
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

    /// Uses Swift Charts' native value-aligned scrolling.
    /// Live scroll state is isolated in `NativeTDDScrollableChart` so summary/header work only occurs after settling.
    /// The 3-month view remains a static latest-90-day overview.
    @ViewBuilder private var chartsView: some View {
        if selectedInterval == .total {
            let range = StatChartUtils.latest90DayTDDRange()

            baseChart
                .chartXScale(domain: range.start ... range.domainEnd)
                .frame(height: 250)
        } else {
            NativeTDDScrollableChart(
                selectedInterval: selectedInterval,
                settledScrollPosition: $settledScrollPosition
            ) {
                baseChart
            }
            .id(selectedInterval)
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

/// Owns the live Swift Charts scroll binding so scrolling does not invalidate the parent's
/// summaries and header on every frame. Snapping remains entirely native Swift Charts behavior.
private struct NativeTDDScrollableChart<Content: View>: View {
    let selectedInterval: Stat.StateModel.StatsTimeInterval
    @Binding var settledScrollPosition: Date
    let content: Content

    @State private var scrollPosition: Date
    @State private var visibleDomainLength: TimeInterval

    init(
        selectedInterval: Stat.StateModel.StatsTimeInterval,
        settledScrollPosition: Binding<Date>,
        @ViewBuilder content: () -> Content
    ) {
        self.selectedInterval = selectedInterval
        _settledScrollPosition = settledScrollPosition

        let initialPosition = settledScrollPosition.wrappedValue
        _scrollPosition = State(initialValue: initialPosition)
        _visibleDomainLength = State(
            initialValue: StatChartUtils.tddVisibleDomainLength(
                from: initialPosition,
                for: selectedInterval
            )
        )
        self.content = content()
    }

    /// Every native stop target is a full period boundary rather than an hourly/daily minor mark.
    /// This is still `ChartScrollTargetBehavior.valueAligned`; there is no custom gesture or velocity logic.
    private var pageAlignmentComponents: DateComponents {
        var components = DateComponents()

        switch selectedInterval {
        case .day:
            components.hour = 0
            components.minute = 0
            components.second = 0
        case .week:
            components.hour = 0
            components.minute = 0
            components.second = 0
            components.weekday = 1 // Sunday
        case .month:
            components.day = 1
            components.hour = 0
            components.minute = 0
            components.second = 0
        case .total:
            break
        }

        return components
    }

    private var configuredChart: some View {
        content
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleDomainLength)
            .chartScrollPosition(x: $scrollPosition)
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: pageAlignmentComponents,
                    majorAlignment: .matching(pageAlignmentComponents),
                    limitBehavior: .always
                )
            )
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                configuredChart
                    .onScrollPhaseChange { _, newPhase in
                        if newPhase == .idle {
                            settleScrollPosition()
                        }
                    }
            } else {
                // iOS 17 has no native scroll-phase callback. Preserve the legacy live summary behavior there.
                configuredChart
                    .onChange(of: scrollPosition) { _, newPosition in
                        settledScrollPosition = newPosition
                    }
            }
        }
        .onAppear {
            synchronizeFromSettledPosition()
        }
        .onChange(of: settledScrollPosition) { _, newPosition in
            guard abs(newPosition.timeIntervalSince(scrollPosition)) > 0.5 else { return }
            scrollPosition = newPosition
            visibleDomainLength = StatChartUtils.tddVisibleDomainLength(
                from: newPosition,
                for: selectedInterval
            )
        }
    }

    /// Publish one state change after native drag/deceleration/snapping is fully idle.
    /// Month width is also updated here so 28/29/30/31-day months each fill the chart.
    private func settleScrollPosition() {
        let finalPosition = scrollPosition
        let finalDomainLength = StatChartUtils.tddVisibleDomainLength(
            from: finalPosition,
            for: selectedInterval
        )

        if abs(finalDomainLength - visibleDomainLength) > 0.5 {
            visibleDomainLength = finalDomainLength
        }

        if abs(finalPosition.timeIntervalSince(settledScrollPosition)) > 0.5 {
            settledScrollPosition = finalPosition
        }
    }

    private func synchronizeFromSettledPosition() {
        if abs(settledScrollPosition.timeIntervalSince(scrollPosition)) > 0.5 {
            scrollPosition = settledScrollPosition
        }

        let expectedLength = StatChartUtils.tddVisibleDomainLength(
            from: settledScrollPosition,
            for: selectedInterval
        )
        if abs(expectedLength - visibleDomainLength) > 0.5 {
            visibleDomainLength = expectedLength
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
