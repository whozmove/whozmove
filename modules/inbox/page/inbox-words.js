// Messages' rules, as plain functions (its page cases check them): every message your sessions sent each other in the
// last two days, as the app last sent them, put together; who each one is from and to, told apart by session, never
// by name; which message answers which; where each stands, in words; what each filter shows; and the inbox strip, in
// the order the app gives. Nothing here draws (inbox-view.js does), and nothing is ever answered or sent from here:
// a held message is let in on its row, and an inbox is read by its own session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What the app last sent (setMessages): the messages, oldest first, each inbox with what it hasn't read yet, this
// week's counts, and how the read stands; null until it has.
moduleState({ messages: null });

// A kept message's priority as its tag says it. A plain message has none: no one set one.
const MX_PRIORITY_WORDS = { urgent: 'Urgent', question: 'Question', report: 'Report', note: 'Note' };
// How a plain message can fail to arrive. A kept one is never lost: its words are in the inbox, however the note
// telling its session went.
const MX_NOT_DELIVERED = ['held', 'expired', 'denied', 'dropped', 'failed'];
// A message as long as this, or longer than three lines, is clipped to three lines with Show All.
const MX_LONG = 220;

// The messages as they stand after what the app just sent: all of them, or the new and changed ones laid over those
// held, by id. A kept message is sent by its inbox's id until its note is seen, then by the note's own id, so one with
// a kept id takes the place of whatever had that kept id before. Oldest first, as the channel reads.
function mxTake(held, messages, whole) {
  const incoming = messages || [];
  const kept = new Set(incoming.map((m) => m.kept?.id).filter(Boolean));
  const ids = new Set(incoming.map((m) => m.id));
  const before = whole ? [] : (held || []).filter((m) => !ids.has(m.id) && !(m.kept && kept.has(m.kept.id)));
  return [...before, ...incoming].sort((a, b) => (a.at || 0) - (b.at || 0) || String(a.id).localeCompare(String(b.id)));
}

// What each session is called here: its name, and where two sessions in these messages share one, which it is (its
// folder, or "ended"), as an agent is its session, never its name. By session id; a receiver with no session (its
// address names none Whozmove knows) isn't listed, as nothing can narrow to it.
function mxNames(list) {
  const parties = new Map();
  for (const m of list || []) {
    for (const p of [m.from, m.to]) if (p?.session && !parties.has(p.session)) parties.set(p.session, p);
  }
  const byName = new Map();
  for (const p of parties.values()) {
    const name = mxPartyName(p);
    byName.set(name, (byName.get(name) || 0) + 1);
  }
  const names = new Map();
  for (const [session, p] of parties) {
    const name = mxPartyName(p);
    const which = byName.get(name) > 1 ? (p.ended ? 'ended' : p.folder || 'ended') : null;
    names.set(session, { name, which, label: which ? `${name} (${which})` : name });
  }
  return names;
}

// A sender's or receiver's name as it reads in a sentence: its session's name, else plainly what it is.
const mxPartyName = (p) => p?.name || (p?.session ? 'An unnamed session' : 'An ended session');

// What each message answers, by id: the latest earlier message its receiver sent its sender that reached it (one that
// arrived, or was kept in an inbox) and that nothing answered yet. So a reply answers what it's a reply to, and two
// messages in a row answer one each, the newest first.
function mxAnswers(list) {
  const answers = new Map(), answered = new Set();
  const sorted = [...(list || [])].sort((a, b) => (a.at || 0) - (b.at || 0));
  sorted.forEach((m, i) => {
    if (!m.from?.session || !m.to?.session) return;
    for (let j = i - 1; j >= 0; j--) {
      const p = sorted[j];
      if (answered.has(p.id) || p.from?.session !== m.to.session || p.to?.session !== m.from.session) continue;
      if (!p.kept && p.delivery !== 'arrived') continue;
      answers.set(m.id, p.id);
      answered.add(p.id);
      return;
    }
  });
  return answers;
}

// The other way round: what answered each message, by id.
function mxAnsweredBy(answers) {
  const by = new Map();
  for (const [reply, to] of answers) by.set(to, reply);
  return by;
}

// Everything the words below are worked out from, once for a draw: the messages by id, the names, and which answers
// which.
function mxContext(list, now) {
  const answers = mxAnswers(list);
  return { list: list || [], byId: new Map((list || []).map((m) => [m.id, m])), names: mxNames(list), answers,
           answeredBy: mxAnsweredBy(answers), now };
}

