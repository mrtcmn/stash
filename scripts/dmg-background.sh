#!/bin/bash
# Renders App/DMG/background.svg into a 1x + 2x TIFF for the DMG window. Needs rsvg-convert (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
rsvg-convert -w 660 -h 400 App/DMG/background.svg -o "$TMP/bg.png"
rsvg-convert -w 1320 -h 800 App/DMG/background.svg -o "$TMP/bg@2x.png"
tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out App/DMG/background.tiff
