#!/bin/bash
# Builds Shelfie and assembles a launchable .app bundle.
# Usage: scripts/build-app.sh [debug|release]
#
# Environment:
#   SHELFIE_SIGN_IDENTITY   codesigning identity (default: first "Developer ID Application")
#   SHELFIE_NOTARY_PROFILE  a `xcrun notarytool store-credentials` profile name; when set,
#                           the signed app is notarized and the ticket stapled to it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/build/Shelfie.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Shelfie" "$APP/Contents/MacOS/Shelfie"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sign with a stable identity when one is available.
#
# This matters: macOS keys every privacy grant (Screen Recording, Automation,
# Photos) to the app's code signing identity. An ad-hoc signature changes with
# every build, so a grant given to one build is thrown away by the next one and
# the user is asked again. A Developer ID keeps the grant.
IDENTITY="${SHELFIE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    # No Developer ID is not an error: fall through to ad-hoc signing.
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }' || true)
fi

ENTITLEMENTS="$ROOT/Resources/Shelfie.entitlements"

# Notarization needs the hardened runtime and a secure timestamp on every
# piece of code. The timestamp comes from Apple's server, so offline builds
# fall back to none (fine for local use, rejected by the notary service).
TIMESTAMPED=1
sign() {
    local target="$1"
    shift
    if codesign --force --options runtime --timestamp "$@" --sign "$IDENTITY" "$target" 2>/dev/null; then
        return 0
    fi
    echo "warning: timestamped signing of $(basename "$target") failed (offline?); signing without a timestamp" >&2
    TIMESTAMPED=0
    codesign --force --options runtime --timestamp=none "$@" --sign "$IDENTITY" "$target"
}

# Nested code first, innermost first, so the outer seal covers signed parts.
sign_bundle() {
    local nested
    while IFS= read -r -d '' nested; do
        sign "$nested" || return 1
    done < <(find "$APP/Contents" -depth -mindepth 2 \
        \( -name '*.framework' -o -name '*.dylib' -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \
           -o -path "$APP/Contents/Helpers/*" -type f -perm -u+x \) -print0)
    sign "$APP" --entitlements "$ENTITLEMENTS"
}

SIGNED_WITH_ID=0
if [ -n "$IDENTITY" ]; then
    if sign_bundle >/dev/null; then
        SIGNED_WITH_ID=1
        if [ "$TIMESTAMPED" = 1 ]; then
            echo "Signed with: $IDENTITY (hardened runtime, secure timestamp)"
        else
            echo "Signed with: $IDENTITY (hardened runtime, NO timestamp: not notarizable)"
        fi
    else
        echo "Signing with $IDENTITY failed; continuing unsigned" >&2
    fi
else
    # Ad-hoc signatures carry no timestamp.
    codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null 2>&1 \
        && echo "Signed ad-hoc (privacy grants will not survive a rebuild)"
fi

NOTARY_PROFILE="${SHELFIE_NOTARY_PROFILE:-}"
if [ -n "$NOTARY_PROFILE" ]; then
    if [ "$SIGNED_WITH_ID" != 1 ] || [ "$TIMESTAMPED" != 1 ]; then
        echo "error: notarization needs a Developer ID signature with a secure timestamp" >&2
        exit 1
    fi
    codesign --verify --strict --deep "$APP"

    ZIP="$ROOT/build/Shelfie-notarize.zip"
    LOG="$ROOT/build/notarytool.log"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"

    echo "Notarizing with profile \"$NOTARY_PROFILE\" (this waits for Apple)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$LOG" || true
    rm -f "$ZIP"

    if ! grep -q 'status: Accepted' "$LOG"; then
        SUBMISSION=$(awk '/^ *id:/ { print $2; exit }' "$LOG")
        echo "error: notarization was not accepted" >&2
        if [ -n "$SUBMISSION" ]; then
            echo "Details: xcrun notarytool log $SUBMISSION --keychain-profile \"$NOTARY_PROFILE\"" >&2
        fi
        exit 1
    fi

    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    echo "Notarized and stapled"
else
    echo "Not notarized (set SHELFIE_NOTARY_PROFILE to notarize)"
fi

echo "$APP"
