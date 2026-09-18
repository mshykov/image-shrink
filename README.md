# Image Shrink

A small macOS app that converts HEIC, JPEG and PNG files to JPEG **under a size limit you
pick at conversion time** — 1 MB, 2 MB, whatever. Built for the case where a phone photo is
8 MB and the form you are uploading it to accepts 2.

Right-click images in Finder → **Quick Actions → Convert to JPEG** → set the limit → convert.

## Install

```bash
./scripts/install.sh
```

That builds the app, installs it to `~/Applications/Image Shrink.app`, installs both Finder
Quick Actions into `~/Library/Services/`, switches them on and restarts Finder. No Xcode
project, no admin password, nothing to enable by hand in Customize….

If a menu entry still does not appear, log out and back in once — Finder caches its services
list.

The first time the app writes into Downloads, Desktop or Documents, macOS asks for permission
to that folder. That prompt is macOS, once per folder.

## Using it

**From Finder** — select any number of images, right-click, and pick one of two Quick Actions:

| Quick Action | What happens |
| --- | --- |
| **Convert to JPEG** | The window opens with the selection loaded. Pick the limit, convert. |
| **Convert to JPEG Now** (**⌃⌘J**) | No window at all. Converts straight away with the settings the window used last, then plays a sound — a pop when it worked, a thud when something failed. |

The shortcut works on a Finder selection without opening any menu. Change it in System
Settings → Keyboard → Keyboard Shortcuts → Services, or edit `SHORTCUT` in
`scripts/install.sh` and run it again.

**By hand** — open the app from `~/Applications` and drag files onto the window, or use
Add Files.

**From the terminal**

```bash
~/Applications/Image\ Shrink.app/Contents/MacOS/ImageShrink --cli --target-mb 2 ~/Downloads/*.heic
```

`--help` lists the options: `--target-mb`, `--max-dim`, `--dest`, `--subfolder`, `--suffix`,
`--replace`, `--strip`, `--no-skip`, `--quiet`.

## Design

The window follows the macOS 26 Liquid Glass style: a translucent window material, a grouped
settings form, and a floating glass action bar at the bottom. On macOS 13–15 the glass falls
back to a standard material, so the app still looks native there.

## What the settings do

| Setting | Meaning |
| --- | --- |
| **Maximum file size** | The hard ceiling. Quality is searched for the best result that fits; if even low quality overshoots, the image is scaled down until it fits. |
| **Longest side** | Optional resolution cap, applied before compressing. `Original` keeps the full resolution. |
| **Save to** | Same folder as the original, a `Converted` subfolder, or a folder you choose. |
| **Move originals to Trash** | Off by default. Originals go to the Trash (recoverable), never deleted outright. |
| **Suffix** | Used only when the output name is already taken — e.g. converting `photo.jpg` in place produces `photo-small.jpg`. |
| **Skip files already under the limit** | A JPEG that already fits is left untouched instead of being re-encoded (re-encoding always loses quality). |
| **Keep original dates** | Copies created/modified timestamps, so photos keep sorting correctly. |
| **Remove metadata** | Drops EXIF and GPS. Orientation is always kept, otherwise the picture would display rotated. |

Settings are remembered between runs, so the window opens pre-filled with what you used last.

## How the size targeting works

1. Decode the image once (HEIC, JPEG, PNG, anything ImageIO reads).
2. Try quality 92. If it fits, done — no point going lower.
3. Otherwise binary-search the quality between 30 and 92 for the largest one that fits.
4. If quality 30 still overshoots, scale the image down by the square root of the overshoot
   and start again. Repeat until it fits or the image gets down to 320 px.
5. Write the JPEG, carrying EXIF/GPS/orientation across unless asked not to.

Files are converted in parallel, one per core.

## Development

```bash
./scripts/build.sh          # build build/Image Shrink.app
./scripts/smoke-test.sh     # generate test photos, convert, assert the results
./scripts/install.sh        # build + install app and Quick Action
./scripts/uninstall.sh      # remove both, and the saved settings
```

The app writes a short trail to `~/Library/Logs/ImageShrink.log` — that is the first place to
look if the Quick Action seems to do nothing.

## Making it yours

- **Name.** It appears in `Resources/Info.plist` (`CFBundleName`, `CFBundleDisplayName`), in
  `scripts/*.sh` (bundle folder and Quick Action titles) and in the window title in
  `AppDelegate.swift`. Avoid parentheses in a Quick Action title — `defaults` cannot parse a
  preference key containing them, which is why the instant one is “Convert to JPEG Now”.
- **Icon.** `tools/make-icon.swift` draws it in code; change the two gradient colours or the
  glyph and rebuild. To use artwork instead, drop a `.icns` at
  `Resources/AppIcon.icns` and have `scripts/build.sh` copy it rather than run the generator.
- **Bundle id** `dev.shykov.imageshrink` is referenced by both Quick Actions and by the
  preference keys; change it in all of them together or the menu entries stop working.

## Uninstall

```bash
./scripts/uninstall.sh
```
