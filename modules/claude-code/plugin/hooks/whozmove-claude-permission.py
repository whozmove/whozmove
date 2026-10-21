#!/usr/bin/env python3
# The permission hook: a request for your OK in Claude Code is asked in the Whozmove panel too, and so is Claude Code's
# "Switch model?" for a switch the panel asked for.
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

A plan waiting for your OK (the ExitPlanMode tool) comes the same way too, but the panel can only turn it down:
send it back with your notes, which Claude gets as it would from its own prompt and so stays in plan mode to
rewrite the plan, or stop it, which stops Claude's turn. Claude Code takes a plan's approval only from its own
prompt and ignores a hook's, so an "allow" for a plan is never passed on: the hook keeps waiting.

If the panel isn't running, the hook steps aside at once and the prompt is answered as usual. So it does
wherever Claude Code wouldn't show its own prompt alongside: for a sub-agent (some wait for the hook before
asking) and a session that isn't interactive (`claude -p`).

It's wired in hooks/hooks.json as a synchronous hook, since a hook that returns a decision can't be async, with a
long timeout, so a request can wait for you. Claude's own prompt stays usable meanwhile.

The same hook runs before every switch of a session's model (PreModelSwitch), a /model typed in the terminal too. Only
a switch the panel has just asked for is its business: right before it types /model, the panel leaves a note for the
session in switches/<session>.panel.json, with the model and when, and the hook takes it, once, only within 20
seconds (Claude Code checks the model with its servers first), and only for that model; the panel takes it back once
its pick is over, so a note left by a pick that never went in can't make a later switch the panel's. Any
other switch is left alone: the hook says nothing, and Claude Code asks as usual. For the panel's switch, Claude Code
says whether the conversation's prompt cache is warm, which is when it would ask "Switch model?" (switching re-reads
the whole conversation). While it isn't, the hook allows the switch, and nothing is asked. While it is, the hook asks
in the panel instead: the question goes in <session>.ask.json, with the model it's leaving, the one it's switching to
and how much the conversation holds, and the panel's answer comes in <session>.answer.json: allowed, the switch goes
on without Claude's own question; turned down, it's blocked, and the session stays on its model. If the panel isn't
running, or doesn't answer within a minute, the hook says nothing, and Claude asks in the terminal as usual: the hook
never decides on its own to re-read a cached conversation. Its timeout in hooks/hooks.json is longer than that wait, as
Claude Code blocks a switch whose hook times out.
"""
import glob
import json
import os
import re
import signal
import subprocess
import sys
import time
import uuid

# Whozmove's folder: must match AppDir in app/shared/Files.m (modules/claude-code/tests/test.sh fails if it doesn't).
ROOT = os.path.expanduser("~/Library/Application Support/Whozmove")
ASKS = os.path.join(ROOT, "asks")
WAIT_LIMIT = 3500  # seconds; just under the hook's timeout in hooks/hooks.json
SWITCHES = os.path.join(ROOT, "switches")
NOTE_LASTS = 20  # seconds a panel's note that it's switching a session's model counts for (kNoteLasts, Switches.m)
SWITCH_WAIT = 60  # seconds the panel's answer to "Switch model?" is waited for; well under the hook's timeout


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
    # The app's executable, CFBundleExecutable in Info.plist (modules/claude-code/tests/test.sh names its stand-in
    # from there).
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


def take_note(session_id, event):
    """Whether the panel left a note that it's switching this session to the model the switch is for, within the
    last NOTE_LASTS seconds. The note is taken as it's read, so it counts once."""
    path = os.path.join(SWITCHES, session_id + ".panel.json")
    try:
        with open(path) as f:
            note = json.load(f)
        os.remove(path)
    except (OSError, ValueError):
        return False
    if not isinstance(note, dict) or not isinstance(note.get("at"), (int, float)) \
            or not isinstance(note.get("to"), str) or not note["to"]:
        return False
    if time.time() * 1000 - note["at"] > NOTE_LASTS * 1000:
        return False
    asked = [m for m in (event.get("requested_model"), event.get("to_model")) if isinstance(m, str)]
    return any(m.startswith(note["to"]) for m in asked)


def switch_decision(decision, reason=None):
    output = {"hookEventName": "PreModelSwitch", "permissionDecision": decision}
    if reason:
        output["permissionDecisionReason"] = reason
    print(json.dumps({"hookSpecificOutput": output}))


def model_switch(event):
    session_id = event["session_id"]
    if not re.fullmatch(r"[A-Za-z0-9-]{1,128}", session_id) or not take_note(session_id, event):
        return
    if event.get("prompt_cache_warm") is False:  # nothing to re-read: Claude Code wouldn't ask
        switch_decision("allow")
        return
    panel = panel_pid()
    if not panel:
        return
    os.umask(0o077)
    os.makedirs(SWITCHES, exist_ok=True)
    question = os.path.join(SWITCHES, session_id + ".ask.json")
    answer = os.path.join(SWITCHES, session_id + ".answer.json")

    def clean_up(*_):
        for path in (question, answer):
            try:
                os.remove(path)
            except OSError:
                pass

    def cancelled(*_):  # stopped by Claude Code
        clean_up()
        sys.exit(0)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, cancelled)
    clean_up()  # an answer left from an earlier question isn't this one's
    tokens = event.get("context_tokens")
    write_atomically(question, {
        "sessionId": session_id,
        "from": event.get("from_model") if isinstance(event.get("from_model"), str) else "",
        "to": event.get("to_model") if isinstance(event.get("to_model"), str) else "",
        "tokens": tokens if isinstance(tokens, int) and tokens > 0 else None,
        "at": int(time.time() * 1000),
        "pid": os.getpid(),
    })
    try:
        started = time.time()
        while time.time() - started < SWITCH_WAIT:
            try:
                with open(answer) as f:
                    reply = json.load(f)
            except (OSError, ValueError):
                reply = {}
            allow = reply.get("allow") if isinstance(reply, dict) else None
            if allow is True:
                switch_decision("allow")
                return
            if allow is False:
                switch_decision("deny", "You kept this model in Whozmove.")
                return
            if not alive(panel):
                return
            time.sleep(0.25)
    finally:
        clean_up()


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(event, dict) or not isinstance(event.get("session_id"), str) or not event["session_id"]:
        return
    if event.get("agent_id"):
        return
    if event.get("hook_event_name") == "PreModelSwitch":
        model_switch(event)
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
            plan = event.get("tool_name") == "ExitPlanMode"
            if behavior in ("allow", "deny") and not (plan and behavior == "allow"):
                question = event.get("tool_name") == "AskUserQuestion"
                if behavior == "allow":
                    decision = {"behavior": "allow"}
                    answers = reply.get("answers")
                    if question and isinstance(answers, dict):
                        decision["updatedInput"] = dict(event.get("tool_input") or {},
                                                        answers={str(k): str(v) for k, v in answers.items()})
                elif plan and reply.get("stop") is True:
                    decision = {"behavior": "deny", "interrupt": True,
                                "message": "The user stopped here and doesn't want this plan carried out."}
                elif plan and isinstance(reply.get("message"), str) and reply["message"].strip():
                    decision = {"behavior": "deny", "message": "The user wants changes to the plan: "
                                + reply["message"].strip()[:10000]}
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
