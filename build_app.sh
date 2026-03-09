#!/bin/bash
set -e

# Start timer
BUILD_START_TIME=$(date +%s)

# Configuration
SCHEME="SessionFlow"
PROJECT="SessionFlow.xcodeproj"
BUILD_DIR="./build_output"
# Team ID found in project.pbxproj
TEAM_ID="RGFAX8X946"

# Function to get current marketing version directly from project file
get_version() {
    grep "MARKETING_VERSION =" "$PROJECT/project.pbxproj" | head -n 1 | sed 's/.*= //;s/;//' | tr -d '[:space:]'
}

# Function to set marketing version directly in project file
set_version() {
    local new_ver="$1"
    # Update all MARKETING_VERSION entries in project.pbxproj
    sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $new_ver;/g" "$PROJECT/project.pbxproj"
}

# Function to get current build number from project file
get_build_number() {
    grep "CURRENT_PROJECT_VERSION =" "$PROJECT/project.pbxproj" | head -n 1 | sed 's/.*= //;s/;//' | tr -d '[:space:]'
}

# Function to set build number directly in project file
set_build_number() {
    local new_build="$1"
    sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $new_build;/g" "$PROJECT/project.pbxproj"
}

# Parse flags
INCREMENT_TYPE="patch"
FORCED_VERSION=""
RELEASE_BUILD=false

ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "--release" ]]; then
        RELEASE_BUILD=true
    else
        ARGS+=("$arg")
    fi
done

if [[ "${ARGS[0]}" == "major" ]]; then
    INCREMENT_TYPE="major"
elif [[ "${ARGS[0]}" == "minor" ]]; then
    INCREMENT_TYPE="minor"
