import SwiftUI

@main
struct RegnskapsskolenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The status item and the main window are AppKit-managed; this scene gives ⌘, a home.
        Settings {
            SettingsView()
                .rootTheme()
                .environment(delegate.store)
                .environment(delegate.navigation)
                .frame(width: 640, height: 560)
        }
    }
}
