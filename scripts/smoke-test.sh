#!/usr/bin/env bash
# End-to-end check: generates test photos, converts them through both the CLI and the
# window's own model, and asserts the results land under the requested limit.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="build/ImageShrink"
[ -x "$BIN" ] || xcrun swiftc -O -o "$BIN" Sources/ImageShrink/*.swift

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "› generating test photos in $WORK"
xcrun swift tools/make-test-image.swift "$WORK/photo.jpg" >/dev/null
sips -s format heic "$WORK/photo.jpg" --out "$WORK/photo.heic" >/dev/null

fail() { echo "FAIL: $*" >&2; exit 1; }
size() { stat -f%z "$1"; }

echo "› CLI, 2 MB limit"
"$BIN" --cli --target-mb 2 --dest "$WORK/out" "$WORK/photo.jpg" "$WORK/photo.heic"
for f in "$WORK/out/photo.jpg" "$WORK/out/photo-small.jpg"; do
    [ -f "$f" ] || fail "missing $f"
    [ "$(size "$f")" -le 2000000 ] || fail "$f is over 2 MB"
done

echo "› CLI, 500 KB limit forces a downscale"
"$BIN" --cli --target-mb 0.5 --dest "$WORK/tiny" "$WORK/photo.heic" >/dev/null
[ "$(size "$WORK/tiny/photo.jpg")" -le 500000 ] || fail "500 KB limit not met"

echo "› CLI, longest side 1920"
"$BIN" --cli --target-mb 5 --max-dim 1920 --dest "$WORK/small" "$WORK/photo.heic" >/dev/null
[ "$(sips -g pixelWidth "$WORK/small/photo.jpg" | tail -1 | tr -dc 0-9)" -eq 1920 ] || fail "not resized to 1920"

echo "› window model, 1 MB limit"
"$BIN" --cli --selftest --target-mb 1 --dest "$WORK/gui" "$WORK/photo.jpg" "$WORK/photo.heic"
for f in "$WORK/gui/photo.jpg" "$WORK/gui/photo-small.jpg"; do
    [ "$(size "$f")" -le 1000000 ] || fail "$f is over 1 MB"
done

echo "› files already under the limit are left alone"
out="$("$BIN" --cli --target-mb 5 "$WORK/tiny/photo.jpg")"
[[ "$out" == *"already under the limit"* ]] || fail "small file was re-encoded: $out"

echo "PASS"
