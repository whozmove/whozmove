# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import os, re

# The README is the project's front page: at most ten features under "What it does for you", each <picture> with a
# dark source and a light image (GitHub shows the one for its reader's theme), and every link and picture in it and in
# the docs there to go to. Code (fenced blocks and `spans`) is left out, as GitHub doesn't link it. A file is found by
# its name exactly as written, upper and lower case and all, as GitHub finds it, though macOS's own file system
# doesn't mind the case. A heading's anchor is GitHub's: lower case, spaces as hyphens, other punctuation dropped.
FRONT_FEATURES = 10
def unfenced(path):
    return re.sub(r"^[ \t]*(```|~~~).*?^[ \t]*\1[^\n]*$", "", open(path, encoding="utf-8").read(), flags=re.S | re.M)
def prose(path):
    return re.sub(r"(`+)(?:(?!\1).)+?\1", "", unfenced(path), flags=re.S)
def anchors(path):
    headings = re.findall(r"^#+ (.+)$", unfenced(path), re.M)
    return {re.sub(r"[^\w\- ]", "", h.strip().lower()).replace(" ", "-") for h in headings}
def there(path):
    folder = "."
    for part in os.path.normpath(path).split(os.sep):
        if part in ("", "."):
            continue
        if part == "..":
            folder = os.path.normpath(os.path.join(folder, part))
            continue
        if not os.path.isdir(folder) or part not in os.listdir(folder):
            return False
        folder = os.path.join(folder, part)
    return True
def targets(text):
    for m in re.finditer(r"\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'(][^)]*)?\)", text):
        yield m.group(1)
    for m in re.finditer(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)", text, re.M):
        yield m.group(1)
    for m in re.finditer(r'\b(href|src|srcset)="([^"]+)"', text):
        if m.group(1) == "srcset":
            yield from (entry.split()[0] for entry in m.group(2).split(",") if entry.strip())
        else:
            yield m.group(2)
if os.path.isfile("README.md"):
    features = re.search(r"^## What it does for you\s*$(.*?)(?=^## |\Z)", prose("README.md"), re.M | re.S)
    if not features:
        problems.append("README.md has no \"## What it does for you\"")
    elif len(re.findall(r"^### ", features.group(1), re.M)) > FRONT_FEATURES:
        problems.append("README.md shows more than %d features under \"What it does for you\": one in means one out"
                        % FRONT_FEATURES)
docs = ["README.md", "SECURITY.md", "CONTRIBUTING.md"] + sorted(
    os.path.join(d, name) for d, _, files in os.walk("docs") for name in files if name.endswith(".md"))
for path in docs:
    if not os.path.isfile(path):
        continue
    text = prose(path)
    for picture in re.findall(r"<picture\b[^>]*>(.*?)</picture>", text, re.S):
        dark = any("prefers-color-scheme: dark" in tag and "srcset=" in tag
                   for tag in re.findall(r"<source\b[^>]*>", picture))
        if not dark or not re.search(r"<img\b[^>]*\bsrc=", picture):
            problems.append("%s: a <picture> without both its dark source and its light image" % path)
    for target in targets(text):
        if re.match(r"[a-z][a-z0-9+.-]*:", target, re.I):
            continue
        file, _, anchor = target.partition("#")
        file = file.split("?")[0]
        if not file:
            where = path
        elif file.startswith("/"):
            where = file.lstrip("/")
        else:
            where = os.path.normpath(os.path.join(os.path.dirname(path), file))
        if not there(where):
            problems.append("%s links to %s, which isn't there (its name must match, case and all)" % (path, target))
        elif anchor and where.endswith(".md") and anchor not in anchors(where):
            problems.append("%s links to %s, which has no heading for #%s" % (path, file or path, anchor))
