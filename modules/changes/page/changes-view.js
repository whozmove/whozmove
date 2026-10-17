// What a session changed: its numbers at the end of its row's details, their card, and the changes view, beside the
// list in the reader's place (reader.js, its "changes" mode).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Pressing a row's numbers grows the panel as the reader does, and shows the files that session changed that aren't
// committed yet, as git status would, with the lines themselves as git shows them: only its own, in green and red
// (another's in the same file are left as the file has them). A switch shows all sessions' instead, each changed line's
// edge in the colour of whose it is; and pressing the island's commits stage shows what the commits not on GitHub yet
// changed. The lines come from the app (Changes.m) when the view opens and each time the session's numbers move, so it
// keeps up while the agent works, and lines that have just come in light up once. How the files are laid out (one
// after another, or one at a time) and how lines are (inline, or side by side) are yours to pick, and kept.

// Why what a session changed isn't known, where it would be shown.
const UNRECORDED = 'Claude Code didn\'t record what one of this session\'s shell commands changed (it records them in '
  + 'auto mode), so which lines this session changed isn\'t known.';

// Who's who, by colour: this session, another session, changed outside these sessions, short or repeated lines, and
// no one named (a session not known sees).
const WHO_COLOURS = { me: '#4aa8ff', other: '#b69cff', outside: '#ffc53d', short: 'rgba(255, 255, 255, 0.2)',
                      none: 'rgba(255, 255, 255, 0.28)' };
const whoColour = (who, sid) => WHO_COLOURS[who === sid ? 'me' : who in WHO_COLOURS ? who : 'other'];

// The editors a file can open in, and the one chosen (Editors.m), sent when the page loads and when it changes; the
// views of each session's changes that came in, kept for a few sessions, newest last, so a view opens at once on one
// asked for ahead; and what was last asked for, by session and scope (prefetchChanges).
moduleState({ editors: { apps: [] }, changesReady: new Map(), changesAsked: {} });
window.setEditors = (editors) => {
  state.editors = editors || { apps: [] };
  if (state.reading?.mode === 'changes') redrawChanges();
};

// What the view keeps while it's open: which changes it shows (the session's own not committed yet, all sessions', or
// the commits not on GitHub yet), the views the app sent of each, the file lit, how files and lines are laid out, and
// the lines already seen.
function changesState(r) {
  return r.changes ??= { scope: r.scope || 'session', views: {}, path: null, layout: store.get('changesLayout', 'all'),
                         split: store.get('changesSplit', false), seen: null };
}

// What the session itself changed, committed or not, "+26 −13", at the end of the details line. Pointed at, it shows how
// that sits in the whole branch (changesCardHTML), with what the work has been through (the proof the line shows
// otherwise); pressed, the changes themselves, beside the list. It shows as pressed while they're open.
function countsHTML(s, kind) {
  const c = s.changes;
  if (!c || !(c.added || c.removed)) return '';
  const proof = workProof(s, kind)?.text;
  const r = state.reading;
  const on = r?.mode === 'changes' && r.sessionId === s.sessionId && !r.closing ? ' on' : '';
  // While what the session changed isn't known, they're the branch's, and look it.
  const branch = c.known === false ? ' branch' : '';
  return `<span class="end"><span class="counts${on}${branch}" data-changes="${esc(s.sessionId)}"`
    + `${proof ? ` data-proof="${esc(proof)}"` : ''}><span class="add">+${thousands(c.added)}</span> `
    + `<span class="del">−${thousands(c.removed)}</span></span></span>`;
}

// A press on a row's numbers: the session's own changes, in the changes view, which opens for them, or turns to them
// from its other tabs (all sessions', the commits); pressed again on them, it closes. The island's commits stage opens
// the view on the commits not on GitHub yet the same way (its scope "commits"), opened on them from the start, so
// they're drawn once, a screenful first, as the panel opens.
function pressCounts(sid) {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  toggleReader(sid, null, 'changes', s?.changes?.known === false ? 'branch' : 'session');
}

// Pressed again on its session, the view turns to the changes pressed for (`scope`), or, showing them already, closes.
function turnChanges(r, scope) {
  const c = changesState(r);
  if (!scope || c.scope === scope) return false;
  c.scope = scope;
  c.path = null;
  redrawChanges();
  return true;
}

