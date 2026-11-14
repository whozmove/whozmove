// The list's HTML: a session's row, and the project headers. The row's template is this part's; what the
// modules show on it goes in its places (core.slots), each giving its HTML or nothing.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The app a session runs in, as a row names it (core.hosts): the module's that holds it (Claude Desktop), else a terminal.
// A terminal session that has ended opens again in the terminal the app names (opensIn).
const TERMINAL_HOST = {
  name: 'Terminal', openNow: 'Open in your terminal now', inName: '',
  closedTip: (s) => (s.opensIn ? `Stopped: click to carry it on in ${s.opensIn}` : 'Stopped'),
};
function hostOf(s) {
  return core.hosts.find((host) => host.holds(s)) || TERMINAL_HOST;
}

// A worktree, wherever it shows (a row's details line, the new conversation card): its icon and its branch's name on a
// chip in the worktree colours. Where it sits adds its own classes and attributes (`cls`, `attrs`), and its size.
function worktreeChip(name, cls = '', attrs = '') {
  return `<span class="wt${cls ? ` ${cls}` : ''}"${attrs}>${WORKTREE_ICON}<span class="wt-name">${esc(name)}</span></span>`;
}

// A session's row in the list, the one in view: none while its group is folded. Never a chat's row beside the folded
// cat (chats.js), which repeats the session's: a chat lands on the list's row and leaves it while the panel already
// counts as folded.
function rowInView(sid) {
  return [...document.querySelectorAll('#list .row[data-id]')]
    .find((r) => r.dataset.id === sid && !r.closest('.prows.closed')) || null;
}

// What a place on a row (or a project's header) shows: each module's part there, in the order they were added.
function slot(name, of) {
  return core.slots[name].map((part) => part(of)).join('');
}

// The line saying what the session is doing while it works: "Thinking" until its first step, then each step as it runs
// (or that it's compacting), shining, under a label that breathes (`label`, Claude's on a row), with the turn's time
// ticking (tickTimes) and a module's end after it. A row's Claude's line while it works, and given to the parts and
// modules that show the same line elsewhere, so it reads the same wherever it's drawn. `still`: the same words without
// the shine or the breathing, for a place where the line sits inside a scroller under sticky bars, which WebKit then
// paints again every frame (One Task's talk): only the time ticks.
function workLineHTML(s, now, { label = 'Claude', end = '', still = false } = {}) {
  const since = s.compacting || s.lastPromptAt || s.statusUpdatedAt;
  const doing = s.compacting ? 'Compacting the conversation' : s.activity || 'Thinking';
  return `<div class="claude work${still ? ' still' : ''}" data-mode="work"><span class="who"`
    + `${still ? '' : ` style="${phase(2800)}"`}>${esc(label)}</span>`
    + `<span class="what">${still ? esc(doing) : shineHTML(doing)}</span>`
    + (since ? `<span class="elapsed" data-since="${since}">${elapsed(now - since)}</span>` : '')
    + (end ? `<span class="chat-end">${end}</span>` : '') + '</div>';
}

// The last exchange under the title, as a chat: your message, and below it Claude's line, each with its label.
// While Claude works, the line shows the step it's on and the turn's time so far, with its label fading in and
// out; when it needs you, what for; then its reply. Both lines stay from one turn to the next, so every change is
// text replaced in place (morph) and nothing moves. A step's name stays up after the step finishes, as in Claude's
// own progress row, and a step shows once it starts running (a hook can't see it sooner). The chat shows while
// Claude works or needs you, and for a reply until its session goes Idle (dimmer once read). Claude's line is its
// reply only when that answers your message: after a turn you stopped, there's only yours. A conversation started
// from the panel and not listed yet (starts.js) says it's starting, or what it waits for, or why it didn't start. A row
// shown briefly has Claude's line alone (`yours` false). Claude's line ends with what the modules put there (`end`:
// the chatEnd slot), after its words. As rowHTML has them: a request answered beside the folded panel (`answered`), and
// a module's line there (`said`).
function chatHTML(s, kind, now, { yours = true, answered = null, end = '', said = null } = {}) {
  const tail = end ? `<span class="chat-end">${end}</span>` : '';
  // Claude's line in one of its looks (`look`, and `mode`, by which morph knows it), saying `text`, with its end.
  const claudeLine = (look, mode, text) => `<div class="claude ${look}" data-mode="${mode}">`
    + `<span class="who">Claude</span><span class="what">${esc(text)}</span>${tail}</div>`;
  // Out beside the folded panel for what a module says is new in the session (a reply in its side chat), Claude's line
  // says that, as a reply you haven't read, in its place (rowHTML).
  if (said) return claudeLine('reply', 'reply', said);
  if (kind === 'idle' && !s.compacting) return '';
  // Your message, or one another session sent, under its name.
  const who = s.promptFrom ? `<span class="who from">${esc(s.promptFrom)}</span>` : '<span class="who">You</span>';
  const you = s.lastPrompt && yours
    ? `<div class="you">${who}<span class="what">${esc(s.lastPrompt)}</span></div>` : '';
  let claude = '';
  if (s.startProblem) {
    claude = claudeLine('wait', 'wait', s.activity);
  } else if (kind === 'busy' || s.compacting) {  // working, or compacting, by itself or asked for
    claude = workLineHTML(s, now, { end });
  } else if (answered) {  // answered beside the folded panel, till the app's rows say the request has gone (rowHTML)
    claude = claudeLine(`done${answered.no ? ' no' : ''}`, 'done', answered.text);
  } else {
    const wants = kind === 'needs' && (s.ask ? core.agent.askLine?.(s.ask) || 'Needs your OK to go on' : s.notice);
    const text = wants || ((s.lastReplyAt || 0) >= (s.lastPromptAt || 0) ? s.lastReply : '');
    const look = wants ? 'wait' : isRead(s, view()) ? 'reply read' : 'reply';
    if (text) claude = claudeLine(look, wants ? 'wait' : 'reply', text);
  }
  return you + claude;
}

