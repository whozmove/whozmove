#!/bin/bash
# The checks that keep the core, the parts and the modules apart, and the page and the app in step. Each prints only
# what's wrong, so there's no recorded output to keep up to date; exits 1 if anything is. Each is a file of its own in
# tests/checks/, run in the order RULES below gives, in one Python process, after tests/checks/common.py has made what
# they share; a new one is added to RULES, or it fails as never run.
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
#     there, by its exact name;
#   - docs/reference/rows.md describes exactly the fields a row has, and the README names each macOS permission the
#     app asks for, while no file names one it doesn't;
#   - no test defines again a helper tests/lib.sh has, but for what tests/helpers-by-hand.txt lists, and that list
#     only gets shorter.
#
#   tests/checks.sh            run the checks
#   tests/checks.sh --update   once a style writes out fewer values, take them off tests/styles-by-hand.txt, the
#                              crossings gone off tests/part-crossings.txt, the ways to your home gone off
#                              tests/real-home.txt, the facts moved into their Facts header off
#                              tests/facts-by-hand.txt, and the helpers no longer copied off tests/helpers-by-hand.txt
#                              (it never adds one), then check
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
. tests/lib.sh
T=$(throwaway checks) || exit 1
leave_nothing "$T"
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
import os, runpy, sys, traceback
# The rules, in the order they run: each a file of its own in tests/checks/, run in this one process with what
# tests/checks/common.py made (runpy, as each is a program, not a module to import). part-crossings goes last, once
# every rule that lets a crossing through has said which it did.
RULES = ["one-scope", "focus", "calls-and-messages", "imports", "talks-to", "part-calls", "styled-alone", "mode-menu",
         "notice-gathering", "services", "module-readmes", "part-readmes", "page-files", "tokens", "styles-by-hand",
         "real-home", "test-sandbox", "helper-copies", "facts", "other-apps", "docs-links", "rows-fields",
         "permissions", "trackers", "approve-plan", "plan-tool", "part-crossings"]
# The rules that let a crossing through. One that stopped hasn't said which it let through, so its crossings would read
# as gone: part-crossings doesn't run then, and nothing is taken off tests/part-crossings.txt.
FEEDERS = {"imports", "part-calls", "styled-alone", "services"}
problems, stopped = [], []
try:
    shared = {name: value for name, value in runpy.run_path("tests/checks/common.py").items()
              if not name.startswith("__")}
    problems = shared["problems"]
    for rule in RULES:
        path = "tests/checks/%s.py" % rule
        if rule == "part-crossings" and FEEDERS & set(stopped):
            problems.append("tests/part-crossings.txt wasn't checked, as %s stopped: nothing in it was taken off"
                            % " and ".join(sorted(FEEDERS & set(stopped))))
            continue
        try:
            runpy.run_path(path, init_globals=shared)
        except Exception as e:
            stopped.append(rule)
            at = [frame.lineno for frame in traceback.extract_tb(e.__traceback__) if frame.filename == path]
            problems.append("%s%s stopped (%s: %s), so it checked nothing more"
                            % (path, ":%d" % at[-1] if at else "", type(e).__name__, e))
except Exception as e:
    at = [frame.lineno for frame in traceback.extract_tb(e.__traceback__) if frame.filename == "tests/checks/common.py"]
    problems.append("tests/checks/common.py%s stopped (%s: %s), so no rule ran"
                    % (":%d" % at[-1] if at else "", type(e).__name__, e))
for name in sorted(os.listdir("tests/checks")):
    if name.endswith(".py") and name != "common.py" and name[:-3] not in RULES:
        problems.append("tests/checks/%s isn't in tests/checks.sh's RULES, so it never runs" % name)
for problem in problems:
    print("Checks:", problem)
sys.exit(1 if problems else 0)
PY
status=$?
[ $status = 0 ] && echo "Checks: all as expected."
exit $status