// The app's view of a session's changes: {scope, v, files} (Changes.m's viewOf:scope:), or {missing}.
window.showChanges = (sid, scope, view) => {
  // Kept for when the view opens on it, as it may have been asked for ahead (prefetchChanges), with what was asked for.
  const key = sid + ' ' + scope;
  if (view && !view.missing) keepChanges(key, state.changesAsked[key], view);
  const r = state.reading;
  if (!r || r.mode !== 'changes' || r.sessionId !== sid) return;
  const c = changesState(r);
  // Its changes not known (the view is asked for again when that changes): no one is named in it.
  const s = readerSession();
  c.views[scope] = view && !view.missing && s?.changes?.known === false ? blindView(view) : view;
  if (c.scope === scope) redrawChanges();
};

// ---- Drawing ----

// From the newest rows, each second: the head and the list of files as they are, and the changes asked for again
// once the session's numbers have moved. The changes themselves are drawn only when a new view comes in.
// `drawing`: called by redrawChanges, which draws the files itself once this returns.
function drawChanges(drawing = false) {
  const r = state.reading, s = readerSession(), c = changesState(r);
  // What a session changed isn't known while a shell command of its ran unrecorded: only all sessions' is shown.
  if (s.changes?.known === false && c.scope === 'session') { c.scope = 'branch'; c.path = null; }
  const want = changesWanted(s, c.scope);
  if (c.asked !== want) {
    c.asked = want;
    // Asked for ahead and come in already: drawn now, so the panel opens on it at once.
    const ready = state.changesReady.get(s.sessionId + ' ' + c.scope);
    if (ready?.want === want) {
      c.views[c.scope] = s.changes?.known === false ? blindView(ready.view) : ready.view;
      if (!drawing) { redrawChanges(); return; }
    } else {
      askChanges(s.sessionId, c.scope, want);
    }
  }
  let changed = putHTML(reader.querySelector('.r-head'), changesHeadHTML(s));
  changed = putHTML(reader.querySelector('.r-src'), changesBarHTML(s, c)) || changed;
  changed = putHTML(reader.querySelector('.r-shelf'), changesShelfHTML(s, c)) || changed;
  if (changed) { fitReader(); syncHover(); }
}

// The view drawn again: the head and list, then the files, keeping where it was scrolled to.
function redrawChanges() {
  const r = state.reading, s = readerSession();
  if (!r || r.mode !== 'changes' || !s) return;
  const c = changesState(r);
  // The list first, as it settles which file is lit (the one shown, one at a time), which may have changed with the view.
  reader.querySelector('.r-shelf').dataset.drawn = '';
  drawChanges(true);
  const view = c.views[c.scope];
  const body = reader.querySelector('.r-body'), top = body.scrollTop;
  const parts = view ? changesBodyParts(s, c, view) : [{ html: '<div class="r-missing">Opening…</div>' }];
  // Drawn for the first time, a long view is drawn a screenful first: once it fills the panel as tall as it can be,
  // the panel can open around it, and the files below it follow a few at a time, frame by frame, so the page keeps
  // answering the pointer meanwhile. Drawn again (the agent at work), it's drawn whole, so where it's scrolled to stays.
  const first = !r.ready || c.drawnScope !== c.scope;
  const token = c.drawn = (c.drawn || 0) + 1;
  body.innerHTML = '<div class="c-blocks"></div>';
  const files = body.firstElementChild, head = reader.querySelector('.r-head').offsetHeight;
  // Adds the next parts, up to about `lines` lines (at least one part); how many were added.
  let shown = 0;
  const add = (lines) => {
    let html = '', count = 0;
    while (shown < parts.length && (html === '' || count + (parts[shown].lines || 0) <= lines)) {
      count += parts[shown].lines || 0;
      html += parts[shown++].html;
    }
    files.insertAdjacentHTML('beforeend', html);
  };
  if (!first || !view) add(Infinity);
  else {
    add(SCREENFUL);
    // Shorter than the panel can be, the panel's size waits on the rest.
    while (shown < parts.length && body.scrollHeight + head + 60 < state.panelMax) add(SCREENFUL);
  }
  body.scrollTop = top;
  r.ready = !!view;
  c.drawnScope = view ? c.scope : null;
  fitReader();
  syncHover();
  // A file picked in the list before its turn: the rest is drawn at once, so it's there to go to.
  // Still the view being drawn: not drawn again since, nor the reader turned to another session or mode.
  const current = () => c.drawn === token && state.reading === r && r.changes === c;
  c.finish = () => { if (current() && shown < parts.length) add(Infinity); };
  const more = () => {
    if (!current() || shown >= parts.length) return;
    add(SCREENFUL);
    syncHover();
    requestAnimationFrame(more);
  };
  if (shown < parts.length) requestAnimationFrame(more);
}

