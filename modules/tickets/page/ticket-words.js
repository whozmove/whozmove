// What the tickets module draws, in plain functions, checked by its page cases: the Ticket chip on the new conversation
// card and its list (finding a ticket, signing in, Create a ticket, or why there's nothing), the line a start adds to
// your words, a row's tag with its key and where it stands (or "New ticket"), the card pointing at it shows, the card
// asking "Work on PAY-148 here?", the one asking "Move PAY-142 to In Review?" and the one asking "Create this ticket?".
// Every word from a tracker or a session goes in escaped. Nothing here knows a tracker or a status by name: each
// ticket brings its own, and its kind (to do, under way, done, dropped) gives its colour.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// A ticket, drawn small: a ticket's outline, which names no tracker.
const TICKET_ICON = '<svg class="tk-i" width="11" height="11" viewBox="0 0 16 16" aria-hidden="true"><path fill="none" '
  + 'stroke="currentColor" stroke-width="1.4" d="M2.5 4.5h11v2a1.5 1.5 0 0 0 0 3v2h-11v-2a1.5 1.5 0 0 0 0-3z"/></svg>';
const TICKET_KINDS = { todo: 'to do', doing: 'under way', done: 'done', dropped: 'dropped' };
const ticketKind = (kind) => (TICKET_KINDS[kind] ? kind : 'todo');

// A time of day as the panel shows one, 10:42.
function ticketClock(ms) {
  const d = new Date(ms);
  return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// The trackers you're signed in to, and the sites they search.
const ticketsSignedIn = (trackers) => (trackers || []).filter((t) => t.signIn === 'in');
const ticketSites = (trackers) => ticketsSignedIn(trackers).flatMap((t) => t.sites || []);

// ---- The card ----

// The chip after where it starts: "Ticket" until one's picked, then its key, or "New ticket", with × to take it off.
function ticketChipHTML(pick) {
  if (!pick) return '<span class="tag chip outline st-chip tk-chip" data-k="t" title="Give it a ticket: find one, '
    + `paste its key or link, or create one">${TICKET_ICON}Ticket</span>`;
  if (pick.create) return '<span class="tag chip st-chip tk-chip on" data-k="t" title="It talks the ticket through with '
    + `you, then shows it on its row for your yes">${TICKET_ICON}New ticket`
    + '<b class="tk-x" title="No ticket" aria-label="No ticket">×</b></span>';
  return `<span class="tag chip st-chip tk-chip on" data-k="t" title="${esc(pick.title || pick.key)}">${TICKET_ICON}`
    + `${esc(pick.key)}<b class="tk-x" title="No ticket" aria-label="No ticket">×</b></span>`;
}

// What the box says once a ticket's picked, and the line a start adds after your words, naming the skill that says how
// to work it, or to make a new one.
const ticketPlaceholder = (pick) => (pick.create ? 'What’s the ticket about? A line is enough: Claude asks the rest'
  : `Anything to add about ${pick.key}? Or just Start`);
function ticketStartLine(pick) {
  if (pick.create) return `Create a ${pick.tracker} ticket from this${pick.site ? `, on ${pick.site}` : ''} `
    + '(the whozmove:working-a-ticket skill says how).';
  return `Work on ${pick.tracker} ticket ${pick.key}${pick.link ? `: ${pick.link}` : ''} `
    + '(the whozmove:working-a-ticket skill says how).';
}

// The first address in your words, as you paste a ticket's link in them: the app says whether it's a ticket.
function ticketLinkIn(text) {
  const found = /https:\/\/[^\s<>"']+/.exec(String(text ?? ''));
  return found ? found[0].replace(/[.,;:!?)\]]+$/, '') : null;
}

// One button in the list, for the module to act on (data-tk-act), naming the tracker it's for.
const ticketButton = (act, label, tracker, main) => `<button class="button ${main ? 'main' : 'quiet'} small tk-act" `
  + `data-tk-act="${act}" data-tracker="${esc(tracker.name)}">${esc(label)}</button>`;

// A tracker's reason as a sentence, ending with its full stop.
function ticketSentence(why) {
  return /[.!?…]$/.test(why) ? why : `${why}.`;
}

