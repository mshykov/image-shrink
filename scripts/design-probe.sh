#!/usr/bin/env bash
# Renders the window to PNGs for a look at the layout.
#
# The plain --snapshot flag cannot show the grid: an offscreen window never gives its
# scroll view a display cycle, so the cards are never drawn (a solid colour in their place
# renders fine, which is how that was established). This builds a copy whose grid has no
# scroll view, and renders the before and after states from it.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-build/design}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -R Sources/ImageShrink "$WORK/probe"
python3 - "$WORK/probe/ContentView.swift" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
start = s.index("    var body: some View {\n        ScrollView {\n            LazyVGrid")
end = s.index("        .scrollContentBackground(.hidden)\n    }\n}")
s = s[:start] + '''    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                ForEach(Array(stride(from: 0, to: model.items.count, by: 3)), id: \\.self) { start in
                    HStack(spacing: 16) {
                        ForEach(model.items[start..<min(start + 3, model.items.count)]) { item in
                            PhotoCard(item: item)
                        }
                        if model.items.count - start < 3 {
                            ForEach(0..<(3 - (model.items.count - start)), id: \\.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            Spacer(minLength: 0)
        }
''' + s[end:]
p.write_text(s)
PY

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
"$WORK/probe-bin" --cli --snapshot "$OUT/after.png" --snapshot-run --target-mb 1 "$WORK/after"/* >/dev/null

echo "wrote $OUT/before.png and $OUT/after.png"
