#!/usr/bin/env bash
# Builds the app's static font files from the upstream variable fonts.
#
# Fredoka (display) and Nunito (UI) are both OFL Google Fonts published only
# as variable TTFs. iOS can load a variable font, but naming a single weight
# from SwiftUI then needs variation-axis plumbing on every call; static
# instances let `Font.custom("Nunito-ExtraBold", ...)` just work and keep the
# PostScript names stable.
#
# Usage:  Supporting/fonts/build_fonts.sh [python-with-fonttools]
# Needs:  curl, and a Python with `fonttools` and `brotli` installed.
set -euo pipefail

PY="${1:-python3}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_FONTS="$ROOT/Pulse/Resources/Fonts"
RENDER_FONTS="$ROOT/Supporting/render/fonts"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"
curl -fsSL -o "$WORK/Fredoka.ttf"     "$BASE/fredoka/Fredoka%5Bwdth,wght%5D.ttf"
curl -fsSL -o "$WORK/Nunito.ttf"      "$BASE/nunito/Nunito%5Bwght%5D.ttf"
curl -fsSL -o "$WORK/OFL-Fredoka.txt" "$BASE/fredoka/OFL.txt"
curl -fsSL -o "$WORK/OFL-Nunito.txt"  "$BASE/nunito/OFL.txt"

mkdir -p "$APP_FONTS" "$RENDER_FONTS"

instance() {  # source  output-name  axis-settings...
  local src="$1" out="$2"; shift 2
  "$PY" -m fontTools.varLib.instancer "$WORK/$src" "$@" \
    --update-name-table --quiet -o "$APP_FONTS/$out.ttf"
  "$PY" - "$APP_FONTS/$out.ttf" "$RENDER_FONTS/$out.woff2" <<'PY'
import sys
from fontTools.ttLib import TTFont
font = TTFont(sys.argv[1]); font.flavor = "woff2"; font.save(sys.argv[2])
PY
}

instance Fredoka.ttf Fredoka-Medium   wght=500 wdth=100
instance Fredoka.ttf Fredoka-SemiBold wght=600 wdth=100
instance Fredoka.ttf Fredoka-Bold     wght=700 wdth=100
instance Nunito.ttf  Nunito-Bold      wght=700
instance Nunito.ttf  Nunito-ExtraBold wght=800
instance Nunito.ttf  Nunito-Black     wght=900

cp "$WORK/OFL-Fredoka.txt" "$APP_FONTS/OFL-Fredoka.txt"
cp "$WORK/OFL-Nunito.txt"  "$APP_FONTS/OFL-Nunito.txt"

# Print the PostScript name of every file: these are the names Swift uses,
# and a mismatch fails silently as a system-font fallback.
"$PY" - "$APP_FONTS" <<'PY'
import sys, pathlib
from fontTools.ttLib import TTFont
for f in sorted(pathlib.Path(sys.argv[1]).glob("*.ttf")):
    print(f"{f.name:26s} {TTFont(f)['name'].getDebugName(6)}")
PY
