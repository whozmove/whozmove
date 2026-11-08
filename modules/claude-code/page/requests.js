// A Claude Code session's requests on its row: a tool waiting for your OK, and a plan waiting for your OK; and your
// answers, which go back through the permission hook (answerAsk). Its questions are questions.js's, and what shows once
// one is answered answered.js's; what each request is, and the words for it, request-words.js's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// By ask id: when the app was last told a request is being answered here (holdAsk); a request's lines shown in full
// (Show all); which of a big change's edits shows (‹ ›); and a plan's notes being written to send it back.
moduleState({ heldAt: {}, askOpen: {}, askChange: {}, sendBack: {} });

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
  if (ask.tool === 'ExitPlanMode') return planAskHTML(ask);
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

// A plan waiting for your OK: its title and its few lines at a glance (the plans module's), or else its first
// PLAN_STEPS_SHOWN steps (of its first list), drawn from its markdown as the reader draws it; then the way to the
// whole plan in the reader beside the list ("Read all 10 steps", or "Read the plan" for a short one or one at a
// glance), as a plan is more than its steps; then Send back… (a box for your notes, which go to Claude with the
// plan's No, as the reader sends them; with picks of yours on its card, the plan beside the list with that box open,
// as only it sends them) and Take me there, to its session, where it's approved (the panel approves one only for a
// session you allow to, May Approve Plans).
const PLAN_STEPS_SHOWN = 4;
function planAskHTML(ask) {
  state.shownAt[ask.id] ??= Date.now();
  // With picks of yours, the box isn't here: what's typed in it waits, says so, and goes with them beside the list.
  const { title, steps, lead } = planOf(ask), picked = core.plans?.picks(ask.id).changed;
  const notes = picked ? null : state.sendBack[ask.id];
  const waits = picked && (state.sendBack[ask.id]?.text || '').trim()
    ? '<p class="ask-say-waits">Your note waits with your picks beside the list.</p>' : '';
  // Its first list's steps only, where its numbers start again within those (decisions after its steps, say), so the
  // card never reads 1, 2, 3, 1.
  const again = steps.findIndex((s, k) => k > 0 && s.n <= steps[k - 1].n);
  const shown = steps.slice(0, again > 0 ? Math.min(again, PLAN_STEPS_SHOWN) : PLAN_STEPS_SHOWN)
    .map((s) => `<li value="${s.n}">${markdownHTML(s.text, 'list')}</li>`).join('');
  // A plan's few lines at a glance, where the plans module finds them, in place of its steps; by the request's id, so
  // they say how many picks you've changed.
  const glance = core.plans?.cardLines(ask.input?.plan || '', ask.id);
  const read = `<button class="button quiet small perm-read">${!glance && steps.length > PLAN_STEPS_SHOWN
    ? `Read all ${steps.length} steps` : 'Read the plan'}</button>`;
  const actions = (notes ? '' : '<button class="ask-send">Send back…</button>')
      + '<button class="button main perm-go">Take me there</button>';
  const box = notes ? `<div class="ask-say"><input class="field small q-type ask-say-box" `
    + `placeholder="What should change?" value="${esc((notes.text || '').replace(/\s*\n\s*/g, ' '))}">`
    + '<button class="button small ask-say-cancel">Cancel</button><button class="button small main ask-say-send"'
    + `${(notes.text || '').trim() ? '' : ' disabled'}>Send back</button></div>` : '';
  const what = glance || (shown ? `<ol class="ask-steps">${shown}</ol>`
    : lead.length ? `<div class="ask-lead-lines">${lead.map((l) => markdownHTML(l, 'list')).join('')}</div>` : '');
  return `<div class="perm plan-ask" data-ask="${esc(ask.id)}">${titleLine(esc(title))}${what}${read}`
    + `${box}${waits}<div class="perm-actions">${actions}</div></div>`;
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
  // With picks of yours on its card in the reader, Send back… opens the plan there with its box open, which takes your
  // words from here (core.planRowNotes): the box here would send your words alone.
  if (button.matches('.ask-send') && s && core.plans?.picks(id).changed) {
    return core.planNotes ? core.planNotes(s.sessionId) : openReader(s.sessionId, null, 'writings');
  }
  if (button.matches('.ask-send')) { state.sendBack[id] = { text: '' }; return render(); }
  if (button.matches('.ask-say-send')) return sendBack(id);
  if (button.matches('.ask-say-cancel')) { delete state.sendBack[id]; return render(); }
  if (button.matches('.perm-read') && s) return openReader(s.sessionId, null, 'writings');
  if (button.matches('.perm-go') && s) return openSession(s);
  if (button.matches('.perm-allow, .perm-deny')) answerRequest(id, button.matches('.perm-allow'));
}

