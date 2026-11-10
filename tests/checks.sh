#!/bin/bash
# The checks that keep the core, the parts and the modules apart, and the page and the app in step. Each prints only
# what's wrong, so there's no recorded output to keep up to date; exits 1 if anything is.
#   - no function or constant in two of the page's scripts (they share one scope, so the later one would win), nor in
#     two of a module's own page's (tools/page.sh --pages: the usage card's);
#   - every page function the app calls is there, every message a page sends has the one module that answers it, and
#     no print mode is claimed twice (Whozmove --print-routes);
#   - no module imports another module's header, and the core and the parts import none; a part's header is imported
#     only if its part.json provides it, and by another part only if that one names it in talksTo;
#   - only the mode menu's own items turn on what a session may do (Allowed's set:for:on: and bringBack:why:, called
#     from the commands module's Commands.m alone, and a print run's own function), so no message from the page, and
#     nothing a session sends, can; and ticked.json is kept (Allowed's keepTickedAt:) only by the app's delegate and a
#     print run's own function, so no print run of the app's own writes your file;
#   - no class is styled on its own (`.name { … }`) by two owners (the core, each part and each module): each would
#     restyle the other's elements;
#   - a page script calls a part's function only if that part's part.json provides it, and a part's script calls
#     another part's only if it also names that part in talksTo; a style variable a part provides (`--name`) is set by
#     one of its scripts or styles;
#   - what decides and delivers in the notifications module reads only its own state on the page: no other's, no
#     field of a row (as docs/reference/rows.md names them), not the body's classes and no part's constant, as a
#     service knows no domain;
#   - what tests/part-crossings.txt lists is let through: the imports, styles and calls that crossed when the parts
#     were made, and what the notifications module read that wasn't its own, and that list only gets shorter;
#   - each module has its README, with its pieces and its rules (docs/guides/adding-a-module.md has its shape), and
#     each part its README, with what it owns, who it talks to and its rules;
#   - every file the panel's page and the modules' own pages load is in the page tools/page.sh writes;
#   - the page's styles take their colours, text sizes and corners from panel/styles/tokens.css: one written out in a
#     style is one that tests/styles-by-hand.txt lists, as often as it lists it, and that list only gets shorter;
#   - every focus() a page script makes passes { preventScroll: true }: WebKit centres a box focused without it that
#     isn't wholly in view, scrolling the list under you, and a box is given the keys only where it's already shown;
#   - each colour in tokens.css has its light value too, in the block the light panel takes, and nothing is there that
#     the dark panel doesn't have;
#   - nothing reaches the account's own home folder past HOME (NSHomeDirectory(), getpwuid(), macOS's folders for the
#     account, its name) nor writes out a real-looking one, anywhere in the project but its docs, but for what
#     tests/real-home.txt lists, as often as it lists it, and that list only gets shorter: every test runs with a
#     throwaway HOME, and this keeps it the only one;
#   - every test script (an executable .sh in a tests folder) runs itself in its own sandbox, by sourcing
#     tests/sandboxed.sh on the line after its `cd`;
#   - each outside program's facts are in its module's Facts header: an outside app's bundle id, or a path into Claude
#     Code's folder or another app's in Application Support, written anywhere else in the app's code is one that
#     tests/facts-by-hand.txt lists, and that list only gets shorter; each Facts header has its line in
#     docs/using/install.md's "What it's tested with", and each file named there is one;
#   - the app acts on another app (Apple events, Accessibility presses, posted keys, openings) only through
#     app/shared's AppleEvents.m, AppleScript.m, Accessibility.m and Links.m, which do nothing from a home that isn't
#     surely yours;
#   - nothing in the project names someone's own tracker: every Jira site and every ticket key in it, code, tests and
#     docs alike, is a made-up one, and no code decides by a ticket's status or step name;
#   - the README shows at most ten features, each <picture> in it and the docs has a dark source and a light image, and
#     every link and picture in the README, SECURITY.md, CONTRIBUTING.md and docs/ (outside code) goes somewhere that's
#     there, by its exact name.
#
#   tests/checks.sh            run the checks
#   tests/checks.sh --update   once a style writes out fewer values, take them off tests/styles-by-hand.txt, the
#                              crossings gone off tests/part-crossings.txt, the ways to your home gone off
#                              tests/real-home.txt, and the facts moved into their Facts header off
#                              tests/facts-by-hand.txt (it never adds one), then check
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
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
tools/page.sh "$T/page" || exit 1
python3 -I - "$T" "${1:-}" <<'PY'
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
# Every focus() says not to scroll there: WebKit centres a box focused without it that isn't wholly in view.
for path in dict.fromkeys(p for s in pages.values() for p in s):
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        for call in re.findall(r"\.focus\(([^)]*)\)", line):
            if "preventScroll: true" not in call:
                problems.append("%s:%d focuses a box without { preventScroll: true }" % (path, n))
