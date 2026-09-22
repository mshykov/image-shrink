#!/usr/bin/env bash
# Puts Sparkle into vendor/, which is gitignored: a 15 MB binary framework does not belong in
# a repository whose whole point is that it is reviewable as text. Pinned by version and by
# checksum, because "download the latest" is how a build becomes someone else's code.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.10.0"
SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${VERSION}/Sparkle-${VERSION}.tar.xz"
DIRECTORY="vendor/sparkle"

if [[ -f "$DIRECTORY/.version" ]] && [[ "$(cat "$DIRECTORY/.version")" == "$VERSION" ]]; then
    echo "Sparkle ${VERSION} is already in ${DIRECTORY}"
    exit 0
fi

echo "› downloading Sparkle ${VERSION}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --proto '=https' --proto-redir '=https' "$URL" -o "$WORK/sparkle.tar.xz"

computed=$(shasum -a 256 "$WORK/sparkle.tar.xz" | cut -d' ' -f1)
if [[ "$computed" != "$SHA256" ]]; then
    echo "refusing: checksum mismatch" >&2
    echo "  expected $SHA256" >&2
    echo "  got      $computed" >&2
    exit 1
fi

tar -xf "$WORK/sparkle.tar.xz" -C "$WORK"
rm -rf "$DIRECTORY"
mkdir -p "$DIRECTORY"
cp -R "$WORK/Sparkle.framework" "$DIRECTORY/"
cp -R "$WORK/bin" "$DIRECTORY/"
cp "$WORK/LICENSE" "$DIRECTORY/LICENSE"
echo "$VERSION" > "$DIRECTORY/.version"

echo "Sparkle ${VERSION} → ${DIRECTORY}"
