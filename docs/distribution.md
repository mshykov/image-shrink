# Distributing Image Shrink

How this app gets from `build/` onto other people's Macs, and how they find out it exists.
Written 2026-09-22; the state section below is measured, not assumed.

## 0. Where the build stands today

| Checked | Result |
| --- | --- |
| Signature | `Developer ID Application: Maksym Shykov (64HRGLZCS4)`, hardened runtime (`flags=0x10000`), secure timestamp present — notarisation-ready |
| Certificate | valid to 1 Feb 2027, so the Developer Program membership is active (notarisation needs it) |
| Architecture | universal — `lipo -archs` → `x86_64 arm64`, and the Intel slice was run under Rosetta |
| Finder actions | installed by the app itself on first launch, verified from a clean state |
| DMG | `scripts/release.sh` builds, signs, notarises and staples it; 2.3 MB |
| Notarised | **yes** — app and disk image both Accepted, both stapled; mounted the DMG and checked the app inside: universal, signature valid, ticket present, `spctl` says `accepted, source=Notarized Developer ID` |
| Version | `1.0.0` (build `1`), minimum macOS 13.0 |
| Updates | "Check for Updates" opens the releases page; no appcast yet |
| Repo | local only, no remote — the site and the download links assume `github.com/mshykov/image-shrink` |

What is left is outside the build: publishing the repo, turning the Pages site on, and the
recording. The DMG on disk is ready to hand to a stranger.

## 1. Make the build shippable

### 1.1 The app installs its own Finder actions — done

Everything the app is *for* — the Quick Actions, the ⌃⌘J hotkey — used to be installed by
`scripts/install.sh`, so a downloaded copy would have arrived as a window with no right-click
entry and no shortcut. `Services.swift` now does it from inside the app:

- `build.sh` generates the five `.workflow` bundles into `Contents/Resources/Services/` before
  signing, with `@IMAGESHRINK_BINARY@` where the executable path goes — a download can sit
  anywhere, and a Quick Action calls the app by path.
- The first launch copies them into `~/Library/Services`, writes its own path into each one,
  switches them on in the `pbs` domain and reloads Finder. It repeats that whenever the app
  moves or updates, which is what the stored `version + path` stamp is for.
- **Reinstall Finder Actions** and **Remove Finder Actions…** in the app menu, and
  `--install-services` / `--uninstall-services` for scripts.
- A recorded shortcut survives: the installer reads it back before rewriting the entries.

Verified from a clean state — actions removed, stamp cleared, app launched: five actions
installed, the shortcut preserved, `automator -i` ran one end to end, and other apps' services
were left alone.

### 1.2 Universal binary — done

`IMAGESHRINK_ARCHS="arm64 x86_64" ./scripts/build.sh` compiles both and `lipo`s them together
before signing; `release.sh` passes it and refuses to continue if the result is not universal.
The const-values file for the Shortcuts metadata comes from the first architecture — one
copy describes them all. The Intel slice was checked by running it under Rosetta.

### 1.3 Notarise and staple — done, in `release.sh`

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

Keep the `.p8` outside the repository — `~/.appstoreconnect/private_keys/` is where Apple's
own tools look, and a password manager is better still. Apple lets you download that file once,
so losing it means generating a new key; an ignored folder inside the repo is not a safe place
for it, as a stray `git add -A` here proved.

`store-credentials` returning 401 is about the password, not the setup: Apple shows an
app-specific password once, at creation, and the list afterwards only shows its label. Having
several of them is fine — they do not conflict. An App Store Connect API key (`--key`,
`--key-id`, `--issuer`) avoids the whole problem and does not expire with the account password.

### 1.4 Ship a DMG — done, `scripts/release.sh`

One command does the whole thing: universal build, the signature checks (Developer ID, secure
timestamp, hardened runtime — it refuses rather than producing something that cannot be
notarised), notarisation of the app and of the disk image, stapling both, and a DMG with the
drag-to-Applications symlink. It prints what Gatekeeper sees and the SHA-256 for a Homebrew
cask.

```bash
./scripts/release.sh                  # the real thing
./scripts/release.sh --skip-notarize  # a DMG for local testing, Gatekeeper will complain
```

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

**A one-page site** — it is built, in `site/`, and `.github/workflows/pages.yml` publishes it
to GitHub Pages on push. Turn Pages on in the repo settings (source: GitHub Actions) and it goes
live at `https://mshykov.github.io/image-shrink/`. What it has, and what still needs a human:

- the sentence the app exists for, the three steps, the feature grid, the privacy block and a
  short FAQ; icons, manifest, OG card and JSON-LD are all in place (the six-line icon checklist
  in `~/.claude/CLAUDE.md` is satisfied);
- **you need to add**: a support email in the footer — an issue tracker alone puts off
  non-developers — and a 15–20 second screen recording of the right-click → limit → done flow.
  The screenshots on the page are offscreen renders of the real window; a recording of it in
  use converts better and only you can capture one.

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

**T-1 — the posts are already written**, in [launch-copy.md](launch-copy.md): Show HN title and
first comment, the Product Hunt tagline and description, the r/macapps post, the social posts,
the pitch email, and the shot list for the recording. Read them once in your own voice and cut
anything that sounds like someone else.

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