elif [[ "${ARGS[0]}" == "version" && -n "${ARGS[1]}" ]]; then
    # Validate version format (e.g., 1.4, 2.0, 10.12)
    if [[ "${ARGS[1]}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        INCREMENT_TYPE="forced"
        FORCED_VERSION="${ARGS[1]}"
    else
        echo "❌ Invalid version format. Use: ./build_app.sh version X.Y (e.g., version 1.4)"
        exit 1
    fi
fi

if [ "$RELEASE_BUILD" = true ]; then
    echo "📋 Preparing RELEASE build ($INCREMENT_TYPE increment)..."
else
    echo "📋 Preparing to build ($INCREMENT_TYPE increment)..."
fi
if [ "$INCREMENT_TYPE" == "forced" ]; then
    echo "   Forcing version $FORCED_VERSION"
fi

# 0. Clean Build Directory
if [ -d "$BUILD_DIR" ]; then
    echo "🧹 Cleaning previous build artifacts..."
    rm -rf "$BUILD_DIR"
fi

# 1. Get Current Version
CURRENT_VERSION=$(get_version)
if [ -z "$CURRENT_VERSION" ]; then
    echo "⚠️  Could not detect current version. Defaulting to 1.0"
    CURRENT_VERSION="1.0"
fi
echo "   Current Version: $CURRENT_VERSION"

# 2. Calculate New Version
IFS='.' read -r -a parts <<< "$CURRENT_VERSION"
major="${parts[0]:-1}"
minor="${parts[1]:-0}"

NEW_VERSION="$CURRENT_VERSION"
VERSION_CHANGED=false

if [ "$INCREMENT_TYPE" == "forced" ]; then
    NEW_VERSION="$FORCED_VERSION"
    if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
        VERSION_CHANGED=true
    fi
elif [ "$INCREMENT_TYPE" == "major" ]; then
    major=$((major + 1))
    minor=0
    NEW_VERSION="$major.$minor"
    VERSION_CHANGED=true
elif [ "$INCREMENT_TYPE" == "minor" ]; then
    minor=$((minor + 1))
    NEW_VERSION="$major.$minor"
    VERSION_CHANGED=true
else
    # Patch increment: we stay on the same marketing version
    # but we will increment the build number below.
    NEW_VERSION="$CURRENT_VERSION"
fi

if [ "$VERSION_CHANGED" = true ]; then
    echo "   New Version:     $NEW_VERSION"
    echo "🔧 Updating Project Version..."
    set_version "$NEW_VERSION"
    echo "   ✓ Updated MARKETING_VERSION in project.pbxproj"
else
    echo "   Version remains: $NEW_VERSION"
fi

# 4. Increment Build Number (Project Version)
echo "🔧 Incrementing Build Number..."
CURRENT_BUILD=$(get_build_number)
NEW_BUILD_NUMBER=$((CURRENT_BUILD + 1))
set_build_number "$NEW_BUILD_NUMBER"
echo "   New Build Number: $NEW_BUILD_NUMBER"

# 5. Build
if [ "$RELEASE_BUILD" = true ]; then
    BUILD_CONFIG="Release"
else
    BUILD_CONFIG="Debug"
fi
echo "🚀 Starting $BUILD_CONFIG Build for $SCHEME..."

xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration "$BUILD_CONFIG" \
           -destination 'platform=macOS,arch=arm64' \
           clean build \
           DEVELOPMENT_TEAM="$TEAM_ID" \
           CODE_SIGN_STYLE="Automatic" \
           CODE_SIGNING_REQUIRED="YES" \
           CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
           MARKETING_VERSION="$NEW_VERSION" \
           CURRENT_PROJECT_VERSION="$NEW_BUILD_NUMBER" \
           -quiet

# 6. Copy Artifact
APP_PATH=$(find "$BUILD_DIR" -maxdepth 1 -name "*.app" | head -n 1)

if [ -n "$APP_PATH" ]; then
    APP_NAME=$(basename "$APP_PATH")
    echo "✅ Build successful! Found $APP_NAME"
    
    # Kill if running
    APP_PROCESS_NAME="${APP_NAME%.app}"
    if pgrep -x "$APP_PROCESS_NAME" > /dev/null 2>&1; then
        echo "🔪 Stopping running instance of $APP_PROCESS_NAME..."
        killall "$APP_PROCESS_NAME" 2>/dev/null || true
        sleep 0.5
    fi
    
    if [ -d "./$APP_NAME" ]; then
        rm -rf "./$APP_NAME"
    fi
    
    cp -R "$APP_PATH" "./$APP_NAME"
    touch "./$APP_NAME"

    # Re-sign with Developer ID for distribution (--release flag)
    if [ "$RELEASE_BUILD" = true ]; then
        echo "🔏 Re-signing with Developer ID (hardened runtime + timestamp)..."

        # Create release entitlements (extract current, strip get-task-allow)
        RELEASE_ENT=$(mktemp /tmp/release-ent-XXXXXXXX).plist
        codesign -d --entitlements "$RELEASE_ENT" --xml "./$APP_NAME" 2>/dev/null
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$RELEASE_ENT" 2>/dev/null || true

        codesign --deep --force --options runtime --timestamp \
            --sign "Developer ID Application: MaksymTW Grigorash ($TEAM_ID)" \
            --entitlements "$RELEASE_ENT" \
            "./$APP_NAME"
        rm -f "$RELEASE_ENT"
        echo "   ✓ Signed for distribution"
    fi

    # Calculate build duration
    BUILD_END_TIME=$(date +%s)
    BUILD_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))
    BUILD_MINUTES=$((BUILD_DURATION / 60))
    BUILD_SECONDS=$((BUILD_DURATION % 60))
    
    if [ $BUILD_MINUTES -gt 0 ]; then
        DURATION_STR="${BUILD_MINUTES}m ${BUILD_SECONDS}s"
    else
        DURATION_STR="${BUILD_SECONDS}s"
    fi
    
    CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")

    echo "🎉 Done! version $NEW_VERSION (build $NEW_BUILD_NUMBER) is ready in this folder."
    echo "⏱️ [$CURRENT_TIME] Build completed in $DURATION_STR"
    open "./$APP_NAME"
else
    echo "❌ [$CURRENT_TIME] Build failed. Could not find .app."
    exit 1
fi
