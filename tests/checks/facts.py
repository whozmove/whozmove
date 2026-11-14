# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# Each outside program's facts live in its module's Facts header (…Facts.h, and its .m), so a change in the program is
# fixed in one place: an outside app's bundle id, or a path into Claude Code's own folder or into another app's folder
# in Application Support, written as a string anywhere else in the app's code, fails here, naming the Facts header it
# belongs in. The ones still written elsewhere are those tests/facts-by-hand.txt lists, and that list only gets
# shorter. And each Facts header has its line in docs/using/install.md's "What it's tested with", which holds the
# version it was checked with, and each file named there is one.
FACTS_BY_HAND = "tests/facts-by-hand.txt"
OUTSIDE_ID = re.compile(r'"((?:com|dev|org|net|io|app)\.[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+)"')
# Claude Code's folder and its files beside it (.claude.json), but not .claude-plugin, Whozmove's own plugin's folder.
OUTSIDE_PATH = re.compile(r'"([^"\n]*(?:\.claude(?:[./][^"\n]*)?|Library/Application Support/[^"\n]+))"')

def facts_home(path):
    """Where a fact written in this file belongs: its module's or part's Facts header, or one of its own there."""
    parts = path.split("/")
    folder = "/".join(parts[:2]) if parts[0] == "app" else "/".join(parts[:2] + ["app"])
    headers = sorted(os.path.join(folder, n) for n in os.listdir(folder) if n.endswith("Facts.h")) \
        if os.path.isdir(folder) else []
    return " or ".join(headers) if headers else "a Facts header of its own in " + folder

facts_heading, facts_listed = [], set()
for line in open(FACTS_BY_HAND, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        facts_heading.append(line)
        continue
    facts_listed.add(tuple(re.split(r"\s{2,}", line.strip())))
facts_found, facts_headers = {}, set()
for top in ("app", "parts", "modules"):
    for folder, folders, files in os.walk(top):
        folders[:] = sorted(f for f in folders if f not in ("tests", "plugin", "page"))
        for name in sorted(files):
            path = os.path.join(folder, name)
            if name.endswith("Facts.h"):
                facts_headers.add(path)
            if not name.endswith((".m", ".h")) or re.search(r"Facts\.[mh]$", name):
                continue
            for at, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
                if line.lstrip().startswith("//"):
                    continue
                for kind, pattern in (("id", OUTSIDE_ID), ("path", OUTSIDE_PATH)):
                    for value in pattern.findall(line):
                        # Whozmove's own ids, and made-up ones (a print run's sample apps), are no outside app's.
                        if kind == "id" and value.startswith(("com.whozmove.", "com.example.")):
                            continue
                        # A path is skipped only for its own folder, never past it with "..".
                        if kind == "path" and ".." not in value:
                            if re.search(r"Application Support/Whozmove(?:/|$)", value):
                                continue
                            # app/shared is where macOS's own folders live: it's the platform, not an outside
                            # program. An app's id there (Terminal's) is still one, with a module of its own.
                            if path.startswith("app/shared/") and value.startswith(
                                    "Library/Application Support/com.apple."):
                                continue
                        facts_found.setdefault((path, kind, value), at)
for key in sorted(set(facts_found) - facts_listed):
    path, kind, value = key
    problems.append("%s:%d writes out %s, an outside app's %s: it belongs in %s"
                    % (path, facts_found[key], value, "bundle id" if kind == "id" else "path", facts_home(path)))
for key in sorted(facts_listed - set(facts_found)):
    if not update:
        problems.append("%s lists %s, which isn't written out there any more: tests/checks.sh --update takes it off"
                        % (FACTS_BY_HAND, "  ".join(key)))
if update and facts_listed - set(facts_found):
    with open(FACTS_BY_HAND, "w", encoding="utf-8") as f:
        f.writelines(facts_heading)
        for key in sorted(facts_listed & set(facts_found)):
            f.write("  ".join(key) + "\n")
    print("Checks: saved " + FACTS_BY_HAND)
tested = re.search(r"^## What it's tested with\s*$(.*?)(?=^## |\Z)",
                   open("docs/using/install.md", encoding="utf-8").read(), re.M | re.S)
named = set(re.findall(r"`([^`\s]+Facts\.h)`", tested.group(1))) if tested else set()
for header in sorted(facts_headers - named):
    problems.append("%s has no line in docs/using/install.md's \"What it's tested with\": add one, with the version "
                    "it was checked with" % header)
for header in sorted(named - facts_headers):
    problems.append("docs/using/install.md's \"What it's tested with\" names %s, which isn't there" % header)
