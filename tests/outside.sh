#!/bin/bash
# What Whozmove reaches outside this Mac, the files that start programs, and what it carries or fetches that isn't the
# project's own, held to tests/outside.txt: every tracked file but docs, Markdown and licences is looked through (a
# tests folder's only for its ways to the network, as tests are full of sample addresses), and the check fails on one
# of these the list doesn't have, or a line of the list the code no longer has. Some things are never let in, listed or
# not:
#   - a certificate check turned off or answered in code, or an App Transport Security exception: every one is macOS's;
#   - a plain http:// or ws:// address that leaves this Mac;
#   - a program started by the app's own code anywhere but app/shared/Processes.m, or code loaded while it runs;
#   - a GitHub Action that isn't GitHub's own, or isn't pinned by its full commit; a framework that isn't Apple's;
#   - a Python import from outside Python's own library, in any Python the repo has (tests' too);
#   - a code file without the project's licence line that the list doesn't name as not the project's own.
# It first runs itself over made-up files with one of each in them (tests/outside-samples.txt, kept as data), and
# compares what it says with tests/outside.expected.txt, so a narrowed pattern shows. Its own patterns are written so
# they never match their own text, and this file is read whole like any other. It needs no build. Prints only problems;
# exits 1 if any.
#
#   tests/outside.sh            check
#   tests/outside.sh --update   take off tests/outside.txt's lines the code no longer has (it never adds one), and
#                               record what the made-up files make it say again; read the diff first
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
cd "$(dirname "$0")/.." || exit 1
. tests/sandboxed.sh "$@"
. tests/lib.sh
T=$(throwaway outside) || exit 1
leave_nothing "$T"
python3 -I - "$T" "${1:-}" <<'PY'
import ast, importlib.util, os, re, subprocess, sys, sysconfig
T, update = sys.argv[1], sys.argv[2] == "--update"
OUTSIDE, EXPECTED = "tests/outside.txt", "tests/outside.expected.txt"
LICENCE_LINE = "SPDX-License-Identifier: GPL-3.0-or-later"

NOT_LOOKED_IN = {"docs"}
# A tests folder is looked in only for its ways to the network (a download, a fetch, a connection): its addresses are
# samples, and its programs started and files carried are the tests' own.
TESTS = "tests"
NOT_TEXT = (".icns", ".png", ".webp", ".jpg", ".gif", ".ico", ".pdf", ".zip", ".gz", ".md")
CODE = (".m", ".h", ".js", ".css", ".py", ".sh", ".html", ".yml", ".yaml")
APP_CODE = ("app/", "parts/", "modules/")  # what tools/compile.sh builds into the app

# Addresses that never leave this Mac, or only name a format: reserved sample names, this Mac, XML's own.
STAYS = re.compile(r"(?:^|\.)(?:example(?:\.com|\.org|\.net)?|test|invalid|localhost)$|^127\.0\.0\.1$")
FORMATS = ("http://www.w3.org/", "http://www.apple.com/DTDs/")
ADDRESS = re.compile(r"\b(https?|wss?)://([A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9])")
NETWORK = {
    "native": re.compile(r"\bNSURLSession\b|\bNSURLConnection\b|\bloadRequest:|Contents[O]fURL:|\bnw_[a-z]+_"
                         r"|\bCFStreamCreate\w*|\bAF_INET6?\b|\bgetaddrinfo\b"),
    "page": re.compile(r"\bsrc=\"(?:https?:|\$\{)|\.src\s*=|<link\b[^>]*\bhref=\"(?:https?:|\$\{)|\bfetch\("
                       r"|\bXMLHttpRequest\b|\bnew (?:WebSocket|EventSource)\b|\bsendBeacon\b|@[i]mport\b"
                       r"|\burl\((?!\s*[\"']?(?:data:|#))"),
    "python": re.compile(r"\burllib\b|\bhttp\.client\b|^\s*(?:import|from)\s+ssl\b|\bAF_INET6?\b"),
}
STARTS = {
    "native": re.compile(r"\b(?:RunTool|RunBriefly|RunConversation(?:On)?|RunInCheckout|SpawnDetached)\(|\bNSTask\b"
                         r"|\bposix_spawnp?\(|\bpopen\(|\bsystem\(|\bexec[lv]p?e?\("),
    "python": re.compile(r"\bsubprocess\b|\bos\.(?:system|popen|exec\w*|spawn\w*)\("),
}
OWN_DOOR = re.compile(r"\bNSTask\b|\bposix_spawnp?\(|\bpopen\(|\bsystem\(|\bexec[lv]p?e?\(|\bdlopen\(")
DOWNLOADS = re.compile(r"(?:^|[\s;|&(`$\"'])(?:curl|wget)\s|\bgh release download\b|\bgit\s+clone\b"
                       r"|\b(?:brew|pip3?|npm|gem|cargo|go) install\b")
