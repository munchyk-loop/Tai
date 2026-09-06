import Charts
import SwiftUI

/// Actual hourly or daily insulin totals, with native calendar-aligned scrolling.
struct TotalDailyDoseChart: View {
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    let tddStats: [TDDStats]

    // Live offsets are deliberately not published. Only a settled range updates the header.
    @State private var scrolling: TDDChartScrollPosition
    @State private var displayedRange: Range<Date>
    @State private var summary: TDDChartData.Summary
    @State private var selectedDate: Date?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return calendar
    }

    init(selectedInterval: Binding<Stat.StateModel.StatsTimeInterval>, tddStats: [TDDStats]) {
        _selectedInterval = selectedInterval
        self.tddStats = tddStats
        let interval = selectedInterval.wrappedValue
        let initial = TDDChartData.initialPosition(for: interval)
        let range = interval == .total ? TDDChartData.recentRange() : TDDChartData.visibleRange(from: initial, for: interval)
        _scrolling = State(initialValue: TDDChartScrollPosition(position: initial))
        _displayedRange = State(initialValue: range)
        _summary = State(initialValue: TDDChartData.summary(of: tddStats, in: range))
    }

    private var selectedTDD: TDDStats? {
        guard let selectedDate else { return nil }
        return tddStats.first {
            calendar.isDate($0.date, equalTo: selectedDate, toGranularity: selectedInterval == .day ? .hour : .day)
                && displayedRange.contains($0.date)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statsView.padding(.bottom)

            VStack(alignment: .trailing) {
                Text(selectedInterval == .day ? "Total Hourly Dose (U)" : "Total Daily Dose (U)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .padding(.bottom, 4)

                chartsView
                    // Reserve annotation space so selection never moves the plot or covers its bars.
                    .padding(.top, selectedInterval == .day ? 80 : 60)
            }
        }
        .environment(\.calendar, calendar)
        .environment(\.timeZone, calendar.timeZone)
        .onChange(of: selectedInterval) {
            selectedDate = nil
            scrolling.isScrolling = false
            scrolling.position = TDDChartData.initialPosition(for: selectedInterval, calendar: calendar)
            updateSummary()
        }
        .onChange(of: tddStats) {
            if !scrolling.isScrolling { updateSummary() }
        }
    }

    private var statsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TDDChartData.rangeLabel(for: displayedRange, interval: selectedInterval, calendar: calendar))
                .font(.callout)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12) {
                GridRow {
                    Text(selectedInterval == .day ? "Hourly Average" : "Daily Average")
                    doseText(summary.average)
                }
                GridRow {
                    Text(selectedInterval == .total ? "Monthly Average" : "Total")
                    doseText(selectedInterval == .total ? summary.monthlyAverage : summary.total)
                }
            }
            .font(.headline)
        }
    }

    private func doseText(_ amount: Double) -> some View {
        Text(amount.formatted(.number.precision(.fractionLength(1))) + "\u{00A0}U")
            .monospacedDigit()
    }

    private func updateSummary() {
        let range = selectedInterval == .total
            ? TDDChartData.recentRange(calendar: calendar)
            : TDDChartData.visibleRange(from: scrolling.position, for: selectedInterval, calendar: calendar)
        displayedRange = range
        summary = TDDChartData.summary(of: tddStats, in: range, calendar: calendar)
    }

    @ViewBuilder private var chartsView: some View {
        if selectedInterval == .total {
            // This is the complete retained history, not a window into a scrollable chart.
            chart
        } else {
            scrollableChart.onScrollPhaseChange { _, phase in
                scrolling.isScrolling = phase != .idle
                if phase == .idle {
                    // Read the final binding value after Swift Charts finishes the scroll update.
                    DispatchQueue.main.async {
                        if !scrolling.isScrolling { updateSummary() }
                    }
                }
            }
        }
    }

    private var scrollableChart: some View {
        chart
            .chartScrollableAxes(.horizontal)
            .chartScrollPosition(x: Binding(
                get: { scrolling.position },
                set: {
                    if selectedDate != nil { selectedDate = nil }
                    scrolling.position = $0
                }
            ))
            .chartScrollTargetBehavior(
                .valueAligned(
                    matching: TDDChartData.minorAlignment(for: selectedInterval),
                    majorAlignment: selectedInterval == .month
                        ? .matching(TDDChartData.majorAlignment(for: selectedInterval)) : .page,
                    limitBehavior: .always
                )
            )
            // Keep the scale length stable throughout dragging and deceleration.
            .chartXVisibleDomain(length: displayedRange.upperBound.timeIntervalSince(displayedRange.lowerBound))
    }

    private var chart: some View {
        let selectedTDD = selectedTDD
        let bars = selectedInterval == .total ? tddStats.filter { displayedRange.contains($0.date) } : tddStats
        return Chart {
            ForEach(bars) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(
                    TDDChartData.highlightsSunday(stat.date, for: selectedInterval, calendar: calendar) ? Color.basal : Color
                        .insulin
                )
                .annotation(position: .top) {
                    if selectedInterval == .week {
                        Text(stat.amount.formatted(.number.precision(.fractionLength(1))))
                            .font(.footnote)
                            .foregroundStyle(Color.primary)
                    }
                }
                .opacity(selectedTDD.map { $0.date == stat.date ? 1 : 0.3 } ?? 1)
            }

            if let selectedTDD {
                RuleMark(x: .value("Selected Date", selectedTDD.date, unit: selectedInterval == .day ? .hour : .day))
                    .foregroundStyle(Color.insulin.opacity(0.5))
                    .zIndex(-1)
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        TDDSelectionPopover(tdd: selectedTDD, selectedInterval: selectedInterval)
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
                    let day = calendar.component(.day, from: date)
                    let hour = calendar.component(.hour, from: date)
                    let showLabel = switch selectedInterval {
                    case .day: hour % 6 == 0
                    case .week: true
                    case .month: calendar.component(.weekday, from: date) == 1
                    case .total: day == 1
                    }
                    if showLabel {
                        AxisValueLabel(format: StatChartUtils.dateFormat(for: selectedInterval), centered: true)
                            .font(.footnote)
                        AxisGridLine()
                    }
                }
            }
        }
        .chartXScale(
            domain: TDDChartData.scrollDomain(for: tddStats, interval: selectedInterval),
            range: .plotDimension(padding: 0)
        )
        .chartXSelection(value: $selectedDate)
        .frame(height: 250)
    }
}

private struct TDDSelectionPopover: View {
    let tdd: TDDStats
    let selectedInterval: Stat.StateModel.StatsTimeInterval

    private var timeText: String {
        let dateText = tdd.date.formatted(.dateTime.month().day().weekday())
        guard selectedInterval == .day else { return dateText }
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: tdd.date)!
        return dateText + "\n" + tdd.date.formatted(.dateTime.hour()) + "–" + end.formatted(.dateTime.hour())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.secondary)
            Text(tdd.amount.formatted(.number.precision(.fractionLength(1))) + "\u{00A0}U")
                .font(.headline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize()
        .foregroundStyle(.primary)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Swift Charts owns gestures, targets and deceleration. This stores its reported position
/// without publishing every frame to the chart and header.
private final class TDDChartScrollPosition {
    var position: Date
    var isScrolling = false

    init(position: Date) {
        self.position = position
    }
}
