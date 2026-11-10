// A Claude Code session's requests on its row: a tool waiting for your OK, and a plan waiting for your OK, as its
// bubble; and your answers, which go back through the permission hook (answerAsk). Its questions are questions.js's,
// and what shows once one is answered answered.js's; what each request is, and the words for it, request-words.js's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// By ask id: when the app was last told a request is being answered here (holdAsk); a request's lines shown in full
// (Show all); and which of a big change's edits shows (‹ ›). By session: the plan its row's Plan bubble last ended in
// its own button for (planGo), so that button waits to be seen.
moduleState({ heldAt: {}, askOpen: {}, askChange: {}, planGo: {} });

// The marks beside a request's file, page, search or app, in the colour of the card's quiet words.
const ASK_ICON = {
  edit: '<path d="M8.6 2.4 10.6 4.4 4.6 10.4 2 11 2.6 8.4Z" fill="none" stroke="currentColor" stroke-width="1.3" '
    + 'stroke-linejoin="round"/>',
  file: '<path d="M3 1.5h4.5L10 4v7.5H3Z M7.5 1.5V4H10" fill="none" stroke="currentColor" stroke-width="1.2" '
    + 'stroke-linejoin="round"/>',
  search: '<circle cx="5.6" cy="5.6" r="3.6" fill="none" stroke="currentColor" stroke-width="1.3"/><path '
    + 'd="M8.3 8.3 11.2 11.2" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>',
  plug: '<path d="M4.5 1.5v3M8.5 1.5v3M3 4.5h7v2a3.5 3.5 0 0 1-7 0Z M6.5 10v2" fill="none" stroke="currentColor" '
    + 'stroke-width="1.2" stroke-linejoin="round" stroke-linecap="round"/>',
};
const askMark = (name) => `<svg class="ask-mark" width="13" height="13" viewBox="0 0 13 13" aria-hidden="true">`
  + `${ASK_ICON[name]}</svg>`;

// A tool waiting for an OK, from the permission hook (Claude shows its own prompt too; whichever is answered first
// counts), with Deny and Allow once, never "always". A click on a card that has only just appeared doesn't count
// (justShown): it may have taken the place of the one being answered, and it hasn't been seen yet. Once answered, a
// line saying so takes the card's place (answered.js) for as long as the request is listed.
//
// Each kind leads with what it's for (Claude's reason for a command, the file and how many lines change, what it asks
// of a page) and then what it would do, in full, since Allow once allows exactly that: the command, the change (the
// lines it takes out, −, and puts in, +), the file being written, any other tool's input field by field. Long text
// shows its first lines, then Show all. A request the panel got cut short (very long input) says so, and Allow once
// still allows all of it, as Claude's own prompt does. One that could do harm (outside the sandbox) is filled red.
function askHTML(ask, now = Date.now(), root = '') {
  if (ask.legacy) return legacyAskHTML(ask);
  if (ask.tool === 'AskUserQuestion') return quizHTML(ask, now);
  state.shownAt[ask.id] ??= Date.now();
  const kind = askKind(ask), i = ask.input || {}, goes = goesHTML(ask, now);
  const risk = kind === 'command' && i.dangerouslyDisableSandbox ? ' risk' : '';
  const body = {
    command: () => commandHTML(ask, goes),
    edit: () => askFileHTML(ask, 'edit', root, goes) + askCodeHTML(ask.id, editLines(editsOf(ask)), 6, '',
                                                                   plainLines(editsOf(ask))),
    bigEdit: () => bigEditHTML(ask, root, goes),
    write: () => askFileHTML(ask, 'file', root, goes) + askCodeHTML(ask.id, esc(i.content ?? ''), 4, '',
                                                                    String(i.content ?? '')),
    read: () => '',
    fetch: () => fetchHTML(ask, goes),
    search: () => '',
    mcp: () => mcpHTML(ask, goes),
  }[kind]?.() ?? otherHTML(ask, goes);
  const cut = ask.truncated ? '<div class="notice inline warn ask-cut">Claude sent more than the panel can show. '
    + 'Allow once allows all of it. '
    + '<button class="button quiet small perm-go">See it in the session</button></div>' : '';
  // Every card's answers sit in the one place, at its foot on the right, with nothing else beside them.
  const answers = `<div class="perm-actions"><button class="perm-deny">Deny</button><button class="perm-allow">`
    + `${esc(TOOL_WORDS[ask.tool]?.yes || 'Allow once')}</button></div>`;
  // A file read and a web search are the whole request in one line.
  if (kind === 'read') {
    return `<div class="perm ask-one-line" data-ask="${esc(ask.id)}"><div class="ask-line">${askMark('file')}`
      + `<span class="card-title">Read</span><span class="ask-obj">${atSlashes(i.file_path || '')}</span>${goes}</div>`
      + `${cut}${answers}</div>`;
  }
  if (kind === 'search') {
    return `<div class="perm" data-ask="${esc(ask.id)}">${titleLine('Search the web', goes)}<div class="ask-line">`
      + `${askMark('search')}<span class="ask-query">${esc(i.query || '')}</span></div>${answers}</div>`;
  }
  return `<div class="perm ask-${kind}${risk}" data-ask="${esc(ask.id)}">${body}${cut}${answers}</div>`;
}

