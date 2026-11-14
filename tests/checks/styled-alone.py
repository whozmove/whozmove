# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import collections, re

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