PY_DOWNLOADS = re.compile(r"""["'](?:curl|wget)["']|["']git["']\s*,\s*["']clone["']|["']git\s+clone\b""")
# Apple's own tools a script reaches Apple's servers with: its notary service and the ticket it staples, and a secure
# timestamp while signing (codesign's --timestamp, but not --timestamp=none, which asks no server).
APPLE_SERVICES = re.compile(r"\bnotarytool\b|\bstapler\b|--timestamp\b(?!=)")
# In a test's script, a line that only writes text out (echo, printf or cat, with nothing run inside it) is a sample
# the test makes (a shell history that clones a repository), not a command, unless it's piped into something that runs
# it; so is a heredoc written into a file.
WRITES_OUT = re.compile(r"^\s*(?:echo|printf|cat)\b")
RUNS_IT = re.compile(r"\|\s*(?:sh|bash|zsh|eval|source|xargs)\b")
HEREDOC_TO_FILE = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?")
NOT_OURS = re.compile(r"Copyright \(c\)|\bMIT License\b|\bApache License\b|\bBSD[- ]\d[- ]Clause\b"
                      r"|Mozilla[ ]Public License|SPDX-License-[I]dentifier:\s*(?!GPL-3\.0-or-later)\S")
MANIFESTS = {"package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Podfile", "Podfile.lock",
             "Package.swift", "Package.resolved", "Cartfile", "Gemfile", "Gemfile.lock", "go.mod", "go.sum",
             "Cargo.toml", "Cargo.lock", "requirements.txt", "pyproject.toml", "uv.lock", "Pipfile", "Pipfile.lock"}
NEVER = [
    (re.compile(r"NS[A]ppTransportSecurity|NS[A]llowsArbitrary\w*|NS[E]xceptionDomains|allows[A]rbitraryLoads"),
     "loosens App Transport Security"),
    (re.compile(r"did[R]eceiveChallenge|did[R]eceiveAuthenticationChallenge|\bSecTrust(?!edApplication)\w*"
                r"|set[V]alidatesSecureCertificate|Server[C]ertificateValidationCallback"),
     "answers a certificate check itself"),
    (re.compile(r"(?i)\bverify\s*=\s*False\b|InsecureSkipVerify\s*:\s*true|rejectUnauthorized\s*:\s*false"
                r"|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*[\"']?0|\bcurl\b[^\n]*\s(?:-k|--insecure)\b"
                r"|CURLOPT_SSL_VERIFY(?:PEER|HOST)\s*,\s*(?:false|0)|_create_[u]nverified_context|\bCERT_NONE\b"
                r"|check_hostname\s*=\s*False|--no-check-[c]ertificate|GIT_SSL_[N]O_VERIFY|sslVerify\s*=?\s*false"),
     "turns a certificate check off"),
]

def python_own(name):
    """Python's own library: built in, or under its standard library's folder and not among what's installed beside
    it (sys.stdlib_module_names says the same, but Apple's developer tools' Python 3.9 doesn't have it)."""
    try:
        spec = importlib.util.find_spec(name)
    except (ImportError, ValueError):
        return False
    origin = spec and spec.origin or ""
    stdlib = os.path.realpath(sysconfig.get_paths()["stdlib"])
    return origin in ("built-in", "frozen") or (os.path.realpath(origin).startswith(stdlib + os.sep)
                                                 and "site-packages" not in origin)