// About as many lines as the panel shows at its tallest: what's drawn before it opens, and in each frame after.
const SCREENFUL = 120;

// What a view of a session's changes is asked for at: its scope, the session's count's version and its commits
// waiting, so a change in any asks again.
const changesWanted = (s, scope) => `${scope}@${s.changes?.v ?? 0}@${unpushedCommits(s.checkout)}`;

function keepChanges(key, want, view) {
  state.changesReady.delete(key);
  state.changesReady.set(key, { want, view });
  while (state.changesReady.size > 6) state.changesReady.delete(state.changesReady.keys().next().value);
}

function askChanges(sid, scope, want) {
  state.changesAsked[sid + ' ' + scope] = want;
  native({ type: 'readChanges', sessionId: sid, scope });
}

// Pointing at a row's numbers, or at its island's commits stage, asks for what pressing it would open, so that by the
// press it's there. Asked once for each version.
function prefetchChanges(sid, scope) {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s) return;
  if (scope === 'session' && s.changes?.known === false) scope = 'branch';
  const key = sid + ' ' + scope, want = changesWanted(s, scope);
  if (state.changesAsked[key] === want || state.changesReady.get(key)?.want === want) return;
  askChanges(sid, scope, want);
}

// The head: the session's name, how many files it changed, and ✕. Only ✕ takes a press there: the rest of the head
// is the panel's handle for dragging it (PanelWindow's readerStrip), so the switches are in a bar under it.
function changesHeadHTML(s) {
  const files = s.changes?.files?.length || 0, commits = unpushedCommits(s.checkout);
  const sub = state.reading?.changes?.scope === 'commits'
    ? `${thousands(commits)} ${commits === 1 ? 'commit' : 'commits'} not on GitHub yet`
    : s.changes?.known === false ? 'What this session changed isn\'t known'
    : `${files} ${files === 1 ? 'file' : 'files'} with changes to commit in this session`;
  return `<span class="r-title">${esc(s.name || base(s.cwd))}</span>
    <span class="r-sub">${sub}</span>
    <button class="r-close" title="Close">${CLOSE_ICON}</button>`;
}

// The bar under the head: whose changes are shown (this session's or all sessions', not committed yet), and how files
// and lines are laid out. The commits not on GitHub yet have no switch here: they open from the island's commits stage.
function changesBarHTML(s, c) {
  const mine = s.changes || { added: 0, removed: 0 }, { total } = branchParts(s, state.last.sessions);
  const nums = (a, d) => `<span class="c-nums"><span class="add">+${thousands(a)}</span>`
    + `<span class="del">−${thousands(d)}</span></span>`;
  const pressed = (on) => on ? ' aria-pressed="true"' : '';
  const pick = (attr, value, label, on) => `<button class="c-opt" data-${attr}="${value}"${pressed(on)}>${label}</button>`;
  // Not known: the switch to this session's own is off, saying why where it would be.
  const own = mine.known === false
    ? `<button class="c-scope" data-scope="session" disabled title="${esc(UNRECORDED)}">This session</button>`
    : `<button class="c-scope" data-scope="session"${pressed(c.scope === 'session')}>This session ${
        nums(mine.added, mine.removed)}</button>`;
  return `<span class="c-switch c-scopes">
      ${own}
      <button class="c-scope" data-scope="branch"${pressed(c.scope === 'branch')}>All sessions ${
        nums(total.added, total.removed)}</button>
    </span><span class="c-grow"></span>
    <span class="c-switch">${pick('layout', 'all', 'All files', c.layout === 'all')}${
      pick('layout', 'one', 'One at a time', c.layout === 'one')}</span>
    <span class="c-switch">${pick('split', '0', 'Inline', !c.split)}${pick('split', '1', 'Side by side', c.split)}</span>`;
}

