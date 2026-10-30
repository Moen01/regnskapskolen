import AppKit
import RegnskapKit
import SwiftUI

/// `REGNSKAP_SCREENSHOTS=<dir>`: renders every screen off-screen to PNG and quits, so the UI can be
/// checked without clicking. Never activates the app.
enum Screenshots {
    @MainActor
    static func capture(to dir: String, store: AppStore) async {
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Anything the screens save (a finished round saves progress) lands beside the PNGs, never in Application Support.
        store.progressStore = ProgressStore(url: folder.appendingPathComponent("fremdrift-demo.json"))
        store.settings.contentFolder = ProcessInfo.processInfo.environment["REGNSKAP_INNHOLD"] ?? ContentLocator.repoContent.path
        store.loadContent()
        store.progress = demoProgress(pool: store.pool)
        store.todayKey = DayKey.today()
        store.today = Scheduler.startDay(store.todayKey, count: 3, pool: store.pool, progress: &store.progress)
        store.claudeStatus = .ready(ClaudeAccount(loggedIn: true, email: "deg@eksempel.no", subscriptionType: "pro", authMethod: "claude.ai"))
        store.loadSandboxDemo()
        let navigation = Navigation()

        for section in AppSection.allCases {
            navigation.section = section
            store.openPuzzle = nil
            await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("\(section.rawValue).png"))
        }
        store.sandboxPane = .bank
        navigation.section = .sandbox
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("sandbox-bank.png"))
        store.sandboxPane = .journal
        // The games: a round just started, then its summary. No clock runs in screenshot mode.
        // Paragrafjakten and the training grounds sit behind the town's TRENING.
        navigation.section = .game
        store.showTraining = true
        store.lynrundeTema = "mva"  // every puzzle in the round is mva, so the shot shows the two-step input
        store.startLightning()
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("spill-lynrunde.png"))
        store.endRound()
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("spill-oppsummering.png"))
        store.lastSummary = nil
        store.startDrill()
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("spill-debet-kredit.png"))
        store.endRound()
        store.lastSummary = nil
        // Too small for the handheld: the screen asks for a bigger window instead of overlapping.
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 500, height: 400), to: folder.appendingPathComponent("spill-lite.png"))
        store.openRegion("mva")
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("spill-region.png"))
        store.startRun()
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("spill-mote.png"))
        store.endRun()
        store.lastRunSummary = nil
        store.selectedRegion = nil
        store.showCollection = true
        await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("spill-samling.png"))
        store.showCollection = false
        store.showTraining = false
        await snapTown(store: store, navigation: navigation, folder: folder)
        navigation.section = .today
        for kind in PuzzleKind.allCases {
            guard let puzzle = store.pool.first(where: { $0.kind == kind }) else { continue }
            store.openPuzzle = puzzle
            store.openFromToday = false
            await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent("oppgave-\(kind.rawValue).png"))
        }
        store.openPuzzle = nil
        if let posting = store.pool.first(where: { $0.kind == .postering }), case .posting(let p) = posting.payload, let first = p.fasit.first {
            var session = PuzzleSession(puzzle: posting)
            session.attempt = .posting([PostingAttemptLine(konto: first.konto, kredit: first.belop), PostingAttemptLine(konto: p.kontoer.last?.nr ?? "", debet: first.belop)])
            session.check()
            await snap(PuzzleView(puzzle: posting, session: session, onResult: { _ in }).environment(store).environment(navigation), size: NSSize(width: 900, height: 760), to: folder.appendingPathComponent("oppgave-postering-feil.png"))
        }
        if let quiz = store.pool.first(where: { $0.kind == .quiz }), case .quiz(let q) = quiz.payload {
            var session = PuzzleSession(puzzle: quiz)
            session.attempt = .quiz(q.svar)
            session.check()
            await snap(PuzzleView(puzzle: quiz, session: session, onResult: { _ in }, onNext: {}).environment(store).environment(navigation), size: NSSize(width: 900, height: 760), to: folder.appendingPathComponent("oppgave-quiz-riktig.png"))
        }
        await snap(PopoverView().environment(store).environment(navigation), size: NSSize(width: 340, height: 360), to: folder.appendingPathComponent("popover.png"))
        navigation.showOnboarding = true
        await snap(OnboardingView().environment(store).environment(navigation), size: NSSize(width: 560, height: 520), to: folder.appendingPathComponent("onboarding.png"))
        print("Skrev skjermbilder til \(folder.path)")
    }

    /// The town in fixed states on fixed days, so the shots are the same on every run: Sentrum,
    /// the counter with a month to close and a term to deliver, Fristnav three days before the term,
    /// the menu with date and energy, the bag, and a customer case as its battle opens.
    @MainActor
    static func snapTown(store: AppStore, navigation: Navigation, folder: URL) async {
        guard let library = store.library else { return }
        let town = library.town
        let visible = Set(store.pool.map(\.id))
        let cafe = "kafe-lysthuset"
        func stage(map: String, x: Int, y: Int, facing: Facing, day: DayKey, _ change: (inout TownState) -> Void = { _ in }) {
            var state = TownState.new(content: town, year: 2026)
            state.mapId = map
            state.walker = TownWalker(x: x, y: y, facing: facing)
            state.calendar = TownCalendar(start: day)
            change(&state)
            store.town = nil
            store.progress.game.town = state
            store.openTown()
        }
        func shot(_ name: String) async {
            await snap(MainView().environment(store).environment(navigation), size: NSSize(width: 1200, height: 800), to: folder.appendingPathComponent(name))
        }

        // In front of a customer case, with a roof, a door, a sign, the grass and a passer-by in view.
        stage(map: "sentrum", x: 23, y: 11, facing: .up, day: DayKey(year: 2026, month: 1, day: 5))
        await shot("spill-by.png")

        // January and February booked and closed; March has no bilag, so it can close on 2 April.
        stage(map: "kontoret", x: 2, y: 3, facing: .up, day: DayKey(year: 2026, month: 4, day: 2)) { state in
            guard let client = town.client(cafe) else { return }
            for month in [MonthKey(year: 2026, month: 1), MonthKey(year: 2026, month: 2)] {
                for id in Ledger.pile(for: client, month: month, start: state.start, state: state.clients[cafe]!, pool: visible) {
                    state.clients[cafe]?.book(BookedBilag(puzzleId: id, month: month, day: month.next.first, correct: true), boxBefore: 0, client: cafe)
                }
                state.clients[cafe]?.closeIfClean(month)
            }
        }
        store.townKey(.a)
        await shot("spill-kontoret.png")

        stage(map: "kontoret", x: 3, y: 3, facing: .left, day: DayKey(year: 2026, month: 4, day: 7)) { state in
            state.clients["nettbutikken-pixel"]?.status = .active
        }
        store.townKey(.a)
        store.townKey(.a)
        await shot("spill-fristnav.png")

        // The menu with the date and energy box, then the bag with two cups from the machine.
        stage(map: "kontoret", x: 3, y: 3, facing: .left, day: DayKey(year: 2026, month: 4, day: 10)) { state in
            state.energy = 85
            state.coffee = 2
        }
        store.townKey(.a)
        await shot("spill-meny.png")
        store.townKey(.down)
        store.townKey(.down)
        store.townKey(.a)
        await shot("spill-bag.png")

        // The bag with three rule cards, the first one put on for the next battle, the cursor on the second.
        let cards = Array(library.rules.prefix(3).map(\.id))
        stage(map: "kontoret", x: 3, y: 3, facing: .left, day: DayKey(year: 2026, month: 4, day: 10)) { state in
            state.regelkort = Set(cards)
            state.equippedCard = cards.first
        }
        store.townKey(.a)
        store.townKey(.down)
        store.townKey(.down)
        store.townKey(.a)
        store.townKey(.down)
        store.townKey(.down)
        store.townKey(.a)
        store.townKey(.down)
        await shot("spill-regelkort.png")

        // Each new district on its arrival square, with the permit that opens it.
        let day = DayKey(year: 2026, month: 1, day: 5)
        for (district, name) in [("havna", "spill-havna.png"), ("industri", "spill-industri.png"), ("bryggen", "spill-bryggen.png")] {
            guard let arrival = TownDistricts.all(in: town).first(where: { $0.id == district })?.ankomst else { continue }
            stage(map: district, x: arrival.x, y: arrival.y, facing: .down, day: day) { $0.fullmakter = [district] }
            await shot(name)
        }

        // Fast travel from Fristnav with all four districts open.
        stage(map: "kontoret", x: 3, y: 3, facing: .left, day: DayKey(year: 2026, month: 4, day: 10)) { state in
            state.fullmakter = ["havna", "industri", "bryggen"]
        }
        store.townKey(.a)
        store.townKey(.a)
        for _ in 0..<12 { store.townKey(.down) }
        store.townKey(.a)
        await shot("spill-reise.png")

        // The gate to Bryggen without a permit.
        stage(map: "sentrum", x: 9, y: 1, facing: .up, day: day)
        store.townKey(.up)
        await shot("spill-stengt.png")

        // The archive on the office PC: the cafe is active, the web shop is put away.
        stage(map: "kontoret", x: 8, y: 2, facing: .up, day: DayKey(year: 2026, month: 4, day: 10)) { state in
            state.clients["nettbutikken-pixel"]?.status = .parked
        }
        store.townKey(.a)
        for _ in 0..<5 where store.town?.phase == .dialog { store.townKey(.a) }
        await shot("spill-arkiv.png")

        // A fagkontor whose gym is not yet full: the dialog ends with the GYM line.
        stage(map: "lonnskontoret", x: 4, y: 3, facing: .up, day: day) { $0.fullmakter = ["industri"] }
        store.townKey(.a)
        for _ in 0..<5 where store.town?.hasMorePages == true { store.townKey(.a) }
        await shot("spill-fagkontor.png")

        // A customer case: the doctor's office asks, JA starts the case, and the battle opens with its question.
        stage(map: "sentrum", x: 23, y: 6, facing: .up, day: DayKey(year: 2026, month: 1, day: 5)) { state in
            state.clients["legekontoret-bryggen"]?.status = .active
        }
        store.townKey(.a)
        for _ in 0..<20 where store.town?.phase == .dialog { store.townKey(.a) }
        store.townKey(.a)
        await shot("spill-kundesak.png")
        store.finishBilag()
        store.town = nil
        store.progress.game.town = nil

        await snapAudit(store: store, folder: folder, stage: { stage(map: $0, x: $1, y: $2, facing: $3, day: $4, $5) }, shot: shot)
    }

    /// The bokettersyn at Avgiftskontoret, the new year and the annual deadlines. All fagkontor badges
    /// are set for the shots and removed again at the end, with the staged town.
    @MainActor
    private static func snapAudit(store: AppStore, folder: URL, stage: (String, Int, Int, Facing, DayKey, (inout TownState) -> Void) -> Void, shot: (String) async -> Void) async {
        guard let library = store.library else { return }
        let town = library.town
        let visible = Set(store.pool.map(\.id))
        let cafe = "kafe-lysthuset"
        let auditDay = DayKey(year: 2027, month: 1, day: 4)
        let badgeKeys = town.kart.flatMap(\.folk).compactMap(\.fagkontor).map(TownTrials.badgeKey)
        for key in badgeKeys { store.progress.game.badges[key] = auditDay }
        let districts: Set<String> = ["havna", "industri", "bryggen"]

        // The desk, A through the dialog to the question. The cards the badges give are in the bag
        // already, so opening the town does not read them out first.
        func atDesk(_ change: @escaping (inout TownState) -> Void = { _ in }) {
            stage("avgiftskontoret", 4, 4, .up, auditDay) { state in
                state.fullmakter = districts
                state.regelkort = Set(library.rules.map(\.id))
                change(&state)
            }
            for _ in 0..<40 where store.town?.phase == .dialog { store.townKey(.a) }
            store.townKey(.a)
            for _ in 0..<10 where store.town?.phase == .dialog { store.townKey(.a) }
        }

        atDesk()
        await shot("spill-avgiftskontoret.png")

        // One wrong bilag at the cafe in November: the review opens on it, at full HP.
        atDesk { state in
            // The café's slices may run out before November; any of its visible puzzles will do as the error.
            guard let client = town.client(cafe), let id = client.oppgaver.first(where: visible.contains) else { return }
            state.clients[cafe]?.book(BookedBilag(puzzleId: id, month: MonthKey(year: 2026, month: 11), day: DayKey(year: 2026, month: 12, day: 1), correct: false), boxBefore: 0, client: cafe)
        }
        store.townKey(.a)
        await shot("spill-bokettersyn.png")
        store.finishAudit()

        // No open errors: the first controller takes over at once.
        atDesk()
        store.townKey(.a)
        await shot("spill-kontrollor.png")
        store.finishAudit()
        store.progress.game.town?.auditTriedOn = nil

        // The pass: the dialog on the desk's map, in the new year.
        stage("avgiftskontoret", 4, 4, .up, auditDay) { $0.fullmakter = districts }
        store.town?.tell(TownFlow.auditResultTexts(won: true, year: 2026, today: auditDay, standing: 0, newBadge: true))
        await shot("spill-nytt-aar.png")

        // Fristnav on 28 May 2027: every 2026 month is closed, the 31 May tax return is the next row.
        stage("kontoret", 3, 3, .left, DayKey(year: 2027, month: 5, day: 28)) { state in
            for month in 1...12 { state.clients[cafe]?.closedMonths.insert(MonthKey(year: 2026, month: month)) }
            state.fullmakter = districts
            state.regelkort = Set(library.rules.map(\.id))
        }
        for _ in 0..<40 where store.town?.phase == .dialog { store.townKey(.a) }
        store.townKey(.a)
        store.townKey(.a)
        await shot("spill-arsfrister.png")

        for key in badgeKeys { store.progress.game.badges[key] = nil }
        store.town = nil
        store.progress.game.town = nil
    }

    @MainActor
    static func snap(_ view: some View, size: NSSize, to url: URL) async {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // An explicit frame: the hosting view would otherwise size the window to the view's ideal size.
        // An explicit background: the window's own is not part of what the content view draws.
        let controller = NSHostingController(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(size)
        let screens = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        window.setFrameOrigin(NSPoint(x: screens.maxX + 4000, y: screens.minY))
        window.orderFrontRegardless()
        // Give SwiftUI a few run-loop turns to lay the view out before the capture.
        try? await Task.sleep(for: .milliseconds(800))
        window.layoutIfNeeded()
        window.displayIfNeeded()
        guard let content = window.contentView, let rep = render(content) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }

    /// `cacheDisplay` draws the window in-process, but what sits inside a glass effect view (the sidebar
    /// on macOS 26) is composited by the window server and comes out blank. Those subtrees are captured
    /// on their own and pasted over the full image.
    @MainActor
    static func render(_ content: NSView) -> NSBitmapImageRep? {
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: rep)
        let holders = glassContents(in: content)
        guard !holders.isEmpty, let context = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for holder in holders {
            guard let part = holder.bitmapImageRepForCachingDisplay(in: holder.bounds) else { continue }
            holder.cacheDisplay(in: holder.bounds, to: part)
            // The context works in points with a bottom-left origin; the content view is flipped.
            var target = content.convert(holder.bounds, from: holder)
            if content.isFlipped { target.origin.y = content.bounds.height - target.maxY }
            let image = NSImage(size: holder.bounds.size)
            image.addRepresentation(part)
            image.draw(in: target)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// The content view of every glass effect container under `view`.
    @MainActor
    static func glassContents(in view: NSView) -> [NSView] {
        if String(describing: type(of: view)).contains("GlassEffectView"), let inner = view.subviews.first { return [inner] }
        return view.subviews.flatMap(glassContents)
    }

    /// Progress with a few days of history, so the screens have something to show.
    @MainActor
    static func demoProgress(pool: [Puzzle]) -> LearnerProgress {
        var progress = LearnerProgress()
        let today = DayKey.today()
        for offset in [-4, -3, -2, -1] {
            let day = today.adding(days: offset)
            let set = Scheduler.startDay(day, count: 3, pool: pool, progress: &progress)
            for (i, p) in set.enumerated() { Scheduler.record(AttemptResult(puzzleId: p.id, correctFirstTry: i != 1), on: day, progress: &progress) }
        }
        for p in pool.filter({ $0.tema == "grunnlag" }).prefix(6) { progress.puzzles[p.id] = PuzzleProgress(box: 3, attempts: 2, correct: 2, lastSeen: today.adding(days: -2), due: today.adding(days: 5)) }
        return progress
    }
}

