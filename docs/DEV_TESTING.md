# Developer Testing Guide

## Hidden Developer Settings

### Activation

**4-click** on the "Settings" title in the header of App Settings to toggle dev settings on/off.

When enabled:

- Developer Settings section appears at the bottom of the Settings panel
- State persists across app launches (stored in UserDefaults)

### Features

#### Reset All Dirty Triggers

- Button: "Reset All Dirty Triggers"
- Function: Clears `hasSeenWelcome`, `hasSeenPatternsGuide`, and `hasSeenTasksGuide`
- Use Case: Re-run the welcome experience and in-app guides from scratch
- Effect: All onboarding popovers will appear again the next time their triggers fire

#### Reset Calendar Setup

- Button: "Reset Calendar Setup"
- Function: Clears the setup completion flag and sends the `ResetCalendarSetup` notification
- Use Case: Test the calendar permission and setup flow multiple times
- Effect: CalendarSetupView appears immediately so you can walk through the entire flow again

#### Reset Presets

- Button: "Reset Presets"
- Function: Removes `SessionFlow.Presets` and `SessionFlow.LastActivePresetID` from UserDefaults and broadcasts `PresetsReset`
- Use Case: Validate preset creation logic and ensure calendar assignments are reapplied correctly
- Effect: All saved presets are removed. Relaunch calendar setup (or create new presets manually) to restore defaults

#### Reset Calendar Permissions

- Button: "Reset Calendar Permissions"
- Function: Executes `tccutil reset Calendar com.kibermaks.SessionFlow` and terminates the app
- Use Case: Force macOS to prompt for Calendar access again without digging through System Settings
- Effect: App quits immediately after issuing the reset; on next launch macOS will prompt for Calendar permissions

## Testing Calendar Permission & Setup Flow

### Reset App State Completely

```bash
# Clear all app preferences
defaults delete com.kibermaks.SessionFlow

# Revoke calendar permissions (manual)
# Go to: System Settings > Privacy & Security > Calendars
# Remove "SessionFlow" from the list
```

### Expected Flow

1. **First Launch (no permissions)**
   - Shows: CalendarPermissionView
   - Action: Click "Grant Calendar Access"
   - System: macOS permission dialog appears
   - After granting: Automatically transitions to setup

2. **After Permissions (no setup)**
   - Shows: CalendarSetupView
   - Action: Select calendars for Work, Side, Deep sessions
   - Action: Click "Complete Setup"
   - After completing: Transitions to main app

3. **Normal Launch**
   - Shows: Main app interface
   - First time only: Welcome guide appears

### Quick Reset for Testing

Using Dev Settings:

1. 4-click "SessionFlow" title
2. Verify version turns green
3. Scroll to bottom of Settings panel
4. Click "Reset Calendar Setup"
5. The setup screen will appear immediately

## App Bundle ID

```code
com.kibermaks.SessionFlow
```

## UserDefaults Keys

### Setup & Permissions

- `SessionFlow.HasCompletedSetup` - Boolean, tracks if calendar setup is done
- `showDevSettings` - Boolean, tracks if dev settings are enabled

### Calendars

- `SessionFlow.SavedState` - JSON, stores current scheduling configuration
- Includes: workCalendarName, sideCalendarName, deepSessionConfig.calendarName

### Guides

- `hasSeenWelcome` - Boolean
- `hasSeenPatternsGuide` - Boolean
- `hasSeenTasksGuide` - Boolean

## Notification Events

- `SetupCompleted` - Posted when calendar setup is completed
- `ResetCalendarSetup` - Posted when dev reset button is clicked
- ContentView listens to both and updates `hasCompletedSetup` accordingly
