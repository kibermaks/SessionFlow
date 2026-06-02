# Agent Knowledge Base

Supplementary domain knowledge for SessionFlow. For build commands, architecture, and workflows, see [CLAUDE.md](CLAUDE.md).

## Build/Test Locking

Before starting any test or build command (`xcodebuild test`, `xcodebuild build`, `./build_app.sh`, `./create_dmg.sh`, or similar), use an improvised repository lock file so parallel agent chats do not fight over DerivedData, build numbers, or copied app bundles.

- Lock path: `.agent-build.lock` in the repo root.
- Create it atomically before the command, including PID, timestamp, command, and agent/session note.
- If the lock already exists, inspect it and check whether the PID is still running. If it is active, wait/poll or tell the user instead of starting another build/test.
- If the lock is stale because the PID is gone, remove it and take a fresh lock.
- Always remove the lock when the build/test command finishes; use a shell `trap` when possible.
- Do not use this lock for quick read-only commands such as `rg`, `sed`, `git status`, or file inspection.

Example:

```sh
lock=.agent-build.lock
if ! ( set -o noclobber; printf 'pid=%s\nstarted=%s\ncmd=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "xcodebuild test ..." > "$lock" ) 2>/dev/null; then
  cat "$lock"
  exit 1
fi
trap 'rm -f "$lock"' EXIT
xcodebuild test -project SessionFlow.xcodeproj -scheme SessionFlow -destination 'platform=macOS'
```

## State Architecture

- `SchedulingEngine` is the main `ObservedObject` — all scheduling config lives here, persisted via `UserDefaults`.
- `CalendarService` owns all `EventKit` interactions (read/write/permissions).
- `ContentView` delegates its body to `ContentViewBody` to manage complex layout states and bindings.
- Settings changes flow through `.onChange` observers → `trigger()` → `generateSchedule()` → `projectedSessions` update.

## AI Control (MCP)

SessionFlow has an optional local MCP server for trusted agents. It is off by default and is enabled from Settings → General → **AI Control (MCP)**.

- Default endpoint: `http://127.0.0.1:8787/mcp`; use the active endpoint shown in Settings if the port was changed.
- Auth: bearer token shown in Settings. Claude Code setup command is available from the same section.
- Server lifecycle: `MCPServerController` is a `@StateObject` in `SessionFlowApp`; if `MCPSettings.enabled` is true, the app starts the server on launch.
- Tool implementation: `SessionFlow/Services/MCP/MCPTools.swift`.
- Calendar write coordination: `SessionFlow/Services/MCP/ScheduleCoordinator.swift` behind the `CalendarWriting` protocol for testability.
- Agent guide: `SessionFlow/Resources/MCP/AgentGuide.md` is served by the `learn` tool and the `sessionflow://guide` resource. Agents should call `learn` first after connecting.
- Tests: `SessionFlowTests` covers tools, listener behavior, coordinator behavior, and guide coverage. Run `xcodebuild test -scheme SessionFlow -destination 'platform=macOS'` after MCP changes.

When adding or changing an MCP tool, update both the tool catalog/dispatch and `AgentGuide.md`; the tests enforce that tool names appear in the guide.

## Developer Mode

Hidden settings panel for development and testing. Activate by quadruple-clicking the **"General"** heading in Settings (toggles `showDevSettings` in `AppStorage`).

**Location:** `AppSettingsView.swift` → `Section("Developer Settings")` (line ~265)

### Available tools

| Tool | What it does | When to use it |
| --- | --- | --- |
| **Reset All Dirty Triggers** | Clears `hasSeenWelcome`, `hasSeenPatternsGuide`, `hasSeenTasksGuide`, `timelineIntroBarDismissed`, `hasSeenSessionAwarenessGuide`, `hasSeenShortcutsGuide` | Testing onboarding flows, "Did You Know" tips, or guide sheets |
| **Reset Calendar Setup** | Re-shows the calendar permission/setup screen | Testing first-launch experience |
| **Simulate Awareness Event** | Fires "Presence Reminder" or "Ending Soon" sounds and flash effects without a real session | Testing awareness sounds, accelerando, transition effects |
| **Override now line** | Pins the red current-time marker to a fixed hour:minute (`devNowLineOverrideHour`, `devNowLineOverrideMinute`) | Screenshots, demos, testing awareness behavior at specific times |
| **Reset Calendar Permissions** | Clears system calendar access — **terminates the app immediately** | Testing permission prompt flow from scratch |

### Relevant AppStorage keys

- `showDevSettings` — whether the section is visible
- `devNowLineOverrideEnabled` — now-line override toggle
- `devNowLineOverrideHour` / `devNowLineOverrideMinute` — pinned time

These persist in UserDefaults, so Developer Mode stays visible across launches once activated.

## Adding a Feature

1. Create the `.swift` file and register it in `project.pbxproj` (see CLAUDE.md → "Adding Files to Xcode").
2. If it has settings, add properties to `SchedulingEngine` and bind in `SettingsPanel`.
3. If it has a tooltip/help, add an `(i)` popover button in `SettingsPanel`.
4. If it affects scheduling, wire `.onChange` observers in `ContentView` (see CLAUDE.md → "Adding New Config Properties").
