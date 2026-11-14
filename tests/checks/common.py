# What tests/checks.sh's rules share, made once before they run: the pages' scripts and styles, the app's code
# files, the parts' part.json, the crossings let through, the project's files, and the list of problems they add to.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import collections, json, os, re, subprocess, sys
T, update = sys.argv[1], sys.argv[2] == "--update"
problems = []
scripts = open(f"{T}/scripts").read().split()
pages = {"the panel's page": scripts}
styles = open(f"{T}/styles").read().split()
for name in open(f"{T}/pages").read().split():
    key = name.replace("/", ".")
    pages["the %s page" % name] = open(f"{T}/scripts.{key}").read().split()
    styles += [path for path in open(f"{T}/styles.{key}").read().split() if path not in styles]

def code(top):
    for folder, _, files in sorted(os.walk(top)):
        for name in sorted(files):
            if name.endswith((".m", ".h")):
                yield os.path.join(folder, name)

native = list(code("app")) + [path for top in ("parts", "modules") if os.path.isdir(top) for path in code(top)]

# What crossed between the parts when they were made, let through until it's taken out: each line its kind (imports,
# styles, calls), where (the file, or the class), and what (the header, the owners, the function).
CROSSINGS = "tests/part-crossings.txt"
crossings_heading, crossings = [], set()
for line in open(CROSSINGS, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        crossings_heading.append(line)
        continue
    crossings.add(tuple(re.split(r"\s{2,}", line.strip())))
crossed = set()
def crossing(*key):
    crossed.add(key)
    return key in crossings

# Each part's part.json, by its name.
part_specs = {}
for name in sorted(os.listdir("parts")) if os.path.isdir("parts") else []:
    if os.path.isfile(os.path.join("parts", name, "part.json")):
        part_specs[name] = json.load(open(os.path.join("parts", name, "part.json"), encoding="utf-8"))

# A colour written in a style, counted in one spelling, so #fff and #ffffff, or .5 and 0.5, are the same one.
COLOUR = re.compile(r"#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\([^)]*\)")

def number(text):
    try:
        return ("%.4f" % float(text)).rstrip("0").rstrip(".") or "0"
    except ValueError:
        return text

def colour(text):
    text = text.lower()
    if text.startswith("#"):
        digits = text[1:]
        return "#" + ("".join(d * 2 for d in digits) if len(digits) in (3, 4) else digits)
    name, inside = text.split("(", 1)
    parts = [number(p) if not p.endswith("%") else p for p in re.split(r"[,\s/]+", inside.rstrip(")").strip()) if p]
    return "%s(%s)" % ("rgba" if name == "rgb" and len(parts) == 4 else name, ", ".join(parts))

def blocks(text, context=""):
    i = 0
    while True:
        j = text.find("{", i)
        if j < 0:
            return
        depth, k = 1, j + 1
        while depth and k < len(text):
            depth += {"{": 1, "}": -1}.get(text[k], 0)
            k += 1
        prelude = " ".join(text[i:j].split())
        if prelude.startswith("@"):
            yield from blocks(text[j + 1:k - 1], prelude)
        else:
            yield prelude, text[j + 1:k - 1]
        i = k

# The fields a row has, as docs/reference/rows.md describes them: each name in backticks in a table's first cell.
row_fields = set()
for cell in re.findall(r"^\| ([^|]+?) \|", open("docs/reference/rows.md", encoding="utf-8").read(), re.M):
    row_fields |= set(re.findall(r"`(\w+)`", cell))

# The project's files as git knows them, new ones too and what .gitignore leaves out left out; in a copy that isn't a
# checkout (a source zip), every file but git's own.
listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                        capture_output=True, text=True)
listed_files = listed.stdout.split("\0") if listed.returncode == 0 else []
if listed.returncode != 0:
    for folder, folders, files in os.walk("."):
        folders[:] = [f for f in folders if f != ".git"]
        listed_files += [os.path.relpath(os.path.join(folder, name)) for name in files]
