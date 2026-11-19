import SwiftUI

/// The look of the non-game screens. `.standard` reproduces the plain macOS app exactly; `.playful`
/// is Catacloud's warm premium skin. One value lives in the environment; the semantic view modifiers
/// below branch on `isPlayful` so the standard path stays byte-for-byte today's styling.
struct AppTheme: Equatable {
    var isPlayful: Bool
    var screenBackground: Color
    var cardBackground: Color
    var accent: Color
    var primaryText: Color
    var secondaryText: Color
    var success: Color
    var successText: Color
    var danger: Color
    var dangerText: Color
    var warning: Color
    var debet: Color
    var kredit: Color
    var cardCornerRadius: CGFloat
    var headingDesign: Font.Design
    var celebrationsEnabled: Bool

    /// Today's plain app. Colors are the semantic constants from `Theme.swift`; no celebrations.
    static let standard = AppTheme(
        isPlayful: false,
        screenBackground: .clear,
        cardBackground: .clear,
        accent: .skole,
        primaryText: .primary,
        secondaryText: .secondary,
        success: .ok,
        successText: .ok,
        danger: .bad,
        dangerText: .bad,
        warning: .warn,
        debet: .debet,
        kredit: .kredit,
        cardCornerRadius: 10,
        headingDesign: .default,
        celebrationsEnabled: false
    )

    /// Catacloud's warm premium skin, with warm dark variants so dark mode does not fall back to grey.
    static func playful(dark: Bool) -> AppTheme {
        AppTheme(
            isPlayful: true,
            screenBackground: dark ? Color(hex: 0x26241F) : Color(hex: 0xF7F5F2),
            cardBackground: dark ? Color(hex: 0x32302A) : .white,
            accent: dark ? Color(hex: 0x7A8FC4) : Color(hex: 0x4A5E9E),
            primaryText: dark ? Color(hex: 0xF7F5F2) : Color(hex: 0x2C2A26),
            secondaryText: dark ? Color(hex: 0xA8A298) : Color(hex: 0x6B6760),
            success: Color(hex: 0x3CBF9C),
            successText: dark ? Color(hex: 0x3CBF9C) : Color(hex: 0x2A8A70),
            danger: Color(hex: 0xF85C5C),
            dangerText: dark ? Color(hex: 0xF85C5C) : Color(hex: 0xC04848),
            warning: Color(hex: 0xF5B04D),
            debet: dark ? Color(hex: 0x7A8FC4) : Color(hex: 0x4A5E9E),
            kredit: dark ? Color(hex: 0xE09A3C) : Color(hex: 0xC98A2E),
            cardCornerRadius: 20,
            headingDesign: .rounded,
            celebrationsEnabled: true
        )
    }
}

extension Color {
    /// 0xRRGGBB literal, matching the hex values in the Catacloud design tokens.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.standard
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Semantic modifiers

extension View {
    /// The warm screen background behind a whole screen; a no-op in the standard theme.
    func themedScreenBackground() -> some View {
        modifier(ThemedScreenBackground())
    }

    /// A card surface. Standard is today's `.quaternary` material at the given radius; playful is a
    /// white (warm-dark) card with soft double shadow and the theme's larger radius.
    func themedCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(ThemedCard(standardRadius: cornerRadius))
    }

    /// The screen's primary action. Standard tints with `.skole`; playful tints with the warm accent.
    func themedPrimaryButton() -> some View {
        modifier(ThemedPrimaryButton())
    }

    /// A heading's font design. Playful rounds it; standard leaves it unchanged.
    func themedHeading() -> some View {
        modifier(ThemedHeading())
    }

    /// Resolve the theme from the learner's setting and the color scheme, and inject it. Apply at the
    /// root of each window; the store must already be in the environment.
    func rootTheme() -> some View {
        modifier(RootTheme())
    }
}

private struct ThemedScreenBackground: ViewModifier {
    @Environment(\.appTheme) private var theme
    func body(content: Content) -> some View {
        if theme.isPlayful {
            content.background(theme.screenBackground)
        } else {
            content
        }
    }
}

private struct ThemedCard: ViewModifier {
    @Environment(\.appTheme) private var theme
    let standardRadius: CGFloat

    func body(content: Content) -> some View {
        if theme.isPlayful {
            // Keep small chips small; real cards take the theme's 20 pt radius.
            let radius = standardRadius < 10 ? standardRadius : theme.cardCornerRadius
            content
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: radius))
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                .shadow(color: .black.opacity(0.04), radius: 24, y: 6)
        } else {
            content.background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: standardRadius))
        }
    }
}

private struct ThemedPrimaryButton: ViewModifier {
    @Environment(\.appTheme) private var theme
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent).tint(theme.isPlayful ? theme.accent : .skole)
    }
}

private struct ThemedHeading: ViewModifier {
    @Environment(\.appTheme) private var theme
    func body(content: Content) -> some View {
        content.fontDesign(theme.headingDesign)
    }
}

private struct RootTheme: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = store.settings.playfulTheme ? AppTheme.playful(dark: scheme == .dark) : .standard
        content
            .environment(\.appTheme, theme)
            .background(theme.isPlayful ? theme.screenBackground : Color.clear)
    }
}
