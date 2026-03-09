import SwiftUI

struct UpdateAlertSheet: View {
    let alert: UpdateService.UpdateAlert
    @EnvironmentObject var updateService: UpdateService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch alert.kind {
            case .updateAvailable(let info):
                updateAvailableContent(info)
            case .upToDate(let version):
                simpleContent(
                    icon: "checkmark.circle.fill",
                    iconColor: Color(hex: "34D399"),
                    title: "You're Up to Date",
                    message: "You're already running version \(version)."
                )
            case .failure(let message):
                simpleContent(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: Color(hex: "FBBF24"),
                    title: "Update Check Failed",
                    message: message
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Update Available

    private func updateAvailableContent(_ info: UpdateService.UpdateInfo) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Button {
                    updateService.dismissAlert()
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
            .padding(.horizontal, 24)
            .padding(.top, 16)

            VStack(spacing: 16) {
                // Icon & title
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "60A5FA"), Color(hex: "818CF8")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 6) {
                    Text("Update Available")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("SessionFlow \(info.version) is ready to install.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.bottom, 16)

            // Release notes
            if !info.releaseNotes.isEmpty {
                releaseNotesView(info.releaseNotes)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }

            // Buttons
            HStack(spacing: 12) {
                Button("Later") {
                    updateService.dismissAlert()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Button("Install Update") {
                    updateService.installLatestUpdate(info)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480)
    }

    private func releaseNotesView(_ notes: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(parseNoteLines(notes), id: \.self) { line in
                    if line.hasPrefix("### ") {
                        Text(String(line.dropFirst(4)))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "60A5FA"))
                            .padding(.top, 6)
                    } else if line.hasPrefix("- ") {
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.3))
                            Text(String(line.dropFirst(2)))
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func parseNoteLines(_ notes: String) -> [String] {
        notes.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Simple Content (Up to Date / Failure)

    private func simpleContent(icon: String, iconColor: Color, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(iconColor)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            Button("OK") {
                updateService.dismissAlert()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 420)
    }
}

// MARK: - Button Styles

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "3B82F6"))
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}