// Why there's nothing to search yet, for the first tracker not signed in: signing in once, waiting for its page, an
// admin's block (with what to ask them), or a sign-in that ran out, or can't be used, in the tracker's words.
function ticketSignInHTML(t, copied) {
  const who = t.signInName || t.name;
  if (t.signIn === 'signing') return `<div class="tk-signin"><span>Waiting for ${esc(who)}’s page in your browser…</span>`
    + `${ticketButton('cancel', 'Cancel', t)}</div>`;
  if (t.signIn === 'blocked') return `<div class="tk-signin"><span>${esc(t.why
      || `Your ${t.name} admin hasn’t let apps sign in from this Mac yet. They can allow it once, for everyone.`)}</span>`
    + `<div class="tk-buttons">${ticketButton('copyAsk', copied ? 'Copied' : 'Copy What to Ask', t, true)}`
    + `${ticketButton('signIn', 'Try Again', t)}</div></div>`;
  if (t.signIn === 'allow') return `<div class="tk-signin"><span>${esc(t.why || `Whozmove was updated, so macOS asks `
      + `once before it hands over your ${who} sign-in.`)}</span><span class="tk-why">Press Allow, then Always Allow in `
    + `macOS’s box.</span>${ticketButton('signIn', 'Allow', t, true)}</div>`;
  if (t.signIn === 'expired') return `<div class="tk-signin"><span>${t.why ? esc(ticketSentence(t.why))
      : `The sign-in with ${esc(who)} has run out.`}</span>`
    + `${ticketButton('signIn', 'Sign In Again', t, true)}</div>`;
  const why = t.why ? `<span class="tk-why">${esc(t.why)}</span>` : '';
  return `<div class="tk-signin"><span>Sign in with ${esc(who)} once to find tickets here</span>${why}`
    + `${ticketButton('signIn', t.why ? 'Try Again' : `Sign In with ${who}`, t, true)}</div>`;
}

// One ticket found: its key, its title (two lines at most), where it stands and its board, and its site when you're
// signed in to more than one.
function ticketFoundHTML(t, i, sel, sites) {
  const group = (t.groups || []).find((g) => g.kind === 'board') || (t.groups || [])[0];
  const where = [t.state?.name, group?.name, sites > 1 ? t.site : ''].filter(Boolean).map(esc).join(' · ');
  return `<div class="option tk-res${i === sel ? ' current' : ''}" data-i="${i}">`
    + `<span class="tk-key">${esc(t.key)}</span><span class="tk-main"><span class="tk-title">${esc(t.title || t.key)}`
    + `</span><span class="tk-meta"><span class="tk-dot tk-${ticketKind(t.state?.kind)}"></span>${where}</span></span></div>`;
}

