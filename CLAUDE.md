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
| `Sources/ImageShrink/CLI.swift` | `--cli` headless mode, `--selftest` (drives `AppModel` without a window) and `--snapshot` (renders the window to a PNG). |
| `Sources/ImageShrink/Glass.swift` | Liquid Glass helpers with pre-26 fallbacks, window chrome, window material. |
| `Sources/ImageShrink/Thumbnail.swift` | Row previews, decoded off the main thread. |
| `Resources/Info.plist` | Bundle metadata, the `NSServices` entry, document types. |
| `scripts/make-quick-action.sh` | Generates both Automator `.workflow` bundles as plain plist XML. |
| `scripts/lib.sh` | Removing earlier installs and pruning their services preferences. |
| `tools/make-icon.swift` | Draws the icon at every size; there is no source art to keep. |

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
- **`log show` is unavailable in some agent shells**, which is why the app keeps its own
  trail at `~/Library/Logs/ImageShrink.log`. Use that to verify a Quick Action run.
- GUI verification from an agent session is limited: `screencapture` needs Screen Recording
  permission. Use `--selftest` (drives the real `AppModel`) instead of trying to click, and
  `--snapshot out.png` to see the layout.
- **`--snapshot` shows layout, not glass.** It captures the hosting view with
  `cacheDisplay`, and Liquid Glass and materials sample a backdrop that does not exist
  offscreen, so controls come out invisible. Blank *content* means something is wrong;
  invisible *buttons* are expected.
- **Do not add `.fullSizeContentView` to the window.** With it the scrolling `Form` renders
  empty (found via `--snapshot`, both with and without a clear window background). The
  transparent titlebar alone gets the seam-free look.

## Design

Liquid Glass, following Apple's guidance that glass is the *control layer floating above
content* — never glass on glass, never behind text that has to stay legible.

- Only the floating action bar is glass (`.buttonStyle(.glass)` / `.glassProminent`, grouped
  in a `GlassEffectContainer` so neighbouring capsules blend instead of stacking). Settings
  stay in a standard grouped `Form`, which already carries the system material.
- Everything glass-related lives in `Glass.swift` behind `if #available(macOS 26.0, *)`, with
  a `.regularMaterial` fallback, so the app still builds and looks right on macOS 13–15.
  Deployment target stays 13.0 — keep the fallbacks when adding glass elsewhere.
- The icon is a superellipse (n≈5), matching Apple's icon grid rather than a circular-corner
  rounded rect, with a single specular highlight. `tools/make-icon.swift` draws it.

## Never inflate

`encodeToTarget` aims at `min(limit, originalBytes)`, not at the limit. Without that, a
1.2 MB HEIC converted with a 2 MB limit comes out at 2.0 MB — measured on a real iPhone
photo, quality 84 — because JPEG needs roughly twice the bytes of HEIC for the same picture.
The no-inflation goal has its own quality floor (`noInflationFloor`, 0.60), higher than the
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

- Ad-hoc code signing (`codesign -s -`) is deliberate: this is a local tool, not a
  distributed one. Notarisation would only matter if it were downloaded.
- The UI is English, matching the system language on this machine.
- Bundle id `dev.shykov.imageshrink`; changing it breaks the installed Quick Action, which
  hard-codes it.
