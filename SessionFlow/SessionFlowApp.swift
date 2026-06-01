import SwiftUI
import AppKit

enum SessionFlowWindowIdentity {
    static let mainWindowSceneID = "main"
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("SessionFlow.mainWindow")

    static func mainWindow(preferVisible: Bool = false) -> NSWindow? {
        if preferVisible,
           let keyWindow = NSApp.keyWindow,
           keyWindow.isVisible,
           isMainWindowCandidate(keyWindow) {
            return keyWindow
        }

        let candidates = NSApp.windows.filter(isMainWindowCandidate)
        if let configured = candidates.first(where: { $0.identifier == mainWindowIdentifier }) {
            return configured
        }
        if preferVisible, let visible = candidates.first(where: \.isVisible) {
            return visible
        }
        return candidates.first
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier == mainWindowIdentifier || isMainWindowCandidate(window)
    }

    private static func isMainWindowCandidate(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel),
              !window.isMiniaturized,
              window.contentView != nil,
              window.frame.width >= 900,
              window.frame.height >= 600
        else { return false }

        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty || title == "SessionFlow"
    }
}

extension ProcessInfo {
    /// True when the process is hosting a unit-test bundle, so app side effects
    /// (single-instance termination, calendar prompts, background services) can be skipped.
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}

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
    @StateObject private var recentEventsStore = RecentEventsStore()
    @StateObject private var eventCreationCoordinator = EventCreationCoordinator()
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var miniPlayerController = MiniPlayerWindowController()
    @StateObject private var mcpServerController = MCPServerController()
    @State private var didInitializeServices = false
    private let dockProgressController = DockProgressController()
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    private var preferredScheme: ColorScheme? {
        AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme
    }

    var body: some Scene {
        WindowGroup("SessionFlow", id: SessionFlowWindowIdentity.mainWindowSceneID) {
            if ProcessInfo.processInfo.isRunningTests {
                EmptyView()
            } else {
                ContentView()
                    .environmentObject(calendarService)
                    .environmentObject(schedulingEngine)
                    .environmentObject(updateService)
                    .environmentObject(sessionAwarenessService)
                    .environmentObject(sessionAwarenessService.timeState)
                    .environmentObject(sessionAudioService)
                    .environmentObject(recentEventsStore)
                    .environmentObject(eventCreationCoordinator)
                    .frame(minWidth: 1100, minHeight: 700)
                    .preferredColorScheme(preferredScheme)
                    .focusEffectDisabled()
                    .onAppear { applyAppearance(appearanceModeRaw) }
                    .onChange(of: appearanceModeRaw) { _, new in applyAppearance(new) }
                    .onAppear {
                        guard !didInitializeServices else { return }
                        didInitializeServices = true
                        updateService.startAutomaticChecks()
                        sessionAwarenessService.start(calendarService: calendarService, audioService: sessionAudioService)
                        SessionFlowAppState.awarenessService = sessionAwarenessService
                        SessionFlowAppState.calendarService = calendarService
                        mcpServerController.configure(engine: schedulingEngine, calendar: calendarService)
                        if MCPSettings.enabled {
                            Task { await mcpServerController.start(port: MCPSettings.port, token: MCPSettings.token) }
                        }
                        menuBarController.setup(
                            awarenessService: sessionAwarenessService,
                            openMainWindow: {
                                openWindow(id: SessionFlowWindowIdentity.mainWindowSceneID)
                            }
                        )
                        miniPlayerController.setup(awarenessService: sessionAwarenessService, audioService: sessionAudioService)
                        dockProgressController.setup(awarenessService: sessionAwarenessService)

                        if let mainWindow = SessionFlowWindowIdentity.mainWindow(preferVisible: true) {
                            appDelegate.configureMainWindow(mainWindow)
                        }
                        appDelegate.awarenessService = sessionAwarenessService
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

                Button("Shortcuts...") {
                    NotificationCenter.default.post(name: Notification.Name("ShowShortcutsGuide"), object: nil)
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
                .preferredColorScheme(preferredScheme)
        }
        .defaultSize(width: 320, height: 420)

        Settings {
            AppSettingsView()
                .environmentObject(calendarService)
                .environmentObject(schedulingEngine)
                .environmentObject(sessionAwarenessService)
                .environmentObject(sessionAudioService)
                .environmentObject(mcpServerController)
                .preferredColorScheme(preferredScheme)
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var monitoredMainWindow: NSWindow?
    private var titlebarDoubleClickMonitor: Any?
    private var windowActivationObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under unit tests the app is only a test host — skip single-instance
        // enforcement (which would terminate a running real instance) and setup.
        guard !ProcessInfo.processInfo.isRunningTests else { return }

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
        windowActivationObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let window = notification.object as? NSWindow,
                  self.isConfiguredMainWindow(window)
            else { return }

            self.configureMainWindow(window)
        }
    }
    weak var awarenessService: SessionAwarenessService?

    func configureMainWindow(_ window: NSWindow) {
        window.identifier = SessionFlowWindowIdentity.mainWindowIdentifier
        window.setFrameAutosaveName("SessionFlowMainWindow")
        installTitlebarDoubleClickMonitor(for: window)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If mini player is active, bring it to front instead of opening the main window
        if awarenessService?.isCollapsed == true,
           let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }) {
            panel.orderFront(nil)
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Behave like a standard Mac app: closing the window keeps the app
        // running. Reopen via the Dock icon; quit via the Dock context menu or
        // the menu bar (Quit / ⌘Q).
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let titlebarDoubleClickMonitor {
            NSEvent.removeMonitor(titlebarDoubleClickMonitor)
            self.titlebarDoubleClickMonitor = nil
        }
        if let windowActivationObserver {
            NotificationCenter.default.removeObserver(windowActivationObserver)
            self.windowActivationObserver = nil
        }
        // Flush pending session/rest shortcuts before quitting
        awarenessService?.flushOnTermination()
    }

    private func installTitlebarDoubleClickMonitor(for window: NSWindow) {
        if monitoredMainWindow === window, titlebarDoubleClickMonitor != nil { return }

        if let titlebarDoubleClickMonitor {
            NSEvent.removeMonitor(titlebarDoubleClickMonitor)
            self.titlebarDoubleClickMonitor = nil
        }

        monitoredMainWindow = window
        titlebarDoubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak window] event in
            guard let self,
                  let window,
                  event.window === window,
                  event.clickCount == 2,
                  self.isClickInNativeTitlebar(event.locationInWindow, of: window),
                  !self.isClickOnStandardWindowButton(event.locationInWindow, of: window)
            else {
                return event
            }

            WindowTitleBarDoubleClick.perform(on: window)
            return nil
        }
    }

    private func isConfiguredMainWindow(_ window: NSWindow) -> Bool {
        SessionFlowWindowIdentity.isMainWindow(window)
    }

    private func isClickInNativeTitlebar(_ location: NSPoint, of window: NSWindow) -> Bool {
        let topY = window.frame.height
        let contentInsetHeight = max(0, topY - (window.contentView?.frame.height ?? topY))
        let titlebarHitHeight = max(contentInsetHeight, 44)

        return location.y >= topY - titlebarHitHeight && location.y <= topY
    }

    private func isClickOnStandardWindowButton(_ location: NSPoint, of window: NSWindow) -> Bool {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        return buttons.contains { buttonType in
            guard let button = window.standardWindowButton(buttonType),
                  let superview = button.superview
            else { return false }

            let point = superview.convert(location, from: nil)
            return button.frame.contains(point)
        }
    }
}

private extension SessionFlowApp {
    func applyAppearance(_ raw: String) {
        let mode = AppearanceMode(rawValue: raw) ?? .system
        switch mode {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func openProjectReadme() {
        guard let url = URL(string: "https://github.com/kibermaks/SessionFlow#readme") else { return }
        NSWorkspace.shared.open(url)
    }

    func openGitHubRepo() {
        guard let url = URL(string: "https://github.com/kibermaks/SessionFlow") else { return }
        NSWorkspace.shared.open(url)
    }
}
