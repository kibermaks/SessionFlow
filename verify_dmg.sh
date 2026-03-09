#!/bin/bash
# Do NOT use set -e — we want to run all checks and report results

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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
WARN=0

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

warn() {
    local label="$1"
    local result="$2"
    if [ $result -eq 0 ]; then
        echo -e "  ${GREEN}PASS${NC}  $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${YELLOW}WARN${NC}  $label"
        WARN=$((WARN + 1))
    fi
}

# 1. Mount the DMG
VOLUME=$(hdiutil attach "$DMG_PATH" -nobrowse 2>/dev/null | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
if [ -z "$VOLUME" ]; then
    echo -e "${RED}Could not mount DMG${NC}"
    exit 1
fi
trap "hdiutil detach '$VOLUME' -force >/dev/null 2>&1 || true" EXIT

APP_PATH="$VOLUME/SessionFlow.app"
CODESIGN_INFO=$(codesign -dvv "$APP_PATH" 2>&1)

echo -e "${BLUE}Structure${NC}"

# App exists in DMG
[ -d "$APP_PATH" ]
check "App bundle exists in DMG" $?

# Applications symlink exists
[ -L "$VOLUME/Applications" ]
check "Applications symlink exists" $?

echo ""
echo -e "${BLUE}Code Signing${NC}"

# Code signature valid (deep)
codesign --verify --deep --strict "$APP_PATH" 2>/dev/null
check "Code signature valid (deep strict)" $?

# Signed with Developer ID (not ad-hoc or development)
echo "$CODESIGN_INFO" | grep -q "Developer ID Application"
check "Signed with Developer ID certificate" $?

# Full authority chain: Developer ID → Apple
echo "$CODESIGN_INFO" | grep -q "Developer ID Certification Authority"
check "Authority chain includes Apple CA" $?

# Hardened runtime enabled (flags=0x10000(runtime))
echo "$CODESIGN_INFO" | grep -q "flags=0x10000(runtime)"
check "Hardened runtime enabled" $?

# Secure timestamp present
echo "$CODESIGN_INFO" | grep -q "Timestamp="
check "Secure timestamp present" $?

# No debug entitlement (get-task-allow must NOT be present)
ENTITLEMENTS=$(codesign -d --entitlements - "$APP_PATH" 2>&1 || true)
if echo "$ENTITLEMENTS" | grep -q "get-task-allow"; then
    # get-task-allow found — check if it's set to false (acceptable) or true (fail)
    if echo "$ENTITLEMENTS" | grep -A1 "get-task-allow" | grep -q "true"; then
        check "No debug entitlement (get-task-allow)" 1
    else
        check "No debug entitlement (get-task-allow)" 0
    fi
else
    check "No debug entitlement (get-task-allow)" 0
fi

# Team ID matches
TEAM=$(echo "$CODESIGN_INFO" | grep "TeamIdentifier" | sed 's/.*=//')
[ "$TEAM" = "RGFAX8X946" ]
check "Team ID is RGFAX8X946" $?

echo ""
echo -e "${BLUE}Notarization${NC}"

# Notarization stapled to app
xcrun stapler validate "$APP_PATH" >/dev/null 2>&1
check "Notarization stapled to app" $?

# Notarization stapled to DMG
xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1
check "Notarization stapled to DMG" $?

# Gatekeeper assessment
spctl --assess --type execute "$APP_PATH" 2>/dev/null
check "Gatekeeper accepts app (spctl)" $?

echo ""
echo -e "${BLUE}Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}"
if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}DMG is ready for distribution.${NC}"
else
    echo -e "${RED}Fix $FAIL failure(s) before distributing.${NC}"
fi
exit $FAIL
