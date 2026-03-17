---
name: release
description: Automate the SessionFlow release process - bump version, update changelog, build, create DMG, commit, tag, and push
disable-model-invocation: true
---

# Release Workflow

Automate the full SessionFlow release process. Usage: `/release [patch|minor|major]` (defaults to patch).

## Steps

1. **Parse version type** from arguments (default: `patch`)

2. **Check working tree is clean**:
   ```bash
   git status --porcelain
   ```
   If dirty, ask user to commit or stash first.

3. **Read current version** from project.pbxproj (MARKETING_VERSION)

4. **Update CHANGELOG.md**:
   - Read `git log` since last tag to summarize changes
   - Add a new version section under `[Unreleased]`
   - Follow CHANGELOG guidelines from CLAUDE.md:
     - Order bullets by importance
     - Don't list sub-features when parent is new in same version
     - Keep entries concise

5. **Build the app**:
   ```bash
   ./build_app.sh [patch|minor|major]
   ```

6. **Create DMG**:
   ```bash
   ./create_dmg.sh
   ```

7. **Read the new version** from build output

8. **Commit, tag, and push**:
   ```bash
   git add -A
   git commit -m "release: v{VERSION}"
   git tag v{VERSION}
   git push && git push --tags
   ```

9. **Create GitHub release**:
   ```bash
   gh release create v{VERSION} \
     --title "v{VERSION}" \
     --notes-file <(changelog section) \
     SessionFlow-{VERSION}.dmg \
     SessionFlow-{VERSION}.zip
   ```

10. **Report** the release URL to the user.
