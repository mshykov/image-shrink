# Distributing Image Shrink

How this app gets from `build/` onto other people's Macs, and how they find out it exists.
Written 2026-09-22 against commit `64e424c`; the state section below is measured, not assumed.

## 0. Where the build stands today

| Checked | Result |
| --- | --- |
| Signature | `Developer ID Application: Maksym Shykov (64HRGLZCS4)`, hardened runtime (`flags=0x10000`), secure timestamp present — notarisation-ready |
| Certificate | valid to 1 Feb 2027, so the Developer Program membership is active (notarisation needs it) |
| Notarised | **no** — every other Mac will refuse the app with "Apple could not verify…" |
| Architecture | `lipo -archs` → `arm64` **only** — will not launch on any Intel Mac |
| Finder actions | installed by `scripts/install.sh`, i.e. **only for people who clone the repo** |
| Version | `1.0.0` (build `1`), minimum macOS 13.0 |
| Updates | none |
| Repo | local only, no remote, no `LICENSE` |

Three of those are release blockers. They are section 1.

## 1. Make the build shippable

### 1.1 The app must install its own Finder actions (biggest gap)

Everything the app is *for* — the Quick Actions, the ⌃⌘J hotkey — is installed by a shell
script in this repo: `scripts/install.sh` writes the `.workflow` bundles into
`~/Library/Services`, flips them on in the `pbs` preference domain and restarts Finder.
Someone who downloads a DMG runs none of that, so they get a window-only app with no
right-click entry and no shortcut.

What has to change:

- `scripts/make-quick-action.sh` output moves into the bundle at build time —
  `Contents/Resources/Services/*.workflow`.
- On first launch (and behind a **Install / repair Finder actions** menu item), the app copies
  those into `~/Library/Services`, writes the `NSServicesStatus` entries and runs `pbs -flush`.
  The code for all of that already exists in `Shortcut.swift` and the install script; it needs
  to move into the app.
- An **uninstall** item that removes them again. A downloaded app has no `scripts/uninstall.sh`.
- The bundled workflows must be signed — they are inside the app bundle, so they are covered
  by the app's signature, but they have to be in place *before* `codesign` runs.

Until this is done, do not ship: the first review will be "the right-click menu never appeared",
which is exactly the bug that took the longest to fix locally.

### 1.2 Universal binary

`build.sh` compiles for `$(uname -m)`. Intel Macs (and Rosetta users) get nothing. Build both
and merge:

```bash
for arch in arm64 x86_64; do xcrun swiftc -O -wmo -target "$arch-apple-macos13.0" -o "build/bin-$arch" Sources/ImageShrink/*.swift; done
```

then `lipo -create build/bin-arm64 build/bin-x86_64 -output "$APP/Contents/MacOS/ImageShrink"`,
and sign **after** the lipo. Keep the `-emit-const-values-path` and `-const-gather-protocols-file`
flags on one of the two passes — that file is what the Shortcuts metadata is extracted from, and
one architecture's copy is enough. Verify with `lipo -archs` before every release.

### 1.3 Notarise and staple

Gatekeeper on another Mac checks for a notarisation ticket, not just a signature. One-time
credential setup — run this yourself, it asks for an app-specific password created at
appleid.apple.com (never put that password in a script or a repo):

```bash
xcrun notarytool store-credentials image-shrink --apple-id <your-apple-id> --team-id 64HRGLZCS4
```

Per release, after `scripts/build.sh`:

```bash
ditto -c -k --keepParent "build/Image Shrink.app" build/ImageShrink.zip
xcrun notarytool submit build/ImageShrink.zip --keychain-profile image-shrink --wait
xcrun stapler staple "build/Image Shrink.app"
spctl -a -vvv -t exec "build/Image Shrink.app"   # must say: accepted, source=Notarized Developer ID
```

If it is rejected, `xcrun notarytool log <submission-id> --keychain-profile image-shrink` says
why. The usual causes are a missing hardened runtime (we have it) and a missing secure
timestamp (we have that too).

