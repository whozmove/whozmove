#!/usr/bin/env python3
# The real Claude Code run's driver (real.sh): runs a Claude Code in a pseudo-terminal, so it has its whole interactive
# screen with no window, and does to it what the panel does, step by step: a reply, a request for your OK answered at
# the panel's own end of the hook's line, a file written, a command typed over a half-written draft, the mode moved
# with Shift+Tab, a question and a plan answered, a command left running, a compaction and folder trust written while
# it runs, and questions asked on its side with the arguments and environment the app gives one. Each step's effect is
# read from what Claude Code sends the stand-in server next, its transcript, its registry and what the hooks recorded,
# never from the screen, which is only waited on and kept when a step fails.
#   pty-driver.py <settings json>
# The settings (real.sh writes them) name the Claude Code, the throwaway home, the project, the app, the stand-in's
# log and port, the stand-in panel's folder and how to start it. What each step found is printed, one line each, for
# real.sh to compare with real.expected.txt. Exit 0 once every step ran; 3 if one couldn't be checked (a screen it
# doesn't know, a request the stand-in doesn't know): the reason is the last line printed.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
import fcntl
import glob
import json
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import threading
import time

S = json.load(open(sys.argv[1]))
HOME, PROJECT, APP, APPDIR = S["home"], S["project"], S["app"], S["appDir"]
LOG, MIRROR, OUT = S["standInLog"], S["mirror"], S["out"]
KEY = "sk-ant-api03-stand-in-" + "0" * 60
CONFIG = os.path.join(HOME, ".claude")


class CouldntCheck(Exception):
    """A step that couldn't be checked: something the run itself doesn't know, not a change Whozmove would break on."""


def say(line=""):
    print(line, flush=True)


