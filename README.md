<div align="center">

<h1 style="display: flex; align-items: center; justify-content: center; gap: 0.4em;">
  <img src="docs/assets/AppIcon.png" width="48" height="48" alt="SessionFlow app icon" />
  SessionFlow
</h1>

**Smart scheduling for productive days**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Build](https://github.com/kibermaks/SessionFlow/actions/workflows/build.yml/badge.svg)](https://github.com/kibermaks/SessionFlow/actions)
[![Release](https://img.shields.io/github/v/release/kibermaks/SessionFlow)](https://github.com/kibermaks/SessionFlow/releases/latest)

SessionFlow is a native macOS app that helps you plan, execute, and reflect on productive days. It automatically schedules work, side, and deep sessions around your existing calendar events, tracks them in real time with ambient sounds and progress indicators, and captures feedback so you can see how your time actually felt.

[Download Latest Release](https://github.com/kibermaks/SessionFlow/releases/latest) • [Documentation](#-documentation) • [Contributing](CONTRIBUTING.md)

</div>

---

## ✨ Key Features

### Plan

- **🧠 Smart Scheduling**: Automatically fits work, side, and deep sessions into available gaps in your macOS Calendar
- **🔄 Dynamic Patterns**: Choose from multiple scheduling patterns (Alternating, All Work First, All Side First, Custom Ratio)
- **💾 Preset Management**: Save and quickly switch between configurations for Workdays, Focus Days, Weekends, or any custom mix
- **📅 Calendar Integration**: Read from and write directly to macOS Calendar with per-calendar filtering and replacement controls
- **⚙️ Customizable Sessions**: Configure names, durations, and target calendars for each session type (Work, Side, Planning, Deep Work)
- **🎯 Hashtag System**: Add `#work`, `#side`, `#deep`, `#plan`, or `#break` to event notes so existing sessions are recognized automatically

### Execute

- **📊 Interactive Timeline**: Drag-and-drop events, resize sessions, lock layout, and freeze projections for manual fine-tuning
- **👁 Session Awareness**: Tracks active calendar events—both tagged sessions and your regular calendar events—with ambient sounds, a progress bar, and gentle reminders as sessions approach their end. A progress donut on the dock icon and an optional menu-bar timer let you glance at remaining time without switching windows
- **🪟 Mini-Player**: Compact floating window that shows session status at a glance—collapse the main window and keep awareness in a small footprint. Displays idle, next-up, active, and feedback states with the same progress and time info as the full panel
- **⌘ Shortcuts Integration**: Trigger macOS Shortcuts when sessions start, end, or approach. Each shortcut receives structured JSON with session details—use it to toggle Focus modes, send notifications, control smart home devices, or anything Shortcuts can do. [Template shortcuts](public/shortcuts/) are available for every trigger
- **🌙 Night-Owl Mode**: Schedule beyond midnight with +1d markers on the timeline (up to 6 am next day)
- **↩️ Undo/Redo**: Full history for event moves and projected session edits

### Reflect

- **📈 Productivity Tracking**: After each session ends you get a quick feedback prompt (rocket/completed/partial/skipped). A daily productivity card and monthly calendar view summarize your ratings, highlight unrated blocks, and compute weighted focus time so you can see how each day and month actually felt

### Polish

- **🌑 Beautiful UI**: Dark-themed glassmorphic design with intuitive controls
- **🔃 Auto-Updates**: Automatic update checks with self-install from GitHub Releases, plus a What's New changelog viewer

## 🖼 Visual Walkthrough

### Welcome Guide

<p align="center">
  <img src="docs/assets/WelcomeGuide.gif" alt="Welcome guide onboarding flow" width="430" />
</p>

### Command Center

Timeline, projections, and controls share a single glass panel so you can see inputs and outputs together.

<p align="center">
  <img src="docs/assets/Main%20Screen.jpg" alt="SessionFlow timeline and settings" width="900" />
</p>

### Dynamic Scheduling + Drag & Drop

Sessions flow around existing events instantly as you tweak durations or presets. You can also drag and drop events to change their time and duration.

<p align="center">
  <img src="docs/assets/DynamicNature.gif" alt="Animated view showing sessions adapting on the timeline" width="900" />
</p>

### Preset Library

Workday, Focus, Weekend, or any custom preset stays one click away.

<p align="center">
  <img src="docs/assets/Presets.png" alt="Preset manager UI and quick switching controls" width="400" />
</p>

### Availability Insights

Summary cards highlight real events, projected work, and when you are supposed to be free.

<p align="center">
  <img src="docs/assets/Projected%20+%20Availability%20Cards.png" alt="Projected sessions and availability cards" width="400" />
</p>

### Session Awareness & Mini-Player

The bottom panel tracks your current session in real time—whether it’s a tagged event (#work, #side, #deep, #plan, #break) or any regular calendar event—displaying elapsed time, a progress bar, and remaining time. Ambient sounds and visual cues keep you in flow, with gentle alerts as the session nears its end. Progress also appears as a donut overlay on the dock icon and as a live timer in the menu bar, so you always know where you stand without switching windows. When a session ends, a quick prompt lets you rate how it went. For a more compact experience, the floating Mini-Player provides the same awareness in a small footprint. You can expand back to the full app anytime.

<p align="center">
  <img src="docs/assets/SessionAwareness.gif" alt="Session Awareness: idle, active session, progress, feedback" width="900" />
</p>

### Productivity Tracking

The right side of the window can show a **Productivity** card once you start leaving feedback on sessions. It aggregates how many rocket/completed/partial/skipped blocks you had today, how many are still unrated, and computes a weighted **Focus Time** score based on both duration and rating. From there, a calendar button opens a monthly productivity view with a compact calendar: each day shows colored dots for rated sessions and a tiny focus-time label, making it easy to spot your strongest days and streaks at a glance.

<p align="center">
  <img src="docs/assets/ProductivityTracking.png" alt="Productivity Tracking" width="400" />
</p>

## 🚀 Installation

### Option 1: Download Pre-built Release (Recommended)

1. Download the latest `SessionFlow-YYYY.M.D.dmg` from [Releases](https://github.com/kibermaks/SessionFlow/releases/latest)
2. Open the DMG file
3. Drag `SessionFlow.app` to your Applications folder
4. Launch from Applications or Spotlight
5. Grant Calendar permissions when prompted

### Option 2: Build from Source

See [Building from Source](#-building-from-source) section below.

## 🎯 Quick Start

1. Launch the app, grant Calendar access, and pick your calendars.
2. Set target counts and durations for Work, Side, Deep, and Planning sessions.
3. Pick a scheduling pattern or load a preset, then review the timeline.
4. Press **Schedule Sessions** when the layout looks right.
5. As sessions begin, the bottom panel (or Mini-Player) tracks your progress with ambient sounds, a dock icon donut, and an optional menu-bar timer. Rate each session when it ends to build your productivity history.

## 🔒 Privacy & Local Processing

- **Local Only**: Scheduling logic, presets, and state live entirely on your Mac—no accounts, telemetry, or remote services.
- **Privacy Respected**: Calendar access is limited to the calendars you explicitly pick, and the data never leaves the device.
- **User Confirmation**: The app only modifies your calendar when you explicitly schedule sessions or drag events — you're always in control.

## 💡 Usage Tips

- **Hashtags**: Add `#work`, `#side`, `#deep`, `#plan`, or `#break` to event notes so existing sessions are detected automatically.
- **Visual Language**: Solid borders mark real events; dashed borders with diagonal stripes are projections.
- **Presets**: Save Workday, Focus, Weekend, or any custom mix for instant reuse.
- **Awareness Mode**: Toggle “Aware of existing tasks” when you want counts to respect what’s already booked.
- **Track Other Events**: Enable “Awareness of your other calendar events” to also track regular (untagged) calendar events with timer, progress, and ambient sound.
- **Shortcuts**: Set up macOS Shortcuts to automate actions at session boundaries. Go to Settings → Shortcuts, enable a trigger, and name your shortcut. Download [ready-made templates](public/shortcuts/) to get started instantly.
- **Dock & Menu Bar**: Enable the dock progress donut and menu-bar timer in Session Awareness settings so you can monitor remaining time from anywhere.
- **Mini-Player**: Click the collapse button on the bottom panel to detach a floating mini-player; expand back anytime.
- **Freeze & Adjust**: After scheduling, freeze projections and drag/resize them by hand for pixel-perfect layouts.
- **Copy Events**: Right-click any timeline event and use “Copy to...” to duplicate it to a nearby day.
- **Lock Dragging**: Toggle the lock icon to prevent accidental event moves while reviewing your schedule.
- **Night Scheduling**: Extend the schedule end hour past midnight to plan late-night sessions with clear +1d markers.
- **Rate Sessions**: After each session ends, use the quick feedback prompt to rate it—these ratings feed into the Productivity card and monthly view.

## ⚡ Power Features

These are the tricks that make SessionFlow click once you know them.

### Keyboard Shortcuts

| Shortcut | What it does |
| --- | --- |
| **⌘Z** | Undo the last drag, resize, or delete on the timeline |
| **⇧⌘Z** | Redo |
| **Esc** | Cancel an active drag, close the detail sheet, or dismiss the event creation popover |
| **Hold ⇧ (Shift)** while dragging | Free-form positioning — skips the 5-minute grid |
| **Hold ⌥ (Option)** while resizing | Snap to 5-minute increments for fine control |

### Timeline Tricks

- **Double-click empty space** (left half) to create a new event right there — no need to open Calendar.app. An autocomplete dropdown suggests recent events so you can recreate them in two keystrokes.
- **Double-click an event block** to open its detail sheet where you can edit the title, notes, and URL inline.
- **Drag the top or bottom edge** of any event or projected session to resize it. The grab zone is about 8 pixels from the edge.
- **Right-click any calendar event** to copy it to an upcoming day or pick a custom date. Great for repeating a meeting you just had.
- **Right-click a projected session** to schedule it immediately, schedule everything up to that point, or rename it.

### Event Creation Popover

When the popover is open after a double-click:

- **Type a few letters** and recent events matching your input appear instantly with their calendar and duration pre-filled. Hit **Tab** to accept.
- **⌘↑ / ⌘↓** cycles through your calendars without touching the mouse.
- **↑ / ↓** navigates suggestions; **Tab** or click applies one.

### Freeze & Manual Layout

Drag any projected session and the app automatically freezes all projections so they stop recalculating. Now you can rearrange sessions by hand — overlapping sessions push out of the way. Unfreeze when you want the engine to take over again.

### Developer Mode

Quadruple-click the "General" heading in Settings to unlock developer tools:

- **Override the "now" line** — pin the red time marker to any hour and minute. Perfect for screenshots or testing how awareness behaves at a specific time.
- **Simulate awareness events** — trigger "Presence Reminder" or "Ending Soon" sounds without waiting for a real session.
- **Reset onboarding** — re-show the welcome wizard, calendar setup, or "Did You Know" tips.

### Awareness Anywhere

You don't need the main window open to stay on track:

- **Dock icon** shows a progress donut for the active session.
- **Menu bar** shows a live countdown timer.
- **Mini-player** floats on your desktop — collapse the bottom awareness panel to switch to it.
- **Mute button** is always accessible from the mini-player and the bottom panel.

### Shortcuts Automation

Each trigger (session start, end, approaching, rest boundaries) sends a structured JSON payload to your macOS Shortcut. You can use this to toggle Focus modes, send yourself a Slack message, control smart lights, or anything else Shortcuts supports — the app doesn't care what you do with the data.

## 🏗 Architecture & Key Elements

The project follows a modular architecture with clear separation of concerns:

```code
SessionFlow/
├── Models/
│   ├── Session.swift
│   ├── Preset.swift
│   ├── SchedulePattern.swift
│   ├── SessionAwarenessConfig.swift
│   └── SessionFeedback.swift
│
├── Services/
│   ├── SchedulingEngine.swift
│   ├── CalendarService.swift
│   ├── AvailabilityCalculator.swift
│   ├── EventUndoManager.swift
│   ├── SessionAwarenessService.swift
│   ├── SessionAudioService.swift
│   ├── DockProgressController.swift
│   ├── MenuBarController.swift
│   └── UpdateService.swift
│
└── Views/
    ├── ContentView.swift
    ├── TimelineView.swift
    ├── SettingsPanel.swift
    ├── PresetManager.swift
    ├── SessionAwarenessPanel.swift
    ├── MiniPlayerView.swift
    ├── ProductivityCard.swift
    ├── WhatsNewView.swift
    ├── AboutView.swift
    └── [other views...]
```

### Key Components

#### Models

- **`Session.swift`**: Defines `SessionType` enum (Work, Side, Deep, Planning) and `ScheduledSession` data structure
- **`Preset.swift`**: Handles preset configuration and persistence via `UserDefaults`
- **`SchedulePattern.swift`**: Generates session orders based on patterns (Alternating, All Work First, etc.)
- **`SessionAwarenessConfig.swift`**: Configuration for session tracking, sounds, dock progress, and menu-bar timer
- **`SessionFeedback.swift`**: `SessionRating` enum and feedback storage via calendar event notes

#### Services

- **`SchedulingEngine.swift`**: Core scheduling algorithm that fits sessions into available time gaps
- **`CalendarService.swift`**: EventKit wrapper for reading/writing calendar events with per-calendar filtering
- **`AvailabilityCalculator.swift`**: Identifies free time slots between existing events
- **`EventUndoManager.swift`**: Custom undo/redo stack for calendar event and projected session changes
- **`SessionAwarenessService.swift`**: Tracks active and upcoming sessions, manages progress, and triggers feedback prompts
- **`SessionAudioService.swift`**: Ambient sound playback, transition sounds, and accelerando during sessions
- **`DockProgressController.swift`**: Renders the progress donut overlay on the dock icon
- **`MenuBarController.swift`**: Manages the optional menu-bar status item with live timer

#### Views

- **`ContentView.swift`**: Main layout container and state management
- **`TimelineView.swift`**: Interactive timeline with drag-and-drop, resize, locking, and freeze mode for both events and projected sessions
- **`SettingsPanel.swift`**: Configuration controls (session counts, durations, patterns)
- **`PresetManager.swift`**: Preset saving, loading, and management UI
- **`SessionAwarenessPanel.swift`**: Bottom panel showing active session, next-up, and feedback states
- **`MiniPlayerView.swift`**: Compact floating window mirroring the awareness panel
- **`ProductivityCard.swift`**: Daily summary and monthly calendar view of session feedback
- **`WhatsNewView.swift`**: Fetches and displays the changelog from GitHub after updates
- **`AboutView.swift`**: About window with version and build info

## 🔧 Development Guide

### Adding a New Session Type

1. Update `SessionType` enum in `Session.swift` with a new case, icon, and color
2. Update `SchedulingEngine.swift` to handle the new type in its generation loop
3. Add UI controls in `SettingsPanel.swift` for configuration
4. Update preset system in `Preset.swift` to include new type
5. Add hashtag support in `CalendarService.swift` if needed

### Modifying Scheduling Logic

- **Core algorithm**: `SchedulingEngine.generateSchedule()`
- **Gap detection**: `AvailabilityCalculator.calculate()`
- **Pattern logic**: `SchedulePattern` enum and `SessionOrderGenerator.generateOrder()`
- **Existing task awareness**: Hashtag parsing in `CalendarService.swift`

### Adding New Files

**IMPORTANT**: When adding new Swift files, you **must** manually update `SessionFlow.xcodeproj/project.pbxproj`:

- `PBXBuildFile` section
- `PBXFileReference` section
- `PBXGroup` section
- `PBXSourcesBuildPhase` section

See [Agents.md](Agents.md) for detailed instructions.

## 📦 Requirements & Dependencies

### System Requirements

- **macOS**: 13.0 (Ventura) or later
- **Processor**: Apple Silicon (M1/M2/M3) or Intel
- **Permissions**: Calendar access (requested on first launch)

### Dependencies

- **SwiftUI**: Main UI framework
- **EventKit**: macOS Calendar integration
- **Foundation**: Core logic and date handling

*No external dependencies or package managers required!*

## 🛠 Building from Source

### Prerequisites

- Xcode 15.0 or later
- macOS 13.0 or later
- Git
- Apple Developer Team ID (update the `TEAM_ID="RGFAX8X946"` placeholder in `build_app.sh` and `SessionFlow.xcodeproj/project.pbxproj` to your own Team ID before running the build scripts)

### Clone and Build

```bash
# Clone the repository
git clone https://github.com/kibermaks/SessionFlow.git
cd SessionFlow

# Build using the build script (creates Release build)
./build_app.sh

# Or open in Xcode
open SessionFlow.xcodeproj
```

### Build Scripts

The project includes several convenience scripts:

#### `./build_app.sh [current|dedicated-version YYYY.M.D]`

Builds a Release version of the app with date-based version management.

> ⚠️ Before running, update the `TEAM_ID="RGFAX8X946"` placeholder in both `build_app.sh` and `SessionFlow.xcodeproj/project.pbxproj` so the script can sign with your Apple Developer account.

```bash
# Set marketing version to today's date and increment build number (default)
./build_app.sh

# Keep current marketing version and increment build number only
./build_app.sh current

# Build with a dedicated version
./build_app.sh dedicated-version 2026.4.9
```

**What it does:**

- Updates version numbers in project file
- Builds Release configuration
- Signs the app (if certificates available)
- Outputs to `./build_output/`
- Copies app to current directory
- Launches the built app

#### `./create_dmg.sh`

Creates a distributable DMG file for the app.

```bash
# Create DMG from built app
./create_dmg.sh
```

**What it does:**

- Packages the app into a DMG
- Creates Applications folder symlink
- Adds README with installation instructions
- Outputs to `./dmg_output/`
- Names file as `SessionFlow-YYYY.M.D.dmg`

### Development Workflow

```bash
# 1. Make your changes in Xcode
open SessionFlow.xcodeproj

# 2. Build and test locally
./build_app.sh

# 3. When ready to release, create DMG
./create_dmg.sh
```

## 📚 Documentation

### For Users

- [Quick Start Guide](#-quick-start)
- [Usage Tips](#-usage-tips)
- [FAQ](https://github.com/kibermaks/SessionFlow/wiki/FAQ) *(coming soon)*

### For Developers

- [Architecture & Key Elements](#-architecture--key-elements)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Code Signing Setup](CODE_SIGNING.md) - **Secure signing for public repos**
- [Agent Knowledge Base](Agents.md) - **READ THIS FIRST** before making changes
- [Changelog](CHANGELOG.md)

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details on:

- Setting up your development environment
- Code style and standards
- Submitting pull requests
- Reporting issues
- Feature requests

## 📋 Roadmap

Future features and improvements:

- [ ] Multi-day scheduling
- [ ] Recurring session templates
- [ ] iCloud sync for presets
- [ ] Custom session colors and icons
- [ ] Calendar widget support

## 🐛 Known Issues

Check the [Issues](https://github.com/kibermaks/SessionFlow/issues) page for current known issues and feature requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/) by Apple
- Calendar integration powered by [EventKit](https://developer.apple.com/documentation/eventkit)
- Inspired by the need for better task scheduling and time management

## 💬 Community & Support

- **Issues**: [GitHub Issues](https://github.com/kibermaks/SessionFlow/issues)
- **Discussions**: [GitHub Discussions](https://github.com/kibermaks/SessionFlow/discussions)
- **GitHub User**: [@kibermaks](https://github.com/kibermaks) *(for security issues only)*

## ⭐ Star History

If you find this project useful, please consider giving it a star!

---

<div align="center">

Made with ❤️ for productive Mac users

[Report Bug](https://github.com/kibermaks/SessionFlow/issues) • [Request Feature](https://github.com/kibermaks/SessionFlow/issues) • [View Releases](https://github.com/kibermaks/SessionFlow/releases)

</div>
