#!/bin/bash
# The panel's page, put together: panel/panel.html, with each module's styles and scripts listed at the two lines the
# page marks for them, in the order of the modules' module.json files ("order", then the module's name). So no shared
# file lists a module's page files, and a module adds its own by naming them in its module.json:
#   {"order": 20, "scripts": ["page/now-playing.js"], "styles": ["page/now-playing.css"]}
#
# A module can have a page of its own as well, for a window of its own (the usage card's): its module.json names it,
# its markup and its scripts and styles, which tools/page.sh lists at the two lines that page marks for them:
#   {"pages": {"card": {"page": "page/card.html", "scripts": ["page/card.js"], "styles": ["page/usage.css"]}}}
#
#   tools/page.sh --scripts    the page's scripts in the order it loads them, as paths in this checkout (tests/panel.sh)
#   tools/page.sh --styles     its styles, the same way
#   tools/page.sh --pages      the modules' own pages, one a line, as <module>/<page> (tests/checks.sh)
#   tools/page.sh --scripts <module>/<page>   one of those pages' scripts, the panel's ones it loads among them
#   tools/page.sh --styles <module>/<page>    its styles, the same way
#   tools/page.sh <folder>     the whole page, written into a new folder (relative to where you are): panel/'s files, and
#                              each module's page files under modules/<name>/ there, its own pages among them (build.sh,
#                              into the app). It never writes over a folder it didn't make.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
here=$PWD
cd "$(dirname "$0")/.."
exec python3 -I - "$here" "$@" <<'PY'
import json, os, re, shutil, sys

STYLES = "<!-- each module's styles: tools/page.sh lists them here, in their module.json order -->"
SCRIPTS = "<!-- each module's scripts: tools/page.sh lists them here, in their module.json order -->"
# The same, in a module's own page, for that module's files.
PAGE_STYLES = "<!-- this page's styles: tools/page.sh lists them here, from its module.json -->"
PAGE_SCRIPTS = "<!-- this page's scripts: tools/page.sh lists them here, from its module.json -->"
# Left in each page this writes, so it knows the folder is one of its own the next time.
MINE = ".written-by-tools-page-sh"

def specs():
    found = []
    if os.path.isdir("modules"):
        for name in os.listdir("modules"):
            path = os.path.join("modules", name, "module.json")
            if os.path.isfile(path):
                with open(path, encoding="utf-8") as f:
                    spec = json.load(f)
                found.append((spec.get("order", 0), name, spec))
    found.sort(key=lambda m: (m[0], m[1]))
    return found

def named(name, file):
    path = os.path.join("modules", name, file)
    if not os.path.isfile(path):
        spec_path = os.path.join("modules", name, "module.json")
        sys.exit("tools/page.sh: %s names %s, which isn't there" % (spec_path, file))
    return path

def modules():
    files = {"scripts": [], "styles": []}
    for _, name, spec in specs():
        for kind in files:
            for file in spec.get(kind, []):
                files[kind].append(named(name, file))
    return files

# The modules' own pages, by <module>/<page>: each one's markup, and its module's scripts and styles for it.
def module_pages():
    pages = {}
    for _, name, spec in specs():
        for page, entry in sorted(spec.get("pages", {}).items()):
            pages["%s/%s" % (name, page)] = {
                "page": named(name, entry["page"]),
                "scripts": [named(name, file) for file in entry.get("scripts", [])],
                "styles": [named(name, file) for file in entry.get("styles", [])],
            }
    return pages

# A module page's lines. Each of its marks must be there exactly once, as the panel's page's must.
def page_lines(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    for mark in (PAGE_STYLES, PAGE_SCRIPTS):
        if lines.count(mark) != 1:
            sys.exit("tools/page.sh: %s must have this line exactly once:\n%s" % (path, mark))
    return lines

# A module page's scripts or styles in the order it loads them, as paths in this checkout: the panel's own ones its
# markup names (in the app the panel's files sit at the top of the page folder, and the modules' under modules/, so a
# path out of the modules' folders is one of the panel's), and its module's at the mark.
def page_listed(key, kind):
    pages = module_pages()
    if key not in pages:
        sys.exit("tools/page.sh: no module has a page %s" % key)
    entry = pages[key]
    if kind == "scripts":
        mark, tag = PAGE_SCRIPTS, r'<script src="(.*)"></script>'
    else:
        mark, tag = PAGE_STYLES, r'<link rel="stylesheet" href="(.*)">'
    here = os.path.dirname(entry["page"])
    out = []
    for line in page_lines(entry["page"]):
        found = re.fullmatch(tag, line)
        if found:
            served = os.path.normpath(os.path.join(here, found.group(1)))
            out.append(served if served.startswith("modules" + os.sep) else os.path.join("panel", served))
        elif line == mark:
            out.extend(entry[kind])
    return out

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
    # Each module's own pages, beside its files: their markup with their module's files listed, linked from where the
    # page is.
    for entry in module_pages().values():
        here = os.path.dirname(entry["page"])
        out = []
        for line in page_lines(entry["page"]):
            out.append(line)
            if line == PAGE_STYLES:
                out.extend('<link rel="stylesheet" href="%s">' % os.path.relpath(p, here) for p in entry["styles"])
            elif line == PAGE_SCRIPTS:
                out.extend('<script src="%s"></script>' % os.path.relpath(p, here) for p in entry["scripts"])
        for path in entry["styles"] + entry["scripts"] + [entry["page"]]:
            os.makedirs(os.path.join(folder, os.path.dirname(path)), exist_ok=True)
            shutil.copy2(path, os.path.join(folder, path))
        with open(os.path.join(folder, entry["page"]), "w", encoding="utf-8") as f:
            f.write("\n".join(out))

here, arguments = sys.argv[1], sys.argv[2:]
if not 1 <= len(arguments) <= 2 or (len(arguments) == 2 and arguments[0] not in ("--scripts", "--styles")):
    sys.exit("Use: tools/page.sh --scripts | --styles | --pages | --scripts <module>/<page> | --styles <module>/<page>"
             " | <folder>")
if arguments[0] in ("--scripts", "--styles") and len(arguments) == 2:
    print("\n".join(page_listed(arguments[1], arguments[0][2:])))
elif arguments[0] in ("--scripts", "--styles"):
    print("\n".join(listed(arguments[0][2:])))
elif arguments[0] == "--pages":
    print("\n".join(module_pages()))
else:
    write(os.path.join(here, os.path.expanduser(arguments[0])))
PY
