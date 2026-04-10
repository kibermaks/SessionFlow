# Agent Knowledge Base

Supplementary domain knowledge for SessionFlow. For build commands, architecture, and workflows, see [CLAUDE.md](CLAUDE.md).

## State Architecture

- `SchedulingEngine` is the main `ObservedObject` — all scheduling config lives here, persisted via `UserDefaults`.
- `CalendarService` owns all `EventKit` interactions (read/write/permissions).
- `ContentView` delegates its body to `ContentViewBody` to manage complex layout states and bindings.
- Settings changes flow through `.onChange` observers → `trigger()` → `generateSchedule()` → `projectedSessions` update.

## Adding a Feature

1. Create the `.swift` file and register it in `project.pbxproj` (see CLAUDE.md → "Adding Files to Xcode").
2. If it has settings, add properties to `SchedulingEngine` and bind in `SettingsPanel`.
3. If it has a tooltip/help, add an `(i)` popover button in `SettingsPanel`.
4. If it affects scheduling, wire `.onChange` observers in `ContentView` (see CLAUDE.md → "Adding New Config Properties").