// The work line, while there's something on it: at its start the session's pull requests (or Create PR, once its
// branch is pushed with none, or how the checkout's last code review went, or where it stands while commits wait), and
// at its end what isn't committed in the checkout and the steps its work has to take. The row's note (stepLine), when it
// has one, is said in the line's place, over what it holds, which stays laid out unseen, so the row keeps its height and
// nothing under it moves; cut short to one line, with all of it over it. While the session's agent is at work (asking
// you something along the way, or compacting, too), the line goes, but for a note, which it keeps saying in its place: a
// step it was just asked, or a deploy still running.
function workHTML(row, note = null) {
  if (!note && (row.kind === 'busy' || row.kind === 'needs' || row.s.compacting)) return '';
  const start = slot('workStart', row), end = slot('numbers', row) + slot('steps', row);
  if (!start && !end) return '';
  const said = note ? `<div class="work-note notice inline${noteTone(note)}" title="${esc(note.text)}">`
    + `${esc(note.text)}</div>` : '';
  return `<div class="work${note ? ' noted' : ''}">${start}${end ? `<span class="work-end">${end}</span>` : ''}`
    + `${said}</div>`;
}

// The bottom line, as an editor's status bar has it: how the session's agent is set up at its start (its model, effort
// and mode, and its context ring but while the row asks something of you: the modules' setup), and where it runs at its
// end: the worktree, or the branch (or, outside git, the folder), which pointed at says the project and more
// (placeCardHTML), and what a module puts after it: what stays there whatever the row's end does (placeStays: Deploy's
// address), then that end (placeEnd: Deploy's button), unless it's at the note's end (row.endAtNote) or the row asks
// something of you (row.asking), when it has one action, at its ask's end. Short of room, a long name where it runs (past a dozen
// letters) shortens first, to about that, then the agent's effort and model give way; the name keeps its dozen
// letters, and the mode never gives way (rows.css).
function whereHTML(row) {
  const { s } = row, g = s.git;
  const branch = g && (g.branch || 'detached @' + g.detached), name = g ? branch : base(s.cwd);
  const place = !g ? `<span class="branch folder">${esc(name)}</span>`
    : g.worktree ? worktreeChip(branch, 'branch') : `<span class="branch">${BRANCH_ICON}${esc(branch)}</span>`;
  const long = [...name].length > 12 ? ' long' : '';
  return `<div class="where">${slot('setup', row)}<span class="gap"></span>`
    + `<span class="place${long}" data-place="${esc(s.sessionId)}">${place}</span>${slot('placeStays', row)}`
    + `${row.asking || row.endAtNote ? '' : slot('placeEnd', row)}</div>`;
}

// Which of the agent's separators show (the "·" between its model, effort and mode), from its parts in order, each
// 'pick', 'gone' (a pick given way whole) or 'sep': only one between two picks that show, so a pick that's gone takes
// its "·" with it. A plain function, which tests/panel.sh checks.
function sepsShown(parts) {
  const shown = [];
  let before = false, sep = -1;
  parts.forEach((part, i) => {
    if (part === 'sep') { shown.push(false); if (before) sep = shown.length - 1; return; }
    if (part === 'pick') {
      if (sep >= 0) shown[sep] = true;
      before = true;
      sep = -1;
    }
  });
  return shown;
}

// A pick on the bottom line squeezed past showing even one letter and its "…" goes whole (`.gone`), with its "·",
// rather than staying a sliver: the effort first, then the model; the mode never does (rows.css). Measured as each
// new list is in, before anything else measures it, so what moves next starts from the line as it will stay. It's
// measured at rest (`.at-rest`, rows.css): what still opens its room on the line as it comes (Deploy's address, its
// server just up) is measured open, or a pick would stay a sliver once that room had opened.
function fitWhere(list) {
  const lines = list.querySelectorAll('.where');
  for (const line of lines) line.classList.add('at-rest');
  for (const agent of list.querySelectorAll('.where .agent')) {
    for (const kind of ['effort', 'model']) {
      const pick = agent.querySelector(`:scope > .pick[data-pick="${kind}"]`);
      if (!pick || pick.scrollWidth <= pick.clientWidth + 1) continue;
      const pad = parseFloat(getComputedStyle(pick).paddingLeft) + parseFloat(getComputedStyle(pick).paddingRight);
      if (pick.clientWidth - pad < textWidth(pick, [...pick.textContent][0] + '…')) pick.classList.add('gone');
    }
    const parts = [...agent.children].map((el) => el.classList.contains('sep') ? 'sep'
      : el.classList.contains('gone') ? 'gone' : 'pick');
    const shown = sepsShown(parts);
    agent.querySelectorAll(':scope > .sep').forEach((sep, i) => sep.classList.toggle('gone', !shown[i]));
  }
  // On a row a module marks `place-gives-way`, where the session runs goes whole, its icon too, once it's squeezed at
  // all, rather than showing cut. The place itself never overflows, as its name shortens inside it: the name is
  // measured (a branch's or folder's own, a worktree chip's name in it).
  for (const place of list.querySelectorAll('.row.place-gives-way .where .place'))
    if ([...place.querySelectorAll('.branch, .wt-name')].some((name) => name.scrollWidth > name.clientWidth + 1))
      place.classList.add('gone');
  for (const line of lines) line.classList.remove('at-rest');
}
core.drawn.push(fitWhere);

// ---- The mark at a row's far edge ----

// A module's button at the far edge of a row (core.slots.edge), the edge the reader opens on: a strip as tall as the row
// in its last 8 points, its own padding past the end of its lines, so nothing pressable there is covered and the row
// never moves. Its bar (rows.css) shows faintly while the row is pointed at, and swells a little and lights while the
// strip is: the row whose strip the pointer is on is kept in state and marked in place as hover looks, and the next
// rebuild draws it so from state.edgePointed, so the swell never plays again as the list is drawn. A module keeps the
// bar lit by marking what's in it `.keep` (its chat open), and lights it in your move's colour by marking it `.lit`.

