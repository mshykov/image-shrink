# Contributing

Thanks for looking. Image Shrink does one thing — a JPEG under a size limit, from a hot key or
Finder — and the quickest way to have a change accepted is to keep it inside that.

## Building it

```bash
./scripts/build.sh        # swiftc → build/Image Shrink.app
./scripts/smoke-test.sh   # converts real photos and asserts the results
./scripts/install.sh      # installs it, then lets the app install its Finder actions
```

There is **no Xcode project and there should not be one**: `scripts/build.sh` compiles the
sources with `swiftc` and lays the bundle out by hand, which keeps the whole app reviewable as
text and buildable in one command. Compile with `xcrun swiftc`, never bare `swiftc` — a toolchain
on `PATH` may be older than Xcode's.

`CLAUDE.md` is the long-form map of the codebase: what each file does, and the traps that have
already cost someone a day. Read the section that covers what you are touching.

## Before you open a pull request

- **Run `./scripts/smoke-test.sh`.** It is the only test there is, and it covers the size
  ceiling, the forced downscale, the resolution cap, cancellation and PNG transparency. Anything
  touching `Converter.swift` or `Estimator.swift` must pass it.
- **If you changed the window, show it.** `./scripts/design-probe.sh build/out` renders the list,
  the finished state and the popover in both appearances; attach the PNG. Screen recording is not
  available to every reviewer, and "looks fine here" is not reviewable.
- **Keep the design system in `Theme.swift`.** Colours, radii, spacing and motion come from
  there; a literal `Color(red:…)` or a hard-coded `16` in a view is the thing reviews will catch.
- **Commits are signed** (the branch rule enforces it) and messages are conventional and
  imperative: `fix: the limit capsule really slides`.

## How a change lands

Branch, push, open a pull request — that is the only way in, and the maintainer works the same
way. `main` takes no direct pushes at all. The `build` check has to pass, every review thread has
to be resolved, and the merge is a squash, so `main` stays a straight line of one commit per
change.

## What is likely to be turned down

- Other output formats. JPEG out is the point; PNG or WebP out is a different app.
- Anything that sends an image anywhere. The app has no network code, and that is a feature
  people choose it for.
- Telemetry, accounts, update pings.
- A second way to do something that already has one.

Small fixes, a format ImageIO reads that we handle badly, a locale where the numbers read wrong,
a macOS version where something breaks — all very welcome. Open an issue first if the change is
large enough that you would be annoyed to have it declined.
