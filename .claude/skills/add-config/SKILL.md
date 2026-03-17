---
name: add-config
description: Add a new configuration property to SessionFlow with all required wiring (model, Codable, UI binding, onChange observer)
---

# Add Config Property

Scaffold a new configuration property with all required wiring. This skill ensures nothing is missed when adding settings.

## Required Information

When invoked, determine:
- **Property name** and **type** (Bool, Int, String, enum, etc.)
- **Default value**
- **Which config model** it belongs to (SchedulingEngine, DeepSessionConfig, Preset, SessionAwarenessConfig, etc.)
- **Where the UI binding goes** (SettingsPanel, AppSettingsView, etc.)
- **Whether it affects scheduling** (needs onChange observer and use in generateSchedule)

## Checklist (all 4 steps from CLAUDE.md)

### 1. Add property to model with Codable support

- Add the property with a default value
- Add to `CodingKeys` enum
- Add `decodeIfPresent` in `init(from decoder:)` with fallback to default (NEVER use `decode` without `IfPresent` — breaks backwards compat)
- Add `encode` in `encode(to encoder:)`

### 2. Add UI binding

- Add the appropriate SwiftUI control in the relevant settings view
- Use `Binding(get:set:)` pattern consistent with surrounding code
- Add caption text explaining the setting

### 3. Add onChange observer in ContentView

**This is the most commonly missed step.**

- Add `.onChange(of: engine.<path>.newProperty) { _, _ in trigger() }` in `ContentView.swift` → `SettingsChangeModifier` → `extraObservers1` or `extraObservers2`
- The modifier has `@EnvironmentObject var calendarService` and `@Binding var selectedDate`
- Skip this step ONLY if the property doesn't affect timeline/schedule

### 4. Use in SchedulingEngine

- Reference the property in `generateSchedule()` or relevant service
- Skip if it's a UI-only or awareness-only setting

## After completion

Run `./build_app.sh` to verify everything compiles.
