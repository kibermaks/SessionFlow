import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.colorScheme) var colorScheme
    var colors: AppColors { AppColors(isDark: colorScheme == .dark) }

    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    private let repoURL = "https://github.com/kibermaks/SessionFlow"
    private let starURL = "https://github.com/kibermaks/SessionFlow"
    private let authorURL = "https://github.com/kibermaks"

    private var displayedVersion: String {
        #if DEBUG
        return "Version \(version) (\(build))"
        #else
        return "Version \(version)"
        #endif
    }

    var body: some View {
        VStack(spacing: 20) {
            // App icon
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            // App name
            Text("SessionFlow")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(colors.textPrimary)

            // Tagline
            Text("Smart scheduling for productive days")
                .font(.system(size: 13))
                .foregroundColor(colors.textSecondary)

            // Version
            Text(displayedVersion)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(colors.textMuted)

            Divider()
                .frame(width: 200)

            // Links
            VStack(spacing: 12) {
                linkRow(icon: "star.fill", title: "Star on GitHub", url: starURL)
                linkRow(icon: "arrow.up.forward.square", title: "Project on GitHub", url: repoURL)
                linkRow(icon: "person.circle", title: "Author Profile", url: authorURL)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(minWidth: 320, minHeight: 380)
        .background(colors.windowBackground)
    }

    private func linkRow(icon: String, title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "8B5CF6"))
                    .frame(width: 24, alignment: .center)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colors.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(colors.subtleBackground)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .hoverEffect(brightness: 0.12)
    }
}
