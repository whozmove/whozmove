# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

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
