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

    /// Computes the exact visible date range based on the current scroll position.
    private var visibleDateRange: (start: Date, end: Date) {
        StatChartUtils.tddVisibleDateRange(from: scrollPosition, for: selectedInterval)
    }

    /// The hourly/daily bars that are currently visible.
    private var visibleStats: [TDDStats] {
        tddStats.filter { stat in
            stat.date >= visibleDateRange.start && stat.date <= visibleDateRange.end
        }
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

    private var averageLabel: String {
        selectedInterval == .day ? "Hourly Average:" : "Daily Average:"
    }

    private var totalLabel: String {
        switch selectedInterval {
        case .day:
            return "Daily Total:"
        case .week:
            return "Weekly Total:"
        case .month:
            return "Monthly Total:"
        case .total:
            return "3-Month Total:"
        }
    }

    /// Retrieves the TDD statistic for a given date.
    /// - Parameter date: The date for which to retrieve TDD data.
    /// - Returns: The `TDDStats` object if available, otherwise `nil`.
    private func getTDDForDate(_ date: Date) -> TDDStats? {
        tddStats.first { stat in
            StatChartUtils.isSameTimeUnit(stat.date, date, for: selectedInterval)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text("Total Daily Dose (U)")
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
            scrollPosition = StatChartUtils.getInitialTDDScrollPosition(for: selectedInterval)
        }
        .onChange(of: selectedInterval) {
            selectedDate = nil
            scrollPosition = StatChartUtils.getInitialTDDScrollPosition(for: selectedInterval)
        }
    }

    /// A view displaying the average and total for the exact bars in the visible range.
    private var statsView: some View {
        HStack {
            Grid(alignment: .leading) {
                GridRow {
                    Text(averageLabel)
                    Text(averageDose.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
                GridRow {
                    Text(totalLabel)
                    Text(totalDose.formatted(.number.precision(.fractionLength(1))))
                        + Text("\u{00A0}") + Text("U")
                }
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

    /// A view displaying raw hourly/daily insulin totals as bars.
    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                let isWeekend = Calendar.current.isDateInWeekend(stat.date)

                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(isWeekend ? Color.basal : Color.insulin)
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

            // Keep the complete current calendar period scrollable even when its future
            // hours/days do not have insulin records yet.
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
                        if weekday == calendar.firstWeekday {
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
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate.animation(.easeInOut))
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: selectedInterval == .day ?
                    DateComponents(minute: 0) :
                    DateComponents(hour: 0),
                majorAlignment: .page
            )
        )
        .chartXVisibleDomain(
            length: StatChartUtils.tddVisibleDomainLength(from: scrollPosition, for: selectedInterval)
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