// The list under the box: its line for words, a key or a link, then what was found, or why not; signing in first when
// no tracker is signed in. `list` is { q, items, sel, asked, answered, end, why, picked }: `end` why the search found
// nothing it could ('failed', 'slow', 'signIn'), `picked`, a key or link that couldn't be the card's ticket ({ key, end,
// site }).
function ticketListHTML(list, trackers, copied) {
  if (!list) return '';
  const signed = ticketsSignedIn(trackers), sites = ticketSites(trackers);
  const open = '<div class="options under-box st-plist tk-list" data-k="tickets">';
  if (!signed.length) {
    const first = (trackers || []).find((t) => t.signIn !== 'in');
    return open + '<div class="c-lhead">Tickets</div>'
      + (first ? ticketSignInHTML(first, copied) : '<div class="tk-none">There’s no ticket tracker here.</div>') + '</div>';
  }
  const field = '<input class="field small st-field tk-q" data-part="tickets" placeholder="Find a ticket: words, its '
    + `key, or a link" value="${esc(list.q)}" spellcheck="false" aria-label="Find a ticket">`;
  const tracker = signed[0], who = esc(tracker.signInName || tracker.name);
  const p = list.picked, said = list.q.length > 30 ? list.q.slice(0, 28) + '…' : list.q;
  // Why it couldn't find or read one, each with its way forward: the same words for a pasted link and a search.
  const ended = (end, what, why) => end === 'signIn'
    ? `<div class="tk-none">${tracker.why || why ? esc(ticketSentence(tracker.why || why))
      : `The sign-in with ${who} has run out.`}</div><div class="tk-signin">`
      + `${ticketButton('signIn', 'Sign In Again', tracker, true)}</div>`
    : end === 'allow'
    ? `<div class="tk-none">Whozmove was updated, so macOS asks once before it hands over your ${who} sign-in.</div>`
      + `<div class="tk-signin">${ticketButton('signIn', 'Allow', tracker, true)}</div>`
    : end === 'slow' ? `<div class="tk-none">${who} asked Whozmove to slow down: try again in a moment.</div>`
    : end === 'notFound' && why ? `<div class="tk-none">${esc(why)}.</div>`
    : `<div class="tk-none">Couldn’t reach ${who} just now.</div>`
      + `<div class="tk-signin">${ticketButton(what, 'Try Again', tracker)}</div>`;
  let body = '';
  if (p?.end === 'elsewhere') body = `<div class="tk-none">That’s a ticket on ${esc(p.site)}, which you haven’t signed `
    + `in to.</div><div class="tk-signin">${ticketButton('signIn', `Sign In with ${tracker.signInName || tracker.name}`,
      tracker, true)}</div>`;
  else if (p?.end === 'site') body = `<div class="tk-none">Paste ${esc(p.key)}’s link, so it’s clear which site it’s on.</div>`;
  else if (p?.end === 'notFound') body = `<div class="tk-none">There’s no ${esc(p.key)} you can see.</div>`;
  else if (p?.end) body = ended(p.end, 'find', '');
  else if (list.asked && !list.answered) body = '<div class="tk-none">Looking…</div>';
  else if (list.end) body = ended(list.end, 'search', list.why);
  else if (list.answered && !list.items.length) body = list.q.trim()
    ? `<div class="tk-none">No tickets match “${esc(said)}”. Type a key such as PAY-142, or paste its link.</div>`
    : '<div class="tk-none">Nothing of yours is open. Type words, a key or a link.</div>';
  else body = list.items.map((t, i) => ticketFoundHTML(t, i, list.sel, sites.length)).join('');
  // Create a ticket, always last, whatever was found, as the card still starts conversations when nothing can be.
  const n = list.items.length;
  const create = `<div class="option tk-res tk-create${list.sel === n ? ' current' : ''}" data-i="${n}">`
    + '<span class="tk-key tk-plus" aria-hidden="true">+</span><span class="tk-main"><span class="tk-title">Create a '
    + 'ticket</span><span class="tk-meta">Claude talks it through with you, then shows it for your yes</span></span></div>';
  // `who` is escaped already.
  const searched = sites.length > 1 ? `searching ${esc(sites.join(', '))}` : `signed in to ${sites[0] ? esc(sites[0]) : who}`;
  return open + field + body + create
    + `<div class="c-lfoot"><b>↑↓</b> and <b>Return</b> to pick · <b>Esc</b> closes · ${searched}</div></div>`;
}

// ---- The row ----

// After the row's name: the key, and where the ticket stands, in its kind's colour; while it's first read, the key
// alone; and when it can't be read, why, briefly. VoiceOver says the kind in words. A session started from Create a
// ticket, with none yet, says "New ticket".
function ticketTagHTML(sid, t, creating) {
  if (!t?.key && creating) return `<span class="tag tk-row tk-new" data-tknew="${esc(sid)}" aria-label="New ticket">`
    + `${TICKET_ICON}<span class="tk-rk">New ticket</span></span>`;
  if (!t?.key) return '';
  const kind = t.state ? ticketKind(t.state.kind) : '';
  const p = t.problem, problem = p?.kind === 'signIn' ? 'sign in again' : p?.kind === 'allow' ? 'allow its sign-in'
    : p && !t.state && p.kind === 'failed' ? 'couldn’t read it now' : '';
  // A sign-in that ran out, or waits for Allow, says so even over where it stood, as nothing is read again until then.
  const first = p?.kind === 'signIn' || p?.kind === 'allow' || !t.state ? problem : '';
  const says = first ? `<span class="tk-rs tk-problem">${first}</span>`
    : t.state ? `<span class="tk-rs tk-${kind}">${esc(t.state.name)}</span>` : '';
  const label = `${t.key}${first ? `, ${first}` : t.state ? `, ${t.state.name}, ${TICKET_KINDS[kind]}` : ''}`;
  // A problem it says is one to put right, so the whole tag is in that colour, the key with it.
  return `<span class="tag tk-row${first ? ' needs' : ''}" data-tk="${esc(sid)}" aria-label="${esc(label)}"`
    + ` title="Open ${esc(t.key)} in your browser">`
    + `${TICKET_ICON}<span class="tk-rk">${esc(t.key)}</span>${says}</span>`;
}

