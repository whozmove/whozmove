#!/usr/bin/env python3
# The words hook: your words from a session's side chat, handed in between its steps, for the Whozmove panel.
# Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
"""Whozmove's words hook, started by whozmove-claude-words.sh on PostToolBatch and Stop while words wait.

Your words from a session's side chat go in between its steps: as its current tool calls finish (PostToolBatch), or as
its turn ends (Stop, which then carries the turn on), the hook asks the panel over a connection of its own to the
panel's socket (HookLine.m, in the Claude Code module) for any words waiting for its session, and hands them to Claude
as the event's additional context, which Claude reads before its next move. Nothing is typed.

Only the panel's own process is asked, and the panel hands words only to a process the session itself started. A
sub-agent's tool calls are skipped: your words are for the session itself. With no panel, nothing to hand, or no answer
within a few seconds, the hook says nothing and the session goes on as it was.
"""
import json
import os
import select
import socket
import subprocess
import sys

# Whozmove's folder: must match AppDir in app/shared/Files.m (modules/claude-code/tests/test.sh fails if it doesn't).
ROOT = os.path.expanduser("~/Library/Application Support/Whozmove")
HOOK_LINE = os.path.join(ROOT, "hook.sock")  # the panel's end of the line (HookLine.m)
SOL_LOCAL, LOCAL_PEERPID = 0, 2  # macOS's <sys/un.h>: who's at the other end of a Unix socket
ANSWER_WAIT = 3  # seconds the panel's answer is waited for; well under the hook's timeout in hooks/hooks.json
EVENTS = ("PostToolBatch", "Stop")


def program_of(pid):
    """The program a process runs, by its path, or None (libproc's proc_pidpath, else /bin/ps)."""
    try:
        import ctypes
        libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
        path = ctypes.create_string_buffer(4096)
        length = libproc.proc_pidpath(ctypes.c_int(pid), path, ctypes.c_uint32(4096))
        return path.value.decode(errors="replace") if length > 0 else None
    except (ImportError, OSError, AttributeError):
        pass
    try:
        return subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True,
                              timeout=5).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def panel_pid():
    """The running panel's pid, or None: the pid it notes, only while that process runs the panel's executable."""
    try:
        with open(os.path.join(ROOT, "panel.pid")) as f:
            pid = int(f.read().strip())
    except (OSError, ValueError):
        return None
    command = program_of(pid)
    return pid if command and os.path.basename(command) == "Whozmove" else None


def ask_panel(session_id, event):
    """The words the panel hands this session's hook now, or None."""
    panel = panel_pid()
    if not panel:
        return None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(ANSWER_WAIT)
        sock.connect(HOOK_LINE)
        if sock.getsockopt(SOL_LOCAL, LOCAL_PEERPID) != panel:
            sock.close()
            return None
        sock.sendall((json.dumps({"words": {"sessionId": session_id, "event": event}}) + "\n").encode())
        buffer = b""
        while b"\n" not in buffer:
            ready, _, _ = select.select([sock], [], [], ANSWER_WAIT)
            if not ready:
                break
            chunk = sock.recv(65536)
            if not chunk:
                break
            buffer += chunk
        sock.close()
    except OSError:
        return None
    try:
        answer = json.loads(buffer.split(b"\n", 1)[0])
    except ValueError:
        return None
    words = answer.get("words") if isinstance(answer, dict) else None
    return words if isinstance(words, str) and words.strip() else None


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    if not isinstance(event, dict):
        return
    name, session_id = event.get("hook_event_name"), event.get("session_id")
    # A sub-agent's tool calls carry its agent_id: your words are for the session itself, never a sub-agent.
    if name not in EVENTS or event.get("agent_id") or not isinstance(session_id, str) or not session_id:
        return
    words = ask_panel(session_id, name)
    if words:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": name, "additionalContext": words}}))


main()
