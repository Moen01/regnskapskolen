import SwiftUI

/// The handheld's few effects: a flash of the screen, a shake, a slide in from the right, and a
/// shrink into nothing. Each fires when its trigger changes.
extension View {
    func gbFlash(trigger: some Equatable) -> some View {
        modifier(GBFlash(trigger: trigger))
    }

    func gbShake(trigger: some Equatable) -> some View {
        modifier(GBShake(trigger: trigger))
    }

    func gbSlideIn(trigger: some Equatable) -> some View {
        modifier(GBSlideIn(trigger: trigger))
    }

    func gbShrink(when shrunk: Bool) -> some View {
        scaleEffect(shrunk ? 0.01 : 1, anchor: .bottom)
            .opacity(shrunk ? 0 : 1)
            .animation(.easeIn(duration: 0.4), value: shrunk)
    }
}

/// Two inversions of the screen over 0.3 s.
private struct GBFlash<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @State private var inverted = false

    func body(content: Content) -> some View {
        content
            .colorInvert(inverted)
            .onChange(of: trigger) {
                Task { @MainActor in
                    for _ in 0..<2 {
                        inverted = true
                        try? await Task.sleep(for: .milliseconds(75))
                        inverted = false
                        try? await Task.sleep(for: .milliseconds(75))
                    }
                }
            }
    }
}

private extension View {
    @ViewBuilder
    func colorInvert(_ on: Bool) -> some View {
        if on { colorInvert() } else { self }
    }
}

/// ± 4 logical px over 0.3 s.
private struct GBShake<Trigger: Equatable>: ViewModifier {
    @Environment(\.gbScale) private var scale
    let trigger: Trigger
    @State private var shift: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: shift * scale)
            .onChange(of: trigger) {
                Task { @MainActor in
                    for step in [4, -4, 3, -3, 2, -2, 0] {
                        shift = CGFloat(step)
                        try? await Task.sleep(for: .milliseconds(43))
                    }
                }
            }
    }
}

/// Slides in from 60 logical px to the right over 0.3 s when the trigger changes, and on appear.
private struct GBSlideIn<Trigger: Equatable>: ViewModifier {
    @Environment(\.gbScale) private var scale
    let trigger: Trigger
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset * scale)
            .onAppear(perform: slide)
            .onChange(of: trigger) { slide() }
    }

    private func slide() {
        guard !AppStore.isScreenshotRun else { return }
        offset = 60
        withAnimation(.easeOut(duration: 0.3)) { offset = 0 }
    }
}