// A ticket's groups, a line for each kind in the order the tracker gave them, labelled by what they are: "Project", or
// "Boards" when it's on several of that kind. A kind it has no word for is a "Group".
const TICKET_GROUP_WORDS = { project: 'Project', board: 'Board', team: 'Team' };
function ticketGroupsHTML(groups) {
  const kinds = [...new Set(groups.map((g) => g.kind))];
  return kinds.map((kind) => {
    const ofKind = groups.filter((g) => g.kind === kind), word = TICKET_GROUP_WORDS[kind] || 'Group';
    const names = ofKind.map((g) => `${esc(g.name)}${g.sprint ? ` · ${esc(g.sprint)}` : ''}`).join('<br>');
    return `<div class="tk-cl"><span class="tk-lab">${word}${ofKind.length > 1 ? 's' : ''}</span><span>${names}</span></div>`;
  }).join('');
}

// A tracker's reason as part of a sentence, without its full stop.
const ticketClause = (why) => String(why).replace(/[.!?…]+$/, '');
// A tracker's reason after a colon, as the rest of a sentence: its first letter small, unless its first word is a name
// (Whozmove, the tracker's, its sign-in's: `names`) or written in capitals (PAY-142, macOS).
function ticketReason(why, names) {
  const clause = ticketClause(why), first = clause.split(/[\s,:;]/)[0];
  if (['Whozmove', ...(names || [])].includes(first) || /^.+[A-Z]/.test(first)) return clause;
  return clause.charAt(0).toLowerCase() + clause.slice(1);
}

// What the ticket's card says of its last move: where it went, and who moved it (this conversation, under May Move Its
// Ticket, or you, with Move It), with how long ago; or why there was nothing to move, until it's read again. Never
// "by itself", which reads as the tracker's own automation.
function ticketMovedHTML(m, now) {
  if (!m) return '';
  const words = m.gone ? `${esc(ticketClause(m.gone))}, so there’s nothing to move`
    : `Moved to ${esc(m.to)} ${m.by === 'itself' ? 'by this conversation' : 'when you pressed Move It'}`;
  return `<div class="tk-cl"><span class="tk-lab">Last move</span><span>${words}`
    + `${m.at && now ? ` · ${ago(now - m.at)}` : ''}</span></div>`;
}