// The files down the side, grouped (changeGroups), the one shown lit.
function changesShelfHTML(s, c) {
  const view = c.views[c.scope];
  if (!view) return '';
  if (view.missing) return `<div class="r-missing">${esc(view.missing)}</div>`;
  const groups = changeGroups(view, s.sessionId, state.last.sessions);
  if (!groups.length) return `<div class="r-missing">${emptyWords(c)}</div>`;
  const rowFiles = Object.fromEntries((s.changes?.files || []).map((f) => [f.path, f]));
  const files = groups.flatMap((g) => g[2]);
  if (!files.some((f) => f.path === c.path)) c.path = files[0].path;
  return groups.map(([label, who, list]) => {
    const swatch = who ? `<span class="c-swatch" style="background:${whoColour(who, s.sessionId)}"></span>` : '';
    return `<div class="r-group">${swatch}${esc(label)}<span class="c-count">${list.length}</span></div>` + list.map((f) => {
      const [a, d] = fileCount(f, s.sessionId, c.scope);
      const mark = f.status === 'new' ? ['new', 'A'] : f.status === 'gone' ? ['gone', 'D'] : ['changed', 'M'];
      const dir = f.path.includes('/') ? f.path.slice(0, f.path.lastIndexOf('/')) : '';
      return `<button class="r-item c-file${f.path === c.path ? ' on' : ''}" data-path="${esc(f.path)}" title="${esc(f.path)}">
          <span class="c-mark ${mark[0]}">${mark[1]}</span>
          <span class="r-name">${esc(base(f.path))}${dir ? `<span class="c-dir">${esc(dir)}</span>` : ''}</span>
          <span class="c-nums"><span class="add">+${a}</span><span class="del">−${d}</span></span>
          <span class="r-meta">${esc(fileLine(f, s.sessionId, c.scope, state.last.sessions, rowFiles[f.path],
                                              state.last.now, f.complete !== false))}</span>
        </button>`;
    }).join('');
  }).join('');
}

// What an empty view says, as git status would: nothing to commit, or no commits waiting to go to GitHub.
const emptyWords = (c) => c.scope === 'commits' ? 'No commits waiting.' : 'No changes to commit.';

// The files' changes: every file one after another, or the one picked. Lines that weren't in the last view of this
// session's changes light up once: what the agent has just written.
// The view's files' HTML, one part each with its count of lines ({html, lines}), or a part saying why there are none.
function changesBodyParts(s, c, view) {
  if (view.missing) return [{ html: `<div class="r-missing">${esc(view.missing)}</div>` }];
  const ordered = changeGroups(view, s.sessionId, state.last.sessions).flatMap((g) => g[2]);
  if (!ordered.length) return [{ html: `<div class="r-missing">${emptyWords(c)}</div>` }];
  const seen = new Set();
  for (const f of ordered) {
    for (const h of f.hunks || []) for (const l of h.lines) if (l[0] === '+') seen.add(f.path + '\n' + l[1]);
  }
  const before = c.seenScope === c.scope ? c.seen : null;
  const fresh = before ? (f, l) => l[0] === '+' && !before.has(f.path + '\n' + l[1]) : () => false;
  c.seen = seen;
  c.seenScope = c.scope;
  const shown = c.layout === 'one' ? ordered.filter((f) => f.path === c.path) : ordered;
  return (shown.length ? shown : ordered.slice(0, 1)).map((f) => ({
    html: fileHTML(s, c, f, fresh), lines: (f.hunks || []).reduce((n, h) => n + h.lines.length + 1, 1) }));
}