### 1.4 Ship a DMG

A ZIP works, but a DMG is what Mac users expect, and it survives being re-hosted:

```bash
hdiutil create -volname "Image Shrink" -srcfolder "build/Image Shrink.app" -ov -format UDZO build/ImageShrink-1.0.0.dmg
codesign --force --sign "Developer ID Application: Maksym Shykov (64HRGLZCS4)" build/ImageShrink-1.0.0.dmg
xcrun notarytool submit build/ImageShrink-1.0.0.dmg --keychain-profile image-shrink --wait
xcrun stapler staple build/ImageShrink-1.0.0.dmg
```

Notarise and staple the DMG as well as the app — a stapled DMG opens cleanly even offline.
`create-dmg` adds the drag-to-Applications background if you want it to look finished.

### 1.5 Test it the way a stranger receives it

Signing and notarising locally proves nothing about the download path. Upload the DMG, then on
a **different Mac or a fresh user account**, download it in Safari (so it gets the quarantine
flag) and open it. What you are checking: no Gatekeeper warning, the app launches, the Finder
actions appear after first launch, the hotkey works, and the folder-permission prompts read
sensibly. Also worth one pass on an older macOS (13 or 14) in a VM, since the Liquid Glass
paths are all behind `#available(macOS 26)` and have never run on an older system.

### 1.6 Versions and updates

- `CFBundleShortVersionString` is what people see (`1.0.0`); `CFBundleVersion` must increase
  every single release — an update mechanism compares it numerically.
- Keep a `CHANGELOG.md`. It feeds the release notes, the site and the Sparkle appcast.
- For updates, [Sparkle 2](https://sparkle-project.org): an EdDSA key pair, `appcast.xml` on
  the site, each DMG signed with the private key. Cheaper interim option: a "Check for
  updates" menu item that opens the GitHub releases page. Do not ship a v1 with no path at
  all — it means every future fix reaches nobody.

## 2. Where it gets published

**GitHub, public, with Releases.** It is the download URL, the changelog, the issue tracker and
the credibility all at once, and Homebrew requires a URL the developer publishes. Add a
`LICENSE` (MIT is the default for this kind of utility), push to `mshykov/image-shrink`, attach
the notarised DMG to each tagged release.

**A one-page site** (GitHub Pages or Vercel), because Reddit and Hacker News links to a bare
repo convert far worse:

- the sentence the app exists for — a phone photo is 8 MB, the form accepts 2;
- a 15–20 second screen recording of the right-click → limit → done flow, autoplaying, muted;
- one download button, plus `brew install --cask image-shrink` once that lands;
- requirements (macOS 13+, Apple silicon and Intel), size, price;
- the privacy line, which is a real selling point against every web converter: **images never
  leave the Mac, there is no network code in the app at all**;
- changelog, support email, uninstall instructions.
- The favicon / apple-touch-icon / manifest checklist in `~/.claude/CLAUDE.md` applies to this
  page — all six `<head>` lines, or iOS shows a globe.

**Homebrew cask** — the developer audience installs this way and it costs nothing to maintain.
Requirements that matter: the download must be the developer's own published URL (GitHub
Releases qualifies), it must pass Gatekeeper (so notarisation first), and new casks need
demonstrable public interest — [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) is
explicit that recent apps are considered only with "substantial, independently verifiable
public interest". Submit after the launch traffic, not before.

**Mac App Store — skip it.** The sandbox cannot write `.workflow` bundles into
`~/Library/Services` or touch the `pbs` domain, which is the entire Finder integration. It
would have to be rebuilt as an app extension, and the App Store review of a
"convert to JPEG" utility is not worth that rewrite.

