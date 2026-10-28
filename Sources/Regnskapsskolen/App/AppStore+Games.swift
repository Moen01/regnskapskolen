import Foundation
import RegnskapKit

// The games: starting rounds, running their clock, handing answers to Kit and booking the result.
extension AppStore {
    var now: TimeInterval { Date().timeIntervalSinceReferenceDate }
    private static var isScreenshotRun: Bool { ProcessInfo.processInfo.environment["REGNSKAP_SCREENSHOTS"] != nil }
    private var seed: UInt64 { UInt64(Date().timeIntervalSince1970) }

    func startLightning() {
        drill = nil
        lastSummary = nil
        newBadges = []
        weeklyRound = false
        lightning = LightningRound(pool: pool, tema: lynrundeTema, progress: progress, today: todayKey, seed: seed, startedAt: now)
        startClock()
    }

    func startDrill() {
        guard let library else { return }
        lightning = nil
        lastSummary = nil
        newBadges = []
        drill = DebitCreditDrill(chart: library.chart, seed: seed, startedAt: now)
        startClock()
    }

    /// Every answer counts in the boxes and for XP, exactly like an answer in «I dag».
    func answerLightning(_ attempt: PuzzleAttempt) {
        guard var round = lightning, let event = round.answer(attempt, at: now) else { return }
        lightning = round
        record(event.result)
        if round.phase == .finished { endRound() }
    }

    func answerDrill(_ side: Side) {
        guard var round = drill, round.answer(side, at: now) != nil else { return }
        drill = round
        if round.phase == .finished { endRound() }
    }

    func nextInRound() {
        if var round = lightning {
            round.next(at: now)
            lightning = round
            if round.phase == .finished { endRound() }
        } else if var round = drill {
            round.next(at: now)
            drill = round
        }
    }

    /// Closes the open round: record, XP, badges, and the summary the screen shows.
    func endRound() {
        clock?.cancel()
        clock = nil
        let summary: RoundSummary
        if var round = lightning {
            round.finish()
            summary = round.summary
            lightning = nil
        } else if var round = drill {
            round.finish()
            summary = round.summary
            drill = nil
        } else {
            return
        }
        lastWasWeekly = weeklyRound
        if weeklyRound {
            // The challenge has its own book: no record, no round badge, one result per week.
            weeklyRound = false
            lastWasRecord = false
            progress.game.weekly[todayKey.weekKey] = summary.score
            progress.game.counters["uke-\(todayKey.weekKey)"] = summary.correct
        } else {
            let key = Self.scoreKey(summary.game, tema: summary.tema)
            lastWasRecord = summary.answered > 0 && summary.score > (progress.game.bestScores[key] ?? 0)
            if lastWasRecord { progress.game.bestScores[key] = summary.score }
            newBadges += Badges.award(.roundFinished(game: summary.game, tema: summary.tema, score: summary.score, correct: summary.correct), on: todayKey, progress: &progress)
        }
        progress.game.xp += summary.xp
        lastSummary = summary
        saveProgress()
    }

    /// This week's ten, without a clock; refused once the week has a result.
    func startWeekly() {
        guard let library, weeklyDone == nil else { return }
        drill = nil
        lastSummary = nil
        newBadges = []
        let week = todayKey.isoWeek
        let ten = WeeklyChallenge.puzzles(approved: library.approved, week: week)
        weeklyRound = true
        lightning = LightningRound(pool: ten, tema: nil, progress: progress, today: todayKey, seed: WeeklyChallenge.seed(for: week), startedAt: now, duration: .infinity)
        startClock()
    }

    var weeklyDone: Int? { progress.game.weekly[todayKey.weekKey] }
    var weeklyCode: String? { weeklyDone.map { WeeklyChallenge.resultCode(week: todayKey.isoWeek.week, score: $0, correct: progress.game.counters["uke-\(todayKey.weekKey)"] ?? 0) } }

    func bestScore(for game: GameKind, tema: String?) -> Int? {
        progress.game.bestScores[Self.scoreKey(game, tema: tema)]
    }

    /// Topic rounds keep their own records; only the all-topics round holds the «lynrunde» record.
    static func scoreKey(_ game: GameKind, tema: String?) -> String {
        game == .lynrunde ? tema.map { "lynrunde:\($0)" } ?? "lynrunde" : game.rawValue
    }

    /// Ten ticks a second; the round itself decides when the time is up. Not in screenshot mode,
    /// where a round must stay still while it is drawn.
    private func startClock() {
        clock?.cancel()
        guard !Self.isScreenshotRun else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                if var round = self.lightning {
                    round.tick(at: self.now)
                    if round.phase != self.lightning?.phase { self.lightning = round }
                    if round.phase == .finished { self.endRound(); return }
                } else if var round = self.drill {
                    round.tick(at: self.now)
                    if round.phase != self.drill?.phase { self.drill = round }
                    if round.phase == .finished { self.endRound(); return }
                } else {
                    return
                }
            }
        }
    }
}