# What the pages say, together: a function the app calls, or a message, is in one of them.
page = "".join(open(path, encoding="utf-8").read() for path in dict.fromkeys(p for s in pages.values() for p in s))

def code(top):
    for folder, _, files in sorted(os.walk(top)):
        for name in sorted(files):
            if name.endswith((".m", ".h")):
                yield os.path.join(folder, name)

native = list(code("app")) + [path for top in ("parts", "modules") if os.path.isdir(top) for path in code(top)]
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

# What each file imports, found as the compiler finds it: beside the file first, then on tools/compile.sh's include
# path. A module may import its own headers and the core's, contracts', shared and parts' ones; the core and the
# parts, no module's; a part, another part's only if it talks to it. A part's header is imported from outside it only
# if its part.json provides it.
def module_of(path):
    parts = os.path.normpath(path).split(os.sep)
    return parts[1] if parts[0] == "modules" and len(parts) > 2 else None
def part_of(path):
    parts = os.path.normpath(path).split(os.sep)
    return parts[1] if parts[0] == "parts" and len(parts) > 2 else None
include_path = [folder for folder in ("app", "app/core", "app/contracts", "app/shared") if os.path.isdir(folder)]
include_path += sorted(os.path.join("parts", name, "app") for name in part_specs
                       if os.path.isdir(os.path.join("parts", name, "app")))
for path in native:
    mine, my_part = module_of(path), part_of(path)
    for name in re.findall(r'^\s*#\s*(?:import|include)\s+"([^"]+)"', open(path, encoding="utf-8").read(), re.M):
        for folder in [os.path.dirname(path)] + include_path:
            found = os.path.normpath(os.path.join(folder, name))
            if os.path.isfile(found):
                theirs, their_part = module_of(found), part_of(found)
                if theirs and theirs != mine:
                    problems.append("%s imports %s, from the %s module" % (path, name, theirs))
                elif (their_part and their_part != my_part
                      and os.path.basename(found) not in part_specs.get(their_part, {}).get("provides", [])
                      and not crossing("imports", path, name)):
                    problems.append("%s imports %s, which parts/%s/part.json doesn't provide"
                                    % (path, name, their_part))
                elif (my_part and their_part and their_part != my_part
                      and their_part not in part_specs.get(my_part, {}).get("talksTo", [])
                      and not crossing("imports", path, name)):
                    problems.append("%s imports %s, from the %s part, which parts/%s/part.json doesn't name in talksTo"
                                    % (path, name, their_part, my_part))
                break

# Each part talks to the core, and to the parts its part.json names in talksTo, which must be there.
for name, spec in part_specs.items():
    for other in spec.get("talksTo", []):
        if other != "core" and other not in part_specs:
            problems.append("parts/%s/part.json names %s in talksTo, which is neither \"core\" nor a part" % (name, other))

# What each part's page scripts define (its functions, and its constants named in capitals), and every use of them by
# name in every other page script, called or passed on (setTimeout(render, …)), comments left out: each one a name
# its part.json provides, and from another part's script, a part it names in talksTo. A function a part gives the app
# (`window.name = …`) counts too, but only where it's called (`name(`), as such names are everyday words elsewhere. A
# name a script declares for itself (a `const`, `let` or `var` inside a function, a loop's, or a function's parameter)
# and never calls is its own, not a use of the part that has a function of that name. Each page's scripts are checked
# against the parts' scripts that page loads, as nothing else is there for them to call.
DEFINED = re.compile(r"^(?:async )?function ([\w$]+)|^const ([\w$]+) = (?:async )?(?:\([^)]*\)|[\w$]+) =>"
                     r"|^const ([A-Z][A-Z0-9_]*) =|^window\.([\w$]+) =", re.M)
part_scripts = {os.path.join("parts", name, file): name for name, spec in part_specs.items()
                for file in spec.get("scripts", [])}
functions, given = {}, set()
for path, name in part_scripts.items():
    for function in DEFINED.findall(open(path, encoding="utf-8").read()):
        functions[next(found for found in function if found)] = name
        if function[3]:
            given.add(function[3])
