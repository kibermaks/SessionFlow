# SessionFlow

macOS productivity app (SwiftUI, macOS 14.0+) for scheduling focus sessions around calendar events.

## Build & Run

```bash
./build_app.sh           # Set marketing version to today's date, bump build number
./build_app.sh current   # Keep current marketing version, bump build number
./create_dmg.sh          # Create DMG for distribution
./notarize.sh            # Notarize for distribution
```

No test targets — verify changes by building and running the app.

**After any code changes**: always finish by running `./build_app.sh` so the user gets a ready-to-test build immediately. Skip only for text-only changes (docs, CHANGELOG, CLAUDE.md, etc.).

## Architecture

MVVM-like: Models → Services → Views. No external dependencies — only Apple frameworks (EventKit, SwiftUI, AppKit, AVFoundation).

- `SessionFlowApp.swift` — app entry point with AppDelegate
- `ContentView.swift` — central layout; `.onChange` observers call `trigger()` to regenerate schedule
- `SchedulingEngine.swift` — `generateSchedule()` produces `projectedSessions`; main `ObservedObject`, persists via `UserDefaults`
- `CalendarService.swift` — EventKit integration for reading/writing calendar events
- `TimelineView.swift` — interactive timeline with drag/resize for events and projected sessions
- `SettingsPanel.swift` — all scheduling parameter UI
- `EventUndoManager.swift` — undo/redo for calendar events and projected sessions

### Adding Files to Xcode

Creating a `.swift` file on disk is NOT enough. You must also register it in `project.pbxproj`: `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase`.

## Session Types & Hashtags

Sessions are identified by hashtags in calendar event notes: `#work`, `#side`, `#deep`, `#plan`. Existing-session awareness depends on these tags.

| Type | Purpose |
|------|---------|
| Work | Primary focus tasks |
| Side | Life admin (emails, errands) |
| Deep | Rare, high-intensity focus blocks |
| Planning | Short strategy block at start of day |

## Visual Conventions

- **Solid** borders = real calendar events; **dashed** borders = projected/preview sessions
- Use `NumericInputField` for numeric settings (supports keyboard typing + stepper)

## Adding New Config Properties

When adding a property to any config model (`DeepSessionConfig`, `Preset`, etc.):
1. Add the property with `Codable` support (`decodeIfPresent` for backwards compat)
2. Add UI binding in `SettingsPanel`
3. **Add `.onChange(of: engine.<path>.newProperty) { _, _ in trigger() }` in ContentView's observer groups** — otherwise the timeline won't refresh
4. Use the property in `SchedulingEngine.generateSchedule()`

Observer groups live in `ContentView.swift` → `SettingsChangeModifier` → `extraObservers1` / `extraObservers2`. The modifier also has `@EnvironmentObject var calendarService` and `@Binding var selectedDate`.

## Visibility vs Scheduling (Separate Concerns)

- `dayEndHour` (13...24) = timeline visibility only, gated by `hideNightHours`
- `scheduleEndHour` (13...30) = when scheduling engine stops, always independent
- `visibleHours` uses `effectiveEndHour = max(dayEndHour, scheduleEndHour)`
- `CalendarService` has its own `scheduleEndHour` synced from ContentView

## Release Process

1. Update `CHANGELOG.md` → `./build_app.sh` → `./create_dmg.sh` → ZIP
2. `git commit` + tag + push → `gh release create` with DMG + ZIP

CHANGELOG guidelines:
- Order bullets by importance (most significant first)
- Don't list sub-features when the parent feature is new in the same version
- Keep entries concise — no implementation details for new features
