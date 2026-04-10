# Quick Start Guide for Developers

A cheat sheet for common development tasks with SessionFlow.

## 🚀 Common Commands

### Development

```bash
# Open in Xcode
open SessionFlow.xcodeproj

# Build and run locally
./build_app.sh

# Build and deploy to Applications
./build_app.sh && ./deploy_app.sh

# Build with specific date version behavior
./build_app.sh                # Use today's date version
./build_app.sh current        # Keep current marketing version
./build_app.sh dedicated-version 2026.4.9
```

### Distribution

```bash
# Create DMG installer
./create_dmg.sh

# Full release process (interactive)
./release.sh
```

### Git Operations

```bash
# Check status
git status

# Create release tag
git tag -a v2026.4.9 -m "Release version 2026.4.9"
git push origin v2026.4.9

# Optional same-day rebuild tag
git tag -a v2026.4.9-2 -m "Release version 2026.4.9 (build 790)"
git push origin v2026.4.9-2

# List all tags
git tag -l
```

## 📁 Important Files

| File | Purpose |
|------|---------|
| `README.md` | Main project documentation |
| `CONTRIBUTING.md` | Contribution guidelines |
| `CHANGELOG.md` | Version history and changes |
| `Agents.md` | Critical info for AI agents/developers |
| `RELEASE_PROCESS.md` | Detailed release instructions |
| `LICENSE` | MIT License |
| `.github/workflows/` | GitHub Actions CI/CD |

## 🏗️ Project Structure

```code
SessionFlow/
├── SessionFlow/              # Main source code
│   ├── Models/                 # Data models
│   ├── Services/               # Business logic
│   ├── Views/                  # SwiftUI views
│   └── Assets.xcassets/        # Images/icons
│
├── SessionFlow.xcodeproj/    # Xcode project
├── build_app.sh               # Build script
├── deploy_app.sh              # Deployment script
├── create_dmg.sh              # DMG creation script
└── release.sh                 # Release automation
```

## 🔧 Development Workflow

### 1. Start New Feature

```bash
git checkout -b feature/my-feature
# Make changes in Xcode
```

### 2. Test Changes

```bash
./build_app.sh
# Test the built app
```

### 3. Commit Changes

```bash
git add .
git commit -m "feat: add my new feature"
```

### 4. Create Pull Request

```bash
git push origin feature/my-feature
# Open PR on GitHub
```

## 📦 Release Workflow

### Quick Release

```bash
./release.sh
# Follow interactive prompts
```

### Manual Release

```bash
# 1. Update CHANGELOG.md

# 2. Build
./build_app.sh

# 3. Create DMG
./create_dmg.sh

# 4. Commit and tag
git add .
git commit -m "chore: bump version to 2026.4.9"
git tag -a v2026.4.9 -m "Release version 2026.4.9"

# 5. Push
git push origin main
git push origin v2026.4.9

# GitHub Actions will handle the rest!
```

## 🐛 Common Issues

### "Build Failed" in Xcode

**Solution**: Clean build folder

- Xcode → Product → Clean Build Folder (Cmd+Shift+K)
- Delete `build_output/` directory
- Try building again

### "Code Signing Failed"

**Solution**: Build script handles signing automatically

- Use `./build_app.sh` instead of Xcode's build
- Or set Code Signing to "Sign to Run Locally" in Xcode

### "App Won't Launch" after install

**Solution**: Remove quarantine attribute

```bash
xattr -cr "/Applications/SessionFlow.app"
```

### New Swift File Not Building

**Problem**: Added file but Xcode doesn't see it

**Solution**: Must update `project.pbxproj` (see Agents.md)

- Or use Xcode: File → Add Files to "SessionFlow"

## 💡 Tips & Tricks

### Preview GitHub Actions Locally

```bash
# Install act: brew install act
act -l  # List workflows
act push -n  # Dry run
```

### Find Build Output

```bash
# Built app location
ls -la ./SessionFlow.app
ls -la ./build_output/

# DMG location
ls -la ./dmg_output/
```

## 📚 Documentation Links

- **For New Contributors**: Start with [CONTRIBUTING.md](CONTRIBUTING.md)
- **For Releases**: See [RELEASE_PROCESS.md](RELEASE_PROCESS.md)
- **For Architecture**: Check [README.md](README.md#-architecture--key-elements)
- **For AI Agents**: Read [Agents.md](Agents.md) FIRST

## 🔗 Useful GitHub URLs

Replace `kibermaks` with your GitHub username:

- **Repository**: `https://github.com/kibermaks/SessionFlow`
- **Issues**: `https://github.com/kibermaks/SessionFlow/issues`
- **Actions**: `https://github.com/kibermaks/SessionFlow/actions`
- **Releases**: `https://github.com/kibermaks/SessionFlow/releases`
- **Discussions**: `https://github.com/kibermaks/SessionFlow/discussions`

## 🎯 Next Steps

### First Time Setup

1. Clone the repo
2. Open in Xcode
3. Build with `./build_app.sh`
4. Read [CONTRIBUTING.md](CONTRIBUTING.md)
5. Check out [Issues](https://github.com/kibermaks/SessionFlow/issues) for good first issues

### Making Your First Contribution

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Update documentation
6. Submit a pull request

### Creating Your First Release

1. Update CHANGELOG.md
2. Run `./release.sh`
3. Follow the prompts
4. Wait for GitHub Actions
5. Announce the release!

---

**Need Help?**

- Check the [documentation](#-documentation-links)
- Open a [GitHub Discussion](https://github.com/kibermaks/SessionFlow/discussions)
- Read [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines
