import SwiftUI
import AppKit

@main
struct TaskSchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var calendarService = CalendarService()
    @StateObject private var schedulingEngine = SchedulingEngine()
    @StateObject private var updateService = UpdateService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarService)
                .environmentObject(schedulingEngine)
                .environmentObject(updateService)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    updateService.startAutomaticChecks()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updateService.userInitiatedCheck()
                }
                .disabled(updateService.isChecking)
            }
            CommandGroup(replacing: .help) {
                Button("Task Scheduler Readme") {
                    openProjectReadme()
                }
                .keyboardShortcut("?", modifiers: .command)
                
                Divider()
                
                Button("Welcome Guide...") {
                    NotificationCenter.default.post(name: Notification.Name("ShowWelcomeScreen"), object: nil)
                }
                
                Button("Patterns Strategy...") {
                    NotificationCenter.default.post(name: Notification.Name("ShowPatternsGuide"), object: nil)
                }
                
                Button("Organizing Tasks...") {
                    NotificationCenter.default.post(name: Notification.Name("ShowTasksGuide"), object: nil)
                }

                Divider()

                Button("What's New...") {
                    NotificationCenter.default.post(name: Notification.Name("ShowWhatsNew"), object: nil)
                }

                Button("Star on GitHub") {
                    openGitHubRepo()
                }
            }
        }
        
        Settings {
            AppSettingsView()
                .environmentObject(calendarService)
                .environmentObject(schedulingEngine)
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

private extension TaskSchedulerApp {
    func openProjectReadme() {
        guard let url = URL(string: "https://github.com/kibermaks/TaskScheduler#readme") else { return }
        NSWorkspace.shared.open(url)
    }

    func openGitHubRepo() {
        guard let url = URL(string: "https://github.com/kibermaks/TaskScheduler") else { return }
        NSWorkspace.shared.open(url)
    }
}
