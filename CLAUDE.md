# SessionFlow

SessionFlow is a macOS-only productivity app (SwiftUI, macOS 14.0+) for scheduling focus sessions around calendar events.

## Build & Run

```bash
./build_app.sh           # Set marketing version to today's date, bump build number, build Debug app
./build_app.sh current   # Keep current marketing version, bump build number, build Debug app
./build_app.sh --release # Build Release app into ./release/
./create_dmg.sh          # Create DMG for distribution
./notarize.sh            # Notarize for distribution
```

The `SessionFlowTests` target (Swift Testing) covers the MCP layer: `xcodebuild test -scheme SessionFlow -destination 'platform=macOS'`. The rest of the app has no tests — verify by building and running.

**After any code changes**: always finish by running `./build_app.sh` so the user gets a ready-to-test build immediately. Skip only for text-only changes (docs, CHANGELOG, CLAUDE.md, etc.).

### Build/Test Locking

Before starting any direct build or test command (`xcodebuild test`, `xcodebuild build`, `./create_dmg.sh`, or similar), use `.agent-build.lock` in the repo root as a repository-wide build mutex. Other chats/threads may be building the same macOS app and can conflict over DerivedData, build numbers, or copied app bundles.

- `./build_app.sh` creates, waits on, and removes `.agent-build.lock` automatically. Run it directly instead of wrapping it in a second lock.
- If `.agent-build.lock` exists and its PID is still running, wait/poll until the lock vanishes. Do not start a second build/test in parallel.
- If the lock is stale because the PID is gone, remove it and take a fresh lock.
- Create the lock atomically before building, including PID, timestamp, command, and agent/session note.
- Always remove your lock when the command finishes; use a shell `trap` where possible.
- Do not use this lock for quick read-only commands such as `rg`, `sed`, `git status`, or file inspection.

## Architecture

MVVM-like: Models → Services → Views. Apple frameworks (EventKit, SwiftUI, AppKit, AVFoundation) plus one external dependency: the official MCP Swift SDK (`modelcontextprotocol/swift-sdk`, product `MCP`) for the AI-control feature.

- `SessionFlowApp.swift` — app entry point with AppDelegate
- `ContentView.swift` — central layout; `.onChange` observers call `trigger()` to regenerate schedule
- `SchedulingEngine.swift` — `generateSchedule()` produces `projectedSessions`; main `ObservedObject`, persists via `UserDefaults`
- `CalendarService.swift` — EventKit integration for reading/writing calendar events
- `TimelineView.swift` — interactive timeline with drag/resize for events and projected sessions
- `SettingsPanel.swift` — all scheduling parameter UI
- `EventUndoManager.swift` — undo/redo for calendar events and projected sessions

### Adding Files to Xcode

Creating a `.swift` file on disk is NOT enough. You must also register it in `project.pbxproj`: `PBXBuildFile`, `PBXFileReference`, `PBXGroup`, and `PBXSourcesBuildPhase`.

## AI Control (MCP server)

`SessionFlow/Services/MCP/` embeds a local MCP server so an AI agent can read and control the app in natural language. Off by default; toggle in Settings → General → "AI Control (MCP)".

- `MCPServerController` — owns the SDK `Server` + handlers; `start(port:token:)`/`stop()`. Created as a `@StateObject` in `SessionFlowApp` and started on launch when `MCPSettings.enabled`.
- `MCPHTTPListener` — loopback `NWListener` that adapts raw HTTP to the SDK's `StatelessHTTPServerTransport` (the SDK owns JSON-RPC routing/validation). `SharedSecretBearerValidator` enforces the bearer token.
- `MCPTools` — tool catalog + dispatch (read: `get_config`/`get_state`/`list_presets`/`get_day`; control: `set_tasks`/`set_config`/`apply_preset`/`save_preset`/`regenerate_schedule`/`commit_schedule`/`move_session`/`resize_session`/`delete_sessions`/`set_freeze`; plus `learn`).
- `ScheduleCoordinator` — regenerate/commit/delete logic mirroring ContentView, behind the `CalendarWriting` seam so tests use a fake (never the real calendar).
- `Resources/MCP/AgentGuide.md` — the capability guide served by `learn` and the `sessionflow://guide` resource. **Adding a tool requires updating this guide** (a test enforces every tool name appears).

Connect (server enabled, token from Settings): Claude Code `claude mcp add --transport http sessionflow http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"`; Claude Desktop via `npx mcp-remote http://127.0.0.1:<port>/mcp --header "Authorization:Bearer <token>"`. After connecting, call `learn` first or read `sessionflow://guide`.

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
