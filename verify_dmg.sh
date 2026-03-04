#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

DMG_PATH="$1"
if [ -z "$DMG_PATH" ]; then
    # Default to latest DMG in dmg_output
    DMG_PATH=$(ls -t dmg_output/*.dmg 2>/dev/null | head -1)
    if [ -z "$DMG_PATH" ]; then
        echo -e "${RED}Usage: ./verify_dmg.sh <path-to-dmg>${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}Verifying: $DMG_PATH${NC}"
echo ""

PASS=0
FAIL=0

check() {
    local label="$1"
    local result="$2"
    if [ $result -eq 0 ]; then
        echo -e "  ${GREEN}PASS${NC}  $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC}  $label"
        FAIL=$((FAIL + 1))
    fi
}

# 1. Mount the DMG
VOLUME=$(hdiutil attach "$DMG_PATH" -nobrowse 2>/dev/null | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
if [ -z "$VOLUME" ]; then
    echo -e "${RED}Could not mount DMG${NC}"
    exit 1
fi
trap "hdiutil detach '$VOLUME' -force >/dev/null 2>&1 || true" EXIT

APP_PATH="$VOLUME/Task Scheduler.app"

# 2. App exists in DMG
[ -d "$APP_PATH" ]
check "App bundle exists in DMG" $?

# 3. Applications symlink exists
[ -L "$VOLUME/Applications" ]
check "Applications symlink exists" $?

# 4. Code signature valid
codesign --verify --deep --strict "$APP_PATH" 2>/dev/null
check "Code signature valid (deep)" $?

# 5. Signed with Developer ID (not ad-hoc or development)
codesign -dvv "$APP_PATH" 2>&1 | grep -q "Developer ID Application"
check "Signed with Developer ID certificate" $?

# 6. Hardened runtime
codesign -dvv "$APP_PATH" 2>&1 | grep -q "runtime"
check "Hardened runtime enabled" $?

# 7. Notarization stapled to app
xcrun stapler validate "$APP_PATH" >/dev/null 2>&1
check "Notarization stapled to app" $?

# 8. Notarization stapled to DMG
xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1
check "Notarization stapled to DMG" $?

# 9. Gatekeeper assessment
spctl --assess --type execute "$APP_PATH" 2>/dev/null
check "Gatekeeper accepts app (spctl)" $?

# 10. Team ID matches
TEAM=$(codesign -dvv "$APP_PATH" 2>&1 | grep "TeamIdentifier" | sed 's/.*=//')
[ "$TEAM" = "RGFAX8X946" ]
check "Team ID is RGFAX8X946" $?

echo ""
echo -e "${BLUE}Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
[ $FAIL -eq 0 ] && echo -e "${GREEN}DMG is ready for distribution.${NC}" || echo -e "${RED}Fix failures before distributing.${NC}"
exit $FAIL
