# Contributing

Short version: keep the Xcode project tidy, test your change, ship it.

## Non‑negotiables

- New Swift files must be registered manually in `SessionFlow.xcodeproj/project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup, PBXSourcesBuildPhase).
- Only use “Deep” wording (never “Extra”); file names mirror their primary type names.
- Follow the existing session hashtag contract (`#work`, `#side`, `#deep`, `#plan`) so counting stays accurate.

## Setup

- macOS 13+, Xcode 15+, Git installed.
- Clone, `open SessionFlow.xcodeproj`, or run `./build_app.sh` (`major|minor|patch` bump) for command‑line builds. `deploy_app.sh` and `create_dmg.sh` exist for release flows.

## Workflow

1. Create a branch.
2. Make the change inside the existing folder layout (Models, Services, Views, etc.).
3. Update `project.pbxproj` for any new files and keep naming consistent.
4. Update docs that matter (`README.md`, `CHANGELOG.md`).
5. Build locally; run the app and exercise the affected feature set with both empty and busy calendar scenarios.

## Coding & UI

- SwiftUI + MV structure already in place; keep related logic grouped and small.
- Use `NumericInputField` for numeric settings; dashed borders are for projections only.
- Prefer clarity over cleverness; add a succinct comment only when logic is not obvious.

## Testing

- App must build cleanly.
- Verify scheduling engine behavior against test calendars (hashtags, overlapping sessions, presets).
- Confirm permissions prompts, deep/work/side counts, and any new UI states.

## Pull Requests

- Rebase on latest main, squash noise.
- Commit message: `type: summary`.
- PR description covers what changed, why, and how to test; include screenshots for UI updates.
- No PR passes review without tests performed and docs updated.

## Need Help?

Open an issue with repro details or feature context. Anything unclear in these notes goes in the issue first, not after a broken merge.
