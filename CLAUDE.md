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
| `Sources/ImageShrink/CLI.swift` | `--cli` headless mode, and `--selftest` which drives `AppModel` without a window. |
| `Resources/Info.plist` | Bundle metadata, the `NSServices` entry, document types. |
| `scripts/make-quick-action.sh` | Generates the Automator `.workflow` as plain plist XML. |
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
- **`log show` is unavailable in some agent shells**, which is why the app keeps its own
  trail at `~/Library/Logs/ImageShrink.log`. Use that to verify a Quick Action run.
- GUI verification from an agent session is limited: `screencapture` needs Screen Recording
  permission. Use `--selftest` (drives the real `AppModel`) instead of trying to click.

## Conventions

- Ad-hoc code signing (`codesign -s -`) is deliberate: this is a local tool, not a
  distributed one. Notarisation would only matter if it were downloaded.
- The UI is English, matching the system language on this machine.
- Bundle id `dev.shykov.imageshrink`; changing it breaks the installed Quick Action, which
  hard-codes it.