// A title line: the title, wrapped to as many lines as it takes, as it may be what says what a request does (Claude's
// reason for a command), and what goes at its end (the ring of a request that goes by itself).
const titleLine = (title, end = '') => `<div class="ask-head"><span class="card-title">${title}</span>${end}</div>`;

// A command: Claude's reason for it as the title, what's risky about it as tags, then the command, wrapped, every line
// of it whole: what Allow once runs is never cut at the card's edge.
function commandHTML(ask, goes) {
  const i = ask.input || {};
  const tags = [i.dangerouslyDisableSandbox && '<span class="tag needs">Outside the sandbox</span>',
                i.run_in_background && '<span class="tag">Keeps running</span>'].filter(Boolean).join('');
  return titleLine(esc(i.description || 'Run a command?'), goes)
    + (tags ? `<div class="ask-tags">${tags}</div>` : '')
    + askCodeHTML(ask.id, esc(i.command ?? ''), 4, '', String(i.command ?? ''), true);
}

// A file's head: its mark, its name, and how many lines the change puts in and takes out (or, for a file written
// whole, how many it holds); under it, the folder it's in (inside the project), and what a notebook edit does to which
// cell.
function askFileHTML(ask, mark, root, goes) {
  const i = ask.input || {}, path = i.file_path || i.notebook_path || '';
  const n = mark === 'file' ? { add: lineCount(i.content), del: 0 } : changeCounts(editsOf(ask));
  const diff = `<span class="diff"><span class="add">+${n.add}</span>${mark === 'file' ? ''
    : ` <span class="del">−${n.del}</span>`}</span>`;
  const cell = ask.tool === 'NotebookEdit' ? `<div class="ask-cell">${esc(notebookWhat(i))}</div>` : '';
  return `<div class="ask-file">${askMark(mark)}<span class="ask-name">${esc(fileName(path))}</span>${diff}${goes}`
    + '</div>'
    + `<div class="ask-dir ask-under">${esc(folderIn(path, root))}</div>${cell}`;
}

// A change's lines, each marked: what it takes out (−), then what it puts in (+); edits apart by a gap.
const markedLines = (text, cls, mark) => String(text ?? '').split('\n')
  .map((l) => `<span class="${cls}">${mark} ${esc(l)}</span>`).join('\n');
const changeLines = (e) => (e.replace_all ? '(every occurrence)\n' : '')
  + (e.old_string ? markedLines(e.old_string, 'ln-del', '−') + '\n' : '') + markedLines(e.new_string, 'ln-add', '+');
const editLines = (edits) => edits.map(changeLines).join('\n<span class="ask-gap">⋯</span>\n');
// The same as text, as the card shows it, for the rule that says whether it's all in view.
const plainLines = (edits) => edits.map((e) => (e.replace_all ? '(every occurrence)\n' : '')
  + (e.old_string ? String(e.old_string).split('\n').map((l) => `− ${l}`).join('\n') + '\n' : '')
  + String(e.new_string ?? '').split('\n').map((l) => `+ ${l}`).join('\n')).join('\n⋯\n');

