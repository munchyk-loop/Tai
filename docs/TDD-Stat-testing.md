# Insulin statistics testing

Based on `munchyk-loop/Tai` branch `dev-(TAI)`, commit `eaccc8fe1e119626bc94941569f191ae8092b504`.

## Behavior

| Picker | Visible span | Header values | Fast-swipe alignment |
| --- | --- | --- | --- |
| D | One calendar day | Hourly Average, Total | Midnight |
| W | Seven calendar days | Daily Average, Total | Sunday midnight |
| M | 31 calendar days | Daily Average, Total | First of the month |
| 3 M | Three calendar months | Daily Average, Monthly Average | First of the month |

Swift Charts handles scrolling with `valueAligned(matching:majorAlignment:limitBehavior:)`. Slow scrolling aligns to individual hours in D and individual days in W/M/3 M. The existing SwiftUI segmented picker is retained. Selection annotations use native overflow fitting, and the chart uses an explicit scale domain instead of invisible marks.

Bars retain the existing hourly insulin aggregation and latest recorded daily TDD totals. No moving-average values, lines, legend, or calculation cache remain in this chart. This change does not alter insulin delivery or the underlying TDD storage calculation.

Headers derive directly from the displayed hourly/daily dataset. The average includes only nonzero doses. Range ends are exclusive, so the next page's first bar is not included. Averages and totals return zero for an empty range and update when the data or picker changes.

Monthly Average is the mean of the monthly totals represented by the visible bars. Months with no positive insulin are excluded. A partially visible month contributes only its visible bars, without extrapolation. For example, visible monthly totals of 30 U, 0 U, and 90 U yield a monthly average of 60 U.

The requested month view always spans 31 days, even in February or a 30-day month. A range beginning on the first is titled with the full month name; other starts show the inclusive date range. In 2026, February 2 through March 4 is 31 days. Daylight-saving changes use calendar arithmetic to retain midnight boundaries.

Sunday has an accent color only in M and 3 M; Saturday uses the ordinary bar color in every mode.

## Validation performed

- 14 Swift Testing tests passed, including parameterized cases for leap years, time zones, DST, empty/zero data, exclusive range ends, custom ranges, monthly averages, and Sunday accents.
- Production chart and range/summary source type-checked against the iOS SDK, targeting iOS 17. The surrounding app enum and asset colors were supplied by a small standalone validation harness; the chart and calculation source were unchanged.
- Xcode project structure and patch whitespace validated. New source and tests are registered with the app and test targets.

This is not a full TAI app build or simulator UI test. Simulator services were inaccessible in the execution environment, and the standalone tests do not exercise native swipe physics.

## Device checks

1. Open Statistics → Insulin → Total Daily Dose. Switch D/W/M/3 M, including rapid changes. Confirm the two header labels match the table and the initial range starts on the expected calendar boundary.
2. Swipe quickly in both directions in D, W, and M. Check midnight-to-midnight, Sunday–Saturday, and first-of-month alignment. Repeat at the oldest and newest available data.
3. Scroll slowly. In W, stop at Wednesday and confirm Wednesday–Tuesday. In M, stop at February 2 and confirm the range label rather than a full-month title.
4. Compare the total against the visible bars. Verify a zero-dose hour/day does not reduce the average. Scroll into an empty range and confirm zero rather than a stale value.
5. In 3 M, compare Daily Average and Monthly Average against the visible data, including a partial month or a month with no insulin.
6. Check that only Sunday is accented in M/3 M and that no moving-average line or description appears. Press and hold bars near both edges to check native selection fitting.
7. Repeat the day/week checks over spring and autumn DST boundaries, and check readability with a larger Dynamic Type size.

Apple API reference: [Value-aligned chart scrolling](https://developer.apple.com/documentation/charts/chartscrolltargetbehavior/valuealigned(matching:majoralignment:limitbehavior:)).
