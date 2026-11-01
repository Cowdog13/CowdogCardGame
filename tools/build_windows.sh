#!/usr/bin/env bash
# Builds the Windows playtest zip: tools/build_windows.sh [path to godot]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"
VERSION=$(grep -oP 'VERSION := "\K[^"]+' scripts/core/build_info.gd)
rm -rf build/windows && mkdir -p build/windows
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/CowdogCardGame.exe
sed "s/{VERSION}/$VERSION/" tools/package/HOW_TO_PLAY.txt > build/windows/HOW_TO_PLAY.txt
cp "tools/package/Start Game Server.bat" build/windows/
rm -f build/CowdogCardGame-windows.zip
(cd build/windows && zip -qr ../CowdogCardGame-windows.zip .)
echo "built build/CowdogCardGame-windows.zip (version $VERSION)"
