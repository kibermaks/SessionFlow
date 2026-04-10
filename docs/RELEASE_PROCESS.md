# Release Process

This document describes the complete release process for SessionFlow, from preparing a release to publishing it on GitHub.

## Table of Contents

- [Overview](#overview)
- [Quick Release (Automated)](#quick-release-automated)
- [Manual Release Process](#manual-release-process)
- [GitHub Actions Workflow](#github-actions-workflow)
- [Post-Release Tasks](#post-release-tasks)
- [Troubleshooting](#troubleshooting)

## Overview

SessionFlow uses a semi-automated release process:

1. **Local**: Build and version the app, create DMG, commit changes
2. **GitHub**: Push tag to trigger automated build and release
3. **GitHub Actions**: Builds app, creates DMG/ZIP, publishes GitHub Release

## Quick Release (Automated)

The fastest way to create a release is using the `release.sh` script:

```bash
./release.sh
```

This interactive script will:
1. Ask you to choose today's date, a custom date version, or keep the current marketing version
2. Check your pre-release checklist
3. Build the app with updated version
4. Create DMG installer
5. Create git commit and tag
6. Push to GitHub (triggers automated release)

### Pre-Release Checklist

Before running `release.sh`, ensure:

- [ ] All changes are committed to git
- [ ] CHANGELOG.md is updated with new version changes
- [ ] App has been tested thoroughly
- [ ] Documentation is up to date
- [ ] No breaking changes (or they're documented)

## Manual Release Process

If you prefer more control, follow these steps:

### 1. Update CHANGELOG.md

Move items from `[Unreleased]` section to a new version section:

```markdown
## [2026.1.20] - 2026-01-20

### Added
- New feature description

### Changed
- Modified behavior description

### Fixed
- Bug fix description

## [1.0] - 2026-01-15
...
```

### 2. Build and Version

Choose the appropriate version increment:

```bash
# Use today's date version and bump build number
./build_app.sh

# Keep current marketing version and bump build number only
./build_app.sh current

# Build with a dedicated date version
./build_app.sh dedicated-version 2026.4.9
```

### 3. Create DMG

```bash
./create_dmg.sh
```

This creates `dmg_output/SessionFlow-YYYY.M.D.dmg`.

### 4. Commit Version Changes

```bash
git add SessionFlow.xcodeproj/project.pbxproj CHANGELOG.md
git commit -m "chore: bump version to YYYY.M.D"
```

### 5. Create and Push Tag

```bash
# Create annotated tag
git tag -a vYYYY.M.D -m "Release version YYYY.M.D"

# Push commits and tag
git push origin main
git push origin vYYYY.M.D
```

Optional same-day rebuild tag:

```bash
git tag -a vYYYY.M.D-2 -m "Release version YYYY.M.D (build BUILD)"
git push origin vYYYY.M.D-2
```

### 6. Wait for GitHub Actions

Once you push the tag, GitHub Actions will:
- Build the app
- Create DMG and ZIP archives
- Generate release notes from CHANGELOG.md
- Create a GitHub Release with artifacts

Monitor progress at: `https://github.com/kibermaks/SessionFlow/actions`

## GitHub Actions Workflow

### Automated Build Workflow

File: `.github/workflows/release.yml`

**Triggers:**
- Push of tag matching `v*.*` (e.g., `v2026.4.9` or `v2026.4.9-2`)
- Manual workflow dispatch (for custom builds)

**What it does:**
1. Checks out code
2. Sets up Xcode 15.4
3. Extracts version from tag
4. Updates project version
5. Builds Release configuration
6. Creates DMG installer
7. Creates ZIP archive
8. Extracts changelog for this version
9. Creates GitHub Release with artifacts

**Artifacts:**
- `SessionFlow-YYYY.M.D.dmg` - DMG installer
- `SessionFlow-YYYY.M.D.zip` - ZIP archive

### Build Check Workflow

File: `.github/workflows/build.yml`

**Triggers:**
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`

**What it does:**
- Builds app to ensure no compilation errors
- Runs on every push/PR for continuous validation

## Post-Release Tasks

After GitHub Actions completes the release:

### 1. Review GitHub Release

1. Go to: `https://github.com/kibermaks/SessionFlow/releases`
2. Find the newly created release
3. Review the auto-generated release notes
4. Edit if needed to add:
   - Highlights of major features
   - Breaking changes (if any)
   - Known issues
   - Upgrade instructions

### 2. Test Released Artifacts

Download and test the DMG:
1. Download `SessionFlow-YYYY.M.D.dmg` from the release
2. Mount and install the app
3. Launch and verify it works correctly
4. Check version number in app header

### 3. Announce the Release

Share the release with users:
- Update project website (if applicable)
- Post on social media
- Notify mailing list/Discord/Slack
- Create blog post for major releases

### 4. Update Documentation

If the release includes new features:
- Update screenshots in README
- Update wiki/documentation site
- Update FAQ if needed

## Troubleshooting

### Build Fails in GitHub Actions

**Problem**: Xcode build fails in CI

**Solutions:**
- Check the Actions log for specific errors
- Ensure project.pbxproj is valid
- Verify code compiles locally with Xcode 15.4
- Check for missing files or broken references

### DMG Creation Fails

**Problem**: `create_dmg.sh` fails

**Solutions:**
- Ensure app was built successfully first
- Check that `SessionFlow.app` exists in `./` or `./build_output/`
- Verify disk space is available
- Check permissions on temp directories

### Wrong Version in Release

**Problem**: Released version doesn't match expected version

**Solutions:**
- Verify tag name matches desired version (e.g., `v2026.4.9`)
- Check that project.pbxproj was committed with updated version
- Ensure build script updated version correctly

### Release Notes Missing

**Problem**: Release notes are empty or incomplete

**Solutions:**
- Ensure CHANGELOG.md has section for this version
- Check section format: `## [YYYY.M.D] - YYYY-MM-DD`
- Verify changelog was committed before tagging
- Can manually edit GitHub Release after creation

### Can't Push Tag

**Problem**: `git push origin vYYYY.M.D` fails

**Solutions:**
```bash
# Check if tag already exists
git tag -l

# Delete local tag if needed
git tag -d vYYYY.M.D

# Delete remote tag if needed
git push origin :refs/tags/vYYYY.M.D

# Create new tag
git tag -a vYYYY.M.D -m "Release version YYYY.M.D"

# Push again
git push origin vYYYY.M.D
```

## Version Numbering Guide

SessionFlow uses date-based marketing versions in the format `YYYY.M.D`.

### Marketing Version
Use:
- Today's date for normal releases
- A custom date only when you need to reproduce or backfill a release tag

Example: `2026.4.9`

### Build Number
Auto-incremented for every build:
- Bug fixes
- Performance improvements
- Documentation updates
- Minor UI tweaks
- Multiple builds on the same date

Example: `2026.4.9 (build 42) → 2026.4.9 (build 43)`

### Optional Same-Day Release Tag
For a second release on the same marketing version, you can optionally create a build-qualified tag:

Examples: `v2026.4.9-2`, `v2026.4.9-3`

This keeps the app version at `2026.4.9`, but gives GitHub and the updater a unique external release identifier. The actual app build number still comes from `CFBundleVersion`.

## Release Frequency

Recommended release schedule:

- **Date releases**: whenever a release is ready
- **Same-day rebuilds**: use the same marketing version with a higher build number

## Beta/Pre-releases

For beta testing:

1. Create tag with `-beta` suffix: `v2026.4.9-beta.1`
2. GitHub Actions will build normally
3. Manually mark as "Pre-release" in GitHub
4. Distribute to beta testers

## Hotfix Process

For urgent bug fixes:

1. Create hotfix branch from main
2. Fix the bug
3. Test thoroughly
4. Merge to main
5. Follow normal release process using today's date or `current` for same-day rebuilds
6. Clearly mark as "Hotfix" in release notes

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Keep a Changelog](https://keepachangelog.com/)
- [Creating Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

---

Questions about the release process? Open a [GitHub Discussion](https://github.com/kibermaks/SessionFlow/discussions).
