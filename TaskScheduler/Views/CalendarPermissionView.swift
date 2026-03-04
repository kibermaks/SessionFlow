import SwiftUI

struct CalendarPermissionView: View {
    @EnvironmentObject var calendarService: CalendarService
    @State private var isRequesting = false
    
    private var wasExplicitlyDenied: Bool {
        calendarService.authorizationStatus == .denied
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "0F172A"), Color(hex: "1E293B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Main content container with frosted glass effect
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: wasExplicitlyDenied ? "lock.shield.fill" : "calendar.badge.exclamationmark")
                    .font(.system(size: 80))
                    .foregroundColor(Color(hex: "EF4444"))
                    .symbolEffect(.bounce, value: isRequesting)
                
                VStack(spacing: 16) {
                    Text(wasExplicitlyDenied ? "Permission Denied" : "Calendar Access Required")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(wasExplicitlyDenied 
                         ? "You previously denied calendar access. To use Task Scheduler, please enable it in System Settings."
                         : "Task Scheduler needs access to your calendar to schedule sessions and detect busy time slots.")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Privacy badges
                    HStack(spacing: 12) {
                        privacyBadge(icon: "shield.checkered", text: "Privacy in Core")
                        privacyBadge(icon: "lock.icloud.fill", text: "Local Only")
                        privacyBadge(icon: "hand.raised.fill", text: "You're in Control")
                    }
                    .padding(.top, 8)
                }
                
                // Privacy note
                if !wasExplicitlyDenied {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "10B981"))
                        
                        Text("The app only modifies your calendar when you explicitly schedule sessions or drag events. You're always in control.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "10B981").opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: "10B981").opacity(0.3), lineWidth: 1.5)
                            )
                    )
                    .padding(.horizontal, 40)
                }
                
                // Show different content based on permission status
                if wasExplicitlyDenied {
                    // Instructions for manually enabling permissions
                    VStack(alignment: .leading, spacing: 16) {
                        manualPermissionStep(
                            icon: "1.circle.fill",
                            title: "Open System Settings",
                            description: "Click the button below to open System Settings"
                        )
                        manualPermissionStep(
                            icon: "2.circle.fill",
                            title: "Navigate to Privacy & Security",
                            description: "Go to Privacy & Security → Calendars"
                        )
                        manualPermissionStep(
                            icon: "3.circle.fill",
                            title: "Enable Task Scheduler",
                            description: "Toggle on Task Scheduler in the list"
                        )
                        manualPermissionStep(
                            icon: "4.circle.fill",
                            title: "Return to App",
                            description: "Come back here and the app will continue"
                        )
                    }
                    .padding(.horizontal, 40)
                } else {
                    // Normal permission steps
                    VStack(alignment: .leading, spacing: 16) {
                        permissionStep(
                            icon: "1.circle.fill",
                            title: "Grant Access",
                            description: "Click the button below to authorize calendar access"
                        )
                        permissionStep(
                            icon: "2.circle.fill",
                            title: "Configure Calendars",
                            description: "Select which calendars to use for different session types"
                        )
                        permissionStep(
                            icon: "3.circle.fill",
                            title: "Start Scheduling",
                            description: "Begin optimizing your day with smart session planning"
                        )
                    }
                    .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Action button
                if wasExplicitlyDenied {
                    Button {
                        openSystemSettings()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape.fill")
                            Text("Open System Settings")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 280)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "8B5CF6"))
                                .shadow(color: Color(hex: "8B5CF6").opacity(0.4), radius: 10, y: 5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                } else {
                    Button {
                        requestPermission()
                    } label: {
                        HStack(spacing: 12) {
                            if isRequesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isRequesting ? "Requesting Access..." : "Grant Calendar Access")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 280)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "EF4444"))
                                .shadow(color: Color(hex: "EF4444").opacity(0.4), radius: 10, y: 5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRequesting)
                    .padding(.bottom, 40)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "1E293B").opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(40)
            .frame(width: 600, height: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func privacyBadge(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "10B981"))
            
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "10B981").opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func permissionStep(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "8B5CF6"))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func manualPermissionStep(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "F59E0B"))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func requestPermission() {
        isRequesting = true
        Task {
            let granted = await calendarService.requestAccess()
            await MainActor.run {
                isRequesting = false
                if granted {
                    // Permission granted, the app will automatically transition to setup
                }
            }
        }
    }
    
    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    CalendarPermissionView()
        .environmentObject(CalendarService())
}