// What a request would do, its first `cap` lines, each on one line, fading where the card cuts it; and Show all
// wherever any of it is out of view (more lines than that, or a line longer than the card shows: showAllNeeded), which
// shows the whole of it, wrapped, with a scroll of its own past a few lines (kept by ask id and the part it's for,
// `part`: '' for the request's own lines, else a tool's field, so a rebuild of the list keeps it open). `text` is the
// lines as HTML, `plain` the same as text, which the rule counts by. `wrapped` (a command) wraps its lines rather than
// cutting them at the card's edge, and its first `cap` lines show whole, so only more lines than that need Show all.
function askCodeHTML(id, text, cap, part = '', plain = text, wrapped = false) {
  const html = text.replace(/\n$/, '');  // a last line ended by its line break is one line, not two
  if (!html) return '';
  const lines = html.split('\n'), open = !!state.askOpen[id]?.[part];
  const more = wrapped ? lines.length > cap : showAllNeeded(plain, cap);
  const cls = more && !open && !wrapped ? ` cut${lines.length > cap ? ' capped' : ''}` : '';
  const shown = more && !open && wrapped ? lines.slice(0, cap).join('\n') : html;
  const button = more ? `<button class="button quiet small ask-more" data-part="${esc(part)}">${open ? 'Show less'
    : lines.length > cap ? `Show all ${lines.length} lines` : 'Show all'}</button>` : '';
  return `<pre class="perm-detail${cls}" style="--lines:${cap}">${shown}</pre>${button}`;
}

// ‹ › stepping through one of several (a big change's edits, several questions), the count between them saying where
// you are (`more`: anything it adds, as " · skipped"), each titled for what it steps to.
function stepperHTML(at, count, before, next, more = '') {
  return `<span class="ask-step"><button class="icon-button small ask-prev" title="${esc(before)}"`
    + `${at ? '' : ' disabled'}>‹</button><span class="ask-of">${at + 1} of ${count}${esc(more)}</span>`
    + `<button class="icon-button small ask-next" title="${esc(next)}"${at < count - 1 ? '' : ' disabled'}>›</button>`
    + '</span>';
}

// A big change: one edit at a time, wrapped, ‹ › stepping through them (kept by ask id), the count saying where you
// are, and over its answers, that Allow once allows every one of them, whichever shows.
function bigEditHTML(ask, root, goes) {
  const i = ask.input || {}, edits = editsOf(ask), at = Math.min(state.askChange[ask.id] || 0, edits.length - 1);
  const step = stepperHTML(at, edits.length, 'The change before', 'The next change');
  return `<div class="ask-file">${askMark('edit')}<span class="card-title">Edit ${esc(fileName(i.file_path))}?</span>`
    + `${step}${goes}</div><div class="ask-dir ask-under">${esc(folderIn(i.file_path, root))}</div>`
    + `<pre class="perm-detail">${changeLines(edits[at] || {})}</pre>`
    + `<div class="card-help ask-all">Allow once allows all ${edits.length} changes</div>`;
}

// An address or a path, escaped, that wraps at its slashes rather than within a word ("…/coupons", never "…/coupon s").
const atSlashes = (text) => esc(text).replace(/\/+/g, '$&<wbr>');

// A page: what Claude wants to learn from it leads, the address under it.
function fetchHTML(ask, goes) {
  const i = ask.input || {};
  const lead = i.prompt ? `<div class="ask-head"><span class="ask-lead">${esc(i.prompt)}</span>${goes}</div>`
    : titleLine(`Read a page on ${esc(urlHost(i.url) || 'the web')}?`, goes);
  return `${lead}<div class="ask-obj ask-url">${atSlashes(i.url || '')}</div>`;
}

// A tool's input, field by field: each field's name ("chart_code" as "Chart code") beside what it holds, a list of
// texts one to a line, anything else as JSON. Words to read (isProse: a description, say) are prose whatever their
// length, their markdown drawn. Fields of `long` characters or more go under the short ones: prose wrapped, its first
// PROSE_LINES lines fading where the card cuts it, with Show all for the whole (kept by ask id and field, as code's);
// anything else in the code's own lines, the first `cap` of them shown.
const PROSE_LINES = 4, PROSE_LINE = 52;  // a line's characters, about, at a card's width
function proseHTML(id, key, text) {
  const lines = text.split('\n').reduce((n, l) => n + Math.max(1, Math.ceil(l.length / PROSE_LINE)), 0);
  const more = lines > PROSE_LINES, open = !!state.askOpen[id]?.[key];
  return `<div class="ask-prose${more && !open ? ' capped' : ''}" style="--lines:${PROSE_LINES}">${markdownHTML(text, 'list')}`
    + '</div>' + (more ? `<button class="button quiet small ask-more" data-part="${esc(key)}">`
    + `${open ? 'Show less' : 'Show all'}</button>` : '');
}
const fieldLabel = (key) => {
  const words = key.replace(/_+/g, ' ').replace(/([a-z\d])([A-Z])/g, '$1 $2').trim().split(/\s+/)
    .map((w) => (/^[A-Z][a-z]/.test(w) ? w.toLowerCase() : w)).join(' ');  // "maxResults" too, but "URL" stays
  return words.charAt(0).toUpperCase() + words.slice(1);
};
const fieldText = (v) => (typeof v === 'string' ? v
  : Array.isArray(v) && v.length && v.every((x) => typeof x === 'string') ? v.join('\n')
  : v && typeof v === 'object' ? JSON.stringify(v, null, 2) : String(v));
