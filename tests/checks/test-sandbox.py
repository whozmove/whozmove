# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# Every test runs in a sandbox of its own (tests/sandboxed.sh), which lets it write only to the temporary folders, so a
# test that reaches for your home folder fails rather than changing it. A test script is any executable .sh in a tests
# folder (the ones sourced, tests/lib.sh and the rest, aren't executable), and it sources tests/sandboxed.sh on the line
# straight after its `cd`, before it does anything else. A sandbox can't stop an Apple Event, which could type into your
# real terminals, so no test sends one: no AppleScript run from a tests folder, nor NSAppleScript or OSAScript in its C
# or Objective-C.
for folder, folders, files in os.walk("."):
    folders[:] = sorted(f for f in folders if f != ".git")
    if "tests" not in os.path.normpath(folder).split(os.sep):
        continue
    for name in sorted(files):
        path = os.path.relpath(os.path.join(folder, name))
        if not name.endswith(".sh") or not os.access(path, os.X_OK) or os.path.islink(path):
            continue
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
        at = next((i for i, line in enumerate(lines) if line.startswith("cd ")), None)
        wrapped = at is not None and at + 1 < len(lines) and re.fullmatch(
            r'\. (\.\./)*tests/sandboxed\.sh (--downloads )?"\$@"', lines[at + 1])
        if not wrapped:
            problems.append("%s doesn't run in its own sandbox: put `. tests/sandboxed.sh \"$@\"` on the line "
                            "after its `cd` to the checkout" % path)
    for name in sorted(files):
        path = os.path.relpath(os.path.join(folder, name))
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        sends = re.search(r"\bosa(?:script)\b", text) or (
            name.endswith((".m", ".c", ".h")) and re.search(r"\b(?:NSAppleScript|OSAScript)\b", text))
        if sends:
            problems.append("%s sends Apple Events (%s), which a test's sandbox can't stop: test with a stand-in "
                            "instead" % (path, sends.group(0)))
