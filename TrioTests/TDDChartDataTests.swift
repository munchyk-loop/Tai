import Foundation
import Testing

@testable import Trio

@Suite("Insulin chart ranges and summaries") struct TDDChartDataTests {
    private func calendar(_ zone: String = "America/New_York") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        result.firstWeekday = 2 // Deliberately use a Monday-first locale.
        return result
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("Day averages use hourly totals and exclude zero hours") func hourlySummary() {
        let c = calendar()
        let start = date(2026, 9, 1, calendar: c)
        let range = TDDChartData.visibleRange(from: start, for: .day, calendar: c)
        let stats = [
            TDDStats(date: start.addingTimeInterval(-3600), amount: 100),
            TDDStats(date: start, amount: 2),
            TDDStats(date: start.addingTimeInterval(3600), amount: 0),
            TDDStats(date: start.addingTimeInterval(7200), amount: 4),
            TDDStats(date: range.upperBound, amount: 100)
        ]
        let summary = TDDChartData.summary(of: stats, in: range, calendar: c)
        #expect(summary.total == 6)
        #expect(summary.average == 3)
    }

    @Test(
        "Daily averages exclude zero days and the following page",
        arguments: [TDDChartData.Interval.week, .month, .total]
    )  func dailySummary(interval: TDDChartData.Interval) {
        let c = calendar()
        let start = date(2026, 1, 1, calendar: c)
        let range = TDDChartData.visibleRange(from: start, for: interval, calendar: c)
        let stats = [
            TDDStats(date: start, amount: 20),
            TDDStats(date: date(2026, 1, 2, calendar: c), amount: 0),
            TDDStats(date: date(2026, 1, 3, calendar: c), amount: 40),
            TDDStats(date: range.upperBound, amount: 999)
        ]
        let summary = TDDChartData.summary(of: stats, in: range, calendar: c)
        #expect(summary.total == 60)
        #expect(summary.average == 30)
    }

    @Test("Monthly average uses visible monthly totals, excluding empty months") func monthlyAverage() {
        let c = calendar()
        let range = date(2026, 1, 1, calendar: c) ..< date(2026, 4, 1, calendar: c)
        let stats = [
            TDDStats(date: date(2026, 1, 1, calendar: c), amount: 10),
            TDDStats(date: date(2026, 1, 2, calendar: c), amount: 20),
            TDDStats(date: date(2026, 2, 1, calendar: c), amount: 0),
            TDDStats(date: date(2026, 3, 1, calendar: c), amount: 90)
        ]
        let summary = TDDChartData.summary(of: stats, in: range, calendar: c)
        #expect(summary.average == 40)
        #expect(summary.total == 120)
        #expect(summary.monthlyAverage == 60)
    }

    @Test("Precision range monthly average counts only visible parts of each month") func partialMonths() {
        let c = calendar()
        let range = date(2026, 1, 15, calendar: c) ..< date(2026, 4, 15, calendar: c)
        let stats = [1, 2, 3, 4].map { month in
            TDDStats(date: date(2026, month, 10, calendar: c), amount: Double(month * 10))
        }
        let summary = TDDChartData.summary(of: stats, in: range, calendar: c)
        #expect(summary.total == 90)
        #expect(summary.monthlyAverage == 30)
    }

    @Test("Empty and all-zero data produce zero rather than NaN") func emptySummary() {
        let c = calendar()
        let start = date(2026, 9, 1, calendar: c)
        let range = TDDChartData.visibleRange(from: start, for: .day, calendar: c)
        for stats in [[], [TDDStats(date: start, amount: 0)]] {
            let summary = TDDChartData.summary(of: stats, in: range, calendar: c)
            #expect(summary.average == 0)
            #expect(summary.monthlyAverage == 0)
            #expect(summary.total == 0)
        }
    }

