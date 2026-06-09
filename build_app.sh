#!/bin/bash
set -e

# Repository-wide build mutex. This protects DerivedData cleanup, build number
# updates, and app bundle copy when multiple agent chats build at once.
LOCK_FILE=".agent-build.lock"
BUILD_LOCK_ACQUIRED=false

is_ancestor_pid() {
    local candidate="$1"
    local pid="$$"

    while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
        if [ "$pid" = "$candidate" ]; then
            return 0
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
    done

    return 1
}

release_build_lock() {
    if [ "$BUILD_LOCK_ACQUIRED" = true ]; then
        rm -f "$LOCK_FILE"
    fi
}

acquire_build_lock() {
    local command="./build_app.sh $*"

    while true; do
        if ( set -o noclobber; printf 'pid=%s\nstarted=%s\ncmd=%s\nnote=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$command" "build_app.sh self-lock" > "$LOCK_FILE" ) 2>/dev/null; then
            BUILD_LOCK_ACQUIRED=true
            trap release_build_lock EXIT
            return 0
        fi

        local existing_pid
        existing_pid=$(awk -F= '/^pid=/{print $2; exit}' "$LOCK_FILE" 2>/dev/null | tr -d '[:space:]' || true)

        if [ -n "$existing_pid" ] && is_ancestor_pid "$existing_pid"; then
            echo "🔒 Using inherited build lock held by parent PID $existing_pid"
            return 0
        fi

        if [ -n "$existing_pid" ] && ps -p "$existing_pid" >/dev/null 2>&1; then
            echo "⏳ Waiting for active build lock held by PID $existing_pid..."
            sleep 10
            continue
        fi

        echo "🧹 Removing stale build lock${existing_pid:+ held by PID $existing_pid}..."
        rm -f "$LOCK_FILE"
    done
}

acquire_build_lock "$@"

# Start timer
BUILD_START_TIME=$(date +%s)

# Configuration
SCHEME="SessionFlow"
PROJECT="SessionFlow.xcodeproj"
BUILD_DIR="./build_output"
DERIVED_DATA_DIR="./build_derived_data"
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
VERSION_MODE="today"
FORCED_VERSION=""
RELEASE_BUILD=false

today_version() {
    date +%Y.%-m.%-d
}

is_valid_date_version() {
    local version="$1"
    if [[ ! "$version" =~ ^([0-9]{4})\.([0-9]{1,2})\.([0-9]{1,2})$ ]]; then
        return 1
    fi

    local year="${BASH_REMATCH[1]}"
    local month="${BASH_REMATCH[2]}"
    local day="${BASH_REMATCH[3]}"

    if (( year < 2000 || year > 9999 )); then
        return 1
    fi
    if (( month < 1 || month > 12 )); then
        return 1
    fi
    if (( day < 1 || day > 31 )); then
        return 1
    fi

    return 0
}

ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "--release" ]]; then
        RELEASE_BUILD=true
    else
        ARGS+=("$arg")
    fi
done

if [[ "${ARGS[0]}" == "current" ]]; then
    VERSION_MODE="current"
elif [[ ( "${ARGS[0]}" == "version" || "${ARGS[0]}" == "dedicated-version" ) && -n "${ARGS[1]}" ]]; then
    if is_valid_date_version "${ARGS[1]}"; then
        VERSION_MODE="forced"
        FORCED_VERSION="${ARGS[1]}"
    else
        echo "❌ Invalid version format. Use: ./build_app.sh dedicated-version YYYY.M.D (e.g., 2026.4.9)"
        exit 1
    fi
elif [[ -n "${ARGS[0]}" ]]; then
    echo "❌ Unknown argument: ${ARGS[0]}"
    echo "   Usage:"
    echo "     ./build_app.sh                 # set marketing version to today and bump build"
    echo "     ./build_app.sh current         # keep current marketing version and bump build"
    echo "     ./build_app.sh dedicated-version YYYY.M.D   # set explicit marketing version and bump build"
    exit 1
fi

if [ "$RELEASE_BUILD" = true ]; then
    echo "📋 Preparing RELEASE build ($VERSION_MODE mode)..."
else
    echo "📋 Preparing to build ($VERSION_MODE mode)..."
fi
if [ "$VERSION_MODE" == "forced" ]; then
    echo "   Forcing version $FORCED_VERSION"
fi

# 0. Clean Build Directory
if [ -d "$BUILD_DIR" ]; then
    echo "🧹 Cleaning previous build artifacts..."
    rm -rf "$BUILD_DIR"
