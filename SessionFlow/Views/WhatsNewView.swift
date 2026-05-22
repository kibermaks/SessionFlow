import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    @ObservedObject var changelog: ChangelogService

    private var displayEntries: [ChangelogEntry] {
        changelog.entries
    }

    var body: some View {
        ZStack {
            colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .frame(width: 520, height: 560)
        .onAppear { changelog.fetchIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's New")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(colors.textPrimary)
                Text("SessionFlow v\(ChangelogService.currentVersion)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(colors.textMuted)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colors.textMuted)
                    .padding(8)
                    .background(Circle().fill(colors.subtleBackground))
            }
            .buttonStyle(.plain)
            .hoverEffect(brightness: 0.2)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if changelog.isLoading && displayEntries.isEmpty {
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                Text("Loading changelog…")
                    .font(.caption)
                    .foregroundColor(colors.textMuted)
                Spacer()
            } else if displayEntries.isEmpty {
                Spacer()
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundColor(colors.textDisabled)
                Text("No changelog available")
                    .font(.subheadline)
                    .foregroundColor(colors.textMuted)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(displayEntries) { entry in
                            versionBlock(entry)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    // MARK: - Version Block

    private func versionBlock(_ entry: ChangelogEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("v\(entry.version)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(colors.textPrimary)
                Text(entry.date)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(colors.textMuted)
            }

            ForEach(entry.sections) { section in
                sectionBlock(section)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colors.subtleBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(colors.divider, lineWidth: 1)
                )
        )
    }

    private func sectionBlock(_ section: ChangelogEntry.Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconForCategory(section.category))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorForCategory(section.category))
                Text(section.category)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(colorForCategory(section.category))
            }

            ForEach(section.items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundColor(colors.textMuted)
                        .padding(.top, 1)
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Category Styling

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "added": return "plus.circle.fill"
        case "changed": return "arrow.triangle.2.circlepath"
        case "fixed": return "wrench.and.screwdriver.fill"
        case "removed": return "minus.circle.fill"
        case "deprecated": return "exclamationmark.triangle.fill"
        case "security": return "lock.shield.fill"
        default: return "circle.fill"
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        if colors.isDark {
            switch category.lowercased() {
            case "added":      return Color(hex: "34D399")
            case "changed":    return Color(hex: "60A5FA")
            case "fixed":      return Color(hex: "FBBF24")
            case "removed":    return Color(hex: "F87171")
            case "deprecated": return Color(hex: "FB923C")
            case "security":   return Color(hex: "A78BFA")
            default: return Color.secondary
            }
        } else {
            switch category.lowercased() {
            case "added":      return Color(hex: "059669")
            case "changed":    return Color(hex: "2563EB")
            case "fixed":      return Color(hex: "D97706")
            case "removed":    return Color(hex: "DC2626")
            case "deprecated": return Color(hex: "EA580C")
            case "security":   return Color(hex: "7C3AED")
            default: return Color.secondary
            }
        }
    }
}
