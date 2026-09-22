#!/usr/bin/env bash
# End-to-end check: generates test photos, converts them through both the CLI and the
# window's own model, and asserts the sizes and the names that come out.
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="build/ImageShrink"
[[ -x "$BIN" ]] || xcrun swiftc -O -o "$BIN" Sources/ImageShrink/*.swift

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "› generating test photos in $WORK"
xcrun swift tools/make-test-image.swift "$WORK/photo.jpg" >/dev/null
sips -s format heic "$WORK/photo.jpg" --out "$WORK/photo.heic" >/dev/null

fail() { echo "FAIL: $*" >&2; exit 1; }
size() { stat -f%z "$1"; }
only() { # the single file matching a glob
    set -- $1
    [[ -f "${1:-}" ]] || fail "no file matching that name"
    echo "$1"
}

echo "› CLI, 2 MB limit — names carry the size, clashing bases carry the format"
"$BIN" --cli --target-mb 2 --dest "$WORK/out" "$WORK/photo.jpg" "$WORK/photo.heic"
[[ -f "$WORK/out/photo-jpg-2MB.jpg" ]] || fail "expected photo-jpg-2MB.jpg"
[[ -f "$WORK/out/photo-heic-2MB.jpg" ]] || fail "expected photo-heic-2MB.jpg"
for f in "$WORK/out"/*.jpg; do
    [[ "$(size "$f")" -le 2000000 ]] || fail "$f is over 2 MB"
done

echo "› CLI, 500 KB limit forces a downscale"
"$BIN" --cli --target-mb 0.5 --dest "$WORK/tiny" "$WORK/photo.heic" >/dev/null
[[ -f "$WORK/tiny/photo-500KB.jpg" ]] || fail "expected photo-500KB.jpg"
[[ "$(size "$WORK/tiny/photo-500KB.jpg")" -le 500000 ]] || fail "500 KB limit not met"

echo "› CLI, longest side 1920"
"$BIN" --cli --target-mb 5 --max-dim 1920 --dest "$WORK/small" "$WORK/photo.heic" >/dev/null
resized=$(only "$WORK/small/photo-*.jpg")
[[ "$(sips -g pixelWidth "$resized" | tail -1 | tr -dc 0-9)" -eq 1920 ]] || fail "not resized to 1920"

echo "› window model, 1 MB limit"
"$BIN" --cli --selftest --target-mb 1 --dest "$WORK/gui" "$WORK/photo.jpg" "$WORK/photo.heic"
for f in "$WORK/gui/photo-jpg-1MB.jpg" "$WORK/gui/photo-heic-1MB.jpg"; do
    [[ -f "$f" ]] || fail "expected $(basename "$f")"
    [[ "$(size "$f")" -le 1000000 ]] || fail "$f is over 1 MB"
done

echo "› a HEIC that already fits is not allowed to grow"
"$BIN" --cli --target-mb 8 --dest "$WORK/noinflate" "$WORK/photo.heic" >/dev/null
grown=$(only "$WORK/noinflate/photo-*.jpg")
[[ "$(size "$grown")" -le "$(size "$WORK/photo.heic")" ]] \
    || fail "converting a HEIC with an 8 MB limit produced a bigger file"

echo "› PNG converts, and transparency lands on white"
xcrun swift tools/make-alpha-image.swift "$WORK/alpha.png" >/dev/null
"$BIN" --cli --target-mb 1 --dest "$WORK/png" "$WORK/alpha.png" >/dev/null
converted=$(only "$WORK/png/alpha-*.jpg")
[[ "$(sips -g format "$converted" | tail -1 | tr -d ' ' )" = "format:jpeg" ]] || fail "PNG did not become a JPEG"
corner=$(xcrun swift tools/corner-pixel.swift "$converted")
[[ "$corner" = "255 255 255" ]] || fail "transparent corner came out $corner, not white"

echo "› a cancelled run stops cleanly and leaves work pending"
mkdir -p "$WORK/many"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do cp "$WORK/photo.jpg" "$WORK/many/photo$i.jpg"; done
"$BIN" --cli --selftest --cancel-after 0.3 --target-mb 1 --dest "$WORK/cancelled" "$WORK/many"/*.jpg \
    | tail -1 | grep -q "still pending" || fail "cancelling left nothing pending"

echo "› files already under the limit are left alone"
out="$("$BIN" --cli --target-mb 5 "$WORK/tiny/photo-500KB.jpg")"
[[ "$out" == *"already under the limit"* ]] || fail "small file was re-encoded: $out"

echo "› odd formats: a CMYK JPEG and a 16-bit TIFF"
xcrun swift tools/make-odd-images.swift "$WORK/odd" >/dev/null
"$BIN" --cli --target-mb 1 --dest "$WORK/oddout" "$WORK/odd/cmyk.jpg" "$WORK/odd/deep.tiff" >/dev/null
[[ -f "$WORK/oddout/cmyk-1MB.jpg" ]] || fail "the CMYK JPEG did not convert"
[[ -f "$WORK/oddout/deep-1MB.jpg" ]] || fail "the 16-bit TIFF did not convert"
for f in "$WORK/oddout"/*.jpg; do
    [[ "$(size "$f")" -le 1000000 ]] || fail "$f is over 1 MB"
done
# The CMYK JPEG comes out CMYK — the encoder keeps the source colour space. Asserted rather
# than assumed, because some upload forms reject CMYK JPEGs, so the day this changes it should
# be a deliberate change with a changelog line, not a surprise.
space=$(sips -g space "$WORK/oddout/cmyk-1MB.jpg" | tail -1 | tr -d ' ')
[[ "$space" = "space:CMYK" ]] || fail "CMYK output is now $space — intended? then update this test"


echo "› a panorama keeps its shape"
"$BIN" --cli --target-mb 0.5 --dest "$WORK/pano" "$WORK/odd/panorama.jpg" >/dev/null
pano=$(only "$WORK/pano/panorama-*.jpg")
[[ "$(size "$pano")" -le 500000 ]] || fail "the panorama came out over 500 KB"
width=$(sips -g pixelWidth "$pano" | tail -1 | tr -dc 0-9)
height=$(sips -g pixelHeight "$pano" | tail -1 | tr -dc 0-9)
# 8000 × 1400 is 5.71:1; anything that resizes by the wrong axis lands far outside 5.6–5.8.
ratio=$(echo "scale=2; $width / $height" | bc)
case "$ratio" in 5.6*|5.7*|5.8*) ;; *) fail "the panorama came out $width × $height ($ratio:1)" ;; esac

echo "› files that are not images fail cleanly"
printf 'this is not an image' > "$WORK/fake.jpg"
: > "$WORK/empty.jpg"
for broken in fake empty; do
    if "$BIN" --cli --target-mb 1 --dest "$WORK/bad" "$WORK/$broken.jpg" >/dev/null 2>&1; then
        fail "$broken.jpg was reported as converted"
    fi
done
[[ -z "$(ls -A "$WORK/bad" 2>/dev/null || true)" ]] || fail "an unreadable file still produced output"

echo "› a JPEG with no extension is still a JPEG"
cp "$WORK/odd/panorama.jpg" "$WORK/extensionless"
"$BIN" --cli --target-mb 1 --dest "$WORK/noext" "$WORK/extensionless" >/dev/null
[[ -f "$WORK/noext/extensionless-1MB.jpg" ]] || fail "a file with no extension did not convert"

echo "› a destination it cannot write to is an error, not a crash"
mkdir -p "$WORK/readonly"
chmod 555 "$WORK/readonly"
if "$BIN" --cli --target-mb 1 --dest "$WORK/readonly" "$WORK/odd/cmyk.jpg" >/dev/null 2>&1; then
    chmod 755 "$WORK/readonly"
    fail "writing into a read-only folder was reported as success"
fi
chmod 755 "$WORK/readonly"
[[ -z "$(ls -A "$WORK/readonly")" ]] || fail "something was written into the read-only folder"

echo "PASS"
