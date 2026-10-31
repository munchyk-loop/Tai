import Foundation

extension Home.StateModel {
    /// Leading edge of the chart-feeding fetch window.
    var chartHistoryStartDate: Date {
        Date(timeIntervalSinceNow: -chartHistorySpan)
    }

    /// One-shot: widens the fetch window to the full history span and
    /// re-anchors the chart-feeding fetched-results controllers. Chart-only;
    /// dosing reads its own storage fetches and is unaffected.
    func expandChartHistory() {
        guard !isChartHistoryExpanded else { return }
        isChartHistoryExpanded = true
        chartHistorySpan = MainChartHelper.Config.maxChartHistorySeconds
        updateStartEndMarkers()
        Task { @MainActor in
            reanchorFetchWindows()
            await setupGlucoseTargets()
        }
    }

    // Update start and  end marker to fix scroll update problem with x axis
    func updateStartEndMarkers() {
        startMarker = Date(timeIntervalSinceNow: -chartHistorySpan)

        let threeHourSinceNow = Date(timeIntervalSinceNow: TimeInterval(hours: 3))

        // min is 1.5h -> (1.5*1h = 1.5*(5*12*60))
        let dynamicFutureDateForCone = Date(timeIntervalSinceNow: TimeInterval(
            Int(1.5) * 5 * minCount * 60
        ))

        endMarker = forecastDisplayType == .lines ? threeHourSinceNow : dynamicFutureDateForCone <= threeHourSinceNow ?
            dynamicFutureDateForCone.addingTimeInterval(TimeInterval(minutes: 30)) : threeHourSinceNow

        // Target profiles are built at setup and end at a midnight;
        // rebuild them when the chart window moves past the last one
        // cf. https://github.com/nightscout/Trio/issues/1581
        if let lastEnd = targetProfiles.last?.endTime,
           lastEnd < endMarker.timeIntervalSinceReferenceDate
        {
            targetProfiles = processFetchedTargets(bgTargets, startMarker: startMarker)
        }
    }
}