// Whether a message has been answered: a plain one once its receiver wrote back to its sender after it, a kept one
// once its inbox's session marked it answered.
const mxAnswered = (m, ctx) => (m.kept ? !!m.kept.answeredAt : ctx.answeredBy.has(m.id));

// Waiting: held for your OK, or kept in an inbox and not answered yet. A report or a note needs only reading; a question
// or an urgent one waits on its answer.
function mxWaiting(m, ctx) {
  if (!m.kept) return m.delivery === 'held';
  if (m.kept.answeredAt) return false;
  return !m.kept.readAt || m.kept.priority === 'urgent' || m.kept.priority === 'question';
}

// Not delivered: a plain message held, or that never got there. One the inbox kept is still read, however its note
// went.
const mxLost = (m) => !m.kept && MX_NOT_DELIVERED.includes(m.delivery);

// A time of day, as the panel's clocks write it: "22:04".
function mxClock(at) {
  const d = new Date(at);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// The day a message was sent, for the line where the day changes: Today, Yesterday, else the day's name.
function mxDayWord(at, now) {
  const day = (t) => { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); };
  const days = Math.round((day(now) - day(at)) / 86400000);
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  return ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][new Date(at).getDay()];
}

// A session's name in a sentence: its name alone, as which one it is shows by its name in the message's head.
const mxName = (p, ctx) => (p?.session && ctx.names.get(p.session)?.name) || mxPartyName(p);

// Where a message stands, in words: {words, tone, go, copy}, or null for nothing to say (a plain message that arrived
// and hasn't been answered, so the channel stays quiet). `tone` is '' (grey: nothing for you to do), read, answered or
// gone (lost: the words are only in the sender's conversation); `go` is the reply a press goes to; `copy` whether its
// words can be copied, for a message that didn't get there. Nothing here is your move: a held message is let in on
// its receiver's row, the one place to act.
function mxWhere(m, ctx) {
  const to = mxName(m.to, ctx);
  const reply = ctx.byId.get(ctx.answeredBy.get(m.id));
  if (m.kept) {
    const k = m.kept;
    if (k.answeredAt) {
      const by = `Answered by ${to} · ${mxClock(k.answeredAt)}`;
      return { words: reply || !k.note ? by : `${by}: ${k.note}`, tone: 'answered', go: reply?.id || null, copy: false };
    }
    if (k.readAt) {
      const reader = k.readBy && ctx.names.get(k.readBy)?.name || to;
      return { words: `Read by ${reader} · ${mxClock(k.readAt)}`, tone: 'read', go: null, copy: false };
    }
    const note = { held: `${to}’s tab held the note telling it`, expired: `the note telling ${to} expired`,
                   denied: `the note telling ${to} was turned down`, dropped: `the note telling ${to} didn’t go`,
                   failed: `the note telling ${to} didn’t go` }[m.delivery];
    if (note) return { words: `Kept in ${to}’s inbox · ${note}`, tone: '', go: null, copy: false };
    return { words: `In ${to}’s inbox · not read yet · ${ago(ctx.now - m.at)}`, tone: '', go: null, copy: false };
  }
  switch (m.delivery) {
    case 'arrived':
      return reply ? { words: `Answered by ${to} · ${mxClock(reply.at)}`, tone: 'answered', go: reply.id, copy: false }
        : null;
    case 'held':
      return m.canAsk ? { words: `Held in ${to}’s tab: your OK is on ${to}’s row`, tone: '', go: null, copy: false }
        : { words: `Held: ${to} can’t ask you to let it in`, tone: '', go: null, copy: true };
    case 'expired': return { words: `Expired unread: ${to} never saw it`, tone: 'gone', go: null, copy: true };
    case 'denied': return { words: `Turned down in ${to}’s tab`, tone: 'gone', go: null, copy: true };
    case 'dropped': return { words: `Dropped: ${to} never got it`, tone: 'gone', go: null, copy: true };
    case 'failed':
      return { words: 'Didn’t go: no session listens at that address now', tone: 'gone', go: null, copy: true };
    case 'sent': return { words: `Sent · not seen in ${to}’s conversation yet`, tone: '', go: null, copy: false };
    default: return null;
  }
}

// Whether a message's words are clipped to three lines, with Show All.
const mxLong = (text) => String(text || '').length > MX_LONG || String(text || '').split('\n').length > 3;