// Deny or Allow once on a request.
function answerRequest(id, allow) {
  answered(id, allow ? 'allow' : 'deny');
  native({ type: 'answerAsk', id, allow });
  render();
}

// A plan sent back with your notes, as the reader sends it (writings.js): its No, with the notes as Claude's to read.
function sendBack(id) {
  const text = (state.sendBack[id]?.text || '').trim();
  // Never your words without your picks: they go from the plan beside the list.
  if (!text || state.answering[id] || core.plans?.picks(id).changed) return;
  answered(id, 'sentBack');
  native({ type: 'answerAsk', id, allow: false, message: text });
  delete state.sendBack[id];
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
// it here, the line saying so takes the card's place (answered.js).
core.rowCards.push({
  name: 'request', order: 10,
  wants: (row) => !!row.s.ask && !state.answering[row.s.ask.id],
  html: (row) => askHTML(row.s.ask, row.now, row.s.git?.root || row.s.cwd || ''),
});
// While a request or a question has the keyboard here (pressed, or its answer's box typed in, and not answered yet),
// it's being answered; the app holds it only while you're at the Mac, so one left that way still goes.
core.updates.push(() => {
  const card = heldCard() || document.activeElement?.closest?.('.perm[data-ask]');
  if (card?.matches('.perm[data-ask]')) holdAsk(card.dataset.ask);
});
core.presses.push(['.perm[data-ask]', pressRequest]);
// A request or a question takes the keyboard once pressed, but where the press answers it, so its keys answer it here
// rather than going to the app in front, where Claude's own copy of it waits; a plan's card has nothing to key.
core.keyCards.push({
  card: '.perm[data-ask]:not(.plan-ask):not(.legacy-ask)',
  id: (card) => card.dataset.ask,
  open: (card) => !state.answering[card.dataset.ask],
  takes: (card, target) => !pressAnswers(card, target),
  key: (card, e) => keyOnRequest(card, e),  // questions.js's, which loads after this
});
// A plan's notes are kept as they're typed, so the rebuild every second keeps them; Return sends them back.
core.typing.push(['.ask-say-box', (box) => {
  const id = box.closest('.perm').dataset.ask;
  holdAsk(id);
  state.sendBack[id] = { text: box.value };
  const send = box.parentElement.querySelector('.ask-say-send');
  if (send) send.disabled = !box.value.trim();
}]);
core.returns.push(['.ask-say-box', (box) => sendBack(box.closest('.perm').dataset.ask)]);
core.forgotten.keys.push('heldAt', 'askOpen', 'askChange', 'sendBack');

// What's typed in a plan's box on its row, taken by the reader's box for your notes, which sends it with your picks,
// and given back if the reader closes unsent (writings.js), after what the row has had typed in it since. Line breaks
// are kept for the reader's box; the row's box, a line, shows them as spaces.
core.planRowNotes = {
  take(id) {
    const text = state.sendBack[id]?.text || '';
    delete state.sendBack[id];
    return text;
  },
  keep(id, words) {
    const had = (state.sendBack[id]?.text || '').trim();
    state.sendBack[id] = { text: [had, words.trim()].filter(Boolean).join('\n\n') };
  },
};