    @Test("Week starts Sunday even in a Monday-first locale") func sundayWeek() {
        let c = calendar()
        let now = date(2026, 9, 9, 12, calendar: c)
        let start = TDDChartData.initialPosition(for: .week, now: now, calendar: c)
        #expect(start == date(2026, 9, 6, calendar: c))
        let range = TDDChartData.visibleRange(from: start, for: .week, calendar: c)
        #expect(range.upperBound == date(2026, 9, 13, calendar: c))
        #expect(
            TDDChartData
                .rangeLabel(for: range, interval: .week, calendar: c, locale: Locale(identifier: "en_US")) == "Sep 6–Sep 12"
        )
    }

    @Test("Slow scrolling can select Wednesday–Tuesday") func customWeek() {
        let c = calendar()
        let start = date(2026, 9, 9, calendar: c)
        let range = TDDChartData.visibleRange(from: start, for: .week, calendar: c)
        #expect(range.lowerBound == start)
        #expect(range.upperBound == date(2026, 9, 16, calendar: c))
    }

    @Test("Month shows 31 days and its full name at the first", arguments: [2024, 2026]) func february(year: Int) {
        let c = calendar()
        let start = date(year, 2, 1, calendar: c)
        let range = TDDChartData.visibleRange(from: start, for: .month, calendar: c)
        #expect(c.dateComponents([.day], from: start, to: range.upperBound).day == 31)
        #expect(
            TDDChartData
                .rangeLabel(for: range, interval: .month, calendar: c, locale: Locale(identifier: "en_US")) == "February"
        )
    }

    @Test("Custom month label shows the actual inclusive dates") func customMonthLabel() {
        let c = calendar()
        let range = TDDChartData.visibleRange(from: date(2026, 2, 2, calendar: c), for: .month, calendar: c)
        #expect(
            TDDChartData
                .rangeLabel(for: range, interval: .month, calendar: c, locale: Locale(identifier: "en_US")) == "Feb 2–Mar 4"
        )
    }

    @Test("Three-month view contains the last 90 days through today, without month padding") func retainedHistory() {
        let c = calendar()
        let now = date(2026, 1, 15, 12, calendar: c)
        let range = TDDChartData.recentRange(now: now, calendar: c)
        #expect(range.lowerBound == date(2025, 10, 18, calendar: c))
        #expect(range.upperBound == date(2026, 1, 16, calendar: c))
        #expect(c.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day == 90)
        #expect(TDDChartData.initialPosition(for: .total, now: now, calendar: c) == range.lowerBound)
        let domain = TDDChartData.scrollDomain(for: [], interval: .total, now: now, calendar: c)
        #expect(domain.lowerBound == range.lowerBound)
        #expect(domain.upperBound == range.upperBound)
    }

    @Test("Custom day ranges display hours without minutes") func wholeHourLabel() {
        let c = calendar()
        let range = TDDChartData.visibleRange(from: date(2026, 9, 1, 9, calendar: c), for: .day, calendar: c)
        let label = TDDChartData.rangeLabel(for: range, interval: .day, calendar: c, locale: Locale(identifier: "en_US"))
        #expect(!label.contains(":"))
        #expect(label.contains("9"))
        #expect(label.contains("Sep 1"))
        #expect(label.contains("Sep 2"))
    }

    @Test(
        "Midnight boundaries survive DST and fractional time zones",
        arguments: ["America/New_York", "Europe/Berlin", "Asia/Kolkata", "Pacific/Kiritimati"]
    )  func calendarBoundaries(zone: String) {
        let c = calendar(zone)
        for (month, day) in [(3, 8), (3, 29), (11, 1)] {
            let start = date(2026, month, day, calendar: c)
            for interval in [TDDChartData.Interval.day, .week, .month, .total] {
                let range = TDDChartData.visibleRange(from: start, for: interval, calendar: c)
                #expect(c.component(.hour, from: range.upperBound) == 0)
                #expect(range.lowerBound == start)
            }
        }
        if zone == "America/New_York" {
            let spring = TDDChartData.visibleRange(from: date(2026, 3, 8, calendar: c), for: .day, calendar: c)
            let fall = TDDChartData.visibleRange(from: date(2026, 11, 1, calendar: c), for: .day, calendar: c)
            #expect(spring.upperBound.timeIntervalSince(spring.lowerBound) == 23 * 3600)
            #expect(fall.upperBound.timeIntervalSince(fall.lowerBound) == 25 * 3600)
        }
    }

    @Test(
        "Fractional native scroll positions retain the intended page",
        arguments: [-0.01, 0.01]
    ) func fractionalPosition(offset: Double) {
        let c = calendar()
        let start = date(2026, 2, 1, calendar: c)
        for interval in [TDDChartData.Interval.day, .week, .month, .total] {
            #expect(
                TDDChartData.visibleRange(from: start.addingTimeInterval(offset), for: interval, calendar: c)
                    .lowerBound == start
            )
        }
    }

    @Test("Only Sunday is accented, and only in month and three-month views") func sundayColor() {
        let c = calendar()
        let saturday = date(2026, 9, 5, calendar: c)
        let sunday = date(2026, 9, 6, calendar: c)
        for interval in TDDChartData.Interval.allCases {
            #expect(!TDDChartData.highlightsSunday(saturday, for: interval, calendar: c))
            #expect(
                TDDChartData
                    .highlightsSunday(sunday, for: interval, calendar: c) == (interval == .month || interval == .total)
            )
        }
    }

    @Test("Scale contains the entire current page even with sparse or no data") func scrollBounds() {
        let c = calendar()
        let now = date(2026, 9, 9, 12, calendar: c)
        for interval in [TDDChartData.Interval.day, .week, .month] {
            for stats in [[], [TDDStats(date: now, amount: 2)]] {
                let domain = TDDChartData.scrollDomain(for: stats, interval: interval, now: now, calendar: c)
                let initial = TDDChartData.initialPosition(for: interval, now: now, calendar: c)
                #expect(domain.lowerBound <= initial)
                #expect(domain.upperBound == TDDChartData.endDate(from: initial, for: interval, calendar: c))
            }
        }
    }
}
