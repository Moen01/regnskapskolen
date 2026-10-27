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
        navigation.section = .game
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