// Pointed at: the ticket as last read: where it stands, its key and type, its priority, its title, what it's part of,
// its project and boards with their sprints, and where it can go next, a step the session stopped at marked as a
// person's, with its why under it; its last move; or why it couldn't be read, with what to press.
function ticketCardHTML(t, who, now) {
  if (!t?.key) return '';
  const p = t.problem;
  const problem = !p ? '' : p.kind === 'allow'
    ? `<div class="tk-cl tk-warn">Whozmove was updated, so macOS asks once before it hands over the sign-in.</div>`
      + '<div class="perm-actions"><button data-act="signIn">Allow</button></div>'
    : p.kind === 'signIn'
    ? `<div class="tk-cl tk-warn">${esc(t.key)} can’t be read until you sign in again.</div>`
      + '<div class="perm-actions"><button data-act="signIn">Sign In Again</button></div>'
    : p.kind === 'slow'
    ? `<div class="tk-cl tk-warn">${esc(who || t.tracker)} asked Whozmove to slow down: reading again`
      + `${p.retryAt ? ` at ${ticketClock(p.retryAt)}` : ' soon'}.</div>`
      + '<div class="perm-actions"><button data-act="now">Try Now</button></div>'
    : `<div class="tk-cl tk-warn">Couldn’t read it now${p.why ? `: ${esc(ticketReason(p.why, [t.tracker, who]))}`
      : ''}.</div>`
      + '<div class="perm-actions"><button data-act="again">Try Again</button></div>';
  if (!t.state) return `<div class="card-head"><span class="c-ref">${esc(t.key)}</span></div>`
    + (problem || '<div class="tk-cl">Reading it…</div>');
  const kind = ticketKind(t.state.kind);
  const groups = ticketGroupsHTML(t.groups || []);
  const stopped = t.stopped || {}, theirs = (s) => typeof stopped[s.id] === 'string';
  const steps = (t.steps || []).map((s) => `<span class="tag tk-step tk-${theirs(s) ? 'theirs' : ticketKind(s.to?.kind)}">`
    + `${esc(s.to?.name || s.name)}${theirs(s) ? ' · a person’s' : ''}</span>`).join('');
  const whys = (t.steps || []).filter(theirs).map((s) => '<div class="tk-cl"><span class="tk-lab"></span>'
    + `<span class="tk-theirs-why">${esc(s.to?.name || s.name)}: ${esc(stopped[s.id])}</span></div>`).join('');
  return `<div class="card-head"><span class="pill tk-pill tk-${kind}">${esc(t.state.name)}</span>`
    + `<span class="c-ref">${esc(t.key)}${t.type ? ` · ${esc(t.type)}` : ''}</span>`
    + `<span class="end">${esc(t.priority || '')}</span></div>`
    + `<div class="card-title c-title">${esc(t.title || t.key)}</div>`
    + (t.parent ? `<div class="tk-cl"><span class="tk-lab">Part of</span><span>${esc(t.parent.key)} `
      + `${esc(t.parent.title || '')}</span></div>` : '')
    + groups
    + (steps ? `<div class="tk-cl"><span class="tk-lab">Next</span><span class="tk-steps">${steps}</span></div>` : '')
    + whys + ticketMovedHTML(t.moved, now)
    + problem
    + `<div class="c-foot tk-foot">Press to open it in your browser${t.site ? `, on ${esc(t.site)}` : ''}</div>`;
}

// The card on the row asking you to give it a ticket it asked for (ticket-use), or the one it had before Whozmove
// started again: the ticket as read (its key, where it stands and its title), or "Reading it…", or why it couldn't be;
// then Use It or Not Now, either way. Nothing is given until you press Use It.
function ticketUseHTML(sid, o, who) {
  if (!o?.key) return '';
  const title = o.again ? `Work on ${o.key} here again?` : o.instead ? `Work on ${o.key} instead?`
    : `Work on ${o.key} here?`;
  const on = o.site ? `, on ${esc(o.site)}` : '';
  const help = o.again ? `It worked on this ticket before Whozmove started again${on}.`
    : o.instead ? `It works on ${esc(o.instead)} now, and asks to change to this ticket${on}.`
    : `This conversation asks to work on this ticket${on}.`;
  const p = o.problem;
  const read = o.state ? `${esc(o.key)} · ${esc(o.state.name)}${o.title ? `: ${esc(o.title)}` : ''}`
    : p ? `Couldn’t read the ticket${p.why ? `: ${esc(ticketReason(p.why, [o.tracker, who]))}` : ' just now'}.`
    : 'Reading it…';
  return `<div class="perm tk-use" data-tkuse="${esc(sid)}" data-key="${esc(o.key)}"><div class="q-top"><span class="card-title">${esc(title)}`
    + `</span></div><div class="q-help">${read}</div><div class="q-help">${help}</div>`
    + '<div class="perm-actions"><button data-act="notNow">Not Now</button>'
    + '<button class="perm-allow" data-act="use">Use It</button></div></div>';
}

