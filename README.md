# Image Shrink

A small macOS app that converts HEIC, JPEG and PNG files to JPEG **under a size limit you
pick at conversion time** — 1 MB, 2 MB, whatever. Built for the case where a phone photo is
8 MB and the form you are uploading it to accepts 2.

Right-click images in Finder → **Quick Actions → Convert to JPEG** → set the limit → convert.

## Install

```bash
./scripts/install.sh
```

That builds the app, removes anything an earlier install left behind, installs it to
`~/Applications/Image Shrink.app`, installs both Finder Quick Actions into
`~/Library/Services/`, switches them on and restarts Finder. No Xcode
project, no admin password, nothing to enable by hand in Customize….

If a menu entry still does not appear, log out and back in once — Finder caches its services
list.

The first time the app writes into Downloads, Desktop or Documents, macOS asks for permission
to that folder. That prompt is macOS, once per folder.

## Using it

**From Finder** — select any number of images, right-click, and pick one of two Quick Actions:

| Quick Action | What happens |
| --- | --- |
| **Convert to JPEG…** | The window opens with the selection loaded. Pick the limit, convert. |
| **Convert to JPEG Now ⌃⌘J** | No window at all. Converts straight away with the settings the window used last (or a preset you pin in Settings), then a sound and a notification. |
| **· Email 2 MB**, **· Web 1 MB**, **· Messenger 500 KB** | One action per preset, also without a window. |

The shortcut is written into the menu title because the Quick Actions submenu does not show
key equivalents by itself, and the app window repeats it along the bottom edge.

The shortcut works on a Finder selection without opening any menu. Change it in System
Settings → Keyboard → Keyboard Shortcuts → Services, or edit `SHORTCUT` in
`scripts/install.sh` and run it again.

**By hand** — open the app from `~/Applications` and drag files onto the window, or use
Add Files.

**From Shortcuts** — the app publishes a **Convert Images to JPEG** action, with the images,
the megabyte limit and an optional longest side as parameters. It returns the converted files,
so it can feed the next step of a shortcut.

**From the terminal**

```bash
~/Applications/Image\ Shrink.app/Contents/MacOS/ImageShrink --cli --target-mb 2 ~/Downloads/*.heic
```

`--help` lists the options: `--target-mb`, `--max-dim`, `--dest`, `--subfolder`, `--suffix`,
`--replace`, `--strip`, `--no-skip`, `--quiet`.

## Presets

| Preset | Limit | Longest side |
| --- | --- | --- |
| Email | 2 MB | original |
| Web | 1 MB | 1920 px |
| Messenger | 500 KB | 1920 px |

They are in the settings popover, each has its own Finder action, and Settings (⌘,) can pin
⌃⌘J to one of them instead of "whatever the window used last". The list lives in
`Sources/ImageShrink/Preset.swift` — the window, the CLI (`--preset`, `--list-presets`) and
the installer all read it, so adding one there adds its Finder action on the next install.

## While it runs

- **Esc stops the batch.** Images already being encoded finish; the rest stay in the list,
  ready to convert again.
- The Dock icon carries a progress bar, so a long run is legible with the window hidden.
- Runs with no window (the Finder actions) finish with a sound and a notification. Both can
  be turned off in Settings.

## Design

The window is a list, and every row answers the question you actually have: **what will this
file weigh?** Before you convert anything each row already reads `2,5 MB → ~1,9 MB · quality
78 %`, or `already under the limit`, and the numbers re-estimate the moment you change the
limit. While it runs each row says what it is doing ("Searching for the largest quality that
fits 2 MB — pass 3 of 6"); when it finishes the header turns green and the footer offers
**Undo**, which puts the new files in the Trash and brings the originals back.

## What the settings do

| Setting | Meaning |
| --- | --- |
| **Maximum file size** | The hard ceiling. Quality is searched for the best result that fits; if even low quality overshoots, the image is scaled down until it fits. |
| **Longest side** | Optional resolution cap, applied before compressing. `Original` keeps the full resolution. |
| **Save to** | Same folder as the original, a `Converted` subfolder, or a folder you choose. |
| **Move originals to Trash** | Off by default. Originals go to the Trash (recoverable), never deleted outright. |
| **Suffix** | Left empty, every output is named after its own finished size, rounded up to 100KB / 500KB / 1MB / 2MB / 3MB / 5MB / 10MB — a 1.7 MB result becomes `photo-2MB.jpg`. Type something to use that instead. |
| **Skip files already under the limit** | A JPEG that already fits is left untouched instead of being re-encoded (re-encoding always loses quality). |
| **Keep original dates** | Copies created/modified timestamps, so photos keep sorting correctly. |
| **Remove metadata** | Drops EXIF and GPS. Orientation is always kept, otherwise the picture would display rotated. |

Settings are remembered between runs, so the window opens pre-filled with what you used last.

## How the size targeting works

1. Decode the image once (HEIC, JPEG, PNG, anything ImageIO reads).
2. If the original is already smaller than the limit, aim for the original's size instead —
   see below.
3. Try quality 92. If it fits, done — no point going lower.
4. Otherwise binary-search the quality between 30 and 92 for the largest one that fits.
5. If quality 30 still overshoots, scale the image down by the square root of the overshoot
   and start again. Repeat until it fits or the image gets down to 320 px.
6. Write the JPEG, carrying EXIF/GPS/orientation across unless asked not to.

**It will not hand you a bigger file than you gave it.** HEIC stores the same photo in about
half the bytes of a JPEG, so re-encoding a 1.2 MB HEIC at high quality sails under a 2 MB
limit while ending up at 2 MB — bigger than the original, which is the opposite of the point.
When the original already fits, the target becomes the original's own size, with a quality
floor of 60 so the picture does not get wrecked chasing the last few kilobytes. A real 1.2 MB
iPhone HEIC converts to a 1.2 MB JPEG at quality 61 instead of a 2 MB one at quality 84.

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

## What the files are called

Converted files land next to the originals, keeping the original name plus the size they
ended up at:

```
IMG_73221.jpg  2,4 MB  →  IMG_73221-2MB.jpg   2,0 MB
IMG_7323.jpg   2,5 MB  →  IMG_7323-jpg-2MB.jpg   1,7 MB
IMG_7323.HEIC  1,2 MB  →  IMG_7323-heic-2MB.jpg  1,2 MB
IMG_7322.HEIC  1,2 MB  →  IMG_7322-2MB.jpg    1,2 MB
```

`IMG_7323.jpg` and `IMG_7323.HEIC` share a base name, so both carry their source format —
decided from the whole batch before anything is written, so the same selection always
produces the same names. Originals are never overwritten unless you ask for it in
**Move originals to Trash**, which keeps the plain name instead.

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

It removes the app, every Quick Action this project ever installed (whatever it was called at
the time), their entries in the services preferences, and the saved settings. `install.sh`
runs the same cleanup first, so reinstalling never leaves stale menu items behind.
