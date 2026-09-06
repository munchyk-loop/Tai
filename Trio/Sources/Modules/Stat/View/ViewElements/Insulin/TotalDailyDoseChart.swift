import Charts
import SwiftUI

/// Actual hourly or daily insulin totals, with native calendar-aligned scrolling.
struct TotalDailyDoseChart: View {
    @Binding var selectedInterval: Stat.StateModel.StatsTimeInterval
    let tddStats: [TDDStats]

    @State private var scrollPosition: Date
    @State private var selectedDate: Date?

    init(selectedInterval: Binding<Stat.StateModel.StatsTimeInterval>, tddStats: [TDDStats]) {
        _selectedInterval = selectedInterval
        self.tddStats = tddStats
        _scrollPosition = State(initialValue: TDDChartData.initialPosition(for: selectedInterval.wrappedValue))
    }

    private var visibleRange: Range<Date> {
        TDDChartData.visibleRange(from: scrollPosition, for: selectedInterval)
    }

    private var selectedTDD: TDDStats? {
        guard let selectedDate else { return nil }
        return tddStats.first {
            StatChartUtils.isSameTimeUnit($0.date, selectedDate, for: selectedInterval) && visibleRange.contains($0.date)
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
            }
        }
        .onChange(of: selectedInterval) {
            selectedDate = nil
            scrollPosition = TDDChartData.initialPosition(for: selectedInterval)
        }
    }

    private var statsView: some View {
        let summary = TDDChartData.summary(of: tddStats, in: visibleRange)
        return VStack(alignment: .leading, spacing: 8) {
            Text(TDDChartData.rangeLabel(for: visibleRange, interval: selectedInterval))
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

    private var chartsView: some View {
        Chart {
            ForEach(tddStats) { stat in
                BarMark(
                    x: .value("Date", stat.date, unit: selectedInterval == .day ? .hour : .day),
                    y: .value("Amount", stat.amount)
                )
                .foregroundStyle(
                    TDDChartData.highlightsSunday(stat.date, for: selectedInterval) ? Color.basal : Color.insulin
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
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
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
                    let calendar = Calendar.current
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
        .chartScrollableAxes(.horizontal)
        .chartXSelection(value: $selectedDate)
        .chartScrollPosition(x: $scrollPosition)
        .chartScrollTargetBehavior(
            .valueAligned(
                matching: TDDChartData.minorAlignment(for: selectedInterval),
                majorAlignment: .matching(TDDChartData.majorAlignment(for: selectedInterval)),
                limitBehavior: .always
            )
        )
        .chartXVisibleDomain(length: visibleRange.upperBound.timeIntervalSince(visibleRange.lowerBound))
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
        return dateText + "\n" + tdd.date.formatted(.dateTime.hour().minute()) + "–" + end.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeText)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.secondary)
            Divider()
            Text(tdd.amount.formatted(.number.precision(.fractionLength(1))) + "\u{00A0}U")
                .font(.headline)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