function fileHTML(s, c, f, fresh) {
  const sid = s.sessionId, [a, d] = fileCount(f, sid, c.scope);
  const slash = f.path.lastIndexOf('/');
  const complete = f.complete !== false;
  const others = Object.keys(f.counts || {}).filter((w) => w !== sid && w !== 'short' && (complete || w !== 'outside'));
  const chips = [f.status === 'new' && '<span class="c-chip new">New</span>',
                 f.status === 'gone' && '<span class="c-chip gone">Deleted</span>',
                 c.scope !== 'commits' && f.saved && '<span class="c-chip">Staged</span>',
                 c.scope === 'session' && others.length && `<span class="c-chip shared">${esc(alsoChanged(others, sid))}</span>`]
    .filter(Boolean).join('');
  const editor = state.editors.apps.find((e) => e.id === state.editors.choice);
  const open = f.status === 'gone' ? '' : `<span class="c-edwrap"><button class="c-open" data-path="${esc(f.path)}">`
    + `${editor ? 'Open in ' + esc(editor.name) : 'Open in Editor'}</button>`
    + `${c.picking === f.path ? pickerHTML(f) : ''}</span>`;
  let body;
  if (f.binary) body = '<div class="c-aside">A file that isn\'t text: its changes can\'t be shown here.</div>';
  else if (f.cut) body = '<div class="c-aside">Too many changes to show them all here. Open the file to see it.</div>';
  else {
    const cols = c.split ? 7 : 5;
    let rows = '';
    // A session's own view comes with only its own changes (OwnHunks in the app).
    const hunks = f.hunks || [];
    hunks.forEach((h, i) => {
      const gap = linesBetween(hunks[i - 1], h);
      const words = `${gap} ${gap === 1 ? 'line' : 'lines'}`;
      if (gap) rows += `<tr class="c-gap"><td colspan="${cols}"><b>${words}</b> unchanged</td></tr>`;
      rows += c.split ? splitHTML(s, c, f, h, fresh) : inlineHTML(s, c, f, h, fresh);
    });
    body = `<table class="c-lines${c.split ? ' split' : ''}">${rows}</table>`;
  }
  return `<section class="c-block" data-block="${esc(f.path)}"><div class="c-fhead">
      <span class="c-path">${slash > 0 ? `<i>${esc(f.path.slice(0, slash + 1))}</i>` : ''}${esc(f.path.slice(slash + 1))}</span>
      <span class="c-nums"><span class="add">+${thousands(a)}</span><span class="del">−${thousands(d)}</span></span>${chips}
      <span class="c-grow"></span>${open}</div>${body}</section>`;
}

// The chip on a file someone else changed too, in its session's own view: "Also changed by Retry tests, outside these
// sessions".
function alsoChanged(others, sid) {
  const names = others.filter((w) => w !== 'outside').map((w) => whoName(w, sid, state.last.sessions));
  const ways = [names.length && `by ${names.join(', ')}`, others.includes('outside') && 'outside these sessions']
    .filter(Boolean);
  return `Also changed ${ways.join(', ')}`;
}

// The lines as git shows them, with nothing between them: whose each changed line is shows only in the thin stripe
// down its edge, in that one's colour.
function inlineHTML(s, c, f, h, fresh) {
  const sid = s.sessionId;
  let old = h.oldStart, now = h.newStart, rows = '';
  for (const line of h.lines) {
    const [sign, text, who] = line;
    const cls = sign === ' ' ? '' : sign === '+' ? 'add' : 'del';
    const stripe = sign === ' ' ? '' : ` style="--who:${whoColour(who, sid)}"`;
    rows += `<tr class="${cls}${fresh(f, line) ? ' live' : ''}"><td class="c-who"${stripe}></td>`
      + `<td class="c-ln">${sign === '+' ? '' : old}</td><td class="c-ln">${sign === '-' ? '' : now}</td>`
      + `<td class="c-sg">${sign === ' ' ? '' : sign === '-' ? '−' : '+'}</td><td class="c-code">${codeHTML(text, f.path)}</td></tr>`;
    if (sign !== '+') old++;
    if (sign !== '-') now++;
  }
  return rows;
}

function splitHTML(s, c, f, h, fresh) {
  const sid = s.sessionId;
  const side = (half, mid) => {
    if (!half) return `<td class="c-ln blank${mid}"></td><td class="c-sg blank"></td><td class="c-code blank"></td>`;
    const [sign, text] = half.line;
    const cls = sign === ' ' ? '' : sign === '+' ? 'add' : 'del';
    const mark = sign === ' ' ? '' : sign === '-' ? '−' : '+';
    return `<td class="c-ln ${cls}${mid}">${half.at}</td><td class="c-sg ${cls}">${mark}</td>`
      + `<td class="c-code ${cls}${fresh(f, half.line) ? ' live' : ''}">${codeHTML(text, f.path)}</td>`;
  };
  let rows = '';
  for (const [left, right] of splitRows(h)) {
    const changed = [left, right].find((x) => x && x.line[0] !== ' ');
    const who = changed?.line[2];
    const stripe = changed ? ` style="--who:${whoColour(who, sid)}"` : '';
    rows += `<tr><td class="c-who"${stripe}></td>${side(left, '')}${side(right, ' mid')}</tr>`;
  }
  return rows;
}