def pythons(path, text):
    """The Python in a file: all of a .py, and each `python3 … <<'END'` block of a shell script."""
    if path.endswith(".py"):
        yield 1, text
    elif path.endswith(".sh"):
        for m in re.finditer(r"python3[^\n]*<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n(.*?)^\1\s*$", text, re.S | re.M):
            yield text[:m.start(2)].count("\n") + 1, m.group(2)

def look(root, paths, all_paths):
    """What the files under root have: {key: where it was first seen}, and what's never allowed."""
    found, problems = {}, []
    def seen(key, path, at):
        found.setdefault(key, "%s:%d" % (path, at))
    for path in paths:
        name = os.path.basename(path)
        test = TESTS in path.split("/")[:-1]
        if name in MANIFESTS and not test:
            seen(("not-ours", path), path, 1)
        try:
            text = open(os.path.join(root, path), encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        lines = text.split("\n")
        kind = "native" if path.endswith((".m", ".h", ".c")) else "page" if path.endswith((".js", ".css", ".html")) \
            else "python" if path.endswith(".py") else None
        app_code = kind == "native" and path.startswith(APP_CODE) and not path.startswith("app/shared/Processes.") \
            and not test
        script = path.endswith((".sh", ".yml", ".yaml")) or lines[0].startswith("#!")
        if path.endswith(".sh"):
            for first, code in pythons(path, text):
                for i, line in enumerate(code.split("\n")):
                    if NETWORK["python"].search(line):
                        seen(("network", path), path, first + i)
                    if PY_DOWNLOADS.search(line):
                        seen(("downloads", path), path, first + i)
        if path.endswith(CODE) and LICENCE_LINE not in text and not test:
            seen(("unlicensed", path), path, 1)
        sample_ends = None
        for at, line in enumerate(lines, 1):
            if test:
                # A test's ways to the network, and nothing else of it.
                if sample_ends:
                    if line.strip() == sample_ends:
                        sample_ends = None
                    continue
                written = WRITES_OUT.match(line) and "$(" not in line and "`" not in line and not RUNS_IT.search(line)
                to_file = HEREDOC_TO_FILE.search(line)
                if written and to_file and ">" in line:
                    sample_ends = to_file.group(1)
                if kind in NETWORK and NETWORK[kind].search(line):
                    seen(("network", path), path, at)
                if kind == "python" and PY_DOWNLOADS.search(line):
                    seen(("downloads", path), path, at)
                if script and kind != "python" and not line.lstrip().startswith("#") and not written \
                        and DOWNLOADS.search(line):
                    seen(("downloads", path), path, at)
                continue
            for scheme, host in ADDRESS.findall(line):
                start = line.find("%s://%s" % (scheme, host))
                if STAYS.search(host.lower()) or line[start:].startswith(FORMATS):
                    continue
                if scheme in ("http", "ws"):
                    problems.append("%s:%d names a plain %s:// address on %s: only https:// may leave this Mac"
                                    % (path, at, scheme, host))
                seen(("address", host.lower(), path), path, at)
            if kind in NETWORK and NETWORK[kind].search(line):
                seen(("network", path), path, at)
            if kind == "python" and PY_DOWNLOADS.search(line):
                seen(("downloads", path), path, at)
            if kind in STARTS and STARTS[kind].search(line):
                seen(("starts", path), path, at)
            if app_code and OWN_DOOR.search(line):
                problems.append("%s:%d starts a program or loads code itself: the app's code starts programs only "
                                "through app/shared/Processes.m, and loads only Apple's frameworks" % (path, at))
            if script and kind != "python" and not line.lstrip().startswith("#") and DOWNLOADS.search(line):
                seen(("downloads", path), path, at)
            if script and kind != "python" and not line.lstrip().startswith("#") and APPLE_SERVICES.search(line):
                seen(("network", path), path, at)
            if NOT_OURS.search(line) or (path.endswith((".js", ".css")) and len(line) > 2000):
                seen(("not-ours", path), path, at)
            for never, does in NEVER:
                if never.search(line):
                    problems.append("%s:%d %s: every certificate check is macOS's, so take it out" % (path, at, does))
            used = re.search(r"^\s*-?\s*uses:\s*([^\s#]+)", line) if "/workflows/" in path else None
            if used:
                action, _, pin = used.group(1).partition("@")
                action = "/".join(action.split("/")[:2])
                if action.split("/")[0] not in ("actions", "github"):
                    problems.append("%s:%d uses %s: only GitHub's own actions run here" % (path, at, action))
                if not re.fullmatch(r"[0-9a-f]{40}", pin):
                    problems.append("%s:%d uses %s at %s: pin it to a release's full commit, as the others are"
                                    % (path, at, action, pin or "no version"))
                seen(("action", action, path), path, at)
    for path in all_paths:
        try:
            text = open(os.path.join(root, path), encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        for first, code in pythons(path, text):
            try:
                tree = ast.parse(code)
            except SyntaxError:
                continue
            for node in ast.walk(tree):
                modules = [a.name for a in node.names] if isinstance(node, ast.Import) else \
                    [node.module] if isinstance(node, ast.ImportFrom) and node.module and not node.level else []
                for module in modules:
                    if not python_own(module.split(".")[0]):
                        problems.append("%s:%d imports %s, which isn't in Python's own library"
                                        % (path, first + node.lineno - 1, module))
    compile_line = os.path.join(root, "tools/compile.sh")
    if os.path.isfile(compile_line):
        for framework in re.findall(r"-framework\s+(\w+)", open(compile_line, encoding="utf-8").read()):
            if not os.path.isdir("/System/Library/Frameworks/%s.framework" % framework):
                problems.append("tools/compile.sh links %s, which isn't one of Apple's frameworks" % framework)
    return found, problems

KINDS = {"connects": 3, "link": 2, "names": 2, "starts": 1, "downloads": 1, "not-ours": 1, "action": 2}

def check(root, listing, update):
    """Everything wrong with what's under root against its list: (problems, the list's lines kept by --update)."""
    def walk():
        for folder, folders, files in os.walk(root):
            folders[:] = sorted(f for f in folders if f != ".git")
            for name in sorted(files):
                yield os.path.relpath(os.path.join(folder, name), root)
    try:
        tracked = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, check=True)
        all_paths = sorted(p for p in tracked.stdout.splitlines() if os.path.isfile(os.path.join(root, p)))
    except (OSError, subprocess.CalledProcessError):
        all_paths = sorted(walk())
    paths = [p for p in all_paths if not set(p.split("/")[:-1]) & NOT_LOOKED_IN and not p.endswith(NOT_TEXT)
             and os.path.basename(p) not in ("LICENSE", "NOTICE")]
    found, problems = look(root, paths, all_paths)
    entries, kept = [], []
    for at, line in enumerate(open(listing, encoding="utf-8"), 1):
        words = line.split("  #")[0].strip()
        if line.startswith("#") or not words:
            kept.append(line)
            continue
        fields = re.split(r"\s{2,}", words)
        if fields[0] not in KINDS or len(fields) != KINDS[fields[0]] + 1:
            problems.append("%s:%d isn't a line it knows: %s" % (OUTSIDE, at, words))
            kept.append(line)
            continue
        entries.append((fields, line))
    network = {k[1] for k in found if k[0] == "network"}
    def there(fields):
        kind = fields[0]
        if kind == "connects":
            return fields[2] in network or ("downloads", fields[2]) in found
        if kind in ("link", "names"):
            return ("address", fields[1], fields[2]) in found
        if kind == "action":
            return ("action", fields[1], fields[2]) in found
        if kind == "not-ours":
            return ("not-ours", fields[1]) in found or ("unlicensed", fields[1]) in found
        return (kind, fields[1]) in found
    covered = set()
    for fields, line in entries:
        kind = fields[0]
        if kind in ("connects", "link", "names"):
            covered.add(("address", fields[1], fields[2]))
            if kind == "connects":
                covered.add(("network", fields[2]))
        elif kind == "not-ours":
            covered |= {("not-ours", fields[1]), ("unlicensed", fields[1])}
        elif kind == "action":
            covered.add(("action", fields[1], fields[2]))
        else:
            covered.add((kind, fields[1]))
        if there(fields):
            kept.append(line)
        elif not update:
            problems.append("%s lists \"%s\", which the code no longer has: tests/outside.sh --update takes it off"
                            % (OUTSIDE, "  ".join(fields)))
    for key in sorted(set(found) - covered):
        kind, where = key[0], found[key]
        if kind == "address":
            problems.append("%s names %s, which %s doesn't list: add \"connects  %s  %s  <what checks its "
                            "certificate>\" if the app reaches it from there, \"link  %s  %s\" if it's only opened "
                            "in your browser, or \"names  %s  %s\" if it's only written out"
                            % (where, key[1], OUTSIDE, key[1], key[2], key[1], key[2], key[1], key[2]))
        elif kind == "network":
            problems.append("%s reaches the network, which %s doesn't list: add \"connects  <its host, or * for "
                            "any a page asks for>  %s  <what checks its certificate>\", and a line in README's Privacy "
                            "if it sends or gets something new" % (where, OUTSIDE, key[1]))
        elif kind == "unlicensed":
            problems.append("%s doesn't carry the project's licence line: add \"%s\", or if it isn't the project's "
                            "own, add \"not-ours  %s\" to %s with where it's from and its licence"
                            % (key[1], LICENCE_LINE, key[1], OUTSIDE))
        elif kind == "action":
            problems.append("%s uses the action %s, which %s doesn't list: add \"action  %s  %s\""
                            % (where, key[1], OUTSIDE, key[1], key[2]))
        else:
            does = {"starts": "starts programs", "downloads": "downloads something",
                    "not-ours": "holds code that isn't the project's own"}[kind]
            problems.append("%s %s, which %s doesn't list: add \"%s  %s\", with a note of what it is"
                            % (where, does, OUTSIDE, kind, key[1]))
    return problems, kept

# Made-up files with one of each, and a list with one line too many, kept as data in tests/outside-samples.txt so
# none of it is this check's own code.
def samples(path):
    files, name = {}, None
    for line in open(path, encoding="utf-8"):
        if line.startswith("@@ "):
            name = line[3:].strip()
            files[name] = ""
        elif name:
            files[name] += line
    return files

SAMPLES = "tests/outside-samples.txt"
SAMPLE = samples(SAMPLES)
SAMPLE_LIST = SAMPLE.pop("list.txt")
sample = os.path.join(T, "sample")
os.makedirs(sample)
# A made-up file is written only inside the samples' folder: a path that's absolute, climbs out with "..", or lands
# elsewhere once resolved is refused, and said, never written.
refused = []
for path, text in SAMPLE.items():
    where = os.path.realpath(os.path.join(sample, path))
    if os.path.isabs(path) or ".." in path.split("/") or not where.startswith(os.path.realpath(sample) + os.sep):
        refused.append("%s names a made-up file outside its folder, %s: refused" % (SAMPLES, path))
        continue
    os.makedirs(os.path.dirname(where), exist_ok=True)
    open(where, "w", encoding="utf-8").write(text)
open(os.path.join(sample, "list.txt"), "w", encoding="utf-8").write(SAMPLE_LIST)
said, _ = check(sample, os.path.join(sample, "list.txt"), False)
said = "".join("%s\n" % p for p in refused + said)
failed = False
if update:
    open(EXPECTED, "w", encoding="utf-8").write(said)
    print("Outside: saved " + EXPECTED)
elif said != open(EXPECTED, encoding="utf-8").read():
    print("Outside: on the made-up files it says something other than %s does:" % EXPECTED)
    print(said, end="")
    failed = True

problems, kept = check(".", OUTSIDE, update)
if update:
    open(OUTSIDE, "w", encoding="utf-8").writelines(kept)
for problem in problems:
    print("Outside:", problem)
sys.exit(1 if problems or failed else 0)
PY
status=$?
[ $status = 0 ] && echo "Outside: all as expected."
exit $status
