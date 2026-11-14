# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

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