# The session in its pseudo-terminal: what it shows is kept (the last part of it), only to save when a step fails.
class Session:
    def __init__(self, argv, env):
        self.screen, self.lock = bytearray(), threading.Lock()
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(PROJECT)
            os.execve(argv[0], argv, env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        while True:
            try:
                ready, _, _ = select.select([self.fd], [], [], 0.2)
                if ready:
                    chunk = os.read(self.fd, 65536)
                    if not chunk:
                        return
                    with self.lock:
                        self.screen.extend(chunk)
                        del self.screen[:-400000]
            except OSError:
                return

    def keys(self, raw, pause=0.15):
        os.write(self.fd, raw.encode() if isinstance(raw, str) else raw)
        time.sleep(pause)

    def text(self):
        with self.lock:
            raw = bytes(self.screen)
        raw = re.sub(rb"\x1b\[[0-9;?<>=]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b[()][0-9A-Za-z]|\x1b[=>78]",
                     b"", raw)
        return raw.decode("utf-8", "replace")

    def save(self, name):
        with open(os.path.join(OUT, f"screen-{name}.txt"), "w") as f:
            f.write(self.text()[-60000:])

    def alive(self):
        try:
            return os.waitpid(self.pid, os.WNOHANG) == (0, 0)
        except ChildProcessError:
            return False

    def stop(self):
        if self.alive():
            os.kill(self.pid, signal.SIGTERM)
            for _ in range(50):
                if not self.alive():
                    break
                time.sleep(0.1)


def wait(what, check, seconds, session=None, step=""):
    end = time.time() + seconds
    while time.time() < end:
        found = check()
        if found:
            return found
        time.sleep(0.2)
    if session:
        session.save(step or "timeout")
    return None


def requests():
    try:
        with open(LOG) as f:
            return [json.loads(line) for line in f if line.strip()]
    except OSError:
        return []


def unknown_requests():
    return [r for r in requests() if r.get("unknown")]


def registry(session):
    path = os.path.join(CONFIG, "sessions", f"{session.pid}.json")
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def hook_record(session_id):
    try:
        with open(os.path.join(APPDIR, "sessions", f"{session_id}.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def settled(session_id, quiet=2.0, seconds=20):
    """Until the hooks have stopped writing their record: they run in the background, so the last of a turn's can come
    after the session is back at its prompt."""
    path = os.path.join(APPDIR, "sessions", f"{session_id}.json")
    wait("settled", lambda: os.path.exists(path) and time.time() - os.path.getmtime(path) >= quiet, seconds)


def transcript(session_id):
    paths = glob.glob(os.path.join(CONFIG, "projects", "*", f"{session_id}.jsonl"))
    if not paths:
        return []
    out = []
    with open(paths[0], errors="replace") as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except ValueError:
                pass
    return out


def transcript_path(session_id):
    paths = glob.glob(os.path.join(CONFIG, "projects", "*", f"{session_id}.jsonl"))
    return paths[0] if paths else None


def idle(session, seconds=60, step="", states=("idle", "shell")):
    """Until the registry says the session waits at its prompt again, after the stand-in's last answer."""
    found = wait("idle", lambda: (registry(session) or {}).get("status") in states, seconds, session, step)
    if not found:
        raise CouldntCheck(f"{step}: the session didn't come back to its prompt "
                           f"(registry status {(registry(session) or {}).get('status')!r}); its screen is kept")


def sent_after(count, check, session, step, seconds=60):
    """The first request the stand-in got after the first `count` that `check` likes."""
    def look():
        if unknown_requests():
            return "unknown"
        return next((r for r in requests()[count:] if check(r)), None)
    found = wait(step, look, seconds, session, step)
    if found == "unknown":
        raise CouldntCheck(f"{step}: Claude Code asked the stand-in for something it doesn't know: "
                           f"{unknown_requests()[0]}")
    return found


def typed(session, words):
    """Types a turn and sends it, as you do at Claude Code's prompt."""
    for ch in words:
        session.keys(ch, 0.01)
    time.sleep(0.3)
    session.keys("\r", 0.3)


def print_run(*args):
    run = subprocess.run([APP, *args], env=dict(S["appEnv"]), capture_output=True, text=True, timeout=120)
    return run.stdout + run.stderr


def asks_waiting():
    return sorted(p for p in glob.glob(os.path.join(MIRROR, "asks", "*.json")) if not p.endswith(".answer.json"))


def answer_ask(session, step, reply, seconds=60):
    """Answers the request the stand-in panel was asked, as the panel does; what it was asked."""
    asked = wait(step, asks_waiting, seconds, session, step)
    if not asked:
        return None
    with open(asked[0]) as f:
        request = json.load(f)
    with open(asked[0][:-len(".json")] + ".answer.json", "w") as f:
        json.dump(reply, f)
    return request


def start_panel(kind):
    """The panel's end of the hook's line: the app's own (--print-hook-line, which answers every request "deny") or
    the stand-in (stand-in-panel.py, which answers as the run says)."""
    argv = S["hookLine"] if kind == "app" else S["standInPanel"]
    process = subprocess.Popen(argv, env=dict(S["appEnv"]), stdout=open(os.path.join(OUT, f"panel-{kind}.txt"), "w"),
                               stderr=subprocess.STDOUT, start_new_session=True)
    if kind != "app":
        # The stand-in is noted as the panel, as the app notes itself as it opens (the app's own print run does).
        with open(os.path.join(APPDIR, "panel.pid"), "w") as f:
            f.write(str(process.pid))
    sock = os.path.join(APPDIR, "hook.sock")
    if not wait("socket", lambda: os.path.exists(sock) and os.path.exists(os.path.join(APPDIR, "panel.pid")), 20):
        raise CouldntCheck(f"the panel's end ({kind}) didn't start listening")
    return process


def stop_panel(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except OSError:
        pass
    process.wait(timeout=10)
    for name in ("hook.sock", "panel.pid"):
        try:
            os.remove(os.path.join(APPDIR, name))
        except OSError:
            pass


def steps(session):
    reg = wait("registry", lambda: registry(session), 60, session, "start")
    if not reg:
        raise CouldntCheck("Claude Code wrote no registry file: it may be at a screen the run doesn't know "
                           "(sign-in, onboarding); its screen is kept")
    idle(session, 60, "start")
    reg = registry(session)
    sid = reg.get("sessionId")
    say("== started")
    for key in ("pid", "sessionId", "startedAt", "cwd", "status", "entrypoint", "kind", "procStart", "statusUpdatedAt"):
        value = reg.get(key)
        shown = {"pid": value == session.pid, "sessionId": bool(value), "startedAt": isinstance(value, int) and
                 value > 1e12, "cwd": value == PROJECT, "procStart": value is not None,
                 "statusUpdatedAt": isinstance(value, int) and value > 1e12}.get(key, value)
        say(f"   registry {key}: {json.dumps(shown)}")
    # What Whozmove takes each process for, as a session asks it something in its own name: the session's own, and
    # this run's (a program as a hook is).
    say("== the programs that may ask in a session's name")
    said = print_run("--print-program", str(session.pid), str(os.getpid())).splitlines()
    for what, line in zip(("the session's", "a program not Claude Code's"), said):
        say(f"   {what}: {line}")

    say("== 1 a reply")
    count = len(requests())
    typed(session, "Say hello STEP:reply")
    asked = sent_after(count, lambda r: "STEP:reply" in (r.get("said") or ""), session, "reply")
    say(f"   the stand-in was asked: {bool(asked)}")
    idle(session, 60, "reply")
    settled(sid)
    record = hook_record(sid)
    for key in sorted(record):
        if key in ("lastPrompt", "lastReply", "permissionMode", "outcome"):
            say(f"   hooks recorded {key}: {json.dumps(record[key])[:120]}")

    say("== 2 a request for your OK, at the panel's own end of the line")
    panel = start_panel("app")
    count = len(requests())
    typed(session, "Run the check STEP:bash")
    result = sent_after(count, lambda r: r.get("results"), session, "bash", 90)
    told = (result or {}).get("results", [{}])[0]
    say(f"   Claude Code was told: {json.dumps(told.get('text'))}{' (an error)' if told.get('error') else ''}")
    try:
        panel.wait(timeout=S["hookLineSeconds"] + 15)
    except subprocess.TimeoutExpired:
        pass
    stop_panel(panel)
    with open(os.path.join(OUT, "panel-app.txt")) as f:
        for line in f.read().splitlines():
            say("   the panel's end: " + line.strip())
    idle(session, 60, "bash")

    say("== 3 a file written, allowed from the panel")
    panel = start_panel("stand-in")
    count = len(requests())
    typed(session, "Write the notes STEP:write")
    request = answer_ask(session, "write", {"behavior": "allow"})
    say(f"   asked in the panel: {request.get('tool') if request else None}")
    result = sent_after(count, lambda r: r.get("results"), session, "write", 60)
    say(f"   the file: {'written' if os.path.exists(os.path.join(PROJECT, 'notes.txt')) else 'missing'};"
        f" Claude Code got its result: {bool(result)}")
    idle(session, 60, "write")

    say("== 4 a command typed over a half-written draft, as the panel types it")
    keys = json.loads(print_run("--print-typing"))["stays at its prompt"]["keys"]
    command = next(k[5:] for k in keys if k.startswith("text /"))
    model = command.split()[-1]
    os.makedirs(os.path.join(APPDIR, "switches"), exist_ok=True)
    with open(os.path.join(APPDIR, "switches", f"{sid}.panel.json"), "w") as f:
        json.dump({"to": model, "at": int(time.time() * 1000)}, f)
    for ch in "half a thought":
        session.keys(ch, 0.01)
    time.sleep(0.3)
    for key in keys:
        if key.startswith("text "):
            for ch in key[5:]:
                session.keys(ch, 0.01)
            continue
        name, times = key.rsplit(" ×", 1)
        raw = {"Ctrl+S": b"\x13", "Return": b"\r", "Backspace": b"\x7f"}[name]
        for _ in range(int(times)):
            session.keys(raw, 0.4)
        if name == "Return":
            switch = wait("switch", lambda: glob.glob(os.path.join(MIRROR, "switches", "*.ask.json")), 8)
            if switch:
                with open(switch[0][:-len(".ask.json")] + ".answer.json", "w") as f:
                    json.dump({"allow": True}, f)
                say("   the switch was asked in the panel: allowed")
            else:
                say("   the switch was asked in the panel: no (switched without asking)")
            idle(session, 30, "typing")
    count = len(requests())
    session.keys("\r", 0.3)
    after = sent_after(count, lambda r: r.get("said"), session, "draft", 60)
    said = (after or {}).get("said", "")
    say(f"   the draft came back as the next message: {said == 'half a thought'}"
        f"{'' if said == 'half a thought' else ' (it was ' + json.dumps(said) + ')'}")
    idle(session, 60, "draft")
    say(f"   the model the reply came from: {after and after.get('model')}")
    path = transcript_path(sid)
    say("   what Whozmove takes the command's result to say:")
    for line in print_run("--print-results", command, path).splitlines():
        say("      " + line.replace(path, "<transcript>"))

    say("== 5 a question, answered from the panel")
    count = len(requests())
    typed(session, "Ask me STEP:ask")
    request = answer_ask(session, "ask", {"behavior": "allow", "answers": {"Which colour?": "Blue"}})
    say(f"   asked in the panel: {request.get('tool') if request else None}")
    result = sent_after(count, lambda r: r.get("results"), session, "ask", 60)
    say(f"   Claude Code got the answer: {'Blue' in (result or {}).get('results', [{}])[0].get('text', '')}")
    idle(session, 60, "ask")

    say("== 6 a command left running in the background")
    count = len(requests())
    typed(session, "Wait for it STEP:background")
    answer_ask(session, "background", {"behavior": "allow"}, 20)
    sent_after(count, lambda r: r.get("results"), session, "background", 60)
    status = wait("shell", lambda: (registry(session) or {}).get("status") == "shell" and "shell", 30)
    say(f"   the registry says: {status or (registry(session) or {}).get('status')}")
    idle(session, 30, "background")

    say("== 7 a compaction")
    count = len(requests())
    typed(session, "/compact")
    sent_after(count, lambda r: r.get("step") == "summary", session, "compact", 90)
    idle(session, 90, "compact")
    boundary = [r for r in transcript(sid) if r.get("subtype") == "compact_boundary"]
    say(f"   a compaction record with its size after: "
        f"{bool(boundary and isinstance((boundary[-1].get('compactMetadata') or {}).get('postTokens'), int))}")
    record = hook_record(sid)
    say(f"   the hooks saw it begin and end: {'compactingAt' in record or 'compactedAt' in record}")

    say("== 8 folder trust, written while Claude Code runs")
    sub = os.path.join(PROJECT, "sub")
    os.makedirs(sub, exist_ok=True)
    print_run("--print-trust", "--trust", sub, sub)
    count = len(requests())
    typed(session, "Once more STEP:reply")
    sent_after(count, lambda r: "Once more" in (r.get("said") or ""), session, "trust")
    idle(session, 60, "trust")
    state = json.load(open(os.path.join(HOME, ".claude.json")))
    say(f"   still trusted: {((state.get('projects') or {}).get(sub) or {}).get('hasTrustDialogAccepted') is True};"
        f" Claude Code's own keys still there: {'hasCompletedOnboarding' in state}")
    say("== 9 the mode, moved with the Shift+Tabs Whozmove gives")
    for target in ("acceptEdits", "plan", "default"):
        mine = json.loads(print_run("--print-mode-moves")).get(sid)
        presses = (mine or {}).get("presses", {}).get(target)
        if presses is None:
            say(f"   {target}: Whozmove wouldn't type it ({json.dumps((mine or {}).get('mode'))} now)")
            continue
        for _ in range(presses):
            session.keys(b"\x1b[Z", 0.4)
        count = len(requests())
        typed(session, "Which mode STEP:reply")
        sent_after(count, lambda r: "Which mode" in (r.get("said") or ""), session, "mode")
        idle(session, 60, "mode")
        landed = wait("mode", lambda: hook_record(sid).get("permissionMode"), 10)
        say(f"   {target}: {presses} Shift+Tab, landed in {landed}")

    say("== 10 a plan, sent back with a note from the panel")
    mine = json.loads(print_run("--print-mode-moves")).get(sid) or {}
    for _ in range(mine.get("presses", {}).get("plan") or 0):
        session.keys(b"\x1b[Z", 0.4)
    count = len(requests())
    typed(session, "Make a plan STEP:plan")
    request = answer_ask(session, "plan", {"behavior": "deny", "message": "Add a step that says goodbye."})
    say(f"   asked in the panel: {request.get('tool') if request else None}")
    result = sent_after(count, lambda r: r.get("results"), session, "plan", 60)
    note = "says goodbye" in (result or {}).get("results", [{}])[0].get("text", "")
    say(f"   Claude Code got the note: {note}")
    idle(session, 60, "plan")

    say("== 10b questions on its side, asked as the panel asks them")
    settled(sid)
    # With the model it was switched to in step 4, as the app asks one with the session's own, and the environment the
    # app gives it: this Whozmove as the checker its hook runs, and git's settings.
    arguments = json.loads(print_run("--print-aside", "--arguments", sid, model, "high"))
    extra = json.loads(print_run("--print-aside", "--environment", PROJECT))
    # A file beside the project, outside the session's folder, and one in it that git follows, for the reads.
    with open(os.path.join(os.path.dirname(PROJECT), "outside-notes.txt"), "w") as f:
        f.write("words from outside the project\n")
    with open(os.path.join(PROJECT, "cart.txt"), "w") as f:
        f.write("one line\n")
    subprocess.run(["git", "-C", PROJECT, "add", "cart.txt"], check=True, env=dict(S["appEnv"]))
    with open(os.path.join(PROJECT, "cart.txt"), "a") as f:
        f.write("another line\n")
    # A checker that's slow: the real one, its input held open after the call, so it can't read it whole in time.
    slow = os.path.join(OUT, "slow-checker.sh")
    with open(slow, "w") as f:
        f.write(f'#!/bin/sh\n{{ cat; sleep 8; }} | "{APP}" "$@"\n')
    os.chmod(slow, 0o755)
    # The session's own requests, taken before any question, so none is compared with another's.
    own = sorted(os.listdir(S["bodies"]))
    for what, steps, checker in (("a question", ["reply"], None),
                                 ("a question that reaches for a command", ["bash"], None),
                                 ("two questions in one copy", ["reply", "reply"], None),
                                 ("a read outside its folder", ["readout"], None),
                                 ("git that would write or run something", ["gitout"], None),
                                 ("git status", ["gitstatus"], None),
                                 ("git status, its checker not there", ["gitstatus"], os.path.join(OUT, "not-there")),
                                 ("git status, its checker too slow", ["gitstatus"], slow)):
        environment = dict(extra, WHOZMOVE_ASIDE_CHECK=checker) if checker else extra
        aside(sid, arguments, environment, what, steps, own)

    settled(sid)
    rows = print_run("--print-rows")
    moves = print_run("--print-mode-moves")
    stop_panel(panel)

    say("== 11 the session ends")
    typed(session, "/exit")
    gone = wait("exit", lambda: not os.path.exists(os.path.join(CONFIG, "sessions", f"{session.pid}.json")), 30)
    say(f"   its registry file went: {bool(gone)}")
    for name, text in (("rows", rows), ("mode-moves", moves), ("kept", print_run("--print-kept"))):
        with open(os.path.join(OUT, f"{name}.json"), "w") as f:
            f.write(text)
    return sid


def home_now():
    """Every file in the throwaway home, with what it holds, but the registry, which a running copy is listed in."""
    seen = {}
    for top, _, files in os.walk(HOME):
        for name in files:
            path = os.path.join(top, name)
            if os.path.dirname(path) == os.path.join(CONFIG, "sessions"):
                continue
            try:
                with open(path, "rb") as f:
                    seen[os.path.relpath(path, HOME)] = hash(f.read())
            except OSError:
                pass
    return seen


def blocks(body):
    """A request as the cache sees it, a block at a time (each with whether it carries a cache mark), its marks taken
    off: tools, system, then messages; Claude Code's billing line, which isn't part of what's cached, left out."""
    bare = lambda v: ({k: bare(x) for k, x in v.items() if k != "cache_control"} if isinstance(v, dict)
                      else [bare(x) for x in v] if isinstance(v, list) else v)
    system = body.get("system") or []
    system = [{"type": "text", "text": system}] if isinstance(system, str) else system
    out = [(json.dumps(bare(t), sort_keys=True), "cache_control" in t) for t in body.get("tools") or []]
    out += [(json.dumps(bare(s), sort_keys=True), "cache_control" in s) for s in system
            if not str(s.get("text", "")).startswith("x-anthropic-billing-header:")]
    for m in body.get("messages") or []:
        content = m.get("content")
        for b in [{"type": "text", "text": content}] if isinstance(content, str) else content or []:
            out.append((m.get("role") + json.dumps(bare(b), sort_keys=True), isinstance(b, dict) and
                        "cache_control" in b))
    return out


def aside(sid, arguments, environment, what, steps, own):
    """Questions on the session's side, run as the app runs them: in its folder, with the environment the app adds
    (`environment`), each question on its input as a stream-json line once the one before has its result, and its input
    closed after the last. Whether it forked (another session listed as its first result came, while its input was still
    open, gone after), how each ended and in how many processes, which tools ran and which were refused, whether the
    file outside the folder was read or one was written outside it, whether the index changed, whether anything else in
    the home changed or any hook ran, and whether its first request starts as the last of the session's own requests
    (`own`, the stand-in's bodies before any question) did, up to that request's last cache mark."""
    bodies, hooks = S["bodies"], os.path.join(APPDIR, "sessions")
    before_bodies, before_home = sorted(os.listdir(bodies)), home_now()
    before_hooks = set(os.listdir(hooks)) if os.path.isdir(hooks) else set()
    registry = os.path.join(CONFIG, "sessions")
    listed = set(os.listdir(registry))
    index = os.path.join(PROJECT, ".git", "index")
    index_before = open(index, "rb").read() if os.path.exists(index) else b""
    run = subprocess.Popen([S["claude"]] + arguments, cwd=PROJECT, env=dict(S["claudeEnv"], **environment),
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    copies, said, results = set(), [], []
    answered = threading.Event()

    # Each question goes in once the one before has its result; its input closes after the last's, which is how Claude
    # Code is told to finish, as the app does. The sessions listed as the first result comes are the ones listed while
    # it ran, however quickly it answered: looking now and then would miss a copy that answers between two looks.
    def read():
        for each in run.stdout:
            said.append(each)
            if '"type":"result"' in each.replace(" ", ""):
                if not results:
                    for name in set(os.listdir(registry)) - listed:
                        try:
                            with open(os.path.join(registry, name)) as f:
                                copies.add(json.load(f).get("sessionId"))
                        except (OSError, ValueError):
                            pass
                results.append(each)
                answered.set()

    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    end = time.time() + 180
    for n, step in enumerate(steps):
        answered.clear()
        line = json.dumps({"type": "user", "message": {"role": "user", "content": f"Why that file? STEP:{step}"}})
        run.stdin.write(line + "\n")
        run.stdin.flush()
        while len(results) <= n and run.poll() is None and time.time() < end:
            answered.wait(0.1)
    run.stdin.close()
    try:
        run.wait(15)
    except subprocess.TimeoutExpired:
        run.kill()
    reader.join(5)
    lines = [json.loads(l) for l in said if l.startswith("{")]
    ended = [l.get("subtype") for l in lines if l.get("type") == "result"]
    words = [l.get("result") for l in lines if l.get("type") == "result"]
    tool_results = [b for l in lines if l.get("type") == "user" for b in l["message"].get("content") or []
                    if isinstance(b, dict) and b.get("type") == "tool_result"]
    ran = sum(1 for b in tool_results if not b.get("is_error"))
    seen = any("words from outside the project" in json.dumps(b.get("content")) for b in tool_results)
    say(f"   {what}: forked {bool(copies) and sid not in copies}, listed after "
        f"{bool(set(os.listdir(registry)) - listed)}; ended {ended}, said {json.dumps(words)}")
    say(f"   {what}: tools ran {ran}, refused {len(tool_results) - ran}; the outside file read {seen}, a file "
        f"written outside {os.path.exists(os.path.join(os.path.dirname(PROJECT), 'written-by-diff.txt'))}, the "
        f"index changed {(open(index, 'rb').read() if os.path.exists(index) else b'') != index_before}")
    after_home = home_now()
    changed = sorted(k for k in set(before_home) | set(after_home) if before_home.get(k) != after_home.get(k))
    new_hooks = (set(os.listdir(hooks)) if os.path.isdir(hooks) else set()) - before_hooks
    say(f"   {what}: the home changed {changed}, a hook ran for it {bool(new_hooks)}")
    sent = [n for n in sorted(os.listdir(bodies)) if n not in before_bodies]
    load = lambda n: json.load(open(os.path.join(bodies, n)))["body"]
    own = [n for n in own if load(n).get("tools")]
    if sent and own:
        mine, its = blocks(load(own[-1])), blocks(load(sent[0]))
        # Up to the session's last cache mark, or the whole of it where nothing is marked (the stand-in Claude Code).
        last = max((i + 1 for i, (_, marked) in enumerate(mine) if marked), default=len(mine))
        same = [b for b, _ in its[:last]] == [b for b, _ in mine[:last]]
        say(f"   {what}: its request starts as the session's last did, up to its last cache mark: {same}")
    else:
        say(f"   {what}: no request to compare")


def main():
    env = {k: v for k, v in S["claudeEnv"].items()}
    session = Session([S["claude"], "--permission-mode", "default", "--model", S["startModel"]], env)
    status = 0
    try:
        steps(session)
    except CouldntCheck as why:
        say(f"couldn't check: {why}")
        status = 3
    finally:
        session.stop()
    sys.exit(status)


main()
