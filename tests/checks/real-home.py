# One of tests/checks.sh's rules, run in its one Python process after tests/checks/common.py, with what that makes.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import collections, os, re

# Every test runs with a throwaway HOME, so nothing it does lands in yours. A way to the account's own home folder that
# doesn't go through HOME reaches yours even then: NSHomeDirectory(), the account's record (getpwuid(), dscl, ~user),
# macOS's folders for the account (NSSearchPathForDirectoriesInDomains, URLsForDirectory, a ~ expanded by
# stringByExpandingTildeInPath), or a folder built from the account's name (NSUserName(), whoami, getpass.getuser(),
# /Users/$USER). So any of them fails here, in every file of the project that isn't its docs (code by its kind, or by
# the program its first line names), as does a real-looking home folder written out (a test's are made up: /Users/you).
# A comment is left out, as each kind of file writes one: a `#` line in C is the preprocessor's, so it's looked at. The
# few the app needs, to tell whether HOME is your own and to find your shell, are the ones tests/real-home.txt lists, as
# often as it lists them, and that list only gets shorter; none of them hands the account's home on (Files.h gives
# Home(), which follows HOME, and yes or no). The patterns are written so their own text doesn't match them.
REAL_HOME_LIST = "tests/real-home.txt"
REAL_HOME_WAYS = re.compile(r"\b(NSHome(?:Directory)\w*|homeDirectory(?:ForCurrentUser|ForUser)|getpw(?:uid|nam|ent)"
                            r"(?:_r)?|pwd\.getpw\w+|NFS(?:Home)Directory|NSUser(?:DomainMask)|NSSearchPath(?:ForDirectories)"
                            r"InDomains|URLs?(?:ForDirectory)|stringByExpanding(?:TildeInPath)|CFCopyHome(?:DirectoryURL)"
                            r"|NSUser(?:Name)|get(?:login)|get(?:user)|who(?:ami)|id -u(?:n))\b|(~\$\{?(?:USER|LOGNAME))"
                            r"|expanduser\(\s*[\"'](~(?=[A-Za-z]))|(/Users(?:/)(?=[$\"'`(%{]))", re.I)
REAL_HOME_FOLDER = re.compile(r"/Users(?:/)([A-Za-z0-9_.-]+)", re.I)
MADE_UP_HOMES = {"you", "me", "x", "shared"}
REAL_HOME_COMMENTS = {".sh": "#", ".py": "#", ".m": "//", ".h": "//", ".c": "//", ".js": "//", ".yml": "#",
                      ".yaml": "#"}
reached = collections.Counter()

for path in sorted(set(listed_files)):
    if not path or path.startswith("docs/") or not os.path.isfile(path) or os.path.islink(path):
        continue
    kind = os.path.splitext(path)[1]
    if kind not in REAL_HOME_COMMENTS and kind not in (".plist", ".json"):
        with open(path, "rb") as f:
            first = f.readline(200)
        if not first.startswith(b"#!"):
            continue
        kind = ".py" if b"python" in first else ".sh"
    comment = REAL_HOME_COMMENTS.get(kind)
    for line in open(path, encoding="utf-8", errors="replace"):
        if comment and line.lstrip().startswith(comment):
            continue
        for match in REAL_HOME_WAYS.finditer(line):
            reached[(path, next(g for g in match.groups() if g))] += 1
        for home in REAL_HOME_FOLDER.findall(line):
            if home.lower() not in MADE_UP_HOMES:
                reached[(path, "%s/%s" % ("/Users", home))] += 1
real_heading, real_listed = [], collections.Counter()
for line in open(REAL_HOME_LIST, encoding="utf-8"):
    if line.startswith("#") or not line.strip():
        real_heading.append(line)
        continue
    path, way, times = re.split(r"\s{2,}", line.strip())
    real_listed[(path, way)] = int(times)
for key in sorted(set(reached) | set(real_listed)):
    path, way = key
    if reached[key] > real_listed[key]:
        problems.append("%s reaches your own home folder with %s%s, whatever HOME says: take it from HOME (Home() in the "
                        "app, $HOME in a script), or write out a made-up one (/Users/you)" % (
                            path, way, ", more often than %s lists it" % REAL_HOME_LIST if real_listed[key] else ""))
    elif reached[key] < real_listed[key] and not update:
        problems.append("%s uses %s less often than %s lists it: tests/checks.sh --update takes it off" % (
            path, way, REAL_HOME_LIST))
if update and not any(reached[key] > real_listed[key] for key in reached) and reached != real_listed:
    with open(REAL_HOME_LIST, "w", encoding="utf-8") as f:
        f.writelines(real_heading)
        for path, way in sorted(reached):
            f.write("%s  %s  %d\n" % (path, way, reached[(path, way)]))
    print("Checks: saved " + REAL_HOME_LIST)