function fieldsHTML(id, input, long = Infinity, cap = 2) {
  const fields = Object.entries(input).map(([key, v]) => [key, fieldText(v), isProse(key, v)]);
  const short = fields.filter(([, v]) => v.length < long && !v.includes('\n'));
  const rest = fields.filter((f) => !short.includes(f));
  return (short.length ? `<dl class="ask-fields">${short.map(([key, v, prose]) => `<dt>${esc(fieldLabel(key))}</dt>`
    + (prose ? `<dd class="prose">${mdInline(v)}</dd>` : `<dd>${esc(v)}</dd>`)).join('')}</dl>` : '')
    + rest.map(([key, v, prose]) => `<div class="ask-field">${esc(fieldLabel(key))}</div>`
      + (prose ? proseHTML(id, key, v) : askCodeHTML(id, esc(v), cap, key, v))).join('');
}

// A connected app's tool: the app, then what it does and to what (its title field, said there and not again), then
// its other fields.
function mcpHTML(ask, goes) {
  const { app, action } = mcpName(ask.tool), { ...fields } = ask.input || {};
  const titled = typeof fields.title === 'string' && fields.title;
  const what = titled ? `${action}: ${fields.title}` : action;
  if (titled) delete fields.title;
  return `<div class="card-head"><span class="ask-app">${askMark('plug')}${esc(app)}</span>`
    + '<span class="end">a connected app</span></div>' + titleLine(esc(what), goes)
    + fieldsHTML(ask.id, fields, 60);
}

// Any other tool: in plain words where the panel knows it, else by its name; then its fields.
function otherHTML(ask, goes) {
  const title = TOOL_WORDS[ask.tool]?.title || `Use ${ask.tool || 'a tool'}?`;
  return titleLine(esc(title), goes) + fieldsHTML(ask.id, ask.input || {}, 60, 3);
}

// A request from a session that started before Whozmove's update, whose hook still asks the old way, which the panel no
// longer answers, as anything running as you could answer it that way too: it's answered in Claude, and the session
// started again asks here as before. Take me there opens the session.
function legacyAskHTML(ask) {
  state.shownAt[ask.id] ??= Date.now();
  return `<div class="perm legacy-ask" data-ask="${esc(ask.id)}"><div class="card-title">Answer this in the session`
    + '</div><div class="perm-why">It started before Whozmove\'s update</div><div class="perm-actions">'
    + '<button class="button main perm-go">Take me there</button></div></div>';
}

// When a request goes by itself if no one answers it: a ring at its title's end, emptying as its time runs out, with
// the minutes left, which the list's tick sets as the time goes (data-until, over its whole wait: data-span; and
// data-left), and what it means when pointed at. None once it's answered here.
function goesHTML(ask, now) {
  const ring = state.answering[ask.id] ? null : goesRing(ask, now);
  if (!ring) return '';
  const until = esc(String(ask.expiresAt)), span = esc(String(goesSpan(ask)));
  return '<span class="ask-goes" title="Goes by itself if no one answers">'
    + `<span class="time-left" data-until="${until}" data-span="${span}" style="--left:${ring.left.toFixed(3)}">`
    + `${TIME_RING_ICON}</span><span data-left="${until}">${ring.words}</span></span>`;
}

// ---- Presses ----

// A request or a question on a row. A button that has only just appeared doesn't count yet. Reading the card
// (scrolling, selecting) doesn't open the conversation.
function pressRequest(card, e) {
  holdAsk(card.dataset.ask);
  const button = e.target.closest('button');
  if (button && justShown(card.dataset.ask)) return e.preventDefault();
  if (pressQuestion(card, e)) return;
  if (!button) return;
  e.preventDefault();
  const id = card.dataset.ask, s = state.last.sessions.find((x) => x.ask?.id === id);
  if (button.matches('.ask-more')) {
    const open = state.askOpen[id] || (state.askOpen[id] = {}), part = button.dataset.part;
    open[part] = !open[part];
    return render();
  }
  if (button.matches('.ask-prev, .ask-next')) {
    if (button.disabled) return;
    state.askChange[id] = Math.max(0, (state.askChange[id] || 0) + (button.matches('.ask-next') ? 1 : -1));
    return render();
  }
  if (button.matches('.perm-go') && s) return openSession(s);
  if (button.matches('.perm-allow, .perm-deny')) answerRequest(id, button.matches('.perm-allow'));
}

