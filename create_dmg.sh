#!/bin/bash
set -e

# Configuration (overridable via env vars for CI/local parity)
APP_NAME="${APP_NAME_OVERRIDE:-SessionFlow}"
APP_FILE="${APP_FILE_OVERRIDE:-$APP_NAME.app}"
DMG_NAME="${DMG_NAME_OVERRIDE:-SessionFlow}"
SOURCE_APP="${APP_SOURCE_OVERRIDE:-./$APP_FILE}"
BUILD_DIR="${BUILD_DIR_OVERRIDE:-./build_output}"
DMG_DIR="${DMG_DIR_OVERRIDE:-./dmg_output}"
VOLUME_NAME="${DMG_VOLUME_NAME_OVERRIDE:-SessionFlow Installer}"
#
# DMG visuals
# Finder AppleScript cannot "draw" an arbitrary overlay at coordinates.
# The only supported options are:
# - set a window background picture, OR
# - position actual items (files/folders) as icons.
#
# We use a background picture that contains ONLY the arrow (transparent elsewhere).
BACKGROUND_FILE="${DMG_BACKGROUND_FILE_OVERRIDE:-dmg_background_arrow.tiff}"

# Layout tuning (overridable for quick iteration)
# Note: Finder window bounds are in screen points. Background pictures are anchored to the window;
# Finder typically centers them, but behavior can vary by macOS version.
#
# These defaults aim to place icons relative to the arrow artwork.
DMG_WINDOW_LEFT="${DMG_WINDOW_LEFT_OVERRIDE:-300}"
DMG_WINDOW_TOP="${DMG_WINDOW_TOP_OVERRIDE:-100}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH_OVERRIDE:-480}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT_OVERRIDE:-380}"
DMG_ICON_SIZE="${DMG_ICON_SIZE_OVERRIDE:-96}"

# Spacing between the two icons (center-to-center). Default gives a nice gap for the arrow.
DMG_ICON_SPACING="${DMG_ICON_SPACING_OVERRIDE:-200}"

# Arrow anchor (within the window). Icons will be placed to the left/right of this point.
# If your arrow artwork isn't centered, override these to match the arrow's actual center.
DMG_ARROW_Y_OFFSET="${DMG_ARROW_Y_OFFSET_OVERRIDE:-40}"
DMG_ARROW_CENTER_X_DEFAULT=$((DMG_WINDOW_WIDTH / 2))
DMG_ARROW_CENTER_Y_DEFAULT=$((DMG_WINDOW_HEIGHT / 2 - DMG_ARROW_Y_OFFSET))
DMG_ARROW_CENTER_X="${DMG_ARROW_CENTER_X_OVERRIDE:-$DMG_ARROW_CENTER_X_DEFAULT}"
DMG_ARROW_CENTER_Y="${DMG_ARROW_CENTER_Y_OVERRIDE:-$DMG_ARROW_CENTER_Y_DEFAULT}"

# Default icon positions derived from the arrow anchor.
DMG_DEFAULT_APP_POS_X=$((DMG_ARROW_CENTER_X - (DMG_ICON_SPACING / 2)))
DMG_DEFAULT_APPLICATIONS_POS_X=$((DMG_ARROW_CENTER_X + (DMG_ICON_SPACING / 2)))
DMG_DEFAULT_APP_POS_Y=$DMG_ARROW_CENTER_Y
DMG_DEFAULT_APPLICATIONS_POS_Y=$DMG_ARROW_CENTER_Y

# Icon positions within the window
DMG_APP_POS_X="${DMG_APP_POS_X_OVERRIDE:-$DMG_DEFAULT_APP_POS_X}"
DMG_APP_POS_Y="${DMG_APP_POS_Y_OVERRIDE:-$DMG_DEFAULT_APP_POS_Y}"
DMG_APPLICATIONS_POS_X="${DMG_APPLICATIONS_POS_X_OVERRIDE:-$DMG_DEFAULT_APPLICATIONS_POS_X}"
DMG_APPLICATIONS_POS_Y="${DMG_APPLICATIONS_POS_Y_OVERRIDE:-$DMG_DEFAULT_APPLICATIONS_POS_Y}"

DMG_WINDOW_RIGHT=$((DMG_WINDOW_LEFT + DMG_WINDOW_WIDTH))
DMG_WINDOW_BOTTOM=$((DMG_WINDOW_TOP + DMG_WINDOW_HEIGHT))
REPO_URL="${DMG_REPO_URL_OVERRIDE:-https://github.com/kibermaks/SessionFlow}"
INCLUDE_README="${DMG_INCLUDE_README_OVERRIDE:-false}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📦 Creating DMG for $APP_NAME...${NC}"

# Function to cleanup any stuck DMG mounts
cleanup_dmg_mounts() {
    echo -e "${BLUE}🧹 Cleaning up any stuck DMG mounts...${NC}"
    hdiutil detach "/Volumes/$VOLUME_NAME" -force 2>/dev/null || true
    pkill -9 diskimages-helper 2>/dev/null || true
    sleep 1
}

get_version() {
    grep "MARKETING_VERSION =" "SessionFlow.xcodeproj/project.pbxproj" | head -n 1 | sed 's/.*= //;s/;//' | tr -d '[:space:]'
}

