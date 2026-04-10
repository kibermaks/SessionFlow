# Changelog

All notable changes to SessionFlow will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and SessionFlow marketing versions now follow the release date format `YYYY.M.D`.

## [2026.4.9] - 2026-04-09

### Added

- Inline event creation — double-click empty space in the timeline to create calendar events with Spotlight-like autocomplete from recent events

### Changed

- Marketing versions now use the release date format (`YYYY.M.D`) while the build number continues incrementing independently

### Fixed

- Mic Aware now detects shared input/output devices (e.g. Thunderbolt Display) and disables itself with a warning
- Mute toggle now persists across app restarts
- Feedback rating icons show tooltips and can be toggled off by clicking again

## [2.7] - 2026-04-07

### Added

- Master on/off switch for Shortcuts — runs independently of Session Awareness
- Session Ending Soon shortcut trigger with configurable lead time
- Mini Player border pulses briefly when the window appears

### Fixed

- Time and duration alignment on the feedback icon
- Stale progress bar and countdown labels in shared awareness components
- Duplicate timers and observers when the root view recreated on launch
- Burst of calendar sync events now coalesces into a single timeline refresh
- Mute toggled from the mini player or bottom panel no longer reverts after unrelated settings tweaks

## [2.6] - 2026-03-23

### Added

- macOS Shortcuts integration — trigger any Shortcut at session start, end, approaching, and rest boundaries with structured JSON payloads
- Shortcuts settings tab with test button, type filters, and example shortcuts

### Fixed

- Mini-player widget now drags with native macOS feel
- Awareness settings UI no longer lags while a session is active

## [2.5] - 2026-03-12

### Added

- Auto-mute when microphone is active — automatically silences sounds during calls and recordings
- Session type filtering on Productivity Card and Calendar view with per-type stats

### Changed

- Mute controls redesigned as independent toggles (manual mute + mic-aware auto-mute)
- Extracted shared awareness components to reduce code duplication

## [2.4] - 2026-03-12

### Added

- New ambient sound: Creek Atmosphere
- Resizable mini-player with adaptive layout and compact progress donut

### Fixed

- Session awareness now stays in sync with live calendar edits
- Mini-player layout and stability improvements

## [2.3] - 2026-03-12

### Added

- Info popover on Productivity Card explaining ratings, focus time calculation, and quick link to settings
- Focus weights editor in Awareness settings with per-rating percentage controls

### Fixed

- "What's New" dialog no longer appears during initial installation
- Numeric input fields auto-size to fit their value range instead of fixed width
- Audio preview now correctly restores playback rate (accelerando) when resuming session ambient

## [2.2] - 2026-03-10

### Added

- Hover effects across all interactive UI elements for better visual feedback
- Mute button visible in all mini-player and awareness panel states

### Fixed

- Side sessions now correctly use side rest duration instead of work rest duration
- Time rounding no longer skips the current 5-minute mark (e.g. 10:05 stays 10:05)
- Schedule end-of-day calculation simplified and corrected
- Preset loading handles missing `sideRestDuration` gracefully for backwards compatibility
- Time rounding strips leftover seconds for cleaner session start times

### Changed

- Enhanced session awareness tracking with more accurate start/end times
- Simplified mute controls — always shows interactive mute button
- Improved mute button tooltips

## [2.1] - 2026-03-10

### Added

- Productivity Card — daily focus time stats and session ratings displayed on the timeline
- Session feedback tags saved directly into calendar events for persistent tracking
- Next session preview in mini-player and awareness panel with countdown timer
- Session Awareness guide with interactive walkthrough
- Menu bar icon flashing on session transitions
- Productivity tracking toggle in settings

### Changed

- Debounced schedule regeneration and throttled dock/UI updates for smoother performance
- Fixed unreliable button click targets across the app
- Eliminated redundant @Published updates reducing ~10 unnecessary redraws per second

## [2.0] - 2026-03-09

### Added

- Rebranded to **SessionFlow** — new name, bundle ID, and identity
- Dynamic mini-player bars showing active session, next up, idle, and feedback states
- Session feedback prompts in the mini-player after sessions end
- Collapse buttons in awareness panel session bars

## [1.15] - 2026-03-08

### Added