for name, spec in part_specs.items():
    for function in spec.get("provides", []):
        if function.endswith(".h"):
            if not os.path.isfile(os.path.join("parts", name, "app", function)):
                problems.append("parts/%s/part.json provides %s, which isn't in its app/" % (name, function))
        elif function.startswith("--"):
            # A style variable it gives the others: one of its scripts or styles sets it.
            if not any(re.search(r"""['"]%s['"]|(?:^|[{;])\s*%s\s*:""" % (re.escape(function), re.escape(function)),
                                 open(os.path.join("parts", name, file), encoding="utf-8").read(), re.M)
                       for file in spec.get("scripts", []) + spec.get("styles", [])):
                problems.append("parts/%s/part.json provides %s, which none of its scripts or styles sets"
                                % (name, function))
        elif functions.get(function) != name and not any(
                re.search(r"^(?:(?:(?:async )?function|const|let) %s\b|(?:const|let) [^\n;]*[\s,]%s =)"
                          % (re.escape(function), re.escape(function)),
                          open(os.path.join("parts", name, file), encoding="utf-8").read(), re.M)
                for file in spec.get("scripts", [])):
            # A name it provides may be one of its top-level constants (an element, say, or one named later in a
            # `const` with others) the others use: the calls below don't follow those, so part.json is where they're
            # said.
            problems.append("parts/%s/part.json provides %s, which none of its scripts defines" % (name, function))
PARAMETERS = re.compile(r"function\s*[\w$]*\s*\(([^()]*)\)|(?<![\w$])\(([^()]*)\)\s*=>|(?<![\w$.])([\w$]+)\s*=>"
                        r"|(?<![\w$.])(?!(?:if|for|while|switch|catch|with)\b)[\w$]+\s*\(([^()]*)\)\s*\{")
def declares(text, name):
    word = re.escape(name)
    if re.search(r"(?<![\w$.])%s\s*\(" % word, text):
        return False
    return bool(re.search(r"\b(?:const|let|var)\s+(?:%s\b|[{\[][^}\]=]*\b%s\b)" % (word, word), text)
                or any(re.search(r"(?<![\w$.])%s\b" % word, "".join(params)) for params in PARAMETERS.findall(text)))
loaded_by = {}
for scripts in pages.values():
    on_page = {part_scripts[p] for p in scripts if p in part_scripts}
    for p in scripts:
        loaded_by.setdefault(p, set()).update(on_page)
for path in dict.fromkeys(p for s in pages.values() for p in s):
    mine = part_scripts.get(path)
    text = re.sub(r"/\*.*?\*/", "", open(path, encoding="utf-8").read(), flags=re.S)
    text = re.sub(r"(?<![:\w\"'`])//.*$", "", text, flags=re.M)
    for function in sorted(set(re.findall(r"(?<![\w$.])([\w$]+)\b(?!\s*:)", text)) & set(functions)):
        theirs = functions[function]
        if theirs not in loaded_by[path] or theirs == mine or re.search(r"^(?:(?:async )?function|const) %s\b" % re.escape(function), text, re.M):
            continue
        if function in given and not re.search(r"(?<![\w$.])%s\s*\(" % re.escape(function), text):
            continue
        if declares(text, function):
            continue
        said = "uses %s" % function if function.isupper() else "calls %s()" % function
        if function not in part_specs[theirs].get("provides", []) and not crossing("calls", path, function):
            problems.append("%s %s, which parts/%s/part.json doesn't provide" % (path, said, theirs))
        elif mine and theirs not in part_specs[mine].get("talksTo", []) and not crossing("calls", path, function):
            problems.append("%s %s, from the %s part, which parts/%s/part.json doesn't name in talksTo"
                            % (path, said, theirs, mine))

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
# :focus or ::after), not a part of something else. The core is one owner, each part another, and each module another;
# two owners styling one class this way style each other's elements, whichever loads later winning.
def owner(path):
    parts = path.split("/")
    if parts[0] in ("modules", "parts"):
        return "the %s %s" % (parts[1], parts[0][:-1])
    return "the core"

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
    if len(owners) > 1 and not crossing("styles", "." + name, " and ".join(sorted(owners))):
        problems.append("the class .%s is styled on its own by %s: give one of them a name of its own" % (
            name, " and by ".join("%s (%s)" % (who, path) for who, path in sorted(owners.items()))))

# What a session may do is turned on only by your press in its mode menu: Allowed's set:for:on: and bringBack:why: are
# called from the commands module's menu (Commands.m), and from no other file, the page's messages' handlers included;
# but for a print run's own function (static int Print…), which the tests run in a throwaway home. And the file that
# offers the switches back after a restart is kept (keepTickedAt:) by the app's delegate, and by a print run's own
# function in a throwaway home, nowhere else.
for path in native:
    if os.path.normpath(path) in ("modules/commands/app/Commands.m", "app/core/Allowed.m"):
        continue
    printing = False
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.match(r"static int Print\w*\(", line) and not line.rstrip().endswith(";"):
            printing = True
        elif line.startswith("}"):
            printing = False
        if not printing and re.search(r"\ballowed\s+(set|bringBack):", line):
            problems.append("%s:%d turns on what a session may do: only the mode menu's items may (Commands.m)"
                            % (path, number))