// The side the reader would open to now, as the app works it out each time the panel moves: on the body, as
// `far-left` when it's the left, so a row's strip is at the edge the reader comes out of (rows.css).
window.readerSide = (side) => { document.body.classList.toggle('far-left', side === 'left'); };

// Each time hover looks: the row whose strip the pointer is on, marked, and the one that was, not. Only the rows
// change, in place.
core.pointerWatchers.push((el) => {
  const row = el?.closest?.('.row[data-id] > .edge-room')?.parentElement;
  const pointed = row ? row.dataset.id : null;
  if (pointed === state.edgePointed) return;
  const was = state.edgePointed;
  state.edgePointed = pointed;
  for (const r of document.querySelectorAll('.row[data-id]')) {
    if (r.dataset.id === was || r.dataset.id === pointed) r.classList.toggle('edge-pointed', r.dataset.id === pointed);
  }
});

// What where a session runs says in its details: a head line, what it is (a worktree, a checkout, a folder) and the app
// it runs in; its project; that it's a worktree of it and on which branch (or which branch it's on, or that it's a
// folder outside git); and its folder.
function placeCardHTML(s) {
  const g = s.git, project = projectOf(s).name;
  const kind = !g ? 'Folder' : g.worktree ? 'Worktree' : 'Checkout';
  const what = !g ? 'A folder outside git'
    : g.worktree ? `A worktree of ${esc(g.worktreeOf || project)}, on branch <b>${esc(g.branch || '')}</b>`
    : g.branch ? `On branch <b>${esc(g.branch)}</b>` : `Detached at <b>${esc(g.detached || '')}</b>`;
  return `<div class="card-head"><span>${kind}</span><span class="end">In ${esc(hostOf(s).name)}</span></div>`
    + `<div class="card-title">${esc(project)}</div><div class="card-lead">${what}</div>`
    + `<div class="pl-path">${esc(g?.root || s.cwd || '')}</div>`;
}

// A conversation open in more than one process at once (s.alsoOpen: resumed in a second tab while it still ran, or open
// in Claude Desktop and a terminal): an icon at the title line's end, in the colour of something to put right, and
// beside it how many times, in words, so it's found without pointing. Rested on, its details say where else
// (twiceCardHTML).
function twiceHTML(s) {
  if (!s.alsoOpen?.length) return '';
  return `<span class="twice" data-sid="${esc(s.sessionId)}">${TWICE_ICON}`
    + `<span class="twice-word">${openTimes(s)}</span></span>`;
}

// How many times it's open, as the row and its details say it.
function openTimes(s) {
  const times = s.alsoOpen.length + 1;
  return times === 2 ? 'Open twice' : `Open ${times} times`;
}

// What "open twice" says in its details: where else the conversation is open, and what that means. Each copy knows
// only what was said in it since the second opened. Nothing goes into a terminal's copy from the panel while another
// runs in a terminal, where a key could land in the other's tab; with the other in an app of its own (Claude Desktop),
// only its mode can't be changed, as the copies share one record of it. One paused in its terminal (Ctrl+Z), maybe in
// the very tab the row's copy runs in, takes nothing, but brought back it would carry on from where it stopped. The
// other copies in terminals can be closed from the card, the one the row follows staying, but not while one works (the
// app checks again, and that none asks anything); one paused, or in Claude Desktop, is closed where it is.
function twiceCardHTML(s) {
  const own = hostOf(s), running = s.alsoOpen.filter((copy) => !copy.paused);
  const apps = [...new Set(running.map(hostOf).filter((host) => host !== TERMINAL_HOST).map((host) => host.name))];
  const tabs = running.filter((copy) => hostOf(copy) === TERMINAL_HOST).length;
  const other = own === TERMINAL_HOST;
  if (tabs > 1) apps.push(`${tabs} ${other ? 'other ' : ''}terminal tabs`);
  else if (tabs) apps.push(`${other ? 'another' : 'a'} terminal tab`);
  const paused = s.alsoOpen.length - running.length;
  const where = [apps.length && `open in ${apps.join(' and ')}`,
                 paused && `paused in ${paused > 1 ? `${paused} terminals` : 'a terminal'}`].filter(Boolean);
  const knows = 'Each copy knows only what was said in it since the second one opened';
  const help = !running.length
    ? "Brought back with fg, it would carry on without what's been said here since: close it when you can."
    : other && tabs ? `${knows}. The panel types nothing into it while another copy runs in a terminal.`
    : other ? `${knows}, so its mode can't be told here: change it in the terminal.`
    : `${knows}.`;
  const working = running.some((copy) => hostOf(copy) === TERMINAL_HOST && copy.busy);
  const close = tabs
    ? `<div class="st-steps"><button class="option" data-act="close"${working ? ' disabled' : ''}>Close the other `
      + `${tabs > 1 ? 'copies' : 'copy'}</button></div>`
      + (working ? `<div class="st-wait">Claude is working there: close it when it's done</div>` : '')
    : '';
  const copies = s.alsoOpen.length + 1;
  return `<div class="card-head"><span class="warn">${openTimes(s)}</span><span class="end">${copies} copies</span></div>
    <div class="card-title">Also ${esc(where.join(', and '))}</div>
    <div class="card-help tw-help">${esc(help)}</div>${close}`;
}