- Session Awareness — tracks active calendar events tagged with session types (#work, #deep, #break, etc.) with ambient sounds, transition effects, and accelerando as sessions approach end
- Dock icon progress donut, menu bar session display, and collapsible floating mini-player
- Awareness settings panel with per-type sound config, device selection, and custom sound import
- Copy event to nearby day via context menu with undo support
- "Did You Know" tips for awareness, drag/resize, and manual mode

## [1.13] - 2026-03-04

### Added

- Collapsible settings sections with persisted state; chevron tooltip previews hidden values on hover
- Calendar visibility warnings when a selected calendar is hidden from timeline filters
- Auto-scrolling when dragging events near timeline edges

### Changed

- Smarter Long Rest placement based on cumulative session time

## [1.12] - 2026-03-04

### Added

- Real-time schedule recalculation during event drag — projected sessions shift live as you move calendar events
- Projected session displacement in Manual mode — dragging/resizing a projected session pushes overlapping sessions out of the way, respecting busy slots and rest durations
- Long Rest projected blocks with configurable threshold and count for deep recovery breaks between sessions
- Code signing and notarization — the app now ships notarized, eliminating Gatekeeper warnings on install

### Changed

- Optimistic UI updates for drag-drop to eliminate flicker
- Timeline visibility now unified with schedule boundary

## [1.11] - 2026-03-03

### Added

- Freeze & manual layout mode: freeze projected sessions and freely move/resize them by hand; preset panel dims with a lock overlay while frozen
- "Copy to..." context menu on timeline events to duplicate an event (time, title, notes, URL) to a nearby day in one click
- Day picker dropdown ("⋮" button) before the Today button for quick navigation to recent days
- Extended night-owl scheduling beyond midnight (up to +6 h next day) with "+1d" markers on the timeline
- Deep session "and then..." spacing parameter to control the gap between consecutive deep sessions
- What's New view that fetches the changelog from GitHub on first launch after an update
- About SessionFlow window
- Event locking toggle in the Timeline to prevent accidental drag moves
- Custom date and time input fields

### Changed

- Schedule Sessions button no longer shows a confirmation modal
- Schedule Sessions split-button now hosts the "Create just planning" option in its dropdown

### Fixed

- Negative hour display when stepping minutes below 00:00 in the time stepper

## [1.10] - 2026-02-27

### Added

- Drag-and-drop event rescheduling in the Timeline with visual previews
- Undo/redo support for event moves with history tracking
- Time snapping for precise event placement

### Changed

- Enhanced scheduling messages with clearer status based on session configuration
- Improved quota tracking in the scheduling engine

## [1.9] - 2026-02-26

### Added

- Task history management with clear confirmation in the Tasks panel

### Changed

- Updated scheduling message
- Improved tracking of events from calendars

### Fixed

- Deep session spacing when offset by busy time slots

## [1.8] - 2026-01-28

### Added

- Calendar replacement controls in App Settings to let you exclude or replace specific calendars when scheduling
- A context menu action on projected sessions to schedule a chosen session immediately

### Changed

- Deep session "inject after" setting now supports a range of 0–10 sessions for more flexible patterns
- Minor usability improvements and refinements

## [1.7] - 2026-01-26

### Added

- New “Did you know?” tips card with rotating tips

### Changed

- Auto-updater now downloads, installs, and relaunches the app on its own with live progress in the header
- Timeline double-click editing for titles, notes, and URLs plus clearer details and side-by-side overlaps
- Updated wording in Settings and other UI elements

## [1.6] - 2026-01-25

### Added

- Sides First & Last pattern
- 'Flexible Side Scheduling' toggle to disallow sides to be scheduled in smaller gaps that work sessions can't fit into
- Suggestion dropdowns with last inputted names for sessions

### Changed

- Overlapping calendar events in the timeline now render side-by-side for better readability
- Update now self-installs from GitHub releases and restarts the app

## [1.5] - 2026-01-18

### Added

- Calendar Filters section in App Settings that lets you uncheck calendars you do not want SessionFlow to consider
- Automatic update checks against GitHub releases plus a “Check for Updates…” menu entry

### Changed

- Calendar fetching, busy slot detection, and existing session awareness now ignore events from calendars that you turn off in settings

### Fixed

- Forced consistent Dark theme for the app

## [1.4] - 2026-01-16

### Added

- Comprehensive Readme guide
- Improved navigation and tooltips for controls
- Bug fixes and improvements

## [1.3] - 2026-01-15

### Added

- Initial open-source release
- MIT License
- Automated build and release workflow
- DMG installer for easy distribution

## [1.2] - 2026-01-10

### Added

- Smart scheduling engine that fits work and side sessions around existing calendar events
- Dynamic scheduling patterns (Alternating, All Work First, All Side First, Custom Ratio)
- Preset management system for saving and applying different configurations
- Interactive timeline visualization with side-by-side view of existing and projected sessions
- macOS Calendar integration via EventKit
- Customizable session types: Work, Side, Planning, and Deep Work
- Awareness of existing tasks via hashtag system (#work, #side, #deep, #plan)
- Beautiful dark-themed glassmorphic UI
- Calendar permission handling
- Welcome screen for first-time users
- Settings panel with numeric keyboard input

### Technical Details

- Built with SwiftUI for macOS
- Modular architecture with clear separation of concerns
- UserDefaults-based persistence for presets and settings
- EventKit integration for calendar access

---

## Version History Notes

### Version Format

- **Major.Minor (Build)**
  - Major: Breaking changes or significant feature additions
  - Minor: New features, improvements, or notable fixes
  - Build: Incremental build number (auto-incremented)

### How to Update This Changelog

When preparing a new release:

1. Move items from `[Unreleased]` to a new version section
2. Add the release date in `YYYY-MM-DD` format
3. Organize changes under these categories:
   - **Added**: New features
   - **Changed**: Changes to existing functionality
   - **Deprecated**: Soon-to-be removed features
   - **Removed**: Removed features
   - **Fixed**: Bug fixes
   - **Security**: Security improvements