// Deny or Allow once on a request.
function answerRequest(id, allow) {
  answered(id, allow ? 'allow' : 'deny');
  native({ type: 'answerAsk', id, allow });
  render();
}

// A request being answered here (pressed, typed in, keyed, or held with the keyboard): the app keeps it from a session
// you allow to answer it for you, and for one that goes by itself tells its hook, which gives it at least another
// minute. Every 10s at most, as each tells it the same.
function holdAsk(id) {
  const ask = state.last.sessions.find((x) => x.ask?.id === id)?.ask;
  if (!ask || ask.legacy || state.answering[id] || Date.now() - (state.heldAt[id] || 0) < 10000) return;
  state.heldAt[id] = Date.now();
  native({ type: 'holdAsk', id });
}

// ---- What it plugs into ----

// Claude's line on a row while a request waits says what it wants (request-words.js), for the core's chat.
core.agent.askLine = askLine;

// The most pressing of a row's cards: while a request waits, it takes the place under the chat; once you've answered
// it here, the line saying so takes the card's place (answered.js). Never a plan's: a plan is its row's bubble alone
// (below), read and answered beside the list, so it has one shape wherever it shows.
core.rowCards.push({
  name: 'request', order: 10,
  wants: (row) => !!row.s.ask && row.s.ask.tool !== 'ExitPlanMode' && !state.answering[row.s.ask.id],
  html: (row) => askHTML(row.s.ask, row.now, row.s.git?.root || row.s.cwd || ''),
});
// The plan Claude still waits on in a session with no request for it up here, as a request stops asking here after an
// hour, or when Whozmove restarts: the session's newest plan, while its transcript lists no answer to it, and either
// Claude Code's own prompt for it is still up in the session (`held`: the registry says waiting) or the session is idle
// at its prompt with nothing typed into it since, when your notes can be typed in as a message (the app checks again,
// AnswerFor's WhyNotTypePlanNotes). { id, title, held } or null. A plain function.
function planLeft(s) {
  if (!s || s.ask) return null;
  const w = (s.writings || []).find((x) => x.kind === 'plan');
  if (w?.status !== 'waiting') return null;
  const held = s.status === 'waiting', idle = s.status === 'idle' || s.status === 'shell';
  if (!held && !(idle && !((s.lastPromptAt || 0) > (w.at || 0)))) return null;
  return { id: w.id, title: w.title || '', held };
}
// The plan Claude waits on in a session, as its row's bubble shows it: its request's, while one is up (from a session
// started before Whozmove's update too), else the one it still waits on with no request up here (planLeft).
// { key, title } or null. A plain function.
function planWaiting(s) {
  const ask = s?.ask;
  if (ask) {
    if (ask.tool !== 'ExitPlanMode') return null;
    const titled = /^\s*#+\s*\S/m.test(String(ask.input?.plan || ''));
    return { key: ask.id, title: titled ? planOf(ask).title : 'Waiting for your OK' };
  }
  const left = planLeft(s);
  return left ? { key: 'w:' + left.id, title: left.title || 'Waiting for your OK' } : null;
}
// A plan Claude waits on, on any row, as an ask: a bubble named "Plan", the plan's title, in your move's colour,
// ending in the button that opens it beside the list (the reader's answer to 'plan', askAct), else the way to its
// session. Only where no other module has something to say (rowNotesLast), so a team's own ask for it wins, and any
// other ask on the row keeps its line, the plan read from the row's tag; none once you've answered it here, when the
// line saying so takes its place.
core.rowNotesLast.push((row) => {
  const plan = planWaiting(row.s);
  if (!plan || state.answering[row.s.ask?.id]) return null;
  const sid = row.s.sessionId, name = row.s.name || base(row.s.cwd || ''), title = plan.title;
  if (state.planGo[sid] !== plan.key) {
    state.planGo[sid] = plan.key;
    state.shownAt['plan-go:' + sid] = Date.now();
  }
  return { html: askLineHTML(title, 0, '', '', `Plan: ${title}`, 'Plan'), cls: 'ask-note cplan', look: 'normal',
           act: { want: 'plan', html: askActHTML(OUT_ICON, name ? `Take Me There: ${name}` : 'Take Me There',
                                                 ` data-plan-go="${esc(sid)}"`) },
           line: true, quiet: false, tone: 'turn' };
});
// Its own button, where nothing opens the plan beside the list: to its session, once seen.
core.presses.push(['[data-plan-go]', (el, e) => {
  e.preventDefault();
  const sid = el.dataset.planGo, s = state.last.sessions.find((x) => x.sessionId === sid);
  if (s && !justShown('plan-go:' + sid)) openSession(s);
}]);
core.pointerTargets.push('[data-plan-go]');
// While a request or a question has the keyboard here (pressed, or its answer's box typed in, and not answered yet),
// it's being answered; the app holds it only while you're at the Mac, so one left that way still goes.
core.updates.push(() => {
  const card = heldCard() || document.activeElement?.closest?.('.perm[data-ask]');
  if (card?.matches('.perm[data-ask]')) holdAsk(card.dataset.ask);
});
core.presses.push(['.perm[data-ask]', pressRequest]);
// A request or a question takes the keyboard once pressed, but where the press answers it, so its keys answer it here
// rather than going to the app in front, where Claude's own copy of it waits.
core.keyCards.push({
  card: '.perm[data-ask]:not(.legacy-ask)',
  id: (card) => card.dataset.ask,
  open: (card) => !state.answering[card.dataset.ask],
  takes: (card, target) => !pressAnswers(card, target),
  key: (card, e) => keyOnRequest(card, e),  // questions.js's, which loads after this
});
core.forgotten.keys.push('heldAt', 'askOpen', 'askChange', 'planGo');
core.forgotten.prefixes.push('plan-go');

