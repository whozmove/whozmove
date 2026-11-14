# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

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
