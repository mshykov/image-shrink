# Changelog

## 1.3.0 — unreleased

- **The whole pill is clickable, not just the digits.** The capsule behind a size limit is drawn
  by the container, so the button underneath was only the text — clicking a few pixels above or
  below it did nothing. The hit area is the whole segment now, corners included.
- **Keyboard.** Every action has a menu item and a shortcut: convert ⌘↩, stop ⌘., the size limit
  ⌘1 … ⌘5, undo ⇧⌘Z, show in Finder ⇧⌘R, clear ⌘⌫. The limit picker takes focus and answers
  ← and →. Items grey out when they would do nothing, and the size limit menu shows which one
  is in force.
- The remove button on a row and the settings button in the menu bar panel got a 22 pt hit area
  instead of a 15 pt glyph.

## 1.2.0 — 2026-09-23

- A build flavour for Setapp: `IMAGESHRINK_FLAVOR=setapp` leaves Sparkle out, drops the feed
  keys from the bundle and hides the update menu item, because that channel installs and
  updates its own apps. Nothing changes for the direct download or Homebrew.
- **A folder works wherever a file does.** Drop one on the window or the menu bar icon, pick it
  in Add Files, or pass it on the command line: every image inside is taken, subfolders
  included. Hidden files and the insides of packages — a `.photoslibrary`, an `.app` — are left
  where they are. Dropping a folder used to do nothing at all.
- **A failed conversion now offers a way out.** The panel that reports a windowless run has a
  **Fix** button: it opens the window with the files that did not convert, where each row says
  why and the limit and destination are right there.
- Images dropped on the menu bar icon report failures instead of claiming success. Every result
  counted as converted, and the finish sound agreed with it, even when nothing was written.
- **A CMYK original now comes out as sRGB.** A CMYK JPEG is what a print workflow hands back,
  and it is valid — but it displays inverted or washed out in much of what people upload to,
  when it is accepted at all. Anything that is not RGB or grayscale is redrawn in sRGB before
  encoding. Grayscale is left alone: it is understood everywhere and would cost three times the
  bytes as RGB.
- The row estimates measure the same image the converter will write. They were measuring the
  original's colour space and, for transparent PNGs, its alpha — so the numbers described a file
  that was never going to be produced.

## 1.1.0 — 2026-09-22

- **The app updates itself.** Sparkle reads a feed of releases and installs them in place,
  verifying each downloaded update against the public key inside the app before it runs;
  it asks on the second launch whether to do that automatically, and the answer is yours to
  change in its dialog. A copy installed through Homebrew updates the same way: the cask is
  marked `auto_updates`, so `brew upgrade` leaves the app to it.
- This is the first version that makes any network connection at all, and the only one it makes:
  the update check, to GitHub. Images are still converted entirely on your Mac.

## 1.0.0 — 2026-09-22

The first public build.

- Right-click any image in Finder → **Quick Actions** → convert it to a JPEG under a limit you
  pick at conversion time: 500 KB, 1, 2 or 5 MB, or your own number.
- **Convert to JPEG Now** and a shortcut (⌃⌘J by default, recorded in the app) convert the
  selection with the last used settings, without opening a window.
- One Quick Action per preset: Email 2 MB, Web 1 MB, Messenger 500 KB.
- HEIC, JPEG, PNG, TIFF, GIF, WebP and camera raw in; JPEG out, next to the original, named for
  the size it reached — `IMG_7301-2MB.jpg`.
- Never larger than the original: the limit is a ceiling, not a target.
- Live estimates for a whole batch, and a resize fallback for a file that cannot reach the limit
  on quality alone.
- Undo a batch, keep or strip metadata, keep the originals or move them to Trash.
- A Shortcuts action, a menu bar item that takes drops, notifications, sound, Dock progress.
- The window follows the Claude Design prototype: three glass layers, one accent, and a light
  appearance that was measured rather than assumed.
- Universal build (Apple silicon and Intel), signed with a Developer ID, hardened runtime.
