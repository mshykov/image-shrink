# Setapp

What a Setapp build of Image Shrink is, what already holds, and the parts only their SDK and
their vendor portal can supply. The technical runbook for the direct channel is
[distribution.md](distribution.md); this file is the delta.

## The build

```bash
IMAGESHRINK_FLAVOR=setapp ./scripts/build.sh
./build/Image\ Shrink.app/Contents/MacOS/ImageShrink --cli --distribution
```

```
channel: setapp
updates: handled by the channel
feed: none
```

That flavour differs from the direct one in exactly three ways, and each is checkable:

- **No Sparkle.** The framework is not linked or embedded, so `Contents/Frameworks` does not
  exist. Setapp installs and updates the apps it distributes, and a second updater replacing
  the same bundle is how a copy ends up half-updated.
- **No `SUFeedURL` or `SUPublicEDKey`** in `Info.plist`. A feed in a build that cannot update
  itself is dead weight and the first thing a reviewer would ask about.
- **No "Check for Updates…" menu item.** An item that opens a GitHub releases page would send
  someone out of the thing that installed the app.

Everything else is the same app: same engine, same Finder Quick Actions, same window.

## What already satisfies their requirements

Verified on the build, not assumed:

| Requirement | State |
| --- | --- |
| Developer ID signature | ✅ `Developer ID Application: Maksym Shykov (64HRGLZCS4)`, hardened runtime, secure timestamp |
| Notarised | ✅ `release.sh` notarises and staples both the app and the disk image |
| Universal binary | ✅ `x86_64 arm64`, and the Intel slice has been run under Rosetta |
| Tested on the latest macOS | ✅ CI builds and runs the suite on the macOS 26 runner every pull request |
| Own licensing disabled | ✅ there has never been any — the app is free and MIT |
| Own updater disabled | ✅ the flavour above |
| No IAP, no donations, no paid extras | ✅ none exist |
| No version number in the app name or bundle id | ✅ `Image Shrink`, `dev.shykov.imageshrink` |
| A privacy policy URL | ✅ https://mshykov.github.io/image-shrink/privacy.html |
| A demo/trial build | n/a — this is the real thing, with nothing held back |

## What is still missing, and needs their side

1. **`Setapp.framework` (or the Vendor API).** Distributed to registered vendors, so it cannot
   be fetched the way Sparkle is. The insertion point is ready: the flavour switch already
   exists, and `Updater.isManagedExternally` is the single place the app asks how it is
   distributed. Integration is then linking the framework and whatever activation call their
   current SDK requires.
2. **A vendor account and the agreement**, which is the step that decides whether any of this
   happens at all.
3. **Store metadata**: description, feature list, categories, icon in their sizes, screenshots
   and the release notes format their portal expects.

## Questions only you can answer

You worked there; these are the ones where the public documentation stops.

- **Does a free, open-source app fit the payout model?** Vendors are paid from the subscription
  pool by usage. A tool that is also a free download elsewhere is an unusual shape, and it is
  better to know their view before building anything to suit them.
- **Bundle id.** Same `dev.shykov.imageshrink` for both channels, or a distinct one for the
  Setapp build? The Finder Quick Actions hard-code the identifier, so the answer changes
  whether both copies can sit on one Mac without fighting over the services entries.
- **Do the Finder Quick Actions pass review?** The app writes `.workflow` bundles into
  `~/Library/Services` and enables them in the `pbs` domain on first launch. It is not
  sandboxed, so nothing forbids it, but it is the sort of thing a reviewer asks about — and it
  is also the app's headline feature, so it cannot simply be dropped.
- **What happens on deactivation?** If a subscription lapses or the app is not activated, does
  their framework expect the app to stop working, and what is the current expectation about how
  that is presented?
- **Do they want the update menu item gone entirely**, as it is now, or replaced by something
  that points at Setapp?

## What stays the same either way

The direct channel keeps working: GitHub releases, the Homebrew cask and Sparkle are untouched
by any of this. A Setapp build is an additional artefact from the same source, not a fork.
