#!/usr/bin/env python3
# The permission hook: a request for your OK in Claude Code is asked in the Whozmove panel too.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
"""When a tool needs your OK, Claude Code shows its own prompt and runs this hook alongside it, and whichever is
answered first wins. The hook leaves the request in ~/Library/Application Support/Whozmove/asks/<id>.json, where
the panel shows it on the session's row, and waits for the panel's answer in <id>.answer.json: "allow" (this
once) or "deny". It never grants more than once: no "always allow" rules.

Claude Code doesn't always stop the hook when its own prompt is answered, so the hook watches the session's
transcript too. Once the tool call has its result there (answered, dismissed or interrupted in Claude), there's
nothing left to ask, and the hook goes. It goes when the session ends, too.

Claude's questions (the AskUserQuestion tool) come the same way, since Claude's question box is the permission
prompt for that tool. They're answered the way that box answers them: the tool's input, with your answers
added. Only for that tool may an answer change a tool's input.

If the panel isn't running, the hook steps aside at once and the prompt is answered as usual. So it does
wherever Claude Code wouldn't show its own prompt alongside: for a sub-agent (some wait for the hook before
asking), a session that isn't interactive (`claude -p`), and for leaving plan mode, which only Claude's own
prompt can approve.

It's wired in hooks/hooks.json as a synchronous hook, since a hook that returns a decision can't be async, with a
long timeout, so a request can wait for you. Claude's own prompt stays usable meanwhile.
"""
import glob
import json
import os
import signal
import subprocess
import sys
import time
import uuid

# Whozmove's folder: must match AppDir in app/Files.m (tests/hooks.sh fails if it doesn't).
ROOT = os.path.expanduser("~/Library/Application Support/Whozmove")
ASKS = os.path.join(ROOT, "asks")
WAIT_LIMIT = 3500  # seconds; just under the hook's timeout in hooks/hooks.json


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def panel_pid():
    """The running panel's pid, or None. A pid left behind by a panel that crashed can belong to some
    other process by now, so it has to be the panel's executable."""
    try:
        with open(os.path.join(ROOT, "panel.pid")) as f:
            pid = int(f.read().strip())
        command = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True,
                                 timeout=5).stdout.strip()
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    # The app's executable, CFBundleExecutable in Info.plist (tests/hooks.sh names its stand-in from there).
    return pid if os.path.basename(command) == "Whozmove" else None


def interactive_session(session_id):
    """Whether the session is one Claude Code is running interactively (its own registry says so), where
    its prompt shows alongside this hook."""
    for path in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try:
            with open(path) as f:
                entry = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(entry, dict) and entry.get("sessionId") == session_id and entry.get("kind") == "interactive" \
                and isinstance(entry.get("pid"), int) and alive(entry["pid"]):
            return True
    return False


def transcript_of(event):
    path = event.get("transcript_path")
    if path and os.path.isfile(path):
        return path
    found = glob.glob(os.path.expanduser("~/.claude/projects/*/%s.jsonl" % event["session_id"]))
    return found[0] if found else None


def find_call(path, event):
    """The tool call this request is for, in the transcript: (its id, the byte offset just past its line), or
    (None, None) while it isn't written yet. Claude Code's id for it if the event has one, else the newest
    call of this tool with this input."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            base = max(0, f.tell() - 4 * 1024 * 1024)
            f.seek(base)
            tail = f.read()
    except OSError:
        return None, None
    end = len(tail)
    while end > 0:
        start = tail.rfind(b"\n", 0, end - 1) + 1
        line = tail[start:end]
        end = start
        if b'"tool_use"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        content = (entry.get("message") or {}).get("content") if isinstance(entry, dict) else None
        for item in content if isinstance(content, list) else []:
            if not isinstance(item, dict) or item.get("type") != "tool_use":
                continue
            if (event.get("tool_use_id") and item.get("id") == event["tool_use_id"]) or (not event.get("tool_use_id")
                    and item.get("name") == event.get("tool_name") and item.get("input") == event.get("tool_input")):
                return item.get("id"), base + start + len(line)
    return None, None


def has_result(path, call_id, offset):
    """Whether the call's result has been written after `offset`; and how far the transcript was read."""
    try:
        with open(path, "rb") as f:
            f.seek(offset)
            chunk = f.read()
    except OSError:
        return False, offset
    end = chunk.rfind(b"\n") + 1  # complete lines only
    for line in chunk[:end].splitlines():
        if call_id.encode() not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        content = (entry.get("message") or {}).get("content") if isinstance(entry, dict) else None
        if entry.get("type") == "user" and isinstance(content, list) and any(
                isinstance(item, dict) and item.get("type") == "tool_result" and item.get("tool_use_id") == call_id
                for item in content):
            return True, offset + end
    return False, offset + end


def write_atomically(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(event, dict) or not event.get("session_id"):
        return
    if event.get("agent_id") or event.get("tool_name") == "ExitPlanMode":
        return
    panel = panel_pid()
    if not panel or not interactive_session(event["session_id"]):
        return

    os.umask(0o077)  # the request carries what the tool would do (a file's contents): yours only
    os.makedirs(ASKS, exist_ok=True)
    try:
        os.chmod(ROOT, 0o700)
    except OSError:
        pass
    ask_id = uuid.uuid4().hex
    request = os.path.join(ASKS, ask_id + ".json")
    answer = os.path.join(ASKS, ask_id + ".answer.json")

    def clean_up(*_):
        for path in (request, answer):
            try:
                os.remove(path)
            except OSError:
                pass

    def cancelled(*_):  # stopped by Claude Code: answered in Claude, or the hook timed out
        clean_up()
        sys.exit(0)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, cancelled)

    write_atomically(request, {
        "id": ask_id,
        "sessionId": event["session_id"],
        "tool": event.get("tool_name", ""),
        "input": event.get("tool_input", {}),
        "cwd": event.get("cwd", ""),
        "at": int(time.time() * 1000),
        "pid": os.getpid(),
    })
    transcript, call_id, read_to = transcript_of(event), None, None
    try:
        started, ticks = time.time(), 0
        while time.time() - started < WAIT_LIMIT:
            try:
                with open(answer) as f:
                    reply = json.load(f)
            except (OSError, ValueError):
                reply = {}
            behavior = reply.get("behavior") if isinstance(reply, dict) else None
            if behavior in ("allow", "deny"):
                question = event.get("tool_name") == "AskUserQuestion"
                if behavior == "allow":
                    decision = {"behavior": "allow"}
                    answers = reply.get("answers")
                    if question and isinstance(answers, dict):
                        decision["updatedInput"] = dict(event.get("tool_input") or {},
                                                        answers={str(k): str(v) for k, v in answers.items()})
                else:
                    decision = {"behavior": "deny", "message": "The user chose not to answer these questions."
                                if question else "Denied in Whozmove."}
                print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": decision}}))
                return
            if not alive(panel):  # the panel quit: leave it to Claude's own prompt
                return
            ticks += 1
            if transcript and ticks % 4 == 0:  # each second: was it settled in Claude meanwhile?
                if read_to is None:
                    call_id, read_to = find_call(transcript, event)
                if read_to is not None:
                    done, read_to = has_result(transcript, call_id, read_to)
                    if done:
                        return
            if ticks % 20 == 0 and not interactive_session(event["session_id"]):  # the session ended
                return
            time.sleep(0.25)
    finally:
        clean_up()


if __name__ == "__main__":
    main()
