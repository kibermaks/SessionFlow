import AppIntents
import Foundation

// MARK: - Shared accessor for AppIntents

/// Provides AppIntents access to the running SessionAwarenessService.
/// Set from SessionFlowApp.onAppear so intents can query live session state.
enum SessionFlowAppState {
    static weak var awarenessService: SessionAwarenessService?
    static weak var calendarService: CalendarService?
}

// MARK: - Get Current Session

struct GetCurrentSession: AppIntent {
    static var title: LocalizedStringResource = "Get Current Session"
    static var description: IntentDescription = "Returns information about the currently active session in SessionFlow."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let service = SessionFlowAppState.awarenessService else {
            return .result(value: "SessionFlow is not running.")
        }

        guard service.isActive else {
            return .result(value: "No active session.")
        }

        let title = service.currentSessionTitle
        let typeName = service.currentSessionType?.rawValue ?? "External"
        let remaining = Int(service.remaining / 60)
        let elapsed = Int(service.elapsed / 60)

        return .result(value: "\(typeName): \(title) — \(elapsed) min elapsed, \(remaining) min remaining")
    }
}

// MARK: - Get Next Session

struct GetNextSession: AppIntent {
    static var title: LocalizedStringResource = "Get Next Session"
    static var description: IntentDescription = "Returns information about the next upcoming session in SessionFlow."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let service = SessionFlowAppState.awarenessService else {
            return .result(value: "SessionFlow is not running.")
        }

        guard let title = service.nextSessionTitle,
              let startTime = service.nextSessionStartTime else {
            return .result(value: "No upcoming sessions.")
        }

        let typeName = service.nextSessionType?.rawValue ?? "External"
        let minutesUntil = Int(startTime.timeIntervalSinceNow / 60)

        if minutesUntil <= 0 {
            return .result(value: "\(typeName): \(title) — starting now")
        }
        return .result(value: "\(typeName): \(title) — in \(minutesUntil) min")
    }
}

// MARK: - Get Today's Focus Time

struct GetTodaysFocusTime: AppIntent {
    static var title: LocalizedStringResource = "Get Today's Focus Time"
    static var description: IntentDescription = "Returns today's total focus time from rated sessions in SessionFlow."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let calendarService = SessionFlowAppState.calendarService,
              let awarenessService = SessionFlowAppState.awarenessService else {
            return .result(value: "SessionFlow is not running.")
        }

        let stats = calendarService.todayFeedbackStats(
            weights: awarenessService.config.focusWeights
        )

        let hours = Int(stats.focusMinutes) / 60
        let minutes = Int(stats.focusMinutes) % 60

        if hours > 0 {
            return .result(value: "\(hours)h \(minutes)m focus time today (\(stats.totalEvents) sessions rated)")
        }
        return .result(value: "\(minutes)m focus time today (\(stats.totalEvents) sessions rated)")
    }
}

// MARK: - Is Session Active

struct IsSessionActive: AppIntent {
    static var title: LocalizedStringResource = "Is Session Active"
    static var description: IntentDescription = "Returns whether a session is currently active in SessionFlow."
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard let service = SessionFlowAppState.awarenessService else {
            return .result(value: false)
        }
        return .result(value: service.isActive)
    }
}

// MARK: - App Shortcuts Provider

struct SessionFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetCurrentSession(),
            phrases: [
                "What session is active in \(.applicationName)?",
                "Current session in \(.applicationName)"
            ],
            shortTitle: "Current Session",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: GetNextSession(),
            phrases: [
                "When is my next session in \(.applicationName)?",
                "Next session in \(.applicationName)"
            ],
            shortTitle: "Next Session",
            systemImageName: "forward.circle.fill"
        )
        AppShortcut(
            intent: GetTodaysFocusTime(),
            phrases: [
                "How much focus time today in \(.applicationName)?",
                "Focus time in \(.applicationName)"
            ],
            shortTitle: "Today's Focus Time",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: IsSessionActive(),
            phrases: [
                "Is a session active in \(.applicationName)?",
                "Am I in a session in \(.applicationName)?"
            ],
            shortTitle: "Session Active?",
            systemImageName: "questionmark.circle.fill"
        )
    }
}