**[Setapp](https://setapp.com/developers)** — a real revenue channel with no marketing effort,
worth doing once v1 is out. Their requirements: Developer ID signed, notarised, universal
binary, tested on the latest macOS, the Setapp framework integrated, your own licensing and
update frameworks disabled, and no version number in the app name or bundle id.

**Directories:** AlternativeTo (list it against ImageOptim, Squash, TinyPNG — people search
that way), MacUpdate, and the small launch boards (Uneed, DevHunt, Microlaunch, Tiny Launch).
Low effort, slow trickle, good for backlinks.

## 3. Free or paid

- **Free and open source** is the right call for v1.0. It is a single-purpose utility competing
  with free web converters; the reach and the goodwill are worth more than the first $200, and
  r/macapps and Hacker News are markedly kinder to it.
- If it gets traction, the money is in **Setapp** (recurring, no support burden of payments) or
  a small one-time licence through a merchant of record — Lemon Squeezy, Paddle or Gumroad —
  which matters from Ukraine because they handle VAT and invoicing for you. Do not build your
  own Stripe checkout for a $7 app.
- Keep the free version complete either way. A crippled free tier on a utility this small reads
  as hostile.

## 4. Launch sequence

**T-7 — the things a stranger needs.** Repo public with LICENSE and a README GIF; notarised
universal DMG tested on a clean Mac; site live; support email; changelog.

**T-3 — the assets.** A 20-second video (the pain first: mail rejects the attachment), three
screenshots in both appearances, a 1280×800 OG image, and the one-sentence description reused
everywhere: *"Right-click any photo in Finder and get a JPEG under the size limit you pick."*

**T-1 — write the posts in advance.** A Show HN title, a Product Hunt tagline plus the first
comment, the r/macapps post, three social posts.

**T-0, a Tuesday–Thursday.**
- **Product Hunt** goes live at 00:01 PT automatically — there is no later slot — and the first
  four hours carry the most weight, with upvote counts hidden. You may ask people to *look*,
  never to upvote; coordinated voting is detected and punished. Answer every comment.
- **Show HN** the same morning, US East hours. Plain title, no adjectives:
  `Show HN: Image Shrink – right-click a photo in Finder, get a JPEG under 2 MB`. Say in the
  first comment why it exists and what it does not do. Stay for the whole day and answer the
  criticism straight — that is what the audience is actually judging.

**T+1 onwards, one channel a day** — spreading it out beats one loud day:
r/macapps (its rules, below), r/MacOS, r/SideProject, r/opensource, Mastodon and Bluesky with
the video, Indie Hackers, then the directories.

**Ongoing, and this is the channel that keeps paying:** people ask "how do I get this photo
under 2 MB" constantly on Ask Different, the MacRumors forums, Apple Support Communities and
Quora. Answer the question properly first, mention the app as the author, once. Point the site
at the same phrasing — "HEIC to JPEG under 2 MB on Mac", "compress photo for upload macOS" —
because that is the search that brings people a year later.

**Writers worth one short email each:** MacStories, Six Colors, 9to5Mac, MacRumors, Michael
Tsai. Two sentences, the link, the video, no press release.

## 5. The rules that get posts removed

- **r/macapps:** self-promotion once per 30 days per developer, counted from your last app post
  even if it was removed; main-feed promotion needs their PCP template; you must disclose that
  you are the developer; links must be the official source with no URL shorteners; and you need
  10 karma in the subreddit before promoting your app in comments.
- **r/apple:** self-promotion is effectively not allowed. Do not spend a post there.
- **Hacker News:** `Show HN:` prefix, no marketing voice, never ask for upvotes, and do not
  post the same project twice in a short window.
- **Product Hunt:** asking for upvotes anywhere — DMs, groups, Slack — risks the launch.

## 6. Measuring it

Privacy-friendly analytics on the site only (Plausible or Umami), never in the app: the
"nothing leaves your Mac" claim is the strongest thing the app has and one telemetry ping
destroys it. Download counts come from the GitHub releases API, referrers from the site.

Sources:
[Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) ·
[Setapp app requirements](https://docs.setapp.com/docs/preparing-your-application-for-setapp) ·
[Preparing for a Product Hunt launch](https://www.producthunt.com/launch/preparing-for-launch) ·
[Sparkle](https://sparkle-project.org)
