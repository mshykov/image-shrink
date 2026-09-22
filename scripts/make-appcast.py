#!/usr/bin/env python3
"""Writes the Sparkle appcast for a built disk image, to stdout.

    python3 scripts/make-appcast.py build/ImageShrink-1.1.0.dmg > build/appcast.xml

The feed is published as a release asset rather than committed, so a release needs no push to
a protected branch. The update is signed with the EdDSA key in this Mac's keychain; an app
whose SUPublicEDKey does not verify it refuses to install it, which is the entire security
model — the DMG travels over HTTPS from GitHub, but the signature is what is trusted.
"""
import datetime
import email.utils
import pathlib
import plistlib
import re
import subprocess
import sys
import urllib.error
import urllib.request

REPOSITORY = "mshykov/image-shrink"
FEED = f"https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml"
SIGN_UPDATE = pathlib.Path("vendor/sparkle/bin/sign_update")
GENERATE_KEYS = pathlib.Path("vendor/sparkle/bin/generate_keys")

if len(sys.argv) != 2:
    sys.exit("usage: make-appcast.py <path-to-dmg>")
dmg = pathlib.Path(sys.argv[1])
if not dmg.is_file():
    sys.exit(f"no disk image at {dmg}")
if not SIGN_UPDATE.is_file():
    sys.exit("no vendor/sparkle/bin/sign_update — run ./scripts/fetch-sparkle.sh")

info = plistlib.loads(pathlib.Path("Resources/Info.plist").read_bytes())
short_version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
minimum = info.get("LSMinimumSystemVersion", "13.0")


def published_build() -> int | None:
    """The build number the current feed advertises, if there is a feed yet."""
    try:
        with urllib.request.urlopen(FEED, timeout=20) as response:
            feed = response.read().decode()
    except (urllib.error.URLError, TimeoutError):
        return None
    found = re.search(r"<sparkle:version>(\d+)</sparkle:version>", feed)
    return int(found.group(1)) if found else None


# Sparkle compares CFBundleVersion, not the version people read. Shipping a release that does
# not raise it means nobody is ever offered the update, silently.
previous = published_build()
if previous is not None and int(build) <= previous:
    sys.exit(f"CFBundleVersion is {build}, and the published feed already offers {previous} — "
             "raise it in Resources/Info.plist, or no one will be offered this update")

# Signing with the wrong key produces an update every installed copy refuses — and the
# refusal happens on the user's machine, days later, silently. Check first.
keychain_key = subprocess.run([str(GENERATE_KEYS), "-p"],
                              capture_output=True, text=True, check=True).stdout.strip()
if keychain_key != info.get("SUPublicEDKey"):
    sys.exit("this keychain's Sparkle key does not match SUPublicEDKey in Resources/Info.plist:\n"
             f"  keychain  {keychain_key}\n"
             f"  Info.plist {info.get('SUPublicEDKey')}\n"
             "Updates signed with it would be rejected by every installed copy.")

signature = subprocess.run([str(SIGN_UPDATE), str(dmg)],
                           capture_output=True, text=True, check=True).stdout.strip()
# sign_update prints the two attributes ready to paste: sparkle:edSignature="…" length="…"
found_signature = re.search(r'sparkle:edSignature="([^"]+)"', signature)
if not found_signature:
    sys.exit(f"sign_update returned something unexpected: {signature}")

# Verify what was just produced, with the same tool the app will effectively use. A signature
# that does not verify here would have shipped as an update nobody could install.
verified = subprocess.run([str(SIGN_UPDATE), "--verify", str(dmg), found_signature.group(1)],
                          capture_output=True, text=True)
if verified.returncode != 0:
    sys.exit(f"the signature does not verify: {verified.stdout}{verified.stderr}")


def release_notes_html() -> str:
    """The changelog section for this version, as the small HTML Sparkle renders."""
    changelog = pathlib.Path("CHANGELOG.md").read_text()
    heading = re.search(r"^## %s\s+—\s+.+?$" % re.escape(short_version), changelog, re.M)
    if not heading:
        return f"<p>Version {short_version}.</p>"
    body = changelog[heading.end():]
    following = re.search(r"^## ", body, re.M)
    if following:
        body = body[:following.start()]

    def inline(text: str) -> str:
        text = (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
        return text

    html, bullets = [], []
    for block in re.split(r"\n\s*\n", body.strip()):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        if lines and lines[0].startswith("- "):
            joined, items = "", []
            for line in lines:
                if line.startswith("- "):
                    if joined:
                        items.append(joined)
                    joined = line[2:]
                else:
                    joined += " " + line
            if joined:
                items.append(joined)
            bullets = "".join(f"<li>{inline(item)}</li>" for item in items)
            html.append(f"<ul>{bullets}</ul>")
        elif lines:
            html.append("<p>%s</p>" % inline(" ".join(lines)))
    return "".join(html) or f"<p>Version {short_version}.</p>"


url = (f"https://github.com/{REPOSITORY}/releases/download/"
       f"v{short_version}/{dmg.name}")
date = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))

print(f'''<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Image Shrink</title>
    <link>{FEED}</link>
    <description>Updates for Image Shrink</description>
    <language>en</language>
    <item>
      <title>{short_version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>
      <description><![CDATA[{release_notes_html()}]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature} />
    </item>
  </channel>
</rss>''')
