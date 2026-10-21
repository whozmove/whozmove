#!/bin/bash
# The checks that keep the core and the modules apart, and the page and the app in step. Each prints only what's
# wrong, so there's no recorded output to keep up to date; exits 1 if anything is.
#   - no function or constant in two of the page's scripts (they share one scope, so the later one would win), nor in
#     two of a module's own page's (tools/page.sh --pages: the usage card's);
#   - every page function the app calls is there, every message a page sends has the one module that answers it, and
#     no print mode is claimed twice (Whozmove --print-routes);
#   - no module imports another module's header, and the core imports none;
#   - no class is styled on its own (`.name { … }`) by both the core and a module, or by two modules: each would
#     restyle the other's elements;
#   - each module has its README, with its pieces and its rules (docs/guides/adding-a-module.md has its shape);
#   - the page's styles take their colours, text sizes and corners from panel/styles/tokens.css: one written out in a
#     style is one that tests/styles-by-hand.txt lists, as often as it lists it, and that list only gets shorter;
#   - each colour in tokens.css has its light value too, in the block the light panel takes, and nothing is there that
#     the dark panel doesn't have.
#
#   tests/checks.sh            run the checks
#   tests/checks.sh --update   once a style writes out fewer values, take them off tests/styles-by-hand.txt (it never
#                              adds one), then check
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
T=$(mktemp -d "${TMPDIR:-/tmp}/whozmove-checks.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
. tests/lib.sh
APP=$(built_app "$T") || exit 1
# Like every test, with a throwaway home: whatever the app writes (its log) stays in it.
HOME="$T" "$APP" --print-routes > "$T/routes.json" || { echo "Checks: Whozmove --print-routes failed"; exit 1; }
tools/page.sh --scripts > "$T/scripts" || exit 1
tools/page.sh --styles > "$T/styles" || exit 1
# Each module's own page's too.
tools/page.sh --pages > "$T/pages" || exit 1
while read -r page; do
  [ -n "$page" ] || continue
  tools/page.sh --scripts "$page" > "$T/scripts.${page//\//.}" || exit 1
  tools/page.sh --styles "$page" > "$T/styles.${page//\//.}" || exit 1
done < "$T/pages"
python3 -I - "$T" "${1:-}" <<'PY'
import collections, json, os, re, sys
T, update = sys.argv[1], sys.argv[2] == "--update"
problems = []
scripts = open(f"{T}/scripts").read().split()
pages = {"the panel's page": scripts}
styles = open(f"{T}/styles").read().split()
for name in open(f"{T}/pages").read().split():
    key = name.replace("/", ".")
    pages["the %s page" % name] = open(f"{T}/scripts.{key}").read().split()
    styles += [path for path in open(f"{T}/styles.{key}").read().split() if path not in styles]

# Each page's scripts share one scope.
for scope in pages.values():
    defined = {}
    for path in scope:
        text = open(path, encoding="utf-8").read()
        for name in re.findall(r"^(?:async )?function ([\w$]+)|^(?:const|let|var|class) ([\w$]+)", text, re.M):
            name = name[0] or name[1]
            defined.setdefault(name, []).append(path)
    for name, where in sorted(defined.items()):
        if len(where) > 1:
            problems.append("%s is defined in %s" % (name, " and ".join(where)))
# What the pages say, together: a function the app calls, or a message, is in one of them.
page = "".join(open(path, encoding="utf-8").read() for path in dict.fromkeys(p for s in pages.values() for p in s))

def code(top):
    for folder, _, files in sorted(os.walk(top)):
        for name in sorted(files):
            if name.endswith((".m", ".h")):
                yield os.path.join(folder, name)

native = list(code("app")) + (list(code("modules")) if os.path.isdir("modules") else [])
called = set()
for path in native:
    called |= set(re.findall(r'call:@"([\w$]+)"', open(path, encoding="utf-8").read()))
for name in sorted(called):
    if not re.search(r"window\.%s\s*=|^(?:async )?function %s\b" % (name, name), page, re.M):
        problems.append("the app calls %s(), which no page script defines" % name)

routes = json.load(open(f"{T}/routes.json"))
for clash in routes.get("clashes", []):
    problems.append("claimed twice: %s" % clash)
sent = set(re.findall(r"\btype: *'(\w+)'", page))
for kind in sorted(sent - set(routes["routes"])):
    problems.append("the page sends %r, which no module answers" % kind)

# What each file imports, found as the compiler finds it: beside the file first, then on tools/compile.sh's include
# path. A module may import its own headers and the core's, contracts' and shared ones; the core, no module's.
def module_of(path):
    parts = os.path.normpath(path).split(os.sep)
    return parts[1] if parts[0] == "modules" and len(parts) > 2 else None
include_path = [folder for folder in ("app", "app/core", "app/contracts", "app/shared") if os.path.isdir(folder)]
for path in native:
    mine = module_of(path)
    for name in re.findall(r'^\s*#\s*(?:import|include)\s+"([^"]+)"', open(path, encoding="utf-8").read(), re.M):
        for folder in [os.path.dirname(path)] + include_path:
            found = os.path.normpath(os.path.join(folder, name))
            if os.path.isfile(found):
                theirs = module_of(found)
                if theirs and theirs != mine:
                    problems.append("%s imports %s, from the %s module" % (path, name, theirs))
                break

# The colours, text sizes and corners written out in the page's styles rather than taken from tokens.css, each file's
# with how often. A :root block is where the tokens are made, so it's left out, and so is a data: URL's own colour (an
# SVG's stroke). A colour is counted in one spelling, so #fff and #ffffff, or .5 and 0.5, are the same one.
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

written = collections.Counter()
for path in styles:
    text = re.sub(r"/\*.*?\*/", "", open(path, encoding="utf-8").read(), flags=re.S)
    for selector, body in blocks(text):
        if selector == ":root":
            continue
        for declaration in re.split(r";(?![^(]*\))", body):
            prop, _, value = (part.strip() for part in declaration.partition(":"))
            if not value or prop.startswith("--"):
                continue
            for found in COLOUR.findall(re.sub(r'url\("[^"]*"\)', "", value)):
                written[(path, "colour", colour(found))] += 1
            if prop == "font-size" and re.search(r"\d", value) and not value.startswith("var("):
                written[(path, "size", value)] += 1
            elif prop == "font":
                size = re.search(r"(?:^|\s)(\d*\.?\d+(?:px|em|rem|%))(?=/|\s)", value)
                if size:
                    written[(path, "size", size.group(1))] += 1
            elif prop == "border-radius" and re.search(r"\d", value) and not value.startswith("var("):
                written[(path, "corner", value)] += 1

# Who styles each class on its own: a rule whose whole selector is that one class (with only a state of it, like
# :focus or ::after), not a part of something else. The core is one owner, and each module another; two owners styling
# one class this way style each other's elements, whichever loads later winning.
def owner(path):
    parts = path.split("/")
    return "the %s module" % parts[1] if parts[0] == "modules" else "the core"

def alone(selector):
    selector = re.sub(r"\[[^\]]*\]|::?[\w-]+(?:\([^)]*\))?", "", selector).strip()
    return selector[1:] if re.fullmatch(r"\.[\w-]+", selector) else None

styled_alone = collections.defaultdict(dict)
for path in styles:
    text = re.sub(r"/\*.*?\*/", "", open(path, encoding="utf-8").read(), flags=re.S)
    for selectors, _ in blocks(text):
        for selector in re.split(r",(?![^(]*\))", selectors):
            name = alone(selector)
            if name:
                styled_alone[name].setdefault(owner(path), path)
for name, owners in sorted(styled_alone.items()):
    if len(owners) > 1:
        problems.append("the class .%s is styled on its own by %s: give one of them a name of its own" % (
            name, " and by ".join("%s (%s)" % (who, path) for who, path in sorted(owners.items()))))

# Each module's README, with its pieces and its rules.
for name in sorted(os.listdir("modules")) if os.path.isdir("modules") else []:
    folder = os.path.join("modules", name)
    if not os.path.isdir(folder):
        continue
    readme = os.path.join(folder, "README.md")
    if not os.path.isfile(readme):
        problems.append("%s has no README.md" % folder)
        continue
    headings = set(re.findall(r"^## (.+?)\s*$", open(readme, encoding="utf-8").read(), re.M))
    for needed in ("Its pieces", "Rules"):
        if needed not in headings:
            problems.append("%s has no \"## %s\" (docs/guides/adding-a-module.md has its shape)" % (readme, needed))

# Each colour token, dark and light: the first :root block is the dark panel's, the one under
# @media (prefers-color-scheme: light) the light panel's.
TOKENS = "panel/styles/tokens.css"
if os.path.isfile(TOKENS):
    text = re.sub(r"/\*.*?\*/", "", open(TOKENS, encoding="utf-8").read(), flags=re.S)
    light = re.search(r"@media\s*\(prefers-color-scheme:\s*light\)\s*\{\s*:root\s*\{([^}]*)\}", text)
    dark = re.search(r"^:root\s*\{([^}]*)\}", text, re.M)
    values = lambda block: dict(re.findall(r"(--[\w-]+)\s*:\s*([^;]+);", block.group(1))) if block else {}
    dark, light = values(dark), values(light)
    for name, value in dark.items():
        if COLOUR.search(value) and name not in light:
            problems.append("%s: the colour %s has no light value: add one to its light block" % (TOKENS, name))
    for name in light:
        if name not in dark:
            problems.append("%s: %s has a light value but no dark one" % (TOKENS, name))

BY_HAND = "tests/styles-by-hand.txt"
heading, listed = [], collections.Counter()
for line in open(BY_HAND, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        heading.append(line)
        continue
    path, kind, value, times = re.split(r"\s{2,}", line.strip())
    listed[(path, kind, value)] = int(times)
for key in sorted(set(written) | set(listed)):
    path, kind, value = key
    if written[key] > listed[key]:
        problems.append("%s writes out the %s %s%s: use a token from panel/styles/tokens.css, or add one there" % (
            path, kind, value, ", more often than %s lists it" % BY_HAND if listed[key] else ""))
    elif written[key] < listed[key] and not update:
        problems.append("%s writes out the %s %s less often than %s lists it: tests/checks.sh --update takes it off" % (
            path, kind, value, BY_HAND))
if update and not any(written[key] > listed[key] for key in written):
    with open(BY_HAND, "w", encoding="utf-8") as f:
        f.writelines(heading)
        for path, kind, value in sorted(written):
            f.write("%s  %s  %s  %d\n" % (path, kind, value, written[(path, kind, value)]))
    print("Checks: saved " + BY_HAND)

for problem in problems:
    print("Checks:", problem)
sys.exit(1 if problems else 0)
PY
status=$?
[ $status = 0 ] && echo "Checks: all as expected."
exit $status
