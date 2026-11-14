# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import json, re

# What the pages say, together: a function the app calls, or a message, is in one of them.
page = "".join(open(path, encoding="utf-8").read() for path in dict.fromkeys(p for s in pages.values() for p in s))

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
