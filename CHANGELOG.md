# Changelog

## 1.2.0 — unreleased

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