core.cards.push({
  selector: '.place[data-place]',
  key: (place) => 'place:' + place.dataset.place,
  html(place) {
    const s = state.last.sessions.find((x) => x.sessionId === place.dataset.place);
    return s ? placeCardHTML(s) : '';
  },
});
core.cards.push({
  selector: '.twice[data-sid]',
  key: (twice) => 'twice:' + twice.dataset.sid,
  html(twice) {
    const s = state.last.sessions.find((x) => x.sessionId === twice.dataset.sid);
    return s?.alsoOpen?.length ? twiceCardHTML(s) : '';
  },
  press(key, act) {
    if (act === 'close') native({ type: 'closeCopy', sessionId: key.slice('twice:'.length) });
  },
});
// The icon and its words cross-fade as they come, and as how many times changes.
core.swaps.push(':scope > .main > .line1 .twice');

// The row's note, { text, quiet, way, sid } or null (what its button does, `go`, stays on state.stepNotes, where
// pressNoteWay reads it): how a step went, or why it couldn't (or why a deploy couldn't start, or its command wasn't
// saved), for 8s, or for 20s with a button past why it couldn't (`way`: iTerm2's Python
// API turned on, or with `go`, Take me there or a module's own, pressNoteWay), which waits to be seen before it takes a
// press; else what a module has to say (the folder's deploy), and only when none has anything, what one says of where
// things stand (core.rowNotesLast).
// It's said in the work line's place (workHTML), or, on a row without one, on a line of its own over the bottom line
// (noteHTML); a note that says what waits on you (`line`) always has that line of its own, so the work line stays.
// The note is the kit's one-line message (controls.css's .notice, inline): in the colour of something to put right, or
// muted when it's quiet, or in your move's colour for a module's `tone: 'turn'`. A module's note may be laid out its
// own way (`cls`, a class of its own) and say more than words (`html`, made safe by the module, said in place of
// `text`). On a row shown briefly, which has no bottom line, what a module puts at that line's end (Deploy's button)
// goes at the note's end instead (`end`), whichever note it is, unless the note says it has no end (`end: false`).
// An ask line (a note of class `ask-note` on a line of its own) is a bubble in the colour of how pressing it is
// (`look`), ending in its one action (`act`: { want, html }): another module's button for what it wants ('try' is
// Deploy's: askAct), else the note's own (`html`, askActHTML). While it asks, the row draws no other Deploy, and each
// module that ends a row (Deploy, the context ring) leaves its own off while `row.asking` says so.
// Of the modules' notes, one in your move's colour gives way to any other (one that puts something right, as Compact at
// Breaks' warning, or a quiet one), and comes back once that's gone.
// A note's colour, as a class of the kit's notice: none when it's quiet, else your move's or something to put right.
const noteTone = (note) => (note.quiet ? '' : note.tone === 'turn' ? ' turn' : ' warn');
function noteHTML(note, end = '') {
  if (!note) return '';
  // Take Me There, to the session, or a module's way to another app (`out`), has the kit's mark for what takes you out
  // of the panel.
  const way = note.way ? ` <button class="button small note-way" data-way="${esc(note.sid)}">${esc(note.way)}`
    + `${note.out ? OUT_ICON : ''}</button>` : '';
  const bubble = isAsk(note) ? ` ask-${askLook(note)}` : '';
  return `<div class="step-note notice inline${noteTone(note)}${note.cls ? ` ${note.cls}` : ''}${bubble}`
    + `${end ? ' ends' : ''}">${note.html ?? esc(note.text)}${way}${end}</div>`;
}
function stepLine(row) {
  const note = state.stepNotes[row.s.sessionId];
  if (note && Date.now() - note.at < (note.way ? 20000 : 8000))
    return note.way
      ? { text: note.text, quiet: note.quiet, way: note.way, sid: row.s.sessionId,
          out: note.go === 'open' || !!core.noteWays[note.go]?.out }
      : { text: note.text, quiet: note.quiet };
  let turn = null;
  for (const say of core.rowNotes) {
    const said = say(row);
    if (said && !said.quiet && said.tone === 'turn') turn ??= said;
    else if (said) return said;
  }
  if (turn) return turn;
  for (const say of core.rowNotesLast) {
    const said = say(row);
    if (said) return said;
  }
  return null;
}

// A module's ask line, in a note (cls 'ask-note'): its priority's name in bold (`priority`, "P1"), else a mark;
// what waits on you in a few words, cut with "…"; and "+N" when more wait, its tip `moreTip`. They're one span, with the
// module's own attributes (`attrs`, made safe by it: what a press on it does) and its words for it whole (`label`), so
// the ask's one action at the note's end (its `act`) stays outside it, with a press of its own.
const ASK_MARK = '<svg class="ask-line-mark" width="11" height="11" viewBox="0 0 12 12" aria-hidden="true">'
  + '<path d="M2 1.6h8a1 1 0 0 1 1 1v4.8a1 1 0 0 1-1 1H6.2L3.6 10.6V8.4H2a1 1 0 0 1-1-1V2.6a1 1 0 0 1 1-1z" '
  + 'fill="none" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/>'
  + '<path d="M3.6 4.2h4.8M3.6 6h3" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>';
function askLineHTML(words, more = 0, moreTip = '', attrs = '', label = '', priority = '') {
  return `<span class="ask-line-says"${attrs}${label ? ` aria-label="${esc(label)}"` : ''}>`
    + (priority ? `<b class="ask-line-priority">${esc(priority)}</b>` : ASK_MARK)
    + `<span class="ask-line-words">${esc(words)}</span>`
    + (more ? `<span class="tag ask-line-more" title="${esc(moreTip)}">+${more}</span>` : '') + '</span>';
}
// The one button an ask has at its end (a note's `act.html`): round, as Deploy's, with the icon of what it does (the
// kit's), its words in its tip, and the module's own attributes (`attrs`, made safe by it: what a press does).
const askActHTML = (icon, tip, attrs) => `<span class="play ask-act" role="button" title="${esc(tip)}"`
  + ` aria-label="${esc(tip)}"${attrs}>${icon}</span>`;