for path in native:
    if os.path.normpath(path) in ("app/core/AppDelegate.m", "app/core/Allowed.m", "app/core/Allowed.h"):
        continue
    printing = False
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.match(r"static int Print\w*\(", line) and not line.rstrip().endswith(";"):
            printing = True
        elif line.startswith("}"):
            printing = False
        if not printing and re.search(r"\bkeepTickedAt:", line):
            problems.append("%s:%d keeps ticked.json: only the app's delegate may (AppDelegate.m), and a print run in a "
                            "throwaway home" % (path, number))

# Only the gathering of notices sets who sent each and what putting one away does (contracts/NoticeGathering.h): Notice
# itself, Modules as it gathers them, and the notifications module; never a sender.
for path in native:
    path = os.path.normpath(path)
    if path in ("app/contracts/Notice.m", "parts/bridge/app/Modules.m") or path.startswith("modules/notifications/"):
        continue
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        if re.match(r'\s*#import\s+"NoticeGathering\.h"', line):
            problems.append("%s:%d imports NoticeGathering.h: only the gathering of notices may (Modules.m)"
                            % (path, number))

# A service knows no domain (docs/how-it-works/modules.md, principle 2), so what decides and delivers in each one reads
# only what's its own: the state its moduleState holds, never another's (state.last, what a session is to you, the
# fold's), nor a row's field (`.ask`, any field docs/reference/rows.md names), the panel's classes
# (document.body.classList) or a part's constant (CHAT_MS). A place it draws itself (the line under the header,
# notice-line.js) reads the panel as every place does, so it isn't held to this. What was still read when the rule
# came is let through by tests/part-crossings.txt ("reads"), and that list only gets shorter.
SERVICES = {"modules/notifications": ["page/decide.js", "page/notices.js"]}
row_fields = set()
for cell in re.findall(r"^\| ([^|]+?) \|", open("docs/reference/rows.md", encoding="utf-8").read(), re.M):
    row_fields |= set(re.findall(r"`(\w+)`", cell))
part_constants = set()
for path in sorted(p for s in pages.values() for p in s if p.startswith("parts/")):
    for line in open(path, encoding="utf-8"):
        if line.startswith("const "):
            part_constants |= set(re.findall(r"\b([A-Z][A-Z0-9_]+) =", line))
for service, deciding in SERVICES.items():
    folder = os.path.join(service, "page")
    names = os.listdir(folder) if os.path.isdir(folder) else []
    own = set()
    for name in sorted(name for name in names if name.endswith(".js")):
        text = open(os.path.join(folder, name), encoding="utf-8").read()
        for block in re.findall(r"^moduleState\(\{\n(.*?)^\}\);", text, re.M | re.S):
            own |= set(re.findall(r"^  (\w+):", block, re.M))
    for path in (os.path.join(service, name) for name in deciding):
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            line = line.split("//")[0]
            reads = ["state." + key for key in re.findall(r"\bstate\.(\w+)", line) if key not in own]
            reads += re.findall(r"\bdocument\.body\.classList\b", line)
            reads += ["." + field for field in re.findall(r"\.(\w+)\b", line) if field in row_fields]
            reads += [name for name in re.findall(r"\b[A-Z][A-Z0-9_]+\b", line) if name in part_constants]
            for what in dict.fromkeys(reads):
                if not crossing("reads", path, what):
                    problems.append("%s:%d reads %s, which isn't its own: a service knows no domain (principle 2 in "
                                    "docs/how-it-works/modules.md)" % (path, number, what))

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

# Each part's README, with what it owns, who it talks to and its rules.
for name in sorted(os.listdir("parts")) if os.path.isdir("parts") else []:
    folder = os.path.join("parts", name)
    if not os.path.isdir(folder):
        continue
    if name not in part_specs:
        problems.append("%s has no part.json" % folder)
    readme = os.path.join(folder, "README.md")
    if not os.path.isfile(readme):
        problems.append("%s has no README.md" % folder)
        continue
    headings = set(re.findall(r"^## (.+?)\s*$", open(readme, encoding="utf-8").read(), re.M))
    for needed in ("What it owns", "Who it talks to", "Rules"):
        if needed not in headings:
            problems.append("%s has no \"## %s\"" % (readme, needed))