get_build_number() {
    grep "CURRENT_PROJECT_VERSION =" "SessionFlow.xcodeproj/project.pbxproj" | head -n 1 | sed 's/.*= //;s/;//' | tr -d '[:space:]'
}

if [ ! -d "$SOURCE_APP" ]; then
    if [ -d "$BUILD_DIR/$APP_FILE" ]; then
        SOURCE_APP="$BUILD_DIR/$APP_FILE"
        echo -e "${YELLOW}ℹ️  Using app from build_output${NC}"
    else
        echo -e "${RED}❌ Error: $APP_FILE not found.${NC}"
        echo "   Please run ./build_app.sh first."
        exit 1
    fi
fi

VERSION="${DMG_VERSION_OVERRIDE:-$(get_version)}"
BUILD=$(get_build_number)

if [ -z "$VERSION" ]; then
    echo -e "${YELLOW}⚠️  Could not detect version. Using 'latest'${NC}"
    VERSION="latest"
fi

echo -e "   Version: ${GREEN}$VERSION${NC} (Build $BUILD)"

cleanup_dmg_mounts

if [ -d "$DMG_DIR" ]; then
    echo -e "${BLUE}🧹 Cleaning previous DMG artifacts...${NC}"
    rm -rf "$DMG_DIR"
fi
mkdir -p "$DMG_DIR"

TEMP_DMG_FOLDER="$DMG_DIR/temp_dmg"
mkdir -p "$TEMP_DMG_FOLDER"

echo -e "${BLUE}📋 Copying app bundle...${NC}"
cp -R "$SOURCE_APP" "$TEMP_DMG_FOLDER/$APP_FILE"

echo -e "${BLUE}🔗 Creating Applications shortcut...${NC}"
ln -s /Applications "$TEMP_DMG_FOLDER/Applications"

# Copy background (arrow-only) if it exists
if [ -f "$BACKGROUND_FILE" ]; then
    mkdir -p "$TEMP_DMG_FOLDER/.background"
    cp "$BACKGROUND_FILE" "$TEMP_DMG_FOLDER/.background/"
fi

INCLUDE_README_NORMALIZED=$(printf '%s' "$INCLUDE_README" | tr '[:upper:]' '[:lower:]')
if [ "$INCLUDE_README_NORMALIZED" = "true" ]; then
    cat > "$TEMP_DMG_FOLDER/README.txt" <<EOF
$APP_NAME - Installation Instructions
=====================================

To install $APP_NAME:

1. Drag "$APP_FILE" to the "Applications" folder
2. Open from Applications or Spotlight
3. Grant Calendar permissions when prompted
4. Start scheduling your productive day!

Requirements:
- macOS 13.0 or later
- Calendar access (requested on first launch)

For more information, visit:
$REPO_URL

---
$APP_NAME is open source software released under the MIT License.
EOF
fi

DMG_FILENAME="${DMG_FILENAME_OVERRIDE:-$DMG_NAME-$VERSION.dmg}"
DMG_PATH="$DMG_DIR/$DMG_FILENAME"

if [ -f "$DMG_PATH" ]; then
    rm "$DMG_PATH"
fi

echo -e "${BLUE}🎨 Creating DMG...${NC}"

TEMP_DMG="$DMG_DIR/temp.dmg"

hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$TEMP_DMG_FOLDER" \
    -ov \
    -format UDRW \
    "$TEMP_DMG" \
    > /dev/null

echo -e "${BLUE}🔧 Configuring DMG layout...${NC}"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse > /dev/null

# Set up the DMG window layout
osascript <<EOF > /dev/null 2>&1 || true
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set containerWindow to container window
        set current view of containerWindow to icon view
        set toolbar visible of containerWindow to false
        set statusbar visible of containerWindow to false
        set the bounds of containerWindow to {$DMG_WINDOW_LEFT, $DMG_WINDOW_TOP, $DMG_WINDOW_RIGHT, $DMG_WINDOW_BOTTOM}
        set viewOptions to the icon view options of containerWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to $DMG_ICON_SIZE
        if exists file ".background:$BACKGROUND_FILE" then
            set background picture of viewOptions to file ".background:$BACKGROUND_FILE"
        end if
        set position of item "$APP_FILE" of containerWindow to {$DMG_APP_POS_X, $DMG_APP_POS_Y}
        set position of item "Applications" of containerWindow to {$DMG_APPLICATIONS_POS_X, $DMG_APPLICATIONS_POS_Y}
        close containerWindow
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

echo -e "${BLUE}💾 Finalizing DMG...${NC}"
sync
hdiutil detach "$MOUNT_DIR" -force > /dev/null 2>&1 || true
sleep 2

hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    > /dev/null 2>&1

# Cleanup again just to be safe
cleanup_dmg_mounts

echo -e "${BLUE}🧹 Cleaning up...${NC}"
rm -rf "$TEMP_DMG_FOLDER"
rm "$TEMP_DMG"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo -e "${GREEN}✅ DMG created successfully!${NC}"
echo -e "   📍 Location: ${BLUE}$DMG_PATH${NC}"
echo -e "   📊 Size: ${YELLOW}$DMG_SIZE${NC}"
echo -e "   🏷️  Version: ${GREEN}$VERSION${NC} (Build $BUILD)"
echo ""
echo -e "${BLUE}🚀 Ready for distribution!${NC}"

if [ -z "${CI:-}" ] && command -v open &> /dev/null; then
    open "$DMG_DIR"
fi
