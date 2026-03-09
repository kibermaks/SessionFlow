import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var changelog: ChangelogService

    private var displayEntries: [ChangelogEntry] {
        changelog.entries
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .frame(width: 520, height: 560)
        .preferredColorScheme(.dark)
        .onAppear { changelog.fetchIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("What's New")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("SessionFlow v\(ChangelogService.currentVersion)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
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
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            } else if displayEntries.isEmpty {
                Spacer()
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.2))
                Text("No changelog available")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.4))
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
                    .foregroundColor(.white)
                Text(entry.date)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }

            ForEach(entry.sections) { section in
                sectionBlock(section)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
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
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 1)
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
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
        switch category.lowercased() {
        case "added": return Color(hex: "34D399")
        case "changed": return Color(hex: "60A5FA")
        case "fixed": return Color(hex: "FBBF24")
        case "removed": return Color(hex: "F87171")
        case "deprecated": return Color(hex: "FB923C")
        case "security": return Color(hex: "A78BFA")
        default: return .white.opacity(0.6)
        }
    }
}
