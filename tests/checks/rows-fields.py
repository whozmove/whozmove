# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# docs/reference/rows.md describes exactly the fields a row has: each field Row sends is described there, and each one
# described is sent. Whichever file implements Row now: there must be just the one.
rows = sorted(os.path.join(d, name) for top in ("app", "parts", "modules") for d, _, files in os.walk(top)
              for name in files if name.endswith(".m")
              and re.search(r"^@implementation Row\b", open(os.path.join(d, name), encoding="utf-8").read(), re.M))
if len(rows) != 1:
    problems.append("Row is implemented in %d files, not one" % len(rows))
else:
    sent = set(re.findall(r'json\[@"(\w+)"\]', open(rows[0], encoding="utf-8").read()))
    for name in sorted(sent - row_fields):
        problems.append("%s sends the field %s, which docs/reference/rows.md doesn't describe" % (rows[0], name))
    for name in sorted(row_fields - sent):
        problems.append("docs/reference/rows.md describes the field %s, which Row doesn't send (%s)" % (name, rows[0]))
