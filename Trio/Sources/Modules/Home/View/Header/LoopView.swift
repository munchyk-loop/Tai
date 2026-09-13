import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Config {
        static let lag: TimeInterval = 30
    }

    let closedLoop: Bool
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool

    let determination: [OrefDetermination]

    private let rect = CGRect(x: 0, y: 0, width: 18, height: 18)

    var body: some View {
        HStack(alignment: .center) {
            if determination.first?
                .deliverAt !=
                nil
            {
                // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
                Text(timeString)
            } else {
                Text("--")
            }
            ZStack {
                if isLooping {
                    CircleProgress()
                } else {
                    Circle()
                        .strokeBorder(color, lineWidth: 3.2)
                        .frame(width: rect.width, height: rect.height, alignment: .center)
                        .mask(mask(in: rect).fill(style: FillStyle(eoFill: true)))
                }
            }
        }
        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
        .foregroundColor(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(loopAccessibilityLabel))
    }

    /// Spoken description of loop state — mirrors the color/text logic so the
    /// color-coded health (green/yellow/red) is conveyed in words, not just hue.
    private var loopAccessibilityLabel: String {
        let status: String
        if manualTempBasal {
            status = String(localized: "manual temporary basal running", comment: "Accessibility: loop status")
        } else if determination.first?.timestamp == nil {
            status = String(localized: "not looping", comment: "Accessibility: loop status")
        } else if !closedLoop {
            status = String(localized: "open loop", comment: "Accessibility: loop status")
        } else {
            // Use the more recent timestamp to handle race condition between lastLoopDate and determination fetch
            let enactedTimestamp = determination.first?.timestamp ?? .distantPast
            let effectiveLoopDate = max(lastLoopDate, enactedTimestamp)
            let delta = timerDate.timeIntervalSince(effectiveLoopDate) - Config.lag
            if delta <= 5.minutes.timeInterval {
                status = String(localized: "looping normally", comment: "Accessibility: loop status")
            } else if delta <= 10.minutes.timeInterval {
                status = String(localized: "last loop delayed", comment: "Accessibility: loop status")
            } else {
                status = String(localized: "loop overdue", comment: "Accessibility: loop status")
            }
        }

        let age: String
        if isLooping {
            age = String(localized: "in progress", comment: "Accessibility: loop currently running")
        } else if determination.first?.deliverAt != nil, timeString != "--" {
            age = String(
                format: String(localized: "last loop %@", comment: "Accessibility: loop age"),
                TimeAgoFormatter.minutesAgoAccessible(from: lastLoopDate)
            )
        } else {
            age = ""
        }

        return [String(localized: "Loop", comment: "Accessibility: loop pill label"), status, age]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var timeString: String {
        let minutesAgo = TimeAgoFormatter.minutesAgoValue(from: lastLoopDate)
        if minutesAgo > 1440 {
            return "--"
        } else {
            return TimeAgoFormatter.minutesAgo(from: lastLoopDate)
        }
    }

    private var color: Color {
        guard determination.first?.deliverAt != nil
        else {
            // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
            return .secondary
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        guard closedLoop == true else {
            return .blue
        }

        // Use the more recent timestamp to handle race condition between lastLoopDate and determination fetch
        // lastLoopDate updates immediately when loop runs, but determination fetch is async
        let enactedTimestamp = determination.first?.timestamp ?? .distantPast
        let effectiveLoopDate = max(lastLoopDate, enactedTimestamp)
        let delta = timerDate.timeIntervalSince(effectiveLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    func mask(in rect: CGRect) -> Path {
        var path = Rectangle().path(in: rect)
        if !closedLoop || manualTempBasal {
            path.addPath(Rectangle().path(in: CGRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)))
        }
        return path
    }
}

struct CircleProgress: View {
    /// Spin speed of the gradient: 24° per 30 ms, as the old timer did.
    private static let degreesPerSecond = 800.0
    /// One pulse direction (thick -> thin), autoreversing.
    private static let pulseHalfPeriod = 1.5

    @State private var startDate = Date()

    private func backgroundGradient(rotationAngle: Double) -> AngularGradient {
        // Create a custom angular gradient based on TaiStyle colors but with custom rotation
        AngularGradient(
            stops: [
                .init(color: Color.orange, location: 0.0),
                .init(color: Color.teal, location: 0.3),
                .init(color: Color.cyan, location: 0.5),
                .init(color: Color.teal, location: 0.8),
                .init(color: Color.orange, location: 1.0)

            ],
            center: .center,
            startAngle: .degrees(rotationAngle),
            endAngle: .degrees(rotationAngle + 360)
        )
    }

    var body: some View {
        let rect = CGRect(x: 0, y: 0, width: 18, height: 18)

        // Both spin and pulse are computed from elapsed time instead of a
        // repeatForever animation: an ancestor transaction (e.g. the animated
        // pull-to-refresh insertion) can cancel repeatForever, but it cannot
        // stop a TimelineView.
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startDate)
            let rotationAngle = (elapsed * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360)
            // Triangle wave 0 -> 1 -> 0 over two half-periods, eased in/out.
            let phase = elapsed.truncatingRemainder(dividingBy: 2 * Self.pulseHalfPeriod) / Self.pulseHalfPeriod
            let triangle = phase < 1 ? phase : 2 - phase
            let pulse = 0.5 - cos(.pi * triangle) / 2

            Circle()
                .trim(from: 0, to: 1)
                .stroke(
                    backgroundGradient(rotationAngle: rotationAngle),
                    style: StrokeStyle(lineWidth: 3.2 + pulse * (6 - 3.2))
                )
                .scaleEffect(1 - pulse * 0.5)
                .frame(width: rect.width, height: rect.height, alignment: .center)
        }
    }
}

// extension View {
//    func animateForever(
//        using animation: Animation = Animation.easeInOut(duration: 1),
//        autoreverses: Bool = false,
//        _ action: @escaping () -> Void
//    ) -> some View {
//        let repeated = animation.repeatForever(autoreverses: autoreverses)
//
//        return onAppear {
//            withAnimation(repeated) {
//                action()
//            }
//        }
//    }
// }
