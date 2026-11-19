import Foundation

/// A moment worth celebrating with confetti and the figure, decided from a day-completion transition.
public enum Celebration: Equatable, Sendable {
    /// The day's set was just finished (a streak that is not a milestone).
    case dayCompleted
    /// The streak just reached a milestone (7, 30 or 100 days).
    case streakMilestone(Int)
}

public enum Celebrations {
    /// Streaks that earn the bigger celebration, in the UI's words.
    public static let milestones = [7, 30, 100]

    /// What to celebrate when an answer flips the day's `done` flag.
    /// Returns nil unless the day went from not-done to done, so a later answer the same day
    /// and app launch never celebrate. A milestone streak outranks a plain completion.
    public static func forDayTransition(wasDone: Bool, isDone: Bool, streak: Int) -> Celebration? {
        guard !wasDone, isDone else { return nil }
        return milestones.contains(streak) ? .streakMilestone(streak) : .dayCompleted
    }
}