# Every file the page tools/page.sh wrote loads, and its modules' own pages, is in it: a part's or a module's file left
# out of its part.json or module.json, or a path written wrong, would be missing from the app's copy.
written_page = os.path.join(T, "page")
for folder, _, files in sorted(os.walk(written_page)):
    for name in sorted(files):
        if not name.endswith(".html"):
            continue
        html = os.path.join(folder, name)
        text = open(html, encoding="utf-8").read()
        for target in re.findall(r'<(?:script|link)\b[^>]*\b(?:src|href)="([^"]+)"', text):
            if re.match(r"[a-z][a-z0-9+.-]*:", target, re.I):
                continue
            if not os.path.isfile(os.path.normpath(os.path.join(folder, target))):
                problems.append("%s loads %s, which isn't in the page tools/page.sh writes"
                                % (os.path.relpath(html, written_page), target))

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

for key in sorted(crossings - crossed):
    if not update:
        problems.append("%s lists %s, which no longer crosses: tests/checks.sh --update takes it off"
                        % (CROSSINGS, "  ".join(key)))
if update and crossings - crossed:
    with open(CROSSINGS, "w", encoding="utf-8") as f:
        f.writelines(crossings_heading)
        for key in sorted(crossings & crossed):
            f.write("  ".join(key) + "\n")
    print("Checks: saved " + CROSSINGS)

# Every test runs with a throwaway HOME, so nothing it does lands in yours. A way to the account's own home folder that
# doesn't go through HOME reaches yours even then: NSHomeDirectory(), the account's record (getpwuid(), dscl, ~user),
# macOS's folders for the account (NSSearchPathForDirectoriesInDomains, URLsForDirectory, a ~ expanded by
# stringByExpandingTildeInPath), or a folder built from the account's name (NSUserName(), whoami, getpass.getuser(),
# /Users/$USER). So any of them fails here, in every file of the project that isn't its docs (code by its kind, or by
# the program its first line names), as does a real-looking home folder written out (a test's are made up: /Users/you).
# A comment is left out, as each kind of file writes one: a `#` line in C is the preprocessor's, so it's looked at. The
# few the app needs, to tell whether HOME is your own and to find your shell, are the ones tests/real-home.txt lists, as
# often as it lists them, and that list only gets shorter; none of them hands the account's home on (Files.h gives
# Home(), which follows HOME, and yes or no). The patterns are written so their own text doesn't match them.
REAL_HOME_LIST = "tests/real-home.txt"
REAL_HOME_WAYS = re.compile(r"\b(NSHome(?:Directory)\w*|homeDirectory(?:ForCurrentUser|ForUser)|getpw(?:uid|nam|ent)"
                            r"(?:_r)?|pwd\.getpw\w+|NFS(?:Home)Directory|NSUser(?:DomainMask)|NSSearchPath(?:ForDirectories)"
                            r"InDomains|URLs?(?:ForDirectory)|stringByExpanding(?:TildeInPath)|CFCopyHome(?:DirectoryURL)"
                            r"|NSUser(?:Name)|get(?:login)|get(?:user)|who(?:ami)|id -u(?:n))\b|(~\$\{?(?:USER|LOGNAME))"
                            r"|expanduser\(\s*[\"'](~(?=[A-Za-z]))|(/Users(?:/)(?=[$\"'`(%{]))", re.I)
REAL_HOME_FOLDER = re.compile(r"/Users(?:/)([A-Za-z0-9_.-]+)", re.I)
MADE_UP_HOMES = {"you", "me", "x", "shared"}
REAL_HOME_COMMENTS = {".sh": "#", ".py": "#", ".m": "//", ".h": "//", ".c": "//", ".js": "//", ".yml": "#",
                      ".yaml": "#"}
reached = collections.Counter()
# The project's files as git knows them, new ones too and what .gitignore leaves out left out; in a copy that isn't a
# checkout (a source zip), every file but git's own.
listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                        capture_output=True, text=True)
listed_files = listed.stdout.split("\0") if listed.returncode == 0 else []
if listed.returncode != 0:
    for folder, folders, files in os.walk("."):
        folders[:] = [f for f in folders if f != ".git"]
        listed_files += [os.path.relpath(os.path.join(folder, name)) for name in files]
