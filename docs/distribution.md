# Distributing Image Shrink

How this app gets from `build/` onto other people's Macs: what a release has to satisfy, how
`release.sh` satisfies it, and where the result is published. Written 2026-09-22; the state
section below is measured, not assumed. (Pricing and the launch plan are not in this repo.)

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
  short FAQ; the full icon set is in place — SVG icon, `.ico` fallback, `apple-touch-icon`,
  `apple-mobile-web-app-title`, `theme-color` and a manifest — plus the OG card and JSON-LD;
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

Sources: [Acceptable Casks](https://docs.brew.sh/Acceptable-Casks) ·
[Setapp app requirements](https://docs.setapp.com/docs/preparing-your-application-for-setapp) ·
[Sparkle](https://sparkle-project.org)
