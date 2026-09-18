import Charts
import Foundation
import SwiftUI

struct CarbView: ChartContent {
    let glucoseData: [GlucoseStored]
    let units: GlucoseUnits
    let carbData: [CarbEntryStored]
    let fpuData: [CarbEntryStored]
    let minValue: Decimal
    let useBars: Bool
    let screenHours: Int16

    /// Scaling reference for bar height: max carb amount across the visible carb data.
    private var maxCarbsValue: Decimal {
        let amounts = carbData.map { Decimal($0.carbs) }
        return amounts.max() ?? 1
    }

    var body: some ChartContent {
        drawCarbs()
        drawFpus()
    }

    private func drawCarbs() -> some ChartContent {
        ForEach(carbData) { carb in
            let carbAmount = carb.carbs
            let carbDate = carb.date ?? Date()

            if let glucose = MainChartHelper.timeToNearestGlucose(
                glucoseValues: glucoseData,
                time: carbDate.timeIntervalSince1970
            )?.glucose {
                let glucoseY = units == .mgdL ? Decimal(glucose) : Decimal(glucose).asMmolL

                if useBars {
                    // Bar mode: anchor at curve, fixed pixel gap. Peak-label collision is handled
                    // by LabelPlacement on the peak labels rather than by shifting the bar.
                    carbBarMark(
                        date: carbDate,
                        yPosition: glucoseY,
                        amount: Decimal(carbAmount),
                        barWidth: MainChartHelper.carbBarWidth(
                            amount: Decimal(carbAmount),
                            minimumSMB: MainChartHelper.Config.smbWidthThreshold,
                            screenHours: screenHours
                        ),
                        label: Formatter.integerFormatter.string(from: carbAmount as NSNumber) ?? "",
                        color: Color.loopYellow
                    )
                } else {
                    // Fixed offset below the curve. Peak labels are now anchored too,
                    // so no extra peak-collision shift is needed here.
                    let yPosition = glucoseY - MainChartHelper.bolusOffset(units: units)
                    let size = min(
                        sqrt(CGFloat(carbAmount) / .pi) * MainChartHelper.Config.carbsScale,
                        MainChartHelper.Config.maxCarbSize
                    )

                    PointMark(
                        x: .value("Time", carbDate, unit: .second),
                        y: .value("Value", yPosition)
                    )
                    .symbol {
                        Image(systemName: "circle.fill").font(.system(size: size)).foregroundStyle(Color.loopYellow)
                            .overlay(
                                Circle().stroke(Color.primary, lineWidth: 0.4)
                            ) }

                    // Xcode 27 annotation-shift fix (upstream #1492): attach the label to a
                    // separate zero-size anchor mark instead of the visible symbol mark.
                    PointMark(
                        x: .value("Time", carbDate, unit: .second),
                        y: .value("Value", yPosition)
                    )
                    .symbolSize(0)
                    .annotation(position: .bottom, spacing: 2) {
                        Text(Formatter.integerFormatter.string(from: carbAmount as NSNumber) ?? "")
                            .font(.caption2)
                            .fixedSize()
                            .rotationEffect(.degrees(-90))
                            .frame(width: 16, height: 22)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
    }

    private func drawFpus() -> some ChartContent {
        ForEach(fpuData, id: \.id) { fpu in
            let fpuAmount = fpu.carbs
            let size = (MainChartHelper.Config.fpuSize + CGFloat(fpuAmount) * MainChartHelper.Config.carbsScale) * 1.8
            let yPosition = minValue // value is parsed to mmol/L when passed into struct based on user settings

            PointMark(
                x: .value("Time", fpu.date ?? Date(), unit: .second),
                y: .value("Value", yPosition)
            )
            .symbolSize(size)
            .foregroundStyle(Color.brown)
        }
    }

    private func carbBarMark(
        date: Date,
        yPosition: Decimal,
        amount: Decimal,
        barWidth: CGFloat,
        label: String,
        color: Color
    ) -> some ChartContent {
        let height = MainChartHelper.carbBarHeight(amount: amount, maxAmount: maxCarbsValue)

        return PointMark(
            x: .value("Time", date, unit: .second),
            y: .value("Value", yPosition)
        )
        .symbolSize(0)
        .annotation(position: .bottom, alignment: .center, spacing: MainChartHelper.Config.carbBarSpacing) {
            VStack(spacing: MainChartHelper.Config.carbAnnotationSpacing) {
                UpArrowBarShape()
                    .fill(color)
                    .overlay(
                        UpArrowBarShape().stroke(Color.primary, lineWidth: 0.4)
                    )
                    .frame(width: barWidth, height: height)
                Text(label)
                    .font(.caption2)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 22)
                    .foregroundStyle(Color.primary)
            }
        }
    }
}
