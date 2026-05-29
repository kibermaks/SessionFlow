# SessionFlow Agent Guide

You are controlling **SessionFlow**, a macOS app that schedules focus sessions around the
calendar. This guide is the source of truth for everything you can do here. Call the `learn`
tool (or read the `sessionflow://guide` resource) any time to re-read it.

## Core concepts

- **Sessions** are timed blocks. Four schedulable types plus breaks:
  - **Work** (`#work`) — primary focus tasks.
  - **Side** (`#side`) — life admin (email, errands).
  - **Deep** (`#deep`) — rare, high-intensity blocks.
  - **Planning** (`#plan`) — a short strategy block at the start of the day.
  - **Long Rest** (`#break`) — generated breaks; never committed to the calendar.
- **Preview vs. committed.** The app first builds a *preview* (projected sessions, shown with
  dashed borders). Committing writes real calendar events (solid borders) tagged with the
  hashtags above. The preview is safe to rebuild freely; committing changes the real calendar.
- **Tasks.** Work/Side/Deep each have a task list (one task per line). When enabled, task names
  become session titles in order; otherwise generic names are used.
- **Presets** are saved configurations (counts, durations, pattern, etc.).
- **Patterns** order Work/Side sessions: `Alternating`, `Alternating Reverse`, `All Work First`,
  `All Side First`, `Sides First & Last`, `Custom Ratio`.

## Typical workflow

A natural-language request like *"schedule me 4 work sessions for these three tasks, drop side
sessions, shorten focus to 30 min, then put them on my calendar for today"* maps to:

1. `set_config` → `{ "workSessions": 4, "sideSessions": 0, "workSessionDuration": 30 }`
2. `set_tasks` → `{ "work": ["Task A", "Task B", "Task C"], "useWork": true }`
3. `regenerate_schedule` → `{ "date": "2026-05-28" }` (builds the preview; returns projected sessions)
4. Inspect the returned preview, adjust if needed (`move_session`, `set_config`, …).
5. `commit_schedule` → `{ "date": "2026-05-28" }` (writes real calendar events)

Always `regenerate_schedule` after changing config or tasks so the preview reflects them, and
read the result before committing. Dates are `YYYY-MM-DD` or ISO-8601; times are ISO-8601.

## Tools

### Discovery
- **`learn`** — returns this guide.

### Read (safe, no changes)
- **`get_config`** — full scheduling configuration.
- **`get_state`** — current preview (projected sessions), quota counts, status, frozen flag, active preset.
- **`list_presets`** — saved presets with id, name, icon, summary, active/modified flags.
- **`get_day`** — `{ date? }` — real events for a day (with SessionFlow type if tagged), existing
  session counts, and availability (free minutes + how many sessions still fit).

### Configure (changes the preview's inputs; no calendar writes)
- **`set_tasks`** — `{ work?, side?, deep?, useWork?, useSide?, useDeep? }` — set task lists (arrays
  of strings) and whether they title sessions. The main natural-language entry point.
- **`set_config`** — patch any subset of the configuration. Lower `workSessions`/`sideSessions` or
  the `*Duration` values to shrink the day. Supports nested `deepSession` and `bigRest` objects.
- **`apply_preset`** — `{ presetId | name }` — switch to a saved preset.
- **`save_preset`** — `{ name, icon? }` — save the current configuration as a new preset.
- **`set_freeze`** — `{ frozen }` — when frozen, `regenerate_schedule` keeps the cached preview.

### Schedule (preview, then commit)
- **`regenerate_schedule`** — `{ date?, startHour? }` — rebuild the preview. No calendar writes.
- **`commit_schedule`** — `{ date? }` — write the current preview to the real calendar.
- **`move_session`** / **`resize_session`** — `{ eventId? | sessionId?, newStart, newEnd }` — set a
  session's interval. Use `eventId` (from `get_day`) for a committed event, or `sessionId`
  (from `get_state`) for a preview session.
- **`delete_sessions`** — `{ date, scope }` — remove SessionFlow-tagged events (`scope`: `future`
  or `all`). Only tagged sessions are removed; other calendar events are never touched.

## Safety

- Reads and preview edits are always safe and reversible.
- `commit_schedule`, `delete_sessions`, and `move_session`/`resize_session` on an `eventId` change
  the **real calendar**. Confirm the user's intent before committing or deleting.
- `delete_sessions` only removes events carrying SessionFlow hashtags — it will not delete the
  user's other appointments.