// The first words of a message, on one line, for the inbox strip and what a reply answers: Markdown's bold and code
// marks taken out, as the line shows them as they'd read.
function mxFirstWords(text, most) {
  const line = String(text || '').replace(/\*\*|__|`/g, '').replace(/\s+/g, ' ').trim();
  return line.length > most ? line.slice(0, most - 1).trimEnd() + '…' : line;
}

// The messages one agent sent and received (`agent`, a session), or those between a pair (`pair`, two sessions), or
// all of them.
function mxNarrowed(list, view) {
  if (view.pair) {
    const [a, b] = view.pair;
    return list.filter((m) => (m.from?.session === a && m.to?.session === b)
                             || (m.from?.session === b && m.to?.session === a));
  }
  if (view.agent) return list.filter((m) => m.from?.session === view.agent || m.to?.session === view.agent);
  return list;
}

// What the channel shows for a view, {filter: all, waiting or lost; agent; pair}, oldest first.
function mxShown(view, ctx) {
  const narrowed = mxNarrowed(ctx.list, view);
  if (view.filter === 'waiting') return narrowed.filter((m) => mxWaiting(m, ctx));
  if (view.filter === 'lost') return narrowed.filter(mxLost);
  return narrowed;
}

// How many wait and how many didn't get there, among what one agent or a pair narrows the channel to, for the filters'
// chips.
function mxCounts(view, ctx) {
  const narrowed = mxNarrowed(ctx.list, view);
  return { all: narrowed.length, waiting: narrowed.filter((m) => mxWaiting(m, ctx)).length,
           lost: narrowed.filter(mxLost).length };
}

// Who the channel is narrowed to, in words: "Wren", or "Wren and Moss"; '' for everyone.
function mxNarrowedTo(view, ctx) {
  const label = (s) => ctx.names.get(s)?.label || 'An ended session';
  if (view.pair) return `${label(view.pair[0])} and ${label(view.pair[1])}`;
  return view.agent ? label(view.agent) : '';
}

// While no agent on this Mac records what its sessions send each other (`facts.agent`, the agent's own name, is null),
// only what was written to an inbox shows: said where the channel would be empty, and above it where it has some.
const MX_NOTHING_YET = 'Nothing to show yet: for now, Messages shows only what’s written to a lead’s inbox';
const MX_NO_AGENT = 'For now, only messages written to a lead’s inbox show here';
const mxNoAgent = (facts) => !!facts && 'agent' in facts && !facts.agent;

// What the channel says with nothing to show, or '' with something: while the first read goes on, without an agent
// that records its messages, with none in the last two days (naming the agent's sessions, in its own word), or with
// none in a view.
function mxEmptyWords(view, ctx, facts) {
  if (mxShown(view, ctx).length) return '';
  if (!ctx.list.length) {
    if (facts?.reading) return 'Reading the last two days…';
    if (mxNoAgent(facts)) return MX_NOTHING_YET;
    return `Messages your ${facts?.agent ? `${facts.agent} ` : ''}sessions send each other show here`;
  }
  const who = mxNarrowedTo(view, ctx);
  const among = view.pair ? `between ${who}` : who ? `from or to ${who}` : '';
  if (view.filter === 'waiting')
    return among ? `Nothing ${among} waits` : 'Nothing waits: every message has been read or answered';
  if (view.filter === 'lost')
    return among ? `Every message ${among} got where it was going` : 'Every message got where it was going';
  return `Nothing ${among} in the last two days`;
}

// This week's counts of what didn't reach a team's lead, in the head's words: "This week: 3 held, 1 lost", only those
// there were; '' with none.
function mxWeekWords(counts) {
  const parts = ['held', 'expired', 'denied', 'dropped', 'failed', 'lost']
    .filter((k) => counts?.[k] > 0)
    .map((k) => `${counts[k]} ${{ denied: 'turned down', failed: 'didn’t go' }[k] || k}`);
  return parts.length ? `This week: ${parts.join(', ')}` : '';
}

// The inbox strip: each inbox with messages its session hasn't read, in the order the app sent them (the one that
// session reads them in: the page never sorts them), each as {project, lead, name, items}; narrowed to one agent's
// messages, or a pair's, as the channel is. An id the messages don't have is left out.
function mxStrip(inboxes, view, ctx) {
  const out = [];
  for (const inbox of inboxes || []) {
    const items = mxNarrowed((inbox.unread || []).map((id) => ctx.byId.get(id)).filter(Boolean), view);
    if (!items.length) continue;
    out.push({ project: inbox.project, lead: inbox.lead, name: mxName(inbox.lead, ctx), items });
  }
  return out;
}

// "2 to read".
const mxToRead = (n) => `${n} to read`;
