#!/usr/bin/env python3
"""Writes the Sparkle appcast for the built disk image, to stdout.

    python3 scripts/make-appcast.py > build/appcast.xml

It takes no arguments on purpose: the disk image is the one Resources/Info.plist describes, so
the feed can only ever advertise the build it was generated from, and nothing from the command
line reaches a subprocess.

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

if len(sys.argv) != 1:
    sys.exit("usage: make-appcast.py   # no arguments; it reads Resources/Info.plist")
if not SIGN_UPDATE.is_file():
    sys.exit("no vendor/sparkle/bin/sign_update — run ./scripts/fetch-sparkle.sh")

info = plistlib.loads(pathlib.Path("Resources/Info.plist").read_bytes())
short_version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
minimum = info.get("LSMinimumSystemVersion", "13.0")

dmg = pathlib.Path("build") / f"ImageShrink-{short_version}.dmg"
if not dmg.is_file():
    sys.exit(f"no {dmg} — run ./scripts/release.sh first")


def published_build() -> int | None:
    """The build number the current feed advertises, or None when there is no feed yet.

    Only a 404 means "no feed". Treating a timeout or a 500 the same way would skip the version
    guard exactly when the network is unreliable, and publish an update nobody is ever offered.
    """
    try:
        with urllib.request.urlopen(FEED, timeout=20) as response:
            feed = response.read().decode()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        sys.exit(f"could not read the published feed ({error.code} {error.reason}); "
                 "refusing to guess whether this build is newer")
    except (urllib.error.URLError, TimeoutError) as error:
        sys.exit(f"could not reach the published feed ({error}); "
                 "refusing to guess whether this build is newer")
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


def changelog_body() -> str:
    """The lines under this version's heading, or nothing if it has no section yet."""
    changelog = pathlib.Path("CHANGELOG.md").read_text()
    heading = re.search(r"^## %s\s+—\s+.+?$" % re.escape(short_version), changelog, re.M)
    if not heading:
        return ""
    body = changelog[heading.end():]
    following = re.search(r"^## ", body, re.M)
    return body[:following.start()] if following else body


def inline(text: str) -> str:
    """Escapes the text, then the two bits of markdown the changelog actually uses."""
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", text)


def bullet_items(lines: list[str]) -> list[str]:
    """Joins wrapped continuation lines back onto the bullet they belong to."""
    items: list[str] = []
    for line in lines:
        if line.startswith("- "):
            items.append(line[2:])
        elif items:
            items[-1] += " " + line
    return items


def release_notes_html() -> str:
    """The changelog section for this version, as the small HTML Sparkle renders."""
    html = []
    for block in re.split(r"\n\s*\n", changelog_body().strip()):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        if not lines:
            continue
        if lines[0].startswith("- "):
            items = "".join(f"<li>{inline(item)}</li>" for item in bullet_items(lines))
            html.append(f"<ul>{items}</ul>")
        else:
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