for path in sorted(set(listed_files)):
    if not path or path.startswith("docs/") or not os.path.isfile(path) or os.path.islink(path):
        continue
    kind = os.path.splitext(path)[1]
    if kind not in REAL_HOME_COMMENTS and kind not in (".plist", ".json"):
        with open(path, "rb") as f:
            first = f.readline(200)
        if not first.startswith(b"#!"):
            continue
        kind = ".py" if b"python" in first else ".sh"
    comment = REAL_HOME_COMMENTS.get(kind)
    for line in open(path, encoding="utf-8", errors="replace"):
        if comment and line.lstrip().startswith(comment):
            continue
        for match in REAL_HOME_WAYS.finditer(line):
            reached[(path, next(g for g in match.groups() if g))] += 1
        for home in REAL_HOME_FOLDER.findall(line):
            if home.lower() not in MADE_UP_HOMES:
                reached[(path, "%s/%s" % ("/Users", home))] += 1
real_heading, real_listed = [], collections.Counter()
for line in open(REAL_HOME_LIST, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        real_heading.append(line)
        continue
    path, way, times = re.split(r"\s{2,}", line.strip())
    real_listed[(path, way)] = int(times)
for key in sorted(set(reached) | set(real_listed)):
    path, way = key
    if reached[key] > real_listed[key]:
        problems.append("%s reaches your own home folder with %s%s, whatever HOME says: take it from HOME (Home() in the "
                        "app, $HOME in a script), or write out a made-up one (/Users/you)" % (
                            path, way, ", more often than %s lists it" % REAL_HOME_LIST if real_listed[key] else ""))
    elif reached[key] < real_listed[key] and not update:
        problems.append("%s uses %s less often than %s lists it: tests/checks.sh --update takes it off" % (
            path, way, REAL_HOME_LIST))
if update and not any(reached[key] > real_listed[key] for key in reached) and reached != real_listed:
    with open(REAL_HOME_LIST, "w", encoding="utf-8") as f:
        f.writelines(real_heading)
        for path, way in sorted(reached):
            f.write("%s  %s  %d\n" % (path, way, reached[(path, way)]))
    print("Checks: saved " + REAL_HOME_LIST)

# Every test runs in a sandbox of its own (tests/sandboxed.sh), which lets it write only to the temporary folders, so a
# test that reaches for your home folder fails rather than changing it. A test script is any executable .sh in a tests
# folder (the ones sourced, tests/lib.sh and the rest, aren't executable), and it sources tests/sandboxed.sh on the line
# straight after its `cd`, before it does anything else. A sandbox can't stop an Apple Event, which could type into your
# real terminals, so no test sends one: no AppleScript run from a tests folder, nor NSAppleScript or OSAScript in its C
# or Objective-C.
for folder, folders, files in os.walk("."):
    folders[:] = sorted(f for f in folders if f != ".git")
    if os.path.basename(folder) != "tests":
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

# Whozmove acts on another app (an Apple event, an Accessibility press or a set value, a posted key, a link or a file
# opened in it) only through app/shared's AppleEvents.m, AppleScript.m, Accessibility.m and Links.m, which do nothing
# while this run's home isn't surely your own (MayActOnOtherApps), so no test, print run or copy given a throwaway home
# drives your apps. A way to act written anywhere else in the app would go round that, so it fails here. Launching an
# app, or bringing one forward, isn't acting on it.
OTHER_APP_WAYS = re.compile(r"\b(NSAppleScript|OSAScript|NSUserAppleScriptTask|NSUserScriptTask|sendEventWithOptions|"
                            r"AESendMessage|AESend|AEDeterminePermissionToAutomateTarget|SBApplication|osa(?:script)|"
                            r"AXUIElementPerformAction|AXUIElementSetAttributeValue|AXUIElementPostKeyboardEvent|"
                            r"CGEventPost|CGEventPostToPid|CGEventPostToPSN|openURLs?)\b")
GUARDED = ("app/shared/AppleEvents.m", "app/shared/AppleScript.m", "app/shared/Accessibility.m",
           "app/shared/Links.m")
# macOS's open is the same opening by another door: run as a program (its path, or "open" given to one of
# Processes.h's runners), it's let through only where the app opens itself again after an update.
OPEN_RUN = re.compile(r"/usr/bin/op(?:en)\b|\b(?:RunTool|SpawnDetached|RunBriefly|RunConversation|RunFeeding|"
                      r"RunInCheckout)\(\s*@\"op(?:en)\"")
OPEN_RUN_WHERE = ("modules/install/app/InstallModule.m",)
for top in ("app", "parts", "modules"):
    for folder, folders, files in os.walk(top):
        folders[:] = sorted(f for f in folders if f not in ("tests", "page", "plugin"))
        for name in sorted(files):
            path = os.path.join(folder, name)
            comment = "#" if name.endswith((".sh", ".py")) else "//"
            if not name.endswith((".m", ".h", ".c", ".sh", ".py")) or path in GUARDED:
                continue
            for at, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
                found = None if line.lstrip().startswith(comment) else OTHER_APP_WAYS.search(line) or (
                    path not in OPEN_RUN_WHERE and OPEN_RUN.search(line))
                if found:
                    problems.append("%s:%d acts on another app with %s, round the check that a throwaway home does "
                                    "nothing: use AppleEvents.h, AppleScript.h, Accessibility.h or Links.h"
                                    % (path, at, found.group(1) if found.re is OTHER_APP_WAYS else "open"))

# The README is the project's front page: at most ten features under "What it does for you", each <picture> with a
# dark source and a light image (GitHub shows the one for its reader's theme), and every link and picture in it and in
# the docs there to go to. Code (fenced blocks and `spans`) is left out, as GitHub doesn't link it. A file is found by
# its name exactly as written, upper and lower case and all, as GitHub finds it, though macOS's own file system
# doesn't mind the case. A heading's anchor is GitHub's: lower case, spaces as hyphens, other punctuation dropped.
FRONT_FEATURES = 10
def unfenced(path):
    return re.sub(r"^[ \t]*(```|~~~).*?^[ \t]*\1[^\n]*$", "", open(path, encoding="utf-8").read(), flags=re.S | re.M)
def prose(path):
    return re.sub(r"(`+)(?:(?!\1).)+?\1", "", unfenced(path), flags=re.S)
def anchors(path):
    headings = re.findall(r"^#+ (.+)$", unfenced(path), re.M)
    return {re.sub(r"[^\w\- ]", "", h.strip().lower()).replace(" ", "-") for h in headings}
def there(path):
    folder = "."
    for part in os.path.normpath(path).split(os.sep):
        if part in ("", "."):
            continue
        if part == "..":
            folder = os.path.normpath(os.path.join(folder, part))
            continue
        if not os.path.isdir(folder) or part not in os.listdir(folder):
            return False
        folder = os.path.join(folder, part)
    return True
def targets(text):
    for m in re.finditer(r"\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'(][^)]*)?\)", text):
        yield m.group(1)
    for m in re.finditer(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)", text, re.M):
        yield m.group(1)
    for m in re.finditer(r'\b(href|src|srcset)="([^"]+)"', text):
        if m.group(1) == "srcset":
            yield from (entry.split()[0] for entry in m.group(2).split(",") if entry.strip())
        else:
            yield m.group(2)
if os.path.isfile("README.md"):
    features = re.search(r"^## What it does for you\s*$(.*?)(?=^## |\Z)", prose("README.md"), re.M | re.S)
    if not features:
        problems.append("README.md has no \"## What it does for you\"")
    elif len(re.findall(r"^### ", features.group(1), re.M)) > FRONT_FEATURES:
        problems.append("README.md shows more than %d features under \"What it does for you\": one in means one out"
                        % FRONT_FEATURES)
docs = ["README.md", "SECURITY.md", "CONTRIBUTING.md"] + sorted(
    os.path.join(d, name) for d, _, files in os.walk("docs") for name in files if name.endswith(".md"))
for path in docs:
    if not os.path.isfile(path):
        continue
    text = prose(path)
    for picture in re.findall(r"<picture\b[^>]*>(.*?)</picture>", text, re.S):
        dark = any("prefers-color-scheme: dark" in tag and "srcset=" in tag
                   for tag in re.findall(r"<source\b[^>]*>", picture))
        if not dark or not re.search(r"<img\b[^>]*\bsrc=", picture):
            problems.append("%s: a <picture> without both its dark source and its light image" % path)
    for target in targets(text):
        if re.match(r"[a-z][a-z0-9+.-]*:", target, re.I):
            continue
        file, _, anchor = target.partition("#")
        file = file.split("?")[0]
        if not file:
            where = path
        elif file.startswith("/"):
            where = file.lstrip("/")
        else:
            where = os.path.normpath(os.path.join(os.path.dirname(path), file))
        if not there(where):
            problems.append("%s links to %s, which isn't there (its name must match, case and all)" % (path, target))
        elif anchor and where.endswith(".md") and anchor not in anchors(where):
            problems.append("%s links to %s, which has no heading for #%s" % (path, file or path, anchor))

# The project is public, so nothing in it names someone's own tracker: a Jira site's address says whose it is, and a
# ticket's key names their space. Every site in the project, in code, tests and docs alike, is a made-up one (acme,
# beta, and a.b, a nested name that's turned away), and every key is in a made-up space (PAY and WEB in the Jira
# module's tests, ABC in the tickets module's made-up tracker). A word shaped like a key that names a standard (GPL-3,
# SHA-256, UTF-8, CRC-32) isn't a ticket's. And no code decides by a ticket's status or step name, as the tickets
# module's rules say: a ticket's next steps come from its tracker each time, by the ids it gives, so a state's or a
# step's name is only shown, never compared with words written in. The patterns are written so their own text doesn't
# match them.
TRACKER_SITE = re.compile(r"\b((?:[a-z0-9-]+\.)*[a-z0-9-]+)\.(?:atlassian|jira)\.(?:net|com)\b", re.I)
TRACKER_HOSTS = {"atlassian.net", "jira.com"}
MADE_UP_SITES = {"acme", "beta", "a.b"}
TICKET_KEY = re.compile(r"(?<![-\w])([A-Z][A-Z0-9]{1,9})-[0-9]+\b")
MADE_UP_SPACES = {"PAY", "WEB", "ABC"}
NOT_TICKETS = {"GPL", "SHA", "UTF", "CRC"}
NAME_DECIDED = re.compile(r"\b(?:state|step|status)\w*\.name\s*(?:isEqualToString:\s*@\"|[!=]==?\s*['\"])", re.I)
named = set()
for path in sorted(set(listed_files)):
    if not path or not os.path.isfile(path) or os.path.islink(path):
        continue
    with open(path, "rb") as f:
        if b"\0" in f.read(8192):
            continue
    code = os.path.splitext(path)[1] in (".m", ".h", ".c", ".js") and "tests" not in path.split("/")
    for line in open(path, encoding="utf-8", errors="replace"):
        for match in TRACKER_SITE.finditer(line):
            host = match.group(0).lower()[len(match.group(1)) + 1:]
            if host in TRACKER_HOSTS and match.group(1).lower() not in MADE_UP_SITES:
                named.add((path, "the Jira site %s" % match.group(0).lower()))
        for key in TICKET_KEY.findall(line):
            if key not in MADE_UP_SPACES | NOT_TICKETS:
                named.add((path, "tickets in the space %s" % key))
        if code and NAME_DECIDED.search(line):
            named.add((path, "a status or step by its name"))
for path, what in sorted(named):
    problems.append("%s names %s: the project is public, so a site and a key in it are made up (acme.atlassian.net, "
                    "PAY-142), and a ticket's steps are only ever its tracker's, by their ids" % (path, what))

# A plan is approved from the panel only by an answer marked approvePlan, which the hook takes for a plan alone, and
# which only AnswerFor adds (sendApproval:), after the one check a session you allow and your press beside the list
# both go through. So no other file of the app sets it on an answer, and the page never names it: your press sends
# approveShownPlan, a message apart, which the app checks before it answers. Its print run (ClaudeCodePrints.m) sends
# one from the page on purpose, to show the hook drops it. The pattern is written so its own text doesn't match it.
APPROVE_SET = {".m": re.compile(r"@\"approve(?:Plan)\"\]?\s*[:=]"), ".js": re.compile(r"\bapprove(?:Plan)\b")}
APPROVE_SETTERS = {"modules/claude-code/app/AnswerFor.m", "modules/claude-code/app/ClaudeCodePrints.m"}
for path in sorted(set(listed_files)):
    kind = os.path.splitext(path)[1]
    if kind not in (".m", ".js") or "tests" in path.split("/") or path in APPROVE_SETTERS or not os.path.isfile(path):
        continue
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        text = line.split("//")[0]
        if APPROVE_SET[kind].search(text):
            problems.append("%s:%d sets or names approvePlan: only AnswerFor adds it to an answer, after its one check, "
                            "and the page sends approveShownPlan instead" % (path, n))

# Claude Code's plan request is its module's to read and answer: another module that shows a plan Claude waits on (the
# reader) asks core.planAsks, which says it in the panel's own words and sends the messages that answer it, so its
# tool's name, and those messages, are named in that module alone. The patterns are written so their own text doesn't
# match them.
PLAN_TOOL = re.compile(r"\bExit(?:PlanMode)\b|'(?:answer|hold)(?:Ask)'|'approve(?:Shown)Plan'")
for path in sorted(set(listed_files)):
    if os.path.splitext(path)[1] not in (".m", ".h", ".js") or "tests" in path.split("/") \
            or path.startswith("modules/claude-code/") or not os.path.isfile(path):
        continue
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        if PLAN_TOOL.search(line.split("//")[0]):
            problems.append("%s:%d names Claude Code's plan tool or a message that answers it: only its module reads "
                            "its requests and answers them, and the others ask core.planAsks" % (path, n))

for problem in problems:
    print("Checks:", problem)
sys.exit(1 if problems else 0)
PY
status=$?
[ $status = 0 ] && echo "Checks: all as expected."
exit $status
