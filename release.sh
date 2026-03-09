#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🚀 SessionFlow Release Helper${NC}"
echo ""

generate_release_notes() {
    local version="$1"
    local output_file="$2"
    local changelog=""
    local version_regex
    version_regex=$(printf '%s\n' "$version" | sed 's/[][(){}?+.^$\\|]/\\&/g')

    if [ -f "CHANGELOG.md" ]; then
        changelog=$(sed -n "/## \\[$version_regex\\]/,/## \\[/p" CHANGELOG.md | sed '$d')
        if [ -z "$changelog" ]; then
            changelog=$(sed -n "/## \\[Unreleased\\]/,/## \\[/p" CHANGELOG.md | sed '$d')
        fi
    fi

    if [ -z "$changelog" ]; then
        changelog="Release v$version\n\nSee CHANGELOG.md for full details."
    fi

    printf "%s\n" "$changelog" > "$output_file"
}

get_version() {
    grep "MARKETING_VERSION =" "SessionFlow.xcodeproj/project.pbxproj" | head -n 1 | sed 's/.*= //;s/;//' | tr -d '[:space:]'
}

if [[ -n $(git status -s) ]]; then
    echo -e "${YELLOW}⚠️  Warning: You have uncommitted changes.${NC}"
    echo "It's recommended to commit all changes before creating a release."
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

CURRENT_VERSION=$(get_version)
echo -e "Current version: ${GREEN}$CURRENT_VERSION${NC}"
echo ""

echo "What type of release is this?"
echo "  1) Major (breaking changes) - ${CURRENT_VERSION} → $(echo $CURRENT_VERSION | awk -F. '{print $1+1".0"}')"
echo "  2) Minor (new features) - ${CURRENT_VERSION} → $(echo $CURRENT_VERSION | awk -F. '{print $1"."$2+1}')"
echo "  3) Patch (bug fixes) - ${CURRENT_VERSION} → ${CURRENT_VERSION} (build number only)"
echo "  4) Custom version"
echo ""
read -p "Enter choice (1-4): " CHOICE

case $CHOICE in
    1)
        INCREMENT="major"
        ;;
    2)
        INCREMENT="minor"
        ;;
    3)
        INCREMENT="patch"
        ;;
    4)
        read -p "Enter new version (e.g., 1.5): " CUSTOM_VERSION
        INCREMENT="version $CUSTOM_VERSION"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}📝 Pre-release Checklist${NC}"
echo ""
echo "Before proceeding, ensure you have:"
echo "  ☐ Updated CHANGELOG.md with changes for this release"
echo "  ☐ Tested the app thoroughly"
echo "  ☐ Updated documentation if needed"
echo "  ☐ Committed all changes to git"
echo ""
read -p "Have you completed the checklist above? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please complete the checklist and try again."
    exit 1
fi

# Build the app
echo ""
echo -e "${BLUE}🔨 Building app...${NC}"
./build_app.sh --release $INCREMENT

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

NEW_VERSION=$(get_version)
DMG_FILENAME="SessionFlow-$NEW_VERSION.dmg"
DMG_PATH="dmg_output/$DMG_FILENAME"
ZIP_FILENAME="SessionFlow-v$NEW_VERSION.zip"
ZIP_PATH="$ZIP_FILENAME"
echo ""
echo -e "${GREEN}✅ Built version $NEW_VERSION${NC}"

# Notarize the .app
echo ""
echo -e "${BLUE}🔏 Notarizing app...${NC}"
./notarize.sh "SessionFlow.app"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ App notarization failed!${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📦 Creating DMG...${NC}"
./create_dmg.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ DMG creation failed!${NC}"
    exit 1
fi

# Notarize the DMG
echo ""
echo -e "${BLUE}🔏 Notarizing DMG...${NC}"
./notarize.sh "$DMG_PATH"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ DMG notarization failed!${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}🗜  Creating ZIP archive...${NC}"
if [ ! -d "SessionFlow.app" ]; then
    echo -e "${RED}❌ 'SessionFlow.app' not found in project root. Cannot create ZIP.${NC}"
    exit 1
fi
if [ -f "$ZIP_PATH" ]; then
    rm -f "$ZIP_PATH"
fi
zip -r "$ZIP_PATH" "SessionFlow.app" -q
echo -e "${GREEN}✅ ZIP created: $ZIP_PATH${NC}"

echo ""
echo -e "${GREEN}✅ Release artifacts created (signed & notarized)!${NC}"
echo ""
echo "The following files are ready:"
ls -lh "$DMG_PATH" 2>/dev/null || echo "  (DMG not found)"
ls -lh "$ZIP_PATH" 2>/dev/null || echo "  (ZIP not found)"
echo ""

echo -e "${BLUE}📚 Git Operations${NC}"
echo ""
read -p "Create git commit for version $NEW_VERSION? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    git add SessionFlow.xcodeproj/project.pbxproj
    git commit -m "chore: bump version to $NEW_VERSION"
    echo -e "${GREEN}✅ Git commit created${NC}"
fi

read -p "Create and push git tag v$NEW_VERSION? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    git tag -a "v$NEW_VERSION" -m "Release version $NEW_VERSION"
    
    read -p "Push to remote? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        git push origin main
        git push origin "v$NEW_VERSION"
        echo -e "${GREEN}✅ Pushed to remote${NC}"
    fi
fi

echo ""
if [ -f "$DMG_PATH" ] && [ -f "$ZIP_PATH" ]; then
    if command -v gh >/dev/null 2>&1; then
        echo -e "${BLUE}☁️ Publish GitHub Release${NC}"
        read -p "Upload local DMG/ZIP to GitHub release now? (Y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            NOTES_FILE=$(mktemp /tmp/sessionflow_release_notes.XXXXXX)
            generate_release_notes "$NEW_VERSION" "$NOTES_FILE"
            RELEASE_TAG="v$NEW_VERSION"
            if gh release create "$RELEASE_TAG" "$DMG_PATH" "$ZIP_PATH" --title "SessionFlow $RELEASE_TAG" --notes-file "$NOTES_FILE" --verify-tag; then
                echo -e "${GREEN}✅ GitHub release published with local artifacts${NC}"
            else
                echo -e "${RED}❌ Failed to publish GitHub release via gh.${NC}"
            fi
            rm -f "$NOTES_FILE"
        else
            echo "Skipping GitHub release upload."
        fi
    else
        echo -e "${YELLOW}⚠️  GitHub CLI (gh) not found. Install it to upload releases automatically.${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Missing DMG or ZIP artifacts; cannot upload release automatically.${NC}"
fi

echo ""
echo -e "${BLUE}📋 Next Steps${NC}"
echo ""
echo "1. Verify the GitHub release (if uploaded automatically)."
echo "2. If you skipped uploading, run 'gh release create v$NEW_VERSION $DMG_PATH $ZIP_PATH --notes \"...\"'."
echo "3. Announce the release to users."
echo ""
echo -e "${GREEN}🎉 Release process complete!${NC}"