// A little colour for code, the same for every language: comments, and text in quotes. Prose (Markdown, plain text)
// stays as it is: its apostrophes aren't quotes, and a heading isn't a comment.
const PROSE = /\.(md|markdown|mdx|txt|rst|adoc)$/i;
function codeHTML(text, path = '') {
  if (PROSE.test(path)) return esc(text);
  const comment = /^(\s*)(\/\/|#|--|\/\*|\*|<!--)/.exec(text);
  if (comment) return `${esc(comment[1])}<span class="c-cm">${esc(text.slice(comment[1].length))}</span>`;
  return text.split(/("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/).map((part, i) =>
    i % 2 ? `<span class="c-str">${esc(part)}</span>` : esc(part)).join('');
}

// The first "Open in Editor" asks which editor, once; the pawn menu's Open With changes it later.
function pickerHTML(f) {
  const apps = state.editors.apps || [];
  return `<div class="c-picker"><div class="c-pq">${apps.length ? 'Open files with' : 'No editor found on this Mac.'}</div>`
    + apps.map((e) => `<button class="c-app" data-editor="${esc(e.id)}" data-path="${esc(f.path)}">`
      + `${esc(e.name)}</button>`).join('')
    + `<div class="c-later">Kept for next time. Change it in the pawn menu, Open With.</div></div>`;
}

// ---- Presses ----

function changesFile(path) {
  const c = state.reading?.changes, view = c?.views[c.scope];
  return view?.files?.find((f) => f.path === path);
}

function openInEditor(path, editor) {
  const r = state.reading, f = changesFile(path);
  if (!f) return;
  native({ type: 'openFile', sessionId: r.sessionId, path, line: firstChangedLine(f, r.sessionId, r.changes.scope),
           ...(editor ? { editor } : {}) });
}

// In one scroll, the file at the top of the view is the one lit in the list; a file picked there is scrolled to.
function showFile(path) {
  const c = state.reading.changes;
  c.path = path;
  c.picking = null;
  if (c.layout === 'one') { redrawChanges(); reader.querySelector('.r-body').scrollTop = 0; return; }
  for (const el of reader.querySelectorAll('.c-file')) el.classList.toggle('on', el.dataset.path === path);
  const find = () => [...reader.querySelectorAll('.c-block')].find((b) => b.dataset.block === path);
  let block = find();
  if (!block && c.finish) { c.finish(); block = find(); }
  if (block) reader.querySelector('.r-body').scrollTo({ top: block.offsetTop, behavior: calm.matches ? 'auto' : 'smooth' });
}

reader.addEventListener('scroll', (e) => {
  const c = state.reading?.mode === 'changes' && state.reading.changes;
  if (!c || c.layout !== 'all' || !e.target.classList?.contains('r-body')) return;
  const top = e.target.getBoundingClientRect().top + 8;
  let current = null;
  for (const b of e.target.querySelectorAll('.c-block')) if (b.getBoundingClientRect().top <= top) current = b.dataset.block;
  current ??= e.target.querySelector('.c-block')?.dataset.block;
  if (!current || current === c.path) return;
  c.path = current;
  for (const el of reader.querySelectorAll('.c-file')) el.classList.toggle('on', el.dataset.path === current);
}, true);

core.readerPresses.push(
  ['.c-file[data-path]', (b) => showFile(b.dataset.path)],
  ['.c-scope[data-scope]', (b) => {
    const c = state.reading.changes;
    if (c.scope === b.dataset.scope || b.disabled) return;
    c.scope = b.dataset.scope;
    c.path = null;
    redrawChanges();
  }],
  ['.c-opt[data-layout]', (b) => {
    const c = state.reading.changes;
    c.layout = b.dataset.layout;
    store.set('changesLayout', c.layout);
    redrawChanges();
    if (c.layout === 'all' && c.path) showFile(c.path);
  }],
  ['.c-opt[data-split]', (b) => {
    const c = state.reading.changes;
    c.split = b.dataset.split === '1';
    store.set('changesSplit', c.split);
    redrawChanges();
  }],
  ['.c-app[data-editor]', (b) => {
    state.reading.changes.picking = null;
    openInEditor(b.dataset.path, b.dataset.editor);
    redrawChanges();
  }],
  ['.c-open[data-path]', (b) => {
    const c = state.reading.changes;
    if (state.editors.choice) return openInEditor(b.dataset.path);
    c.picking = c.picking === b.dataset.path ? null : b.dataset.path;
    redrawChanges();
  }],
);

// ---- The card ----

// What a row's numbers say when pointed at (core.cards): this session's own changes not committed yet, large; their share
// of all that isn't committed in the checkout, as one bar with this session's part lit; who made the rest; the whole's
// total; and what the work has been through.
function changesCardHTML(s, proof) {
  if (s.changes.known === false) {
    return `<div class="cc-big"><b class="add">+${thousands(s.changes.added)}</b><b class="del">−${
        thousands(s.changes.removed)}</b><span>not committed, all sessions</span></div>
      <div class="cc-lede">${esc(UNRECORDED)}</div>
      ${proof ? `<div class="cc-proof">${esc(proof)}</div>` : ''}<div class="cc-hint">Press to see the changes.</div>`;
  }
  const { parts, total, share } = branchParts(s, state.last.sessions), size = total.added + total.removed;
  const mine = s.changes, files = mine.files?.length || 0;
  const bar = parts.map((p) => `<i style="width:${size ? (100 * (p.added + p.removed) / size).toFixed(2) : 0}%;`
    + `background:${whoColour(p.who, s.sessionId)}"></i>`).join('');
  const legend = parts.map((p) => {
    const more = p.who === s.sessionId ? ` · ${files} ${files === 1 ? 'file' : 'files'}` : '';
    return `<span class="cc-sw" style="background:${whoColour(p.who, s.sessionId)}"></span>`
      + `<span class="cc-name${p.who === s.sessionId ? ' me' : ''}">${esc(p.name)}<small>${more}</small></span>`
      + `<span class="cc-v">+${thousands(p.added)} −${thousands(p.removed)}</span>`;
  }).join('');
  return `<div class="cc-big"><b class="add">+${thousands(mine.added)}</b><b class="del">−${thousands(mine.removed)}</b>
      <span>this session, not committed</span></div>
    <div class="cc-lede">${share}% of what isn't committed in this checkout</div>
    <div class="cc-bar">${bar}</div><div class="cc-legend">${legend}</div>
    <div class="cc-total"><span>All sessions</span>
      <b>+${thousands(total.added)} −${thousands(total.removed)}</b></div>
    ${proof ? `<div class="cc-proof">${esc(proof)}</div>` : ''}<div class="cc-hint">Press to see the changes.</div>`;
}

// ---- What it plugs into ----

// The reader's mode: wide, as code needs the room. What it keeps on the reader (state.reading.changes) goes when the
// reader turns to another session or mode.
core.readerModes.changes = {
  draw: () => drawChanges(),
  wide: () => true,
  reset(r) { r.changes = null; },
  turn: turnChanges,
  cls: 'k-changes',
};

// The row's numbers, ending its details' first line; pressed, its changes. Pointed at, their card; and what pressing
// them would open is asked for now, so it's there by the press, as it is for the island's commits stage.
core.slots.end.push((row) => countsHTML(row.s, row.kind));
core.presses.push(['.counts[data-changes]', (counts, e) => { e.preventDefault(); pressCounts(counts.dataset.changes); }]);
core.pointerTargets.push('.counts[data-changes]');
core.swaps.push(':scope > .main > .where .counts');
core.cards.push({
  selector: '.counts[data-changes]',
  key: (counts) => (state.reading ? null : 'changes:' + counts.dataset.changes),
  html(counts) {
    const s = state.last.sessions.find((x) => x.sessionId === counts.dataset.changes);
    return s?.changes ? changesCardHTML(s, counts.dataset.proof) : '';
  },
});
core.pointerWatchers.push((el) => {
  const counts = el?.closest('.counts[data-changes]');
  if (counts) prefetchChanges(counts.dataset.changes, 'session');
  const commits = el?.closest('.seg[data-stage="commits"]');
  const sid = commits?.closest('.island')?.dataset.sid;
  if (sid && +commits.dataset.count > 0) prefetchChanges(sid, 'commits');
});
