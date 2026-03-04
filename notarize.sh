#!/bin/bash
set -e

# Configuration
KEYCHAIN_PROFILE="${2:-TaskScheduler}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validate arguments
if [ -z "$1" ]; then
    echo -e "${RED}Usage: ./notarize.sh <path-to-app-or-dmg> [keychain-profile]${NC}"
    echo "  Default keychain profile: TaskScheduler"
    echo ""
    echo "  One-time setup:"
    echo "    xcrun notarytool store-credentials \"TaskScheduler\" \\"
    echo "      --apple-id \"your@email.com\" \\"
    echo "      --team-id \"RGFAX8X946\" \\"
    echo "      --password \"app-specific-password\""
    exit 1
fi

ARTIFACT="$1"

if [ ! -e "$ARTIFACT" ]; then
    echo -e "${RED}❌ Not found: $ARTIFACT${NC}"
    exit 1
fi

echo -e "${BLUE}🔏 Notarizing: $ARTIFACT${NC}"
echo -e "   Keychain profile: ${GREEN}$KEYCHAIN_PROFILE${NC}"

# Determine submission path
CLEANUP_ZIP=""
if [[ "$ARTIFACT" == *.app ]]; then
    # notarytool requires zip/dmg/pkg — zip the .app to a temp file
    SUBMIT_PATH=$(mktemp /tmp/notarize_XXXXXX.zip)
    CLEANUP_ZIP="$SUBMIT_PATH"
    echo -e "${BLUE}📦 Zipping app for submission...${NC}"
    ditto -c -k --keepParent "$ARTIFACT" "$SUBMIT_PATH"
elif [[ "$ARTIFACT" == *.dmg ]]; then
    SUBMIT_PATH="$ARTIFACT"
else
    echo -e "${RED}❌ Unsupported file type. Provide a .app or .dmg${NC}"
    exit 1
fi

# Submit for notarization
echo -e "${BLUE}📤 Submitting to Apple notary service...${NC}"
xcrun notarytool submit "$SUBMIT_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

NOTARY_EXIT=$?

# Clean up temp zip
if [ -n "$CLEANUP_ZIP" ]; then
    rm -f "$CLEANUP_ZIP"
fi

if [ $NOTARY_EXIT -ne 0 ]; then
    echo -e "${RED}❌ Notarization failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Notarization accepted${NC}"

# Staple the ticket
echo -e "${BLUE}📎 Stapling notarization ticket...${NC}"
xcrun stapler staple "$ARTIFACT"

# Validate
echo -e "${BLUE}🔍 Validating staple...${NC}"
xcrun stapler validate "$ARTIFACT"

echo -e "${GREEN}✅ Notarization complete: $ARTIFACT${NC}"