fi
if [ -d "$DERIVED_DATA_DIR" ]; then
    rm -rf "$DERIVED_DATA_DIR"
fi

# 1. Compute Today's Version
TODAY_VERSION=$(today_version)

# 1. Get Current Version
CURRENT_VERSION=$(get_version)
if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="$TODAY_VERSION"
    echo "⚠️  Could not detect current version. Defaulting to $CURRENT_VERSION"
fi
echo "   Current Version: $CURRENT_VERSION"

# 2. Calculate New Version
NEW_VERSION="$CURRENT_VERSION"
VERSION_CHANGED=false

if [ "$VERSION_MODE" == "forced" ]; then
    NEW_VERSION="$FORCED_VERSION"
elif [ "$VERSION_MODE" == "today" ]; then
    NEW_VERSION="$TODAY_VERSION"
fi

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    VERSION_CHANGED=true
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

# SWIFT_ENABLE_EXPLICIT_MODULES=NO: the universal (x86_64) slice of the transitive
# swift-nio dependency (pulled in by the MCP SDK via EventSource) fails to resolve
# modules under explicit modules. The x86_64 package graph also needs a warm-up
# build before the combined universal build after a clean.
COMMON_XCODEBUILD_ARGS=(
    -project "$PROJECT"
    -scheme "$SCHEME"
    -configuration "$BUILD_CONFIG"
    -destination 'generic/platform=macOS'
    -derivedDataPath "$DERIVED_DATA_DIR"
    ONLY_ACTIVE_ARCH=NO
    SWIFT_ENABLE_EXPLICIT_MODULES=NO
    DEVELOPMENT_TEAM="$TEAM_ID"
    CODE_SIGN_STYLE="Automatic"
    CODE_SIGNING_REQUIRED="YES"
    MARKETING_VERSION="$NEW_VERSION"
    CURRENT_PROJECT_VERSION="$NEW_BUILD_NUMBER"
)

xcodebuild "${COMMON_XCODEBUILD_ARGS[@]}" clean -quiet

echo "   Warming x86_64 package build..."
xcodebuild "${COMMON_XCODEBUILD_ARGS[@]}" ARCHS='x86_64' build -quiet

xcodebuild "${COMMON_XCODEBUILD_ARGS[@]}" ARCHS='arm64 x86_64' build -quiet

# 6. Copy Artifact
APP_PATH="$DERIVED_DATA_DIR/Build/Products/$BUILD_CONFIG/$SCHEME.app"

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

    # Release builds go to ./release/ to avoid being overwritten by debug builds
    if [ "$RELEASE_BUILD" = true ]; then
        OUTPUT_DIR="./release"
        mkdir -p "$OUTPUT_DIR"
    else
        OUTPUT_DIR="."
    fi

    if [ -d "$OUTPUT_DIR/$APP_NAME" ]; then
        rm -rf "$OUTPUT_DIR/$APP_NAME"
    fi

    cp -R "$APP_PATH" "$OUTPUT_DIR/$APP_NAME"
    touch "$OUTPUT_DIR/$APP_NAME"

    # Re-sign with Developer ID for distribution (--release flag)
    if [ "$RELEASE_BUILD" = true ]; then
        echo "🔏 Re-signing with Developer ID (hardened runtime + timestamp)..."

        # Create release entitlements (extract current, strip get-task-allow)
        RELEASE_ENT=$(mktemp /tmp/release-ent-XXXXXXXX).plist
        codesign -d --entitlements "$RELEASE_ENT" --xml "$OUTPUT_DIR/$APP_NAME" 2>/dev/null
        /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$RELEASE_ENT" 2>/dev/null || true

        codesign --deep --force --options runtime --timestamp \
            --sign "Developer ID Application: MaksymTW Grigorash ($TEAM_ID)" \
            --entitlements "$RELEASE_ENT" \
            "$OUTPUT_DIR/$APP_NAME"
        rm -f "$RELEASE_ENT"
        echo "   ✓ Signed for distribution"
    fi

    # The derived data directory is only a scratch location for this script.
    rm -rf "$DERIVED_DATA_DIR"

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

    echo "🎉 Done! version $NEW_VERSION (build $NEW_BUILD_NUMBER) is ready in $OUTPUT_DIR/"
    echo "⏱️ [$CURRENT_TIME] Build completed in $DURATION_STR"
    if [ "$RELEASE_BUILD" = false ]; then
        open "$OUTPUT_DIR/$APP_NAME"
    fi
else
    echo "❌ [$CURRENT_TIME] Build failed. Could not find .app."
    exit 1
fi
