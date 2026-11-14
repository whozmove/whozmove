# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

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
