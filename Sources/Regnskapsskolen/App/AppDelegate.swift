import AppKit
import RegnskapKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today, practice, game, sandbox, rules, stats, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "I dag"
        case .practice: "Øv"
        case .game: "Spill"
        case .sandbox: "Sandkasse"
        case .rules: "Regler"
        case .stats: "Statistikk"
        case .settings: "Innstillinger"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .practice: "list.bullet.rectangle"
        case .game: "gamecontroller"
        case .sandbox: "tray.2"
        case .rules: "book.closed"
        case .stats: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class Navigation {
    var section: AppSection = .today
    var showOnboarding = false
}

/// Owns the status item, its popover and the main window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    let store = AppStore()
    let navigation = Navigation()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        GBFont.register()
        if let dir = ProcessInfo.processInfo.environment["REGNSKAP_SCREENSHOTS"] {
            Task { await Screenshots.capture(to: dir, store: store); NSApp.terminate(nil) }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        store.start()
        store.updateBadge = { [weak self] in self?.updateBadge() }
        setUpStatusItem()
        setUpPopover()
        Reminder.shared.requestAuthorization()
        Reminder.shared.onOpen = { [weak self] in self?.showMainWindow(section: .today) }
        Reminder.shared.onOpenUpdate = { [weak self] in self?.showMainWindow(section: .settings) }
        store.startUpdateLoop()
        // A menu-bar app is rarely "activated": the day must also roll over at midnight and when the popover opens.
        for name in [NSApplication.didBecomeActiveNotification, .NSCalendarDayChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.reloadIfNewDayOrChanged() }
            }
        }
        updateBadge()
        if !store.settings.onboardingDone {
            navigation.showOnboarding = true
            showMainWindow(section: .today)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: "Regnskapsskolen")
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func updateBadge() {
        guard let button = statusItem?.button else { return }
        let remaining = store.remainingToday
        button.title = remaining > 0 ? " \(remaining)" : ""
        button.toolTip = remaining > 0 ? "\(remaining) oppgaver igjen i dag" : "Dagens oppgaver er gjort"
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Åpne Regnskapsskolen", action: #selector(openMain), keyEquivalent: "")
            menu.addItem(withTitle: "Innstillinger…", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Avslutt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            for item in menu.items { item.target = item.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func openMain() { showMainWindow() }

    /// After an update is installed: close the popover, start the new bundle once this process has quit.
    func relaunch() {
        popover?.performClose(nil)
        AppUpdater.relaunch(Bundle.main.bundlePath)
    }
    @objc private func openSettings() { showMainWindow(section: .settings) }

    private func setUpPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 360)
        popover.contentViewController = NSHostingController(rootView: PopoverView().environment(store).environment(navigation))
    }

    func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            store.reloadIfNewDayOrChanged()
            store.checkForUpdateIfStale()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Main window

    func showMainWindow(section: AppSection? = nil) {
        if let section { navigation.section = section }
        popover?.performClose(nil)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Regnskapsskolen"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 820, height: 560)
            w.contentViewController = NSHostingController(rootView: MainView().environment(store).environment(navigation))
            w.setFrameAutosaveName("main")
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
