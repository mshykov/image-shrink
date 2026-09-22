# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | ✅ active line — fixes ship as patch releases |
| < 1.0 | ❌ there is nothing older |

## Reporting a vulnerability

**Please do not open a public issue for a security problem.** Use GitHub's private reporting —
the **Report a vulnerability** button under [Security](https://github.com/mshykov/image-shrink/security)
— or email maksym.shykov@gmail.com. You should hear back within 48 hours; if you do not, follow
up, because it means the message was lost rather than ignored.

Please include what you did, what happened, the macOS version, and whether the app came from a
release DMG, Homebrew, or a local build.

## What is worth reporting

The app has no network code, no accounts and no telemetry, so the usual server-side surface does
not exist. What does:

- **Writing outside the chosen destination** — a crafted file name that makes a converted image
  land somewhere other than the folder you picked.
- **The Finder actions.** The app writes `.workflow` bundles into `~/Library/Services` and
  entries into the `pbs` preference domain on first launch. Anything that makes it write
  elsewhere, run something other than its own binary, or clobber another app's services entry.
- **The shell command inside a Quick Action**, which carries the path of the app's own
  executable. A way to get another path in there is a real finding.
- **Signature and notarisation**: a release DMG that fails `spctl -a -t exec`, or an app whose
  signature does not satisfy its designated requirement.

Metadata handling is a privacy matter rather than a vulnerability: EXIF and GPS are copied by
default and dropped when you switch **Remove metadata** on. If you find a path where that switch
does not take effect, report it — quietly, because it affects photos people have already shared.
