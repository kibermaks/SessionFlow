import SwiftUI
import AppKit

// MARK: - Global Focus Ring Suppression

/// Suppresses default focus rings app-wide by overriding NSView's focusRingType.
/// This prevents the system blue ring on all controls (text fields, buttons, etc.).
class FocusRingController {
    static let shared = FocusRingController()
    private static var swizzled = false

    func install() {
        guard !Self.swizzled else { return }
        Self.swizzled = true

        // Swizzle NSView.focusRingType getter to return .none globally
        let original = class_getInstanceMethod(NSView.self, #selector(getter: NSView.focusRingType))!
        let replacement = class_getInstanceMethod(FocusRingController.self, #selector(FocusRingController.noFocusRingType))!
        method_setImplementation(original, method_getImplementation(replacement))
    }

    @objc private func noFocusRingType() -> UInt {
        return NSFocusRingType.none.rawValue
    }
}

@main
struct SessionFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var calendarService = CalendarService()
    @StateObject private var schedulingEngine = SchedulingEngine()
    @StateObject private var updateService = UpdateService()
    @StateObject private var sessionAwarenessService = SessionAwarenessService()
    @StateObject private var sessionAudioService = SessionAudioService()
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var miniPlayerController = MiniPlayerWindowController()
    private let dockProgressController = DockProgressController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(calendarService)
                .environmentObject(schedulingEngine)
                .environmentObject(updateService)
                .environmentObject(sessionAwarenessService)
                .environmentObject(sessionAudioService)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    updateService.startAutomaticChecks()
                    sessionAwarenessService.start(calendarService: calendarService, audioService: sessionAudioService)
                    SessionFlowAppState.awarenessService = sessionAwarenessService
                    SessionFlowAppState.calendarService = calendarService
                    menuBarController.setup(awarenessService: sessionAwarenessService)
                    miniPlayerController.setup(awarenessService: sessionAwarenessService, audioService: sessionAudioService)
                    dockProgressController.setup(awarenessService: sessionAwarenessService)

                    // Persist main window frame across launches
                    if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                        mainWindow.setFrameAutosaveName("SessionFlowMainWindow")
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About SessionFlow") {
                    openWindow(id: "about")
                }
                Button("Check for Updates...") {
                    updateService.userInitiatedCheck()
                }
                .disabled(updateService.isChecking)
            }
            CommandGroup(replacing: .help) {
                Button("SessionFlow Readme") {
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

                Button("Session Awareness...") {
                    NotificationCenter.default.post(name: Notification.Name("ShowSessionAwarenessGuide"), object: nil)
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
        
        Window("About SessionFlow", id: "about") {
            AboutView()
        }
        .defaultSize(width: 320, height: 420)

        Settings {
            AppSettingsView()
                .environmentObject(calendarService)
                .environmentObject(schedulingEngine)
                .environmentObject(sessionAwarenessService)
                .environmentObject(sessionAudioService)
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            // Another instance is already running — activate it and quit this one
            if let other = running.first(where: { $0 != NSRunningApplication.current }) {
                other.activate()
            }
            NSApp.terminate(nil)
        }

        FocusRingController.shared.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when main window is hidden for mini-player
        let hasVisiblePanel = NSApp.windows.contains { $0 is NSPanel && $0.isVisible }
        return !hasVisiblePanel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let hasVisiblePanel = NSApp.windows.contains { $0 is NSPanel && $0.isVisible }
        let hasVisibleMainWindow = NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible }

        if hasVisiblePanel && !hasVisibleMainWindow {
            // Mini-player is active, main window is hidden — flash the panel instead
            if let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) {
                flashWindow(panel)
            }
            return false // Don't open main window
        }
        return true
    }

    private func flashWindow(_ window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let flash = NSView(frame: contentView.bounds)
        flash.wantsLayer = true
        flash.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
        flash.layer?.cornerRadius = 10
        flash.alphaValue = 0
        contentView.addSubview(flash)
        flash.autoresizingMask = [.width, .height]

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            flash.animator().alphaValue = 1
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                flash.animator().alphaValue = 0
            }, completionHandler: {
                // Second flash
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    flash.animator().alphaValue = 1
                }, completionHandler: {
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.3
                        flash.animator().alphaValue = 0
                    }, completionHandler: {
                        flash.removeFromSuperview()
                    })
                })
            })
        })
    }
}

private extension SessionFlowApp {
    func openProjectReadme() {
        guard let url = URL(string: "https://github.com/kibermaks/SessionFlow#readme") else { return }
        NSWorkspace.shared.open(url)
    }

    func openGitHubRepo() {
        guard let url = URL(string: "https://github.com/kibermaks/SessionFlow") else { return }
        NSWorkspace.shared.open(url)
    }
}