// Whether a note says what waits on you (an ask line: class `ask-note`, on a line of its own), and the colour its
// bubble is in, by how pressing it is (`look`: urgent, normal or low; normal when it doesn't say).
const isAsk = (note) => !!note?.line && (note.cls || '').split(' ').includes('ask-note');
const ASK_LOOKS = ['urgent', 'normal', 'low'];
const askLook = (note) => (ASK_LOOKS.includes(note.look) ? note.look : 'normal');

// The card under a row's chat: of the modules' cards that want to show there (a request, Compact, Deploy's set-up),
// the most pressing. The others are told they're away, so one that's back waits again before
// it takes a press.
// Sorted once the modules start, when every card is there (they add them as their scripts load).
const sortCards = () => [...core.rowCards].sort((a, b) => a.order - b.order);
let sortedCards = null;
core.starts.push(() => { sortedCards = sortCards(); });
const rowCards = () => sortedCards ?? sortCards();
function rowCard(row) {
  let html = '', taken = false;
  for (const card of rowCards()) {
    if (!taken && card.wants(row)) {
      taken = true;
      html = card.html(row);
    } else card.away?.(row);
  }
  return html;
}

// A card opening on a row closes the cards that would hide it, the more pressing ones that can be closed (Compact, for
// Deploy's set-up), so it shows.
function openingCard(sid, name) {
  for (const card of rowCards()) {
    if (card.name === name) return;
    card.close?.(sid);
  }
}

// Steps as one bar, the same length whatever their count (a board of three and one of twelve look alike): `count` of
// them, what's done up to the one at `at`, then that one in `look` (a class the styles colour: urgent, normal, low,
// busy or idle), never thinner than a dot nor past the bar's end (rows.css). VoiceOver says where it stands in words,
// "Step 4 of 5", with the caller's `label` for it after ("Step 4 of 5, Your test"). It knows no steps of its own: what
// they are, and which look, is the caller's. At none of them (`at` -1), nothing is done and none is marked. Fewer than
// two steps draw nothing, wherever a track is drawn: a track of one says nothing.
function stepTrackHTML(count, at, look, label = '') {
  if (count < 2) return '';
  const said = at < 0 ? `${count} steps` : `Step ${at + 1} of ${count}${label ? `, ${label}` : ''}`;
  return `<span class="step-track" role="img" aria-label="${esc(said)}" style="--n:${count};--at:${Math.max(0, at)}">`
    + `<i class="step-done"></i>${at < 0 ? '' : `<i class="step-now ${look}"></i>`}</span>`;
}

// What a session runs in the background, round its dot: a mark for each job (backgroundRunning), three at most, spaced
// evenly round one ring, which turns on the page's clock (phase), so a rebuild never starts it over. None once the
// session has ended. `timed` false leaves the ring's phase for whoever puts it on the page (the waiting strip, which
// writes its HTML only when it changes), as orbitTimed.
const ORBIT_MOST = 3, ORBIT_MS = 2400, ORBIT_REACH = 7.5, ORBIT_SPREAD_MS = 300, ORBIT_GROW_MS = 200;
function orbitHTML(s, timed = true) {
  const running = s.status === 'closed' ? 0 : backgroundRunning(s), n = Math.min(ORBIT_MOST, running);
  if (!n) return '';
  const marks = Array.from({ length: n }, (_, i) => `<i style="--at:${(360 / n) * i}deg"></i>`).join('');
  const said = `${running} running in the background`;
  return `<span class="orbit" data-count="${n}"${timed ? ` style="${phase(ORBIT_MS)}"` : ''} role="img"`
    + ` aria-label="${esc(said)}">${marks}</span>`;
}
const timeOrbit = (orbit) => { orbit.style.animationDelay = `-${Math.round(performance.now() % ORBIT_MS)}ms`; };
function orbitTimed(root) {
  for (const orbit of root.querySelectorAll('.orbit')) timeOrbit(orbit);
}

