# Changelog

All notable changes to SessionFlow will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
