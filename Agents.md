# Agent Knowledge Base & Precautions

This file serves as a dedicated knowledge repository for AI agents working on the SessionFlow project. Read this file before making any structural or logic changes.

## ⚠️ CRITICAL PRECAUTIONS

### 1. Xcode Project Structure

This is a standard Xcode project. **Adding a new file to the filesystem is NOT enough.** You must manually edit `SessionFlow.xcodeproj/project.pbxproj` to register new files in the following sections:

- `PBXBuildFile` (for the actual compilation)
- `PBXFileReference` (for the file location)
- `PBXGroup` (to show it in the 'Views', 'Models', etc. group)
- `PBXSourcesBuildPhase` (to include it in the target's source files)

**Failure to do this will result in compilation errors.**

### 2. Renaming Conventions

- **"Deep" vs "Extra"**: The term "Extra" has been deprecated in favor of **"Deep"** (for Deep Work). Ensure all UI labels and internal logic use "Deep".
- **Naming**: Always follow `NameOfFile.swift` matching the struct/class name within.

## 🧠 CORE CONCEPTS

### 1. The Hashtag System

The application identifies existing sessions by parsing event notes in the macOS Calendar.

- `#work`: Work Sessions
- `#side`: Side Sessions
- `#deep`: Deep Sessions
- `#plan`: Planning Sessions

Accurate counting of existing tasks (when `awareExistingTasks` is enabled) depends entirely on these tags being present in the calendar event notes.

### 2. Session Types

- **Work**: Primary focus tasks (Emerald/Purple).
- **Side**: "Life admin" tasks (Paying bills, emails, quick errands).
- **Deep**: Rare, high-intensity focus blocks.
- **Planning**: A short strategy block at the start of the day.

### 3. Visual Language

- **Solid Borders**: Real calendar events.
- **Dashed Borders**: Projected/Preview sessions. This applies to the `sessionsSummaryCard` in the right panel and the projected blocks in `TimelineView`.
- **Keyboard Input**: Use `NumericInputField` for numeric settings instead of standard `Stepper` to allow both keyboard typing and incremental adjustment.

## ⚙️ TECHNICAL DETAILS

### 1. State Management

- `SchedulingEngine` is the main source of truth (ObservedObject). It handles persistence via `UserDefaults`.
- `CalendarService` handles `EventKit` interactions.
- `ContentView` uses a `ContentViewBody` extraction to manage complex layout states and bindings.

### 2. Versioning & Build

The `./build_app.sh` script handles versioning:

- `major`: Bumps X.0
- `minor`: Bumps Y.1
- `patch` (default): Only increments build number.
Marketing version is displayed in `HeaderView`.
it also launches app.

## 🛠 COMMON WORKFLOWS

### Adding a Feature

1. Create the `.swift` file.
2. Update `project.pbxproj` (Sections: BuildFile, FileRef, Group, Sources).
3. If it has settings, update `SchedulingEngine` and `SettingsPanel`.
4. If it has a UI tooltip/help, add an `(i)` button via a popover in `SettingsPanel`.
