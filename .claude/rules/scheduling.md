---
paths:
  - "SessionFlow/Services/SchedulingEngine.swift"
  - "SessionFlow/Services/AvailabilityCalculator.swift"
  - "SessionFlow/Services/CalendarService.swift"
  - "SessionFlow/Models/Session.swift"
  - "SessionFlow/Models/SchedulePattern.swift"
---

# Scheduling Engine

- `dayEndHour` controls timeline visibility only — never use it to limit scheduling
- `scheduleEndHour` controls when scheduling stops — keep it independent from display
- `CalendarService.scheduleEndHour` must stay synced with the engine value via ContentView
- Session types: Work, Side, Planning, Deep, Long Rest — defined in `Session.swift`
