# Image Shrink — project rules

A macOS utility that converts HEIC/JPEG/PNG to JPEG under a user-chosen size limit, driven
from a Finder Quick Action. User-facing docs live in [README.md](README.md).

## Build and test

```bash
./scripts/build.sh        # swiftc → build/Image Shrink.app (ad-hoc signed)
./scripts/smoke-test.sh   # end-to-end: generates photos, converts, asserts sizes
./scripts/install.sh      # build + install into ~/Applications and ~/Library/Services
```

- **There is no Xcode project and there should not be one.** `scripts/build.sh` compiles the
  sources with `swiftc` and lays out the bundle by hand. That keeps the whole app reviewable
  as text and buildable in one command.
- **Always compile with `xcrun swiftc`, never bare `swiftc`.** This machine has swiftly on
  `PATH` with an older toolchain (5.9); `xcrun` resolves Xcode's current one.
- Run `./scripts/smoke-test.sh` before committing anything that touches the engine. It is the
  only test there is, and it covers the size ceiling, the forced downscale, the resolution cap
  and the skip path.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/ImageShrink/Converter.swift` | The engine — quality search, downscale fallback, metadata, file naming. Used by both the window and the CLI. |
| `Sources/ImageShrink/NameReserver.swift` | Hands out output names to the parallel workers. |
| `Sources/ImageShrink/AppModel.swift` | Window state, settings persistence, the parallel run. |
| `Sources/ImageShrink/ContentView.swift` | The SwiftUI window, hosted in an AppKit `NSWindow`. |
| `Sources/ImageShrink/Theme.swift` | The design system: layers, colours, type, geometry. |
| `Sources/ImageShrink/Estimator.swift` | Size-versus-quality curves, so rows can predict the result. |
| `Sources/ImageShrink/SettingsPopover.swift` | The popover behind the toolbar's slider button. |
| `Sources/ImageShrink/MenuBar.swift` | Status item, drops on the icon, and the window-less run it starts. |
| `Sources/ImageShrink/MenuBarPanel.swift` | The panel behind the status item. |
| `Sources/ImageShrink/HUD.swift` | The floating panel that reports a run with no window. |
| `Sources/ImageShrink/History.swift` | Recent batches, shown in the menu bar panel. |
| `Sources/ImageShrink/CLI.swift` | `--cli` headless mode, `--selftest` (drives `AppModel` without a window) and `--snapshot` (renders the window to a PNG). |
| `Sources/ImageShrink/Glass.swift` | Liquid Glass helpers with pre-26 fallbacks, window chrome, window material. |
| `Sources/ImageShrink/Thumbnail.swift` | Card previews, decoded off the main thread. |
| `Sources/ImageShrink/Preset.swift` | The named presets — single source of truth for the window, the CLI and the installer. |
| `Sources/ImageShrink/Progress.swift` | Cancellation, the Dock progress bar, notifications, the finish sound. |
| `Sources/ImageShrink/Settings.swift` | App-level preferences (sound, notification, pinned instant preset). |
| `Sources/ImageShrink/SettingsView.swift` | The ⌘, window. |
| `Sources/ImageShrink/Intents.swift` | The Shortcuts action (App Intents). |
| `Resources/appintents-protocols.json` | Protocol list the const-value extractor gathers. |
| `Resources/Info.plist` | Bundle metadata, the `NSServices` entry, document types. |
| `scripts/make-quick-action.sh` | Generates both Automator `.workflow` bundles as plain plist XML. |
| `scripts/lib.sh` | Removing earlier installs and pruning their services preferences. |
| `tools/make-icon.swift` | Draws the icon at every size; there is no source art to keep. |
| `tools/make-alpha-image.swift`, `tools/corner-pixel.swift` | Fixtures for the PNG transparency test. |

## Things that bite

- **Concurrency and output names.** Workers run in parallel, so checking the disk for a free
  name is not enough — two files converted at once both see it free. Every output name must
  come from `NameReserver`. This was a real bug: two sources collapsed into one file.
- **Orientation.** Downscaling goes through `CGImageSourceCreateThumbnailAtIndex` with
  `kCGImageSourceCreateThumbnailWithTransform: false`, so the pixels stay in their stored
  orientation and the EXIF orientation tag stays valid. If you ever set that to `true`, the
  tag must be dropped in the same change or every rotated photo comes out sideways.
  `Remove metadata` also keeps orientation, for the same reason.
- **Never delete an original outright.** `Move originals to Trash` uses `trashItem`. Keep it
  that way — a conversion is lossy and the user may want the original back.
- **The Quick Action is hand-written plist**, modelled on what Automator saves. The pieces
  that matter: `workflowTypeIdentifier = com.apple.Automator.servicesMenu`,
  `serviceInputTypeIdentifier = …fileSystemObject.image`, and `inputMethod = 1` so the shell
  script gets the paths as `"$@"`. It calls `open -b dev.shykov.imageshrink "$@"`, which
  reaches `application(_:open:)` in the app.
- **`NSSendFileTypes` in the workflow's own `Info.plist` is not optional.** Without it the
  service registers fine and `pbs -dump_pboard` lists it, but the menu item never appears —
  there is nothing for Finder to match the selection against. Apple's
  `/System/Library/Services/Set Desktop Picture.workflow` is the reference: same key, same
  `public.image` value. This cost a whole round trip to find; do not "simplify" it away.
  Check with `pbs -dump_pboard | grep -A12 'Convert to JPEG.workflow'`.
- **The Finder shortcut is recorded in the app**, CleanShot style, not in System Settings.
  `Shortcut` reads and writes `key_equivalent` in the `pbs` domain's `NSServicesStatus`
  entry through `CFPreferences` and then runs `pbs -flush`; verified that an ordinary process
  can write there. The menu title must stay free of key glyphs, or recording a new shortcut
  leaves a stale title behind — and the title is part of the preference key.
  `install.sh` carries an already recorded shortcut across a reinstall (`existing_shortcut`).
- **Quick Actions are switched on from `install.sh`**, by writing
  `pbs NSServicesStatus` entries keyed `"<CFBundleIdentifier> - <menu title> - <NSMessage>"`
  with `presentation_modes.ContextMenu = 1`. Without that the user has to enable them in the
  Finder menu's Customize… sheet. `key_equivalent` in the same entry is the keyboard
  shortcut (⌃⌘J, written `@^j`).
- **Renaming a Quick Action orphans its preference entry** — the key contains the menu title,
  so the old one lingers in System Settings → Keyboard Shortcuts → Services. `install.sh`
  prunes every `dev.shykov.imageshrink*` key through `defaults export | python3 | defaults
  import` before writing the current ones; `plistlib.load` needs a seekable stream, so it
  reads with `loads(stdin.buffer.read())`.
- **No parentheses in a Quick Action title.** `defaults write … -dict-add` cannot parse a key
  containing them (`Could not parse: … (Instant) …`), which is why the instant action is
  called “Convert to JPEG Now”.
- **The instant action runs the binary directly**, `…/Contents/MacOS/ImageShrink --cli
  --saved --quiet`, so there is no window and no dock icon. `--saved` builds its settings by
  constructing `AppModel`, which reads the same `UserDefaults` the window writes — keep it
  that way rather than duplicating the key list.
- **`NSApp` is nil in the CLI paths and traps when unwrapped.** Anything touching the Dock
  tile, `NSApp.isActive` or the icon has to go through `NSApp?`. This crashed `--selftest`
  (exit 133, no output) the moment the Dock progress bar was added.
- **Never name a `UserDefaults` suite after the bundle identifier.** macOS logs "does not
  make sense and will not work" and the store misbehaves; inside the bundle
  `UserDefaults.standard` already is that domain.
- **The engine's quality floors are load-bearing.** `noInflationFloor` is 0.50: a real
  1.2 MB iPhone HEIC needs about q60 to match its own size, so at 0.60 the rule sat exactly
  on the edge — the smoke test flickered between q60 fitting and not fitting, which looked
  like an engine bug and was not.
- **The Shortcuts action needs two build steps, not just a source file.** `swiftc` must run
  with `-wmo` (without it `-emit-const-values-path` silently produces nothing) and with
  `-const-gather-protocols-file Resources/appintents-protocols.json`; then
  `appintentsmetadataprocessor` turns that into `Contents/Resources/Metadata.appintents`.
  `scripts/build.sh` does both and skips gracefully when the processor is missing. Check the
  result with `python3 -c "import json;print(json.load(open('…/extract.actionsdata'))['actions'])"`.
- **Never pin a height on a grouped `Form`** — it is a scroll view, so the content gets
  clipped and has to be scrolled by a few pixels. `.frame(width:)` plus
  `.fixedSize(horizontal: false, vertical: true)` makes it report its real height; the
  popover then sizes itself, and the Settings window takes `hosting.fittingSize`.
- **A SwiftUI popover must be measured before it is shown.** `NSHostingController` has no
  size until it lays out, AppKit places the popover before that, and when the content then
  grows the window is pushed to the top of the screen — the popover ends up floating above
  the titlebar, attached to nothing, and no `preferredEdge` or anchor changes it. Hand over
  `preferredContentSize` and `popover.contentSize` from `view.fittingSize` first
  (`AppDelegate.sizedController`). Measured: without it the popover's top sat at the screen
  edge (949) whatever the anchor; with it, at the button's bottom (818).
- **`toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)` runs more than once** — the
  customisation palette asks for items too. Holding on to a button created there gives you
  one that may never enter the window, and a popover anchored to it floats away from the
  window entirely. Anchor to the `sender`, or look the item up in `window.toolbar?.items`.
- **On macOS a `TextField`'s first argument is a label, not a placeholder.** It renders
  beside the field and wraps. Placeholders go in `prompt:`, with `.labelsHidden()`.
- **App Intents parameter APIs are version-gated**: `supportedContentTypes` on an array
  parameter is macOS 15+, so with a 13.0 target the images parameter takes any file and the
  engine filters.
- **`log show` is unavailable in some agent shells**, which is why the app keeps its own
  trail at `~/Library/Logs/ImageShrink.log`. Use that to verify a Quick Action run.
- GUI verification from an agent session is limited: `screencapture` needs Screen Recording
  permission. Use `--selftest` (drives the real `AppModel`) instead of trying to click, and
  `--snapshot out.png` to see the layout.
- **`--snapshot` shows layout, not glass**, and not scroll-view content either — see the
  design section. It renders the hosting view's layer tree; materials sample a backdrop that
  does not exist offscreen, so they come out flat or invisible.
- **Do not add `.fullSizeContentView` to the window.** With it the scrolling `Form` renders
  empty (found via `--snapshot`, both with and without a clear window background). The
  transparent titlebar alone gets the seam-free look.

## Design

The window follows the Claude Design prototype in `docs/prototype/` — a list, not a grid,
with the numbers doing the talking.

- **Every row carries its own estimate.** Before anything is converted each file shows
  `2,5 MB → ~1,9 MB`, the quality it will land at, and a bar for how much survives. This is
  the feature the layout exists for, and it is why `Estimator` exists.
- **Three states, one list.** Idle shows estimates; converting shows the live stage per row
  ("Searching for the largest quality that fits 2 MB — pass 3 of 6") with the settings locked;
  finished turns the header green and swaps the footer for Undo / Show in Finder.
- **`Theme.swift` holds the system**: three glass layers (L1 window, L2 flat content panel,
  L3 floating popover — glass never sits on glass), one accent, five text sizes, radii
  16 → 14 → 12 → 8, spacing 6 · 10 · 12 · 16 · 24. Colours: accent for the chosen limit and
  the primary button, green only on numbers that went down, orange for a file that could not
  reach the limit, red only for moving originals to Trash.
- **No disabled primary button**: with an empty queue there is no footer at all.
- **Light appearance is not free.** `--snapshot-light` renders it (and the capture fills its
  own backdrop from `windowBackgroundColor`, or a light render looks broken for no reason).
  Two things had to change for it: the prototype's palette is the dark-mode one, so
  `Theme.saved`/`attention`/`destructive` are now dynamic colours with the darker siblings
  macOS uses on white; and `.tertiary` text sits below the system's 52 % floor and stops
  reading — captions use `Theme.caption` instead. The content panel is near-white with a
  hairline in light, where a translucent wash would vanish into the window.
- **Motion needs measuring, not guessing.** `--snapshot-motion <dir>` captures frames while
  the limit changes; scanning them for the accent colour showed the capsule's x position per
  frame. That is how `matchedGeometryEffect` was ruled out (already at its destination 50 ms
  in, modifier or transaction) and replaced with a single capsule positioned from a
  `PreferenceKey` of the pill frames — and how the spring was ruled out in favour of a
  timing curve (a spring had it arriving by 100 ms of its nominal 220).
  Beware the y band: a scan aimed at the wrong rows measured thumbnail pixels and said
  nothing changed.
- **Motion belongs on the container, not on each child.** The limit capsule uses
  `matchedGeometryEffect`, and with `.animation(…)` on every pill it stuttered: the effect
  needs one transaction, so the animation sits on the group. `Theme.limitChange` (220 ms,
  the prototype's number) drives the capsule and the custom field's transition;
  `Theme.numbers` settles estimates, bars and totals, with `.numericTransition()` rolling
  the digits on macOS 14+. Every one of them is skipped under Reduce Motion.
- **No button wraps.** `PrimaryButton` and `SecondaryButton` pin `.lineLimit(1)` and
  `.fixedSize()`; a two-line button label is a defect, not a layout outcome.
- **The window is the exception, not the product.** Conversions started in Finder or by
  dropping on the menu bar icon report through `ConversionHUD` — a floating panel under the
  menu bar that lingers six seconds — and never open a window. Closing the window leaves the
  app in the menu bar and drops the Dock icon (`setActivationPolicy(.accessory)`); the panel
  carries the limit, a drop zone, recent batches and Quit.
- Numbers use `.tabularNumbers()` so they stop jittering as estimates update.

### Estimates

`Estimator` measures a real size-versus-quality curve per file: four full-size encodes,
0.1–0.6 s, then `log(bytes)` is interpolated linearly in quality to answer "what fits 2 MB?"
instantly. Changing the limit is interpolation; changing the resolution invalidates the curves
and re-measures in the background.

A downscaled proxy was tried first and is not usable: measured against the truth it lands
between 0.42× and 1.39× depending on how smooth the picture is. The estimator mirrors the
converter's rules — the skip path, the no-inflation ceiling and both quality floors — so the
preview and the result agree; measured within a few per cent on the test images.

### Looking at the layout without Screen Recording

`--snapshot` renders the window offscreen, but **a scroll view's content never appears**: an
offscreen window gets no display cycle, so the rows are never drawn. A solid colour in the
list's place renders fine, which is how that was pinned down — blank *content* is the capture,
not a bug. `scripts/design-probe.sh` works around it by building a copy whose list does not
scroll, and renders the idle, finished and popover states. Glass and materials still come out
invisible in any capture, so judge layout and typography there, never the finish.

## Never inflate

`encodeToTarget` aims at `min(limit, originalBytes)`, not at the limit. Without that, a
1.2 MB HEIC converted with a 2 MB limit comes out at 2.0 MB — measured on a real iPhone
photo, quality 84 — because JPEG needs roughly twice the bytes of HEIC for the same picture.
The no-inflation goal has its own quality floor (`noInflationFloor`, 0.50), higher than the
hard floor, so matching the original's size never costs more than it is worth; when 0.60 is
not enough the hard limit takes over and the file is allowed to grow. Same photo after the
rule: 1.2 MB at quality 61. `scripts/smoke-test.sh` asserts it with an 8 MB limit on a
2.5 MB HEIC.

## Naming the outputs

Every output is `<original name><suffix>.jpg`, where an empty suffix setting means the
finished file's own size rounded up a fixed ladder — 100KB, 500KB, 1MB, 2MB, 3MB, 5MB, 10MB,
then whole MB above that. The size is of the *result*, so the name can only be chosen after
encoding: `outputURL` is called with `encoded.data.count`, not before the work as it used to
be. A suffix typed into the field wins over the automatic one.

Two earlier attempts were wrong and should not come back: `-small` (says nothing about a 2 MB
file) and naming after the *limit* (a 1.2 MB result labelled `-2MB` because the limit was
2 MB).

When two sources in one batch share a base name — `IMG_7323.jpg` and `IMG_7323.HEIC` — both
get their source format in the name. `NameReserver` is constructed with the whole source
list so it knows this before any worker starts; otherwise whichever finished first kept the
plain name and the names changed from run to run.

## Conventions

- **Signing picks the personal Developer ID**, never the work one: `build.sh` matches
  "Developer ID Application" (Maksym Shykov, 64HRGLZCS4) and falls back to ad-hoc when there
  is none. `IMAGESHRINK_SIGN_IDENTITY` overrides it. Notarisation would only matter if the
  app were downloaded rather than built here.
- **The app installs into `/Applications`** (`IMAGESHRINK_APP_DIR` overrides; it falls back
  to `~/Applications` when that is not writable). The Finder actions call the binary by
  absolute path, so `install.sh` exports the folder to `make-quick-action.sh` and removes any
  copy from the other location — two copies would leave the actions pointing at a stale one.
- The UI is English, matching the system language on this machine.
- Bundle id `dev.shykov.imageshrink`; changing it breaks the installed Quick Action, which
  hard-codes it.
- **Input formats are declared explicitly** in `Resources/Info.plist` and in the Quick
  Actions' `NSSendFileTypes` — `public.image` alone works, but naming PNG, HEIC, TIFF, GIF,
  WebP and raw leaves no doubt about what Finder should offer them for.