// The words for what the marks show, under Claude's line: each job by its command (a shell command's), else by what
// Claude calls it, and how many first once there are more than marks ("Running 5: …").
function runningHTML(s) {
  const jobs = s.status === 'closed' ? [] : s.background || [];
  if (!jobs.length) return '';
  const names = jobs.map((job) => job.command || job.what).filter(Boolean).join(' · ');
  const count = jobs.length > ORBIT_MOST || !names ? `${jobs.length}${names ? ':' : ''} ` : '';
  return `<div class="background-work" title="${esc(names)}">Running ${esc(count)}${esc(names)}</div>`;
}
// How many marks each row's ring had when its list was last drawn (by list, then by row: its id), so a change of count
// is seen through, never a jump (orbitChange).
const orbitCounts = new WeakMap();
// A mark's place on a ring of `n`: one at the top, two opposite, three at thirds; at `scale` of its size.
const markAt = (i, n, scale = 1) => `rotate(${(360 / n) * i}deg) translateY(-${ORBIT_REACH}px) scale(${scale})`;
// Once a list is drawn again, each ring whose count changed moves to its new count, the ring turning on through it.
// Room is made before anything enters it: one joining, the marks there move apart to their new places first, then the
// new one grows in from nothing at its own; one leaving shrinks to nothing where it is, then the rest close up. The
// last one leaving shrinks on a ring of its own, which goes once it has. With reduced motion, the marks stand still,
// and the old ones fade out as the new ones fade in.
function orbitChange(list) {
  const was = orbitCounts.get(list) || new Map(), now = new Map();
  for (const row of list.querySelectorAll('.row[data-id]')) {
    const key = row.dataset.id;
    const dot = row.querySelector(':scope > .dot'), orbit = dot?.querySelector(':scope > .orbit');
    const n = orbit ? Number(orbit.dataset.count) : 0;
    now.set(key, n);
    const before = was.get(key);
    if (dot && before !== undefined && before !== n) moveMarks(dot, orbit, before, n);
  }
  orbitCounts.set(list, now);
}
function moveMarks(dot, orbit, was, n) {
  // The marks that were there, on a copy of the ring at their old places, turning in step: what goes leaves from it.
  const ghost = () => {
    const ring = document.createElement('span');
    ring.className = 'orbit';
    ring.setAttribute('aria-hidden', 'true');
    ring.innerHTML = Array.from({ length: was }, (_, i) => `<i style="--at:${(360 / was) * i}deg"></i>`).join('');
    timeOrbit(ring);
    dot.append(ring);
    return ring;
  };
  if (calm.matches) {
    const old = ghost();
    old.animate([{ opacity: 1 }, { opacity: 0 }], { duration: ORBIT_GROW_MS, fill: 'forwards' })
      .onfinish = () => old.remove();
    orbit?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: ORBIT_GROW_MS, fill: 'backwards' });
    return;
  }
  const marks = orbit ? [...orbit.children] : [];
  if (n > was) {
    marks.forEach((mark, i) => {
      if (i < was) mark.animate([{ transform: markAt(i, was) }, { transform: markAt(i, n) }],
                                { duration: ORBIT_SPREAD_MS, easing: 'ease-in-out' });
      else mark.animate([{ transform: markAt(i, n, 0) }, { transform: markAt(i, n) }],
                        { duration: ORBIT_GROW_MS, delay: was ? ORBIT_SPREAD_MS : 0, easing: 'ease-out',
                          fill: 'backwards' });
    });
    return;
  }
  const old = ghost(), leaving = [...old.children];
  leaving.forEach((mark, i) => {
    if (i < n) { mark.remove(); return; }  // these stay, on the new ring
    mark.animate([{ transform: markAt(i, was) }, { transform: markAt(i, was, 0) }],
                 { duration: ORBIT_GROW_MS, easing: 'ease-in', fill: 'forwards' });
  });
  setTimeout(() => old.remove(), ORBIT_GROW_MS);
  marks.forEach((mark, i) => mark.animate([{ transform: markAt(i, was) }, { transform: markAt(i, n) }],
                                          { duration: ORBIT_SPREAD_MS, delay: ORBIT_GROW_MS, easing: 'ease-in-out',
                                            fill: 'backwards' }));
}
core.drawn.push(orbitChange);

// With Show Conversation Text off, whether Claude's line stays on a row: only while it says what the panel knows of the
// session, never what anyone wrote: while it asks you something (what for, in a few words, over its card), just after
// you answered beside the folded panel (what you answered, `answered`), while it compacts, and while a conversation you
// started from the panel is still starting (or says why it didn't). A plain function, which tests/panel.sh checks.
function conversationLine(s, kind, answered) {
  return kind === 'needs' || !!answered || !!s.compacting || !!s.pending;
}

// What a row's dot says to VoiceOver while the conversation is hidden: what the row is, in a few words, as its colour
// says it: a request just answered beside the folded panel (`answered`) as such, and a session that has stopped with a
// reply still to read as both. A plain function, which tests/panel.sh checks.
const DOT_WORDS = { needs: 'Asks you', busy: 'Working', background: 'Working in the background',
                    turn: 'A reply to read', seen: 'Replied', idle: 'Idle' };
function dotWords(s, kind, answered = null) {
  if (s.status === 'closed') return kind === 'turn' ? 'Stopped, a reply to read' : 'Stopped';
  const running = backgroundRunning(s);
  return (answered ? 'Answered' : DOT_WORDS[kind] || 'Idle') + (running ? `, ${running} running in the background` : '');
}

// Whether a row shown briefly has Claude's line, which says each thing once: none while the row asks something of you
// (an ask's bubble says what the session wants), none under a request's card (`card`: it says what it would run), none
// while it works or once its reply is read; only what it asks when nothing else says it (a question, with no card),
// and its finished line on a reply you haven't read, until you have. A plain function, which tests/panel.sh checks.
function briefLine(row, card = '') {
  if (row.asking) return false;
  return row.kind === 'needs' ? !card : row.kind === 'turn';
}