// The card on the row asking you to move its ticket by the step the session asked for (ticket-move), while May Move Its
// Ticket is off: where it goes, the note it adds to the ticket, whole, and each field the step sets, with its value,
// whole; and, asked again, the move it takes the place of. Move It or Not Now; while it moves, "Moving it…"; when it
// couldn't, why, with Try Again or Not Now; when its tracker turned it away, what the tracker said, with its own page
// first, then Try Again or Not Now. Nothing moves until you press.
function ticketMoveHTML(sid, m, tracker, who) {
  if (!m?.key || !m.stepId) return '';
  const to = m.to?.name || m.name;
  const again = m.instead ? `<div class="q-help">Asked again: this takes the place of moving it to ${esc(m.instead)}.`
    + '</div>' : '';
  const note = m.note ? `<div class="q-help">It adds this to ${esc(m.key)} as it goes:</div>`
    + `<div class="tk-note">${esc(m.note)}</div>` : '';
  const fields = (m.fields || []).map((f) => `<div class="tk-cl"><span class="tk-lab">${esc(f.name)}</span>`
    + `<span class="tk-val">${esc(f.value)}</span></div>`).join('');
  const p = m.problem, refused = p?.kind === 'refused';
  // What the tracker itself said of a move it turned away, as it said it, under who said it.
  const says = refused && p.says ? `<div class="q-help">${tracker ? esc(tracker) : 'It'} says:</div>`
    + `<div class="tk-note">${esc(p.says)}</div>` : '';
  const foot = m.moving ? '<div class="q-help tk-moving">Moving it…</div>'
    : (p?.kind === 'allow' ? '<div class="perm-why tk-warn">Whozmove was updated, so macOS asks once before it hands '
      + 'over the sign-in.</div>'
      : p ? `<div class="perm-why tk-warn">Couldn’t move it${p.why ? `: ${esc(ticketReason(p.why, [tracker, who]))}`
        : ' just now'}.`
      + `</div>${says}` : '')
      + '<div class="perm-actions"><button data-act="notNow">Not Now</button>'
      // One its tracker turned away needs something done on the ticket itself first (a field to fill in), or someone
      // else to move it, which trying again as it is won't change: its own page leads, with Try Again beside it.
      + (refused ? '<button data-act="move">Try Again</button><button class="perm-allow" data-act="open">'
        + `${tracker ? `Open in ${esc(tracker)}` : 'Open the Ticket'}</button>`
        // A move the sign-in stops is let through only by signing in again (or Allow), never by trying again as it is.
        : p?.kind === 'signIn' ? '<button class="perm-allow" data-act="signIn">Sign In Again</button>'
        : p?.kind === 'allow' ? '<button class="perm-allow" data-act="signIn">Allow</button>'
        : `<button class="perm-allow" data-act="move">${p ? 'Try Again' : 'Move It'}</button>`) + '</div>';
  return `<div class="perm tk-move" data-tkmove="${esc(sid)}" data-tracker="${esc(tracker || '')}" `
    + `data-key="${esc(m.key)}" data-step="${esc(m.stepId)}" data-state="${esc(ticketMoveState(m))}" `
    + `data-at="${esc(String(m.at || ''))}"><div class="q-top"><span class="card-title">`
    + `${esc(`Move ${m.key} to ${to}?`)}</span></div>${again}${note}${fields}${foot}</div>`;
}

// Pointed at, the tag of a session started from Create a ticket that has none yet: what happens before anything is
// made in its tracker.
function ticketNewCardHTML(c) {
  if (!c?.tracker) return '';
  return '<div class="card-head"><span class="c-ref">New ticket</span></div>'
    + `<div class="tk-cl">Claude is talking it through with you. Before anything is made in ${esc(c.tracker)}, the ticket `
    + 'shows on this row for your yes.</div>';
}

// The state a move's card shows, for its press to wait until it has been seen: asked, being moved, or why it wasn't.
const ticketMoveState = (m) => (m.moving ? 'moving' : m.problem?.kind || 'asked');

// The state a new ticket's card shows, for its press to wait until it has been seen: checked or not, then being
// checked, made, or why it couldn't be.
const ticketDraftState = (d) => `${d.checked ? 'checked' : 'unchecked'}:${d.creating ? 'creating'
  : d.checking ? 'checking' : d.problem ? d.problem.kind : 'ready'}`;

