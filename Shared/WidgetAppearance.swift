import SwiftUI

/// How a layout's widget looks: its background, and whether tiles draw in
/// light or dark colors whatever the phone is set to.
enum WidgetAppearance: String, Codable, CaseIterable, Identifiable {
    /// Follows the phone's light and dark setting.
    case system
    case light
    case dark
    case black
    /// No background, so the Home Screen wallpaper shows through.
    case transparent
    case sky
    case ember

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .black: return "Black"
        case .transparent: return "Transparent"
        case .sky: return "Sky"
        case .ember: return "Ember"
        }
    }

    /// The scheme tiles draw in. Nil follows the phone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system, .transparent: return nil
        case .light: return .light
        case .dark, .black, .sky, .ember: return .dark
        }
    }

    /// The widget's container background.
    @ViewBuilder
    var background: some View {
        switch self {
        case .system:
            Rectangle().fill(.background)
        case .light:
            Color.white
        case .dark:
            Color(red: 0.11, green: 0.11, blue: 0.12)
        case .black:
            Color.black
        case .transparent:
            Color.clear
        case .sky:
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.17, blue: 0.40), Color(red: 0.10, green: 0.42, blue: 0.58)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .ember:
            LinearGradient(
                colors: [Color(red: 0.40, green: 0.08, blue: 0.14), Color(red: 0.70, green: 0.27, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// The background for in-app previews. A transparent widget sits on a
    /// stand-in wallpaper, otherwise nothing would show where it ends.
    @ViewBuilder
    var previewBackground: some View {
        switch self {
        case .system:
            Color(.systemBackground)
        case .transparent:
            LinearGradient(
                colors: [Color.indigo.opacity(0.5), Color.teal.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            background
        }
    }
}

private struct WidgetAppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemScheme
    let appearance: WidgetAppearance

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, appearance.colorScheme ?? systemScheme)
    }
}

extension View {
    /// Draws the content in the colors of a widget appearance.
    func widgetAppearance(_ appearance: WidgetAppearance) -> some View {
        modifier(WidgetAppearanceModifier(appearance: appearance))
    }
}
