#!/bin/bash
# Renders Resources/AppIcon.svg into Resources/AppIcon.icns.
# Needs Google Chrome (headless) for the SVG; sips and iconutil ship with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A page that shows the SVG at exactly 1024×1024 on a transparent background.
cat > "$WORK/icon.html" <<EOF
<html><body style="margin:0;background:transparent">
<img src="file://$ROOT/Resources/AppIcon.svg" width="1024" height="1024" style="display:block">
</body></html>
EOF

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
    --user-data-dir="$WORK/profile" \
    --force-device-scale-factor=1 --window-size=1024,1024 \
    --default-background-color=00000000 \
    --screenshot="$WORK/icon_1024.png" "file://$WORK/icon.html" >/dev/null 2>&1

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "$ROOT/Resources/AppIcon.icns"
