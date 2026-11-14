# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import collections, re

# The colours, text sizes and corners written out in the page's styles rather than taken from tokens.css, each file's
# with how often. A :root block is where the tokens are made, so it's left out, and so is a data: URL's own colour (an
# SVG's stroke).
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