// A session's row. `row` is what each module's part is given: the session, what it is now (kind: classify), the time
// the rows were sent (now), whether it speaks for its checkout while Show Next Steps is on (owner), the page's own
// clock, which Deploy's press and animations are timed by, whether it's drawn as a chat beside the folded panel (chat:
// chats.js) rather than in the list, with a module's line to say in Claude's place there (said: { line, at }), and
// what each module found when it first looked at the row (core.rowLooks: its
// next steps, Deploy's button).
function rowHTML(s, kind, now, { chat = false, said = null } = {}) {
  // Every row in the list is shown briefly (row.brief), the one view for everyone, but one still starting from the
  // panel, which says how that goes; a chat beside the folded panel is the row whole, there to say what's new.
  // The row you're on (the session in front in its app) keeps its tools all the same (row.tools): its work line (pull
  // requests, what isn't committed, its next steps) and its bottom line (the agent's model, effort and mode, the
  // context ring, where it runs, Deploy), under its short lines, so the session you're working in is the one you can
  // steer from here, and the rest of the list stays short.
  const row = { s, kind, now, owner: state.switches.nextSteps && state.owners.has(s.sessionId),
                clock: Date.now(), chat, brief: !chat && !s.pending };
  row.tools = row.brief && !!s.focused;
  // Beside the folded panel, a request you've answered there shows the answer going in until the app's next rows say
  // it has gone, up to a second on: its card goes, Claude's line says what you answered, written over what it asked
  // (the agent's answeredLine), and its dot is the working one, so the chat shrinks once and never reads as still
  // asking with its card gone. The list keeps the line in the card's place instead.
  const answered = chat && kind === 'needs' && s.ask ? core.agent.answeredLine?.(s.ask) ?? null : null;
  // Beside the folded panel, out for what a module says is new (`said`, { line, at }, a reply in its side chat): its
  // line in Claude's place, and its time on the title line. With Show Conversation Text off (`hidden`), only its time:
  // the line is what someone wrote.
  const hidden = !state.conversationShown;
  const news = chat && said?.line ? said : null, saying = hidden ? null : news;
  for (const look of core.rowLooks) look(row);
  // Whether it has its work line and bottom line: drawn whole, or the row you're on.
  const lined = !row.brief || row.tools;
  // How long ago, on the title line; not while it works (or compacts), when Claude's line has the time (unless the
  // row has no Claude's line: a row shown briefly where something else says it, or none that Show Conversation Text
  // keeps (conversationLine), or Claude's line says what a module said: `saying`, with its own time).
  const since = Number.isFinite(news?.at) ? news.at : kind === 'needs' ? s.statusUpdatedAt || 0 : lastActive(s);
  const time = ago(now - since);
  const closed = s.status === 'closed' ? ' closed' : '';
  const focused = s.focused ? ' focused' : '';
  const tip = s.focused ? hostOf(s).openNow : closed ? hostOf(s).closedTip?.(s) || '' : '';
  const title = tip ? `title="${esc(tip)}"` : '';
  // A module's own classes (a new conversation's row, still landing), after `brief` for a row shown briefly, and
  // `talk-hidden` while Show Conversation Text is off.
  const marks = (row.brief ? ' brief' : '') + (answered ? ' answered' : '') + (hidden ? ' talk-hidden' : '')
    + slot('rowClass', row);
  // A row shown briefly (row.brief) is its title line, with the modules' own parts after the name (their brief slot, in
  // place of the others' name parts), Claude's line without yours only where nothing else says it (briefLine), its
  // card (a request) and its note, under the name a module gives it (row.name), else the session's; and, on the row
  // you're on (row.tools), its work line and bottom line under them, as a whole row has.
  // Its note; whether it asks something of you (row.asking: an ask line), and what its one action is for
  // (row.askWant: the note's `act.want`, such as 'try', which another module's button answers, askAct); whether
  // the bottom line's end is drawn (row.placeEnd): never while the row asks, as an ask has one action and its row
  // draws no other Deploy or context ring, else always on a full row and the row you're on, and on another row shown
  // briefly only at its note's end (row.endAtNote); then Claude's line, with the modules' end after its words while it's there, and
  // whether it is (row.claudeLine). What must stay on the bottom line, Deploy's address, is in a slot of its own there
  // (placeStays). All are known before the title line's places are asked, so a module puts its part in one.
  const note = stepLine(row);
  row.asking = isAsk(note);
  row.askWant = row.asking ? note.act?.want || '' : '';
  row.placeEnd = !row.asking && (lined || (!!note && note.end !== false));
  row.endAtNote = !lined && row.placeEnd;
  // Its card, the most pressing that wants to show (a request), known before Claude's line, which a request's card
  // takes the place of on a row shown briefly.
  const asks = rowCard(row);
  // On a row shown briefly, Claude's line only where nothing else says it (briefLine). With Show Conversation Text
  // off, no one's words: not yours (nor another session's), and Claude's line only where conversationLine keeps it.
  const chatless = (row.brief && !briefLine(row, asks)) || (hidden && !conversationLine(s, kind, answered));
  const chatLines = chatless ? ''
    : chatHTML(s, kind, now, { yours: !row.brief && !hidden, answered, end: slot('chatEnd', row), said: saying?.line });
  row.claudeLine = chatLines.includes('<div class="claude ');
  const work = lined ? workHTML(row, note?.line ? null : note) : '';
  // The note's end: an ask's one action (another module's for what it wants, else the note's own), or on a row shown
  // briefly the parts that end its bottom line (the context ring, Deploy).
  const given = row.asking ? slot('askAct', row) : '';
  const end = row.asking ? given || note.act?.html || '' : row.endAtNote ? slot('placeEnd', row) : '';
  // What ends a row moves: to its note's end (a row shown briefly has no bottom line, and an ask has its action there),
  // and back to the bottom line once the ask has gone, so it comes and goes with the note; and at the note's end it
  // changes, between an ask's own button ('own'), another module's for it ('act': Deploy) and what ends a row shown
  // briefly ('note'). Each time it comes to a place it wasn't in, or another takes its place, what's on the row counts
  // as only just shown (showAgain), so a press meant for what was there (Copy) doesn't land on what's now there
  // (Deploy) before it's been seen.
  // A full row's very first draw is no move, as its end was at the bottom line all along. Its chat beside the folded
  // panel, drawn beside the row with each update, keeps where its own end was apart from the row's, so the two never
  // count as each other's moves, while a move in the chat (its ask arriving) still waits to be seen. Both are kept
  // under the session, so they're forgotten with it.
  const ends = state.briefEnds[s.sessionId] ??= {}, drawn = chat ? 'chat' : 'row';
  const endAt = given ? 'act' : end ? (row.asking ? 'own' : 'note') : !lined || row.asking ? '' : 'line';
  const endWas = ends[drawn];
  if (endAt && endAt !== endWas && (endWas !== undefined || row.brief)) showAgain(s);
  ends[drawn] = endAt;
  // A row that gains or loses its work line and bottom line (`lined`: the row you're on changing, or a start from the
  // panel landing) counts what's on it as only just shown, as when its end moves, whatever its end does: an asking
  // row's end stays the ask's, while its work line's steps (Push, Commit) and its bottom line come in under a press
  // meant for the row that was below it. (A chat beside the folded panel is always drawn whole.)
  const linedKey = drawn + ':lined';
  if (ends[linedKey] !== undefined && ends[linedKey] !== lined) showAgain(s);
  ends[linedKey] = lined;
  // After the title line's words, what follows them (a module's, on a row shown briefly), then, past a gap that
  // lines it up from row to row, what goes at the line's end before the time (a team's job track).
  const titleEnd = slot('titleEnd', row), trail = slot('titleTrail', row);
  const titleTail = (titleEnd ? `<span class="title-end">${titleEnd}</span>` : '')
    + (trail ? `<span class="title-gap"></span>${trail}` : '');
  const timeHTML = (kind === 'busy' || s.compacting) && !chatless && !saying ? ''
    : `<span class="time" data-ago="${since}">${time}</span>`;
  // Its dot, with what the session runs in the background going round it, and what that is under Claude's line, or
  // under its card, so a request's reason and its card stay together.
  const dot = kind === 'needs' && !answered ? phase(1600) : kind === 'busy' || answered ? phase(1400) : '';
  // With no Claude's line (the conversation hidden, or a row shown briefly where nothing needs it), the dot says in words
  // what the row is, as Claude's line would have, for VoiceOver.
  const dotSays = hidden || !row.claudeLine ? ` role="img" aria-label="${esc(dotWords(s, kind, answered))}"` : '';
  const card = asks + (lined ? runningHTML(s) : '');
  // A module's button at the row's far edge (core.slots.edge), its last child; its bar swelled while the pointer is on
  // it (state.edgePointed). There whatever card is open on the row: the strip is the row's own padding past its lines,
  // and a card ends at its lines, its buttons further in still, so it never covers what a card asks you to press.
  const edge = slot('edge', row);
  const room = edge ? `<span class="edge-room">${edge}</span>` : '';
  const pointed = edge && state.edgePointed === s.sessionId ? ' edge-pointed' : '';
  const lines = `<div class="row ${kind}${closed}${focused}${marks}${pointed}" data-id="${esc(s.sessionId)}" ${title}>
      <span class="dot" style="${dot}"${dotSays}>${orbitHTML(s)}</span>
      <div class="main">
        <div class="line1">
          <span class="name">${esc(row.name || s.name || base(s.cwd))}</span>${slot(row.brief ? 'brief' : 'name', row)}
          ${titleTail}${timeHTML}${twiceHTML(s)}
        </div>
        ${chatLines}
        ${card}
        ${work}${work && !note?.line ? '' : noteHTML(note, end)}${lined ? whereHTML(row) : ''}`;
  // Under its lines, the details open on it (parts/details), from what the row now has.
  return `${lines}${detailsHTML(s.sessionId, chat, lines)}
      </div>${room}
    </div>`;
}

