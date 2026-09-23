#!/usr/bin/env bash
# Renders the window to PNGs for a look at the layout.
#
# The plain --snapshot flag cannot show the file list: an offscreen window never gives its
# scroll view a display cycle, so the rows are never drawn (a solid colour in their place
# renders fine, which is how that was established). This builds a copy whose list does not
# scroll, and renders the states from it.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/design}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -R Sources/ImageShrink "$WORK/probe"
python3 - "$WORK/probe/ContentView.swift" <<'PYEOF'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
# An offscreen window never gives a scroll view a display cycle, so its rows never draw.
old = """            ScrollView {
                LazyVStack(spacing: 0) {"""
new = """            VStack(spacing: 0) {
                VStack(spacing: 0) {"""
assert old in s, "probe: the list layout moved"
p.write_text(s.replace(old, new))
PYEOF

echo "› building the probe"
xcrun swiftc -O -o "$WORK/probe-bin" "$WORK/probe"/*.swift

echo "› test photos"
xcrun swift tools/make-test-image.swift "$WORK/photo.jpg" >/dev/null
mkdir -p "$WORK/before" "$WORK/after"
for i in 1 2 3 4 5; do
    sips -s format heic -s formatOptions 45 "$WORK/photo.jpg" --out "$WORK/before/IMG_730$i.HEIC" >/dev/null
done
cp "$WORK/photo.jpg" "$WORK/before/IMG_7306.jpg"
cp "$WORK/before"/* "$WORK/after/"

"$WORK/probe-bin" --cli --snapshot "$OUT/before.png" "$WORK/before"/* >/dev/null
"$WORK/probe-bin" --cli --snapshot "$OUT/after.png" --snapshot-run --target-mb 2 "$WORK/after"/* >/dev/null
"$WORK/probe-bin" --cli --snapshot "$OUT/popover.png" --snapshot-popover >/dev/null
"$WORK/probe-bin" --cli --snapshot "$OUT/hud.png" --snapshot-hud >/dev/null

cp -R "$WORK/before" "$WORK/light"
"$WORK/probe-bin" --cli --snapshot "$OUT/before-light.png" --snapshot-light "$WORK/light"/* >/dev/null
"$WORK/probe-bin" --cli --snapshot "$OUT/empty-light.png" --snapshot-light >/dev/null
"$WORK/probe-bin" --cli --snapshot "$OUT/popover-light.png" --snapshot-light --snapshot-popover >/dev/null
"$WORK/probe-bin" --cli --snapshot "$OUT/hud-light.png" --snapshot-light --snapshot-hud >/dev/null

echo "wrote dark and light renders into $OUT"