// The card on the row asking you to create the new ticket the session drafted (ticket-draft). First, when it was
// drafted again, or the session has a ticket the new one would take the place of, it says so; then its title, where it
// goes (the group, by what its tracker calls it, and its site when you're signed in to more than one: `sites`), its
// type, priority and parent, and its whole description. While its tracker checks where it can go, "Checking it with
// …"; while it's made, "Creating it…". When the check couldn't be done, why, with Try Again (`check`); when making it
// couldn't, why, with Try Again (`create`), or, when it may have been made all the same, where to look first, with
// Create Again; Sign In Again or Allow when the sign-in stopped it; and Not Yet. Nothing is made until you press
// Create Ticket.
function ticketDraftHTML(sid, d, who, sites) {
  if (!d?.title || !d.at) return '';
  const line = (label, value) => (value ? `<div class="tk-cl"><span class="tk-lab">${label}</span>`
    + `<span class="tk-val">${esc(value)}</span></div>` : '');
  const where = TICKET_GROUP_WORDS[d.groupKind] || 'Group';
  const why = [d.again ? 'Drafted again.' : '',
    d.instead ? `This conversation works on ${esc(d.instead)} now: once it’s created, the new ticket takes its place.` : '']
    .filter(Boolean).join(' ');
  const p = d.problem, reason = p?.why ? esc(ticketReason(p.why, [d.tracker, who])) : '';
  const signedOut = p?.kind === 'signIn' || p?.kind === 'allow';
  const failed = !p ? '' : p.kind === 'allow'
    ? '<div class="perm-why tk-warn">Whozmove was updated, so macOS asks once before it hands over the sign-in.</div>'
    : d.mayBeMade && !signedOut
    ? `<div class="perm-why tk-warn">Couldn’t tell whether it was made${reason ? ` (${reason})` : ''}: look in `
      + `${esc(d.group)}${sites > 1 ? ` on ${esc(d.site)}` : ''} first, and create it again only if it isn’t there.</div>`
    : `<div class="perm-why tk-warn">Couldn’t ${d.checked ? 'create' : 'check'} it${reason ? `: ${reason}` : ' just now'}.`
      + '</div>';
  const again = !d.checked ? '<button class="perm-allow" data-act="check">Try Again</button>'
    : `<button class="perm-allow" data-act="create">${d.mayBeMade ? 'Create Again' : p ? 'Try Again'
      : 'Create Ticket'}</button>`;
  const foot = d.creating ? '<div class="q-help tk-moving">Creating it…</div>'
    : d.checking ? `<div class="q-help tk-moving">Checking it with ${esc(d.tracker)}…</div>`
      + '<div class="perm-actions"><button data-act="notYet">Not Yet</button></div>'
    : failed + '<div class="perm-actions"><button data-act="notYet">Not Yet</button>'
      // A new ticket the sign-in stops goes only once you've signed in again (or allowed it), never by trying again.
      + (p?.kind === 'signIn' ? '<button class="perm-allow" data-act="signIn">Sign In Again</button>'
        : p?.kind === 'allow' ? '<button class="perm-allow" data-act="signIn">Allow</button>' : again) + '</div>';
  return `<div class="perm tk-draft" data-tkdraft="${esc(sid)}" data-tracker="${esc(d.tracker)}" `
    + `data-at="${esc(String(d.at))}" data-state="${esc(ticketDraftState(d))}"><div class="q-top">`
    + '<span class="card-title">Create this ticket?</span></div>'
    + (why ? `<div class="q-help">${why}</div>` : '')
    + line('Title', d.title) + line(where, d.group) + (sites > 1 ? line('On', d.site) : '') + line('Type', d.type)
    + line('Priority', d.priority) + line('Part of', d.parent)
    + (d.description ? `<div class="q-help">Its description:</div><div class="tk-note">${esc(d.description)}</div>` : '')
    + (d.creating ? '' : '<div class="q-help">To change anything, say so in the conversation, and it shows here '
      + 'again.</div>')
    + `${foot}</div>`;
}
