# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# The tests share their helpers from tests/lib.sh, so a fix to one reaches every test that uses it. A script in a tests
# folder (or a folder inside one) that defines a function of the same name as one of lib.sh's has a copy of it, and
# fails here, but for those tests/helpers-by-hand.txt lists, and that list only gets shorter.
HELPERS_BY_HAND = "tests/helpers-by-hand.txt"
shared_helpers = set(re.findall(r"^([A-Za-z_]\w*)\(\)\s*\{", open("tests/lib.sh", encoding="utf-8").read(), re.M))
copies = {}
for folder, folders, files in os.walk("."):
    folders[:] = sorted(f for f in folders if f != ".git")
    if "tests" not in os.path.normpath(folder).split(os.sep):
        continue
    for name in sorted(files):
        path = os.path.relpath(os.path.join(folder, name))
        if not name.endswith(".sh") or path == "tests/lib.sh" or os.path.islink(path):
            continue
        for at, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
            # name() {, or bash's function name { with or without the ().
            defined = re.match(r"\s*(?:function\s+([A-Za-z_]\w*)\s*(?:\(\)\s*)?\{|([A-Za-z_]\w*)\s*\(\))", line)
            helper = defined and (defined.group(1) or defined.group(2))
            if helper in shared_helpers:
                copies.setdefault((path, helper), at)
helpers_heading, helpers_listed = [], set()
for line in open(HELPERS_BY_HAND, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        helpers_heading.append(line)
        continue
    helpers_listed.add(tuple(re.split(r"\s{2,}", line.strip())))
for key in sorted(set(copies) - helpers_listed):
    path, helper = key
    problems.append("%s:%d defines %s(), which tests/lib.sh has: use lib.sh's, so a fix to it reaches this test too"
                    % (path, copies[key], helper))
for key in sorted(helpers_listed - set(copies)):
    if not update:
        problems.append("%s lists %s, which isn't copied there any more: tests/checks.sh --update takes it off"
                        % (HELPERS_BY_HAND, "  ".join(key)))
if update and helpers_listed - set(copies):
    with open(HELPERS_BY_HAND, "w", encoding="utf-8") as f:
        f.writelines(helpers_heading)
        for key in sorted(helpers_listed & set(copies)):
            f.write("  ".join(key) + "\n")
    print("Checks: saved " + HELPERS_BY_HAND)
