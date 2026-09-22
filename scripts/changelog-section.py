#!/usr/bin/env python3
"""Writes one version's CHANGELOG entry to a file, for use as release notes.

Kept out of release.sh because a Python heredoc inside a shell heredoc is how this repo has
already lost a script once: the inner terminator ends the outer block.
"""
import pathlib
import re
import sys

if len(sys.argv) != 3:
    sys.exit("usage: changelog-section.py <version> <output-file>")

version, output = sys.argv[1], sys.argv[2]
try:
    changelog = pathlib.Path("CHANGELOG.md").read_text()
except FileNotFoundError:
    sys.exit("no CHANGELOG.md here — run this from the repository root")

heading = re.compile(r"^## %s\s+—\s+(.+?)\s*$" % re.escape(version), re.M)
found = heading.search(changelog)
if not found:
    sys.exit(f"CHANGELOG.md has no '## {version} — <date>' section; write it before releasing")
if found.group(1).strip().lower() == "unreleased":
    sys.exit(f"CHANGELOG.md still calls {version} unreleased; give it a date before releasing")

body = changelog[found.end():]
next_heading = re.search(r"^## ", body, re.M)
if next_heading:
    body = body[:next_heading.start()]
body = body.strip()
if not body:
    sys.exit(f"the {version} section is empty; a release with no notes is not a release")

pathlib.Path(output).write_text(body + "\n")
