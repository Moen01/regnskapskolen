import RegnskapKit
import SwiftUI

/// The celebration shown when the day's set is finished or a streak milestone is reached: the figure
/// cheering with a message, plus confetti. Honours Reduce Motion by dropping the confetti. Auto-dismisses
/// and can be dismissed with a click. Only ever shown when the playful theme is on.
struct CelebrationOverlay: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let celebration: Celebration
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea().onTapGesture(perform: onDone)
            VStack(spacing: 14) {
                AccountantFigure(pose: .celebrating, size: 140)
                Text(message).font(.title.weight(.bold)).themedHeading().foregroundStyle(theme.primaryText)
                Text(subtitle).font(.callout).foregroundStyle(theme.secondaryText)
            }
            .padding(32)
            .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
            if !reduceMotion { ConfettiView() }
        }
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.6 : 2.6))
            onDone()
        }
    }

    private var message: String {
        switch celebration {
        case .dayCompleted: "Dagens økt er ferdig!"
        case .streakMilestone(let days): "\(days) dager på rad!"
        }
    }

    private var subtitle: String {
        switch celebration {
        case .dayCompleted: "Godt jobbet. Vi ses i morgen."
        case .streakMilestone: "Du holder streaken i gang. Stå på!"
        }
    }
}
