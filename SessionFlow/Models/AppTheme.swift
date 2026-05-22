import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

struct AppColors {
    let isDark: Bool

    // MARK: - Backgrounds
    var windowBackground: Color { isDark ? Color(hex: "0F172A") : Color(hex: "F8FAFC") }
    var panelBackground: Color  { isDark ? Color(hex: "1E293B") : Color.white }
    var cardBackground: Color   { isDark ? Color(hex: "1E293B") : Color(hex: "F1F5F9") }
    var subtleBackground: Color { isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04) }
    var hoveredBackground: Color { isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.07) }

    var backgroundGradient: LinearGradient {
        if isDark {
            return LinearGradient(colors: [Color(hex: "0F172A"), Color(hex: "1E293B")], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            return LinearGradient(colors: [Color(hex: "F0F4FF"), Color(hex: "EFF6FF")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: - Text
    var textPrimary: Color    { isDark ? .white : Color(hex: "0F172A") }
    var textSecondary: Color  { isDark ? Color.white.opacity(0.6)  : Color(hex: "334155") }
    var textMuted: Color      { isDark ? Color.white.opacity(0.35) : Color(hex: "64748B") }
    var textDisabled: Color   { isDark ? Color.white.opacity(0.25) : Color(hex: "94A3B8") }

    // MARK: - Borders / Dividers
    var divider: Color       { isDark ? Color.white.opacity(0.1)  : Color.black.opacity(0.08) }
    var border: Color        { isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.12) }
    var borderStrong: Color  { isDark ? Color.white.opacity(0.25) : Color.black.opacity(0.2)  }

    // MARK: - Overlays / Toasts
    var toastBackground: Color  { isDark ? Color.black.opacity(0.85) : Color(hex: "1E293B").opacity(0.92) }
    var overlayBackground: Color { isDark ? Color.black.opacity(0.2) : Color.black.opacity(0.06) }
    var sheetBackground: Color  { isDark ? Color(hex: "0F172A") : Color(hex: "F8FAFC") }
    var popoverBackground: Color { isDark ? Color(hex: "1E293B") : Color.white }

    // MARK: - Session Colors (same in both themes — good contrast in both)
    var work: Color    { Color(hex: "8B5CF6") }
    var side: Color    { Color(hex: "3B82F6") }
    var deep: Color    { Color(hex: "10B981") }
    var plan: Color    { Color(hex: "EF4444") }
    var rest: Color    { Color(hex: "F59E0B") }
    var bigRest: Color { Color(hex: "F59E0B") }
}