// The plan a session's agent waits for your OK on, in the panel's own words, for the module that shows it beside the
// list (the reader), and what it sends to answer it, so what Claude Code's request holds, and the messages that answer
// it, are this module's alone (core.planAsks). A plan cut short on its way to the panel (`truncated`) is drawn from
// the transcript's copy, so the digest isn't of what's shown, and it's approved in its tab; what the app already knows
// stands in Approve's way (`approveWhyNot`) comes after that.
core.planAsks.push({
  of(s) {
    const ask = s?.ask;
    if (ask?.tool !== 'ExitPlanMode') return null;
    return {
      id: ask.id, at: ask.at, text: String(ask.input?.plan ?? ''), path: ask.input?.planFilePath,
      whole: !ask.truncated, answerable: !ask.legacy, digest: ask.digest || '', approval: ask.approval || null,
      whyNot: ask.truncated ? 'it\'s too long for the panel to show whole, so approve it in its tab'
        : ask.approveWhyNot || '',
    };
  },
  // Your Approve of request `id` beside the list, as its row says it went (answeredFor, yours): 'pending' until its
  // transcript says 'approved', or 'notTaken'; null for anything else.
  yours(s, id) {
    const a = s?.answeredFor;
    return a?.yours && a.what === 'approved' && a.askId === id ? a.state || 'pending' : null;
  },
  // The plan Claude still waits on with no request for it up here (planLeft): { id (the writing's), held (its own
  // prompt is still up in the session, so only there can it be answered) }, or null.
  left(s) {
    const left = planLeft(s);
    return left && { id: left.id, held: left.held };
  },
  // Your notes on that plan, typed into its session as a message on your press (typePlanNotes: the app leads them with
  // Claude Code's words and checks again before each key), and how that went, as its row says it (answeredFor, yours):
  // { state (typing, typed or notTyped), why, way (the button past the terminal's reason, if any), at } or null.
  typeBack(s, id, words) { native({ type: 'typePlanNotes', sessionId: s.sessionId, planId: id, words }); },
  typed(s, id) {
    const a = s?.answeredFor;
    return a?.yours && a.what === 'sentBack' && a.askId === id
      ? { state: a.state || 'typing', why: a.why || '', way: a.way || '', at: a.at || 0 } : null;
  },
  // Your press on Approve, for the request and the digest of the text it was drawn with: the app checks them both
  // before it answers (approveShownPlan, never answerAsk, which can't approve a plan).
  approve(s, id, digest) { native({ type: 'approveShownPlan', sessionId: s.sessionId, id, digest }); },
  // Sent back with your notes, or stopped: Claude stays in plan mode with them, or stops.
  sendBack(s, id, message) { native({ type: 'answerAsk', id, allow: false, message }); },
  stop(s, id) { native({ type: 'answerAsk', id, allow: false, stop: true }); },
  // It's being answered beside the list, so no session you allow answers it for you meanwhile.
  hold(s, id) { native({ type: 'holdAsk', id }); },
});