// A group's rows in a body that folds to nothing: folded, a group hides all its rows, even one that waits on you, as its
// header says how many do (groupsHTML), a request still comes out beside the folded panel, and the count beside the
// pawn counts it. The rows stay in the body, in place, so opening the group slides to its true height.
function groupBody(rows, closed, bare = false) {
  return `<div class="prows${closed ? ' closed' : ''}${bare ? ' bare' : ''}">${rows.map((r) => r.html).join('')}</div>`;
}

// The list in groups (a project's, or a module's: core.topGroups), each under a header with its name and its chevron,
// which folds it, and on a project's, what the modules put there (＋ for a new conversation in it); and, while it's
// folded, how many of its rows wait on you, in the colour of a request when one of them is one (the more pressing). A
// header says only that: how many rows a group has is VoiceOver's to say, "Reviewers, folded, 2 wait on you, 3
// sessions".
function groupsHTML(groups, now) {
  return groups
    .map((p) => {
      const rows = p.rows.map(({ s, kind, held, waits }) => ({ s, kind, held, waits, html: rowHTML(s, kind, now) }));
      // A module's group with no name has no header, but its room, and never folds (the session leading a team, above
      // its team).
      if (p.name == null) return groupBody(rows, false, true);
      const closed = !!state.closedProjects[p.key];
      const yours = closed ? rows.filter((r) => waitsOnYou(r.kind) || r.waits) : [];
      const wait = yours.length ? `${yours.length} ${yours.length === 1 ? 'waits' : 'wait'} on you` : '';
      const needs = wait ? `<span class="pneeds${yours.some((r) => r.kind === 'needs') ? ' asks' : ''}">${wait}</span>`
        : '';
      const sessions = `${rows.length} ${rows.length === 1 ? 'session' : 'sessions'}`;
      const said = [p.name, closed ? 'folded' : '', wait, sessions].filter(Boolean).join(', ');
      const head = `<div class="project${closed ? ' collapsed' : ''}" data-key="${esc(p.key)}"`
        + `${p.project ? ` title="${esc(p.key)}"` : ''} aria-label="${esc(said)}">
            <span class="pname">${esc(p.name)}</span><span class="pchev">${CHEVRON_ICON}</span>${needs}
            ${p.project ? slot('project', p) : ''}
          </div>`;
      return head + groupBody(rows, closed);
    })
    .join('');
}

// Sets the clocks in what's drawn (data-since: how long a step has run; data-ago: how long ago; data-left: how long is
// left until then; data-until, over a time it counts down from, data-span: how much of it is left, as the kit's ring
// draws it, --left) to `now`, writing only those that changed: the list keeps its rows between rebuilds, and these are
// all of it that moves by itself.
function tickTimes(root, now) {
  for (const el of root.querySelectorAll('[data-since]')) {
    const text = elapsed(now - Number(el.dataset.since));
    if (el.textContent !== text) el.textContent = text;
  }
  for (const el of root.querySelectorAll('[data-ago]')) {
    const text = ago(now - Number(el.dataset.ago));
    if (el.textContent !== text) el.textContent = text;
  }
  for (const el of root.querySelectorAll('[data-left]')) {
    const text = minutesLeft(Math.max(0, Number(el.dataset.left) - now));
    if (el.textContent !== text) el.textContent = text;
  }
  for (const el of root.querySelectorAll('[data-until]')) {
    const span = Number(el.dataset.span), left = Math.max(0, Number(el.dataset.until) - now);
    const value = (span > 0 ? Math.min(1, left / span) : 0).toFixed(3);
    if (el.style.getPropertyValue('--left') !== value) el.style.setProperty('--left', value);
  }
}
