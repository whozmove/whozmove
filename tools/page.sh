#!/bin/bash
# The panel's page, put together: panel/panel.html, with each module's styles and scripts listed at the two lines the
# page marks for them, in the order of the modules' module.json files ("order", then the module's name). So no shared
# file lists a module's page files, and a module adds its own by naming them in its module.json:
#   {"order": 20, "scripts": ["page/now-playing.js"], "styles": ["page/now-playing.css"]}
#
#   tools/page.sh --scripts    the page's scripts in the order it loads them, as paths in this checkout (tests/panel.sh)
#   tools/page.sh --styles     its styles, the same way
#   tools/page.sh <folder>     the whole page, written into a new folder (relative to where you are): panel/'s files, and
#                              each module's page files under modules/<name>/ there (build.sh, into the app). It never
#                              writes over a folder it didn't make.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
here=$PWD
cd "$(dirname "$0")/.."
exec python3 -I - "$here" "$@" <<'PY'
import json, os, re, shutil, sys

STYLES = "<!-- each module's styles: tools/page.sh lists them here, in their module.json order -->"
SCRIPTS = "<!-- each module's scripts: tools/page.sh lists them here, in their module.json order -->"
# Left in each page this writes, so it knows the folder is one of its own the next time.
MINE = ".written-by-tools-page-sh"

def modules():
    found = []
    if os.path.isdir("modules"):
        for name in os.listdir("modules"):
            path = os.path.join("modules", name, "module.json")
            if os.path.isfile(path):
                with open(path, encoding="utf-8") as f:
                    spec = json.load(f)
                found.append((spec.get("order", 0), name, spec))
    found.sort(key=lambda m: (m[0], m[1]))
    files = {"scripts": [], "styles": []}
    for _, name, spec in found:
        for kind in files:
            for file in spec.get(kind, []):
                path = os.path.join("modules", name, file)
                if not os.path.isfile(path):
                    spec_path = os.path.join("modules", name, "module.json")
                    sys.exit("tools/page.sh: %s names %s, which isn't there" % (spec_path, file))
                files[kind].append(path)
    return files

# The page's lines. Each mark must be there exactly once, or the modules' files would quietly be left out.
def page():
    with open("panel/panel.html", encoding="utf-8") as f:
        lines = f.read().split("\n")
    for mark in (STYLES, SCRIPTS):
        if lines.count(mark) != 1:
            sys.exit("tools/page.sh: panel/panel.html must have this line exactly once:\n" + mark)
    return lines

def listed(kind):
    if kind == "scripts":
        mark, tag = SCRIPTS, r'<script src="(.*)"></script>'
    else:
        mark, tag = STYLES, r'<link rel="stylesheet" href="(.*)">'
    lines, theirs = page(), modules()[kind]
    out = []
    for line in lines:
        found = re.fullmatch(tag, line)
        if found:
            out.append("panel/" + found.group(1))
        elif line == mark:
            out.extend(theirs)
    return out

def write(folder):
    if os.path.exists(folder):
        if not os.path.isfile(os.path.join(folder, MINE)):
            sys.exit("tools/page.sh: %s is already there, and isn't a page this wrote: name a new folder" % folder)
        shutil.rmtree(folder)
    lines, theirs = page(), modules()
    shutil.copytree("panel", folder)
    with open(os.path.join(folder, MINE), "w", encoding="utf-8") as f:
        f.write("Written by tools/page.sh, which may write over this folder.\n")
    out = []
    for line in lines:
        out.append(line)
        if line == STYLES:
            out.extend('<link rel="stylesheet" href="%s">' % p for p in theirs["styles"])
        elif line == SCRIPTS:
            out.extend('<script src="%s"></script>' % p for p in theirs["scripts"])
    for path in theirs["styles"] + theirs["scripts"]:
        os.makedirs(os.path.join(folder, os.path.dirname(path)), exist_ok=True)
        shutil.copy2(path, os.path.join(folder, path))
    with open(os.path.join(folder, "panel.html"), "w", encoding="utf-8") as f:
        f.write("\n".join(out))

here, arguments = sys.argv[1], sys.argv[2:]
if len(arguments) != 1:
    sys.exit("Use: tools/page.sh --scripts | --styles | <folder>")
if arguments[0] in ("--scripts", "--styles"):
    print("\n".join(listed(arguments[0][2:])))
else:
    write(os.path.join(here, os.path.expanduser(arguments[0])))
PY
