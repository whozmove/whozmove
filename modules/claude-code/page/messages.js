// A message another session sent this one (its prompt, `promptFrom`): what this session replies to it goes back to
// that session, not to you, so the reply never waits on you, anywhere in the list. The sender is known by
// its session or its address (`promptFromSession`, `promptFromAddress`, as the app finds them in Claude Code's
// wrapper), never by a name alone. A reply from before that message, and a request or question the session asks you
// itself, still do (classify in whose-move.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Whether the session's last reply answered a message another session sent it.
function repliedToSession(s) {
  return !!(s.promptFrom && (s.promptFromSession || s.promptFromAddress))
    && (s.lastReplyAt || 0) >= (s.lastPromptAt || 0);
}
core.repliesElsewhere.push(repliedToSession);
