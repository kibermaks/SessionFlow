---
name: release
description: Full SessionFlow release — build signed app, notarize, create DMG, commit, tag, push, GitHub release
user_invocable: true
disable-model-invocation: true
---

# Release Workflow

Usage: `/release` — creates a release with today's date as the marketing version (e.g. `2026.4.10`).

SessionFlow uses date-based versioning: `YYYY.M.D`. The build number auto-increments independently.

## Steps

### 1. Check prerequisites

```bash
git status --porcelain
```

If dirty (uncommitted changes), stop and tell the user to commit or stash first.

```bash
git log --oneline $(git describe --tags --abbrev=0)..HEAD
```

Collect all commits since the last tag — used to write the changelog.

### 2. Update CHANGELOG.md

- Read existing `CHANGELOG.md` to see the format
- Add a new `## [YYYY.M.D] - YYYY-MM-DD` section at the top (below the header, above the previous version)
- Summarize changes from the git log since last tag:
  - Group into `### Added`, `### Changed`, `### Fixed` — only include sections that have entries
  - Order bullets by importance (most significant first)
  - Keep entries concise — no implementation details, no sub-features when parent is listed
  - PLAIN TEXT ONLY — no bold (`**`), no italic (`_`), no other markdown inside bullet text
  - Do not list internal refactors or build-only changes unless they directly affect users
- Commit the CHANGELOG update separately before proceeding (it must be clean for the version bump commit)

### 3. Build (Release-signed)

```bash
./build_app.sh --release
```

The `--release` flag:
- Builds in `Release` configuration (not Debug)
- Re-signs the app with Developer ID Application certificate + hardened runtime + timestamp
- This is required for notarization and Gatekeeper approval

The script sets the marketing version to today's date and bumps the build number automatically.

For same-day rebuilds (version already matches today), use:
```bash
./build_app.sh --release current
```

Confirm the output says the correct version (e.g. `version 2026.4.10 (build 750) is ready`).

**IMPORTANT**: Do NOT open the app after building — close it if the build script opened it. The next step (notarization) needs the .app bundle unmodified.

### 4. Notarize the app

```bash
./notarize.sh "SessionFlow.app"
```

This submits the signed app to Apple's notary service, waits for approval, and staples the notarization ticket. Takes 1-5 minutes typically.

Requires keychain credentials stored under profile "SessionFlow" (one-time setup by the user).

### 5. Create DMG

For same-day suffix releases, set the override:
```bash
DMG_VERSION_OVERRIDE="YYYY.M.D-N" ./create_dmg.sh
```

For normal releases:
```bash
./create_dmg.sh
```

The DMG is created in `dmg_output/SessionFlow-{VERSION}.dmg`.

### 6. Notarize the DMG

```bash
./notarize.sh "dmg_output/SessionFlow-{VERSION}.dmg"
```

The DMG also needs its own notarization ticket stapled.

### 7. Create ZIP

The ZIP contains the notarized `.app` (not the DMG):

```bash
zip -r "SessionFlow-{VERSION}.zip" "SessionFlow.app" -q
```

The ZIP is created in the project root.

### 8. Determine tag and artifact names

**Normal release** (new version today):
- Tag: `v{VERSION}` (e.g. `v2026.4.10`)
- Artifacts: `SessionFlow-{VERSION}.dmg`, `SessionFlow-{VERSION}.zip`

**Same-day rebuild** (version matches an existing tag):
- Check existing tags: `git tag -l "v{VERSION}-*"`
- Find next suffix number
- Tag: `v{VERSION}-{N}` (e.g. `v2026.4.10-2`)
- Artifacts use the suffixed name: `SessionFlow-{VERSION}-{N}.dmg`, `SessionFlow-{VERSION}-{N}.zip`
- Ask the user before using a same-day suffix

### 9. Commit, tag, push

Stage only the project file (version bump). CHANGELOG was already committed in step 2.

```bash
git add SessionFlow.xcodeproj/project.pbxproj
git commit -m "chore: release version {VERSION}

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
git tag -a {TAG} -m "Release version {VERSION} (build {BUILD})"
git push origin main --tags
```

### 10. Create GitHub release

```bash
gh release create {TAG} \
  "dmg_output/SessionFlow-{ARTIFACT_LABEL}.dmg" \
  "SessionFlow-{ARTIFACT_LABEL}.zip" \
  --title "SessionFlow {TAG} (build {BUILD})" \
  --notes "RELEASE_NOTES"
```

Release notes = the new CHANGELOG section content, plain text, no markdown formatting.

### 11. Report

Tell the user the release URL returned by `gh release create`.

## Common mistakes to avoid

- Do NOT build without `--release` — Debug builds lack Developer ID signing and will fail notarization
- Do NOT skip notarization — both the .app AND the DMG must be notarized separately
- Do NOT create the ZIP from the DMG — ZIP the `.app` bundle, not the `.dmg` file
- Do NOT use bold/italic in changelog bullets or release notes
- Do NOT `git add -A` — only stage project.pbxproj (CHANGELOG is committed separately)
- Do NOT create the GitHub release before pushing the tag
- DMG is in `dmg_output/`, ZIP is in the project root
- Do NOT open or launch the app between building and notarizing
