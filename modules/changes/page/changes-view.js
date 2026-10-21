// What isn't committed in a row's checkout: its numbers at the end of the row's details, their card, and the changes
// view, beside the list in the reader's place (reader.js, its "changes" mode).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Pressing a row's numbers grows the panel as the reader does, and shows what isn't committed in its checkout as git
// shows it, in git status's own tabs: Changes (not staged yet, new files included), Staged, and Outgoing (the commits
// not on GitHub yet, one by one), each with its step: Commit (what's staged, or everything when nothing is), Push, or
// Publish for a branch never pushed. The lines come from the app (Changes.m) when the view opens and each time the
// numbers move, so it keeps up while the agent works, and lines that have just come in light up once. How the files
// are laid out (one after another, or one at a time) and how lines are (inline, or side by side) are yours to pick,
// and kept.

// The editors a file can open in, and the one chosen (Editors.m), sent when the page loads and when it changes; the
// views that came in, kept for a few sessions, newest last, so a view opens at once on one asked for ahead; and what
// was last asked for, by session and scope (prefetchChanges).
moduleState({ editors: { apps: [] }, changesReady: new Map(), changesAsked: {} });
window.setEditors = (editors) => {
  state.editors = editors || { apps: [] };
  if (state.reading?.mode === 'changes') redrawChanges();
};

// What the view keeps while it's open: which tab it shows, the views the app sent of each, the file lit (by its key,
// viewFiles'), how files and lines are laid out, and the lines already seen.
function changesState(r) {
  return r.changes ??= { scope: r.scope || 'unstaged', views: {}, key: null, layout: store.get('changesLayout', 'all'),
                         split: store.get('changesSplit', false), seen: null };
}

// The checkout's numbers, "+26 −13": everything not committed in it, as git counts it, at the end of the work line of
// the row that speaks for it (`owner`), before the steps. Pointed at, their card (changesCardHTML); pressed, the changes view. They
// show as pressed while it's open.
function countsHTML(s, owner) {
  const all = s.changes?.all;
  if (!owner || !all?.files) return '';
  const r = state.reading;
  const on = r?.mode === 'changes' && r.sessionId === s.sessionId && !r.closing ? ' on' : '';
  return `<span class="counts${on}" data-changes="${esc(s.sessionId)}">`
    + `<span class="add">+${thousands(all.added)}</span> `
    + `<span class="del">−${thousands(all.removed)}</span></span>`;
}

// A press on a row's numbers: the changes view, open on Changes, or turned to it from another tab; pressed again on
// it, it closes. It opens on it from the start, so it's drawn once, a screenful first, as the panel opens.
function pressCounts(sid) {
  toggleReader(sid, null, 'changes', 'unstaged');
}

// Pressed again on its session, the view turns to the tab pressed for (`scope`), or, showing it already, closes.
function turnChanges(r, scope) {
  const c = changesState(r);
  if (!scope || c.scope === scope) return false;
  c.scope = scope;
  c.key = null;
  redrawChanges();
  return true;
}

// The app's view of a checkout's changes for one tab (Changes.m's view:scope:done:), or {missing}, or {counting} while
// git hasn't finished counting them (it's asked again once the numbers come in).
window.showChanges = (sid, scope, view) => {
  // Kept for when the view opens on it, as it may have been asked for ahead (prefetchChanges), with what was asked for.
  const key = sid + ' ' + scope;
  if (view && !view.missing && !view.counting) keepChanges(key, state.changesAsked[key], view);
  const r = state.reading;
  if (!r || r.mode !== 'changes' || r.sessionId !== sid) return;
  const c = changesState(r);
  c.views[scope] = view;
  if (c.scope === scope) redrawChanges();
};

// ---- Drawing ----

// From the newest rows, each second: the head, the bar and the list of files as they are, and the tab asked for again
// once the numbers have moved. The changes themselves are drawn only when a new view comes in.
// `drawing`: called by redrawChanges, which draws the files itself once this returns.
function drawChanges(drawing = false) {
  const r = state.reading, s = readerSession(), c = changesState(r);
  const want = changesWanted(s, c.scope);
  // While git is still counting, asked again every few seconds too: a count that ends with too much to count gives the
  // row no numbers, so nothing else would move `want`.
  if (c.asked !== want || (c.views[c.scope]?.counting && Date.now() - c.askedAt > COUNTING_AGAIN_MS)) {
    c.asked = want;
    c.askedAt = Date.now();
    // Asked for ahead and come in already: drawn now, so the panel opens on it at once.
    const ready = state.changesReady.get(s.sessionId + ' ' + c.scope);
    if (ready?.want === want) {
      c.views[c.scope] = ready.view;
      if (!drawing) { redrawChanges(); return; }
    } else {
      askChanges(s.sessionId, c.scope, want);
    }
  }
  // Until the tab's view is in, its body says where it's coming from, as the panel opens.
  if (!drawing && !changesShown(c)) readerWait(reader.querySelector('.r-body'), changesWaitWords(s, c));
  let changed = putHTML(reader.querySelector('.r-head'), changesHeadHTML(s, c));
  changed = putHTML(reader.querySelector('.r-src'), changesBarHTML(s, c)) || changed;
  changed = putHTML(reader.querySelector('.r-shelf'), changesShelfHTML(s, c)) || changed;
  // Drawn again with the files (redrawChanges), the panel is fitted once they're in.
  if (changed && !drawing) { fitReader(); syncHover(); }
}

const COUNTING_AGAIN_MS = 3000;

// The tab's view, once it's in: not while git is still counting the changes.
const changesShown = (c) => (c.views[c.scope]?.counting ? null : c.views[c.scope]);

// Where a tab's view is coming from while it's on its way: git, counting the checkout's changes (until it has, there's
// nothing to send), or the app reading the changes, or the commits, from it. A plain function.
function changesWaitWords(s, c) {
  const where = base((s.workGit || s.git)?.root || s.cwd);
  if (c.views[c.scope]?.counting) return `Still counting the changes in ${where} with git…`;
  if (c.scope === 'outgoing') {
    const ahead = unpushedCommits(s.checkout);
    return `Reading ${ahead ? 'the ' + commitsWord(ahead) : 'the commits'} not on GitHub yet from git…`;
  }
  return c.scope === 'staged' ? `Reading what's staged in ${where} from git…`
    : `Reading the changes in ${where} from git…`;
}

// The view drawn again: the head and list, then the files, keeping where it was scrolled to.
function redrawChanges() {
  const r = state.reading, s = readerSession();
  if (!r || r.mode !== 'changes' || !s) return;
  const c = changesState(r);
  // The list first, as it settles which file is lit (the one shown, one at a time), which may have changed with the view.
  reader.querySelector('.r-shelf').dataset.drawn = '';
  drawChanges(true);
  const view = changesShown(c);
  const body = reader.querySelector('.r-body'), top = body.scrollTop;
  const token = c.drawn = (c.drawn || 0) + 1;
  if (!view) {
    readerWait(body, changesWaitWords(s, c));
    r.ready = false;
    c.drawnScope = null;
    fitReader();
    syncHover();
    return;
  }
  // In place of the words it waited with, the view comes in once they've gone.
  if (body.querySelector(':scope > .r-wait')) {
    readerRefill(body, () => { body.innerHTML = ''; redrawChanges(); });
    return;
  }
  const parts = changesBodyParts(c, view);
  // Drawn for the first time, a long view is drawn a screenful first: once it fills the panel as tall as it can be,
  // the panel can open around it, and the files below it follow a few at a time, frame by frame, so the page keeps
  // answering the pointer meanwhile. Drawn again (the agent at work), it's drawn whole, so where it's scrolled to stays.
  const first = !r.ready || c.drawnScope !== c.scope;
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
  if (!first) add(Infinity);
  else {
    add(SCREENFUL);
    // Shorter than the panel can be, the panel's size waits on the rest.
    while (shown < parts.length && body.scrollHeight + head + 60 < state.panelMax) add(SCREENFUL);
  }
  body.scrollTop = top;
  r.ready = true;
  c.drawnScope = c.scope;
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

// What a tab is asked for at: its scope, the checkout's count's version and its commits waiting, so a change in any
// asks again.
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

// Pointing at a row's numbers asks for what pressing them would open, so that by the press it's there. Asked once for
// each version.
function prefetchChanges(sid, scope) {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (!s) return;
  const key = sid + ' ' + scope, want = changesWanted(s, scope);
  if (state.changesAsked[key] === want || state.changesReady.get(key)?.want === want) return;
  askChanges(sid, scope, want);
}

// The head: the session's name, what the tab holds in git's words (changesSub), and ✕. Only ✕ takes a press there:
// the rest of the head is the panel's handle for dragging it (PanelWindow's readerStrip), so the tabs are in a bar
// under it.
function changesHeadHTML(s, c) {
  return `<span class="r-title">${esc(s.name || base(s.cwd))}</span>
    <span class="r-sub">${esc(changesSub(c.scope, s.changes?.all, c.views.outgoing))}</span>
    <button class="r-close" title="Close">${CLOSE_ICON}</button>`;
}

// The bar under the head: the tabs, each with its count (lines put in and taken out, or the commits waiting); the tab's
// step, while Show Next Steps is on: Commit, with its other ways under ⌄, or Push, or Publish for a branch never
// pushed, each pressable only while it has something to take; then how files and lines are laid out.
function changesBarHTML(s, c) {
  const all = s.changes?.all, ahead = unpushedCommits(s.checkout);
  const pressed = (on) => on ? ' aria-pressed="true"' : '';
  const pick = (attr, value, label, on) => `<button class="c-opt" data-${attr}="${value}"${pressed(on)}>${label}</button>`;
  const nums = (side) => side?.files ? `<span class="c-nums"><span class="add">+${thousands(side.added)}</span>`
    + `<span class="del">−${thousands(side.removed)}</span></span>` : '';
  const tabs = CHANGE_TABS.map(([scope, name]) => {
    const count = scope === 'outgoing' ? (ahead ? `<span class="c-nums c-ahead">↑${thousands(ahead)}</span>` : '')
      : nums(all?.[scope]);
    return `<button class="c-tab" data-scope="${scope}"${pressed(c.scope === scope)}>${name}${count ? ' ' + count : ''}</button>`;
  }).join('');
  const off = (can) => can ? '' : ' disabled';
  let step = '';
  if (state.switches.nextSteps && c.scope === 'outgoing') {
    step = s.checkout?.upstream
      ? `<button class="c-step" data-step="push" title="Asks Claude to push the commits"${off(ahead > 0)}>Push</button>`
      : `<button class="c-step" data-step="publish" title="Asks Claude to publish this branch on GitHub"${
          off(ahead > 0)}>Publish</button>`;
  } else if (state.switches.nextSteps) {
    const staged = all?.staged?.files || 0, can = !!all?.files;
    const tip = staged ? `Asks Claude to commit what's staged (${filesWord(staged)})` : 'Asks Claude to commit the changes';
    step = `<span class="c-commit"><button class="c-step" data-step="commit" title="${esc(tip)}"${off(can)}>Commit</button>`
      + `<button class="c-step c-ways" title="Commit and Push, or Commit and Open a Pull Request"${off(can)}>`
      + `${CHEVRON_ICON}</button></span>`;
  }
  return `<span class="c-switch c-tabs">${tabs}</span>${step}<span class="c-grow"></span>
    <span class="c-switch">${pick('layout', 'all', 'All files', c.layout === 'all')}${
      pick('layout', 'one', 'One at a time', c.layout === 'one')}</span>
    <span class="c-switch">${pick('split', '0', 'Inline', !c.split)}${pick('split', '1', 'Side by side', c.split)}</span>`;
}

// A commit, over its files: its subject, then its short id and how long ago, in the list and over its files.
function commitHeadHTML(k, cls) {
  return `<div class="${cls}"><span class="k-subject">${esc(k.subject)}</span>`
    + `<span class="k-meta">${esc(k.short)} · ${ago(state.last.now - k.at)}</span></div>`;
}

// The files down the side, as git lists them, each with its letter; in Outgoing, under the commit each is from. The one
// shown is lit.
function changesShelfHTML(s, c) {
  const view = changesShown(c);
  if (!view) return '';
  if (view.missing) return `<div class="r-missing">${esc(view.missing)}</div>`;
  const list = viewFiles(view);
  if (!list.length) return `<div class="r-missing">${emptyWords(c.scope)}</div>`;
  if (!list.some((f) => f.key === c.key)) c.key = list[0].key;
  let html = '', commit = null;
  for (const f of list) {
    if (f.commit && f.commit !== commit) html += commitHeadHTML(commit = f.commit, 'r-group k-commit');
    const [a, d] = fileCount(f), [mark, letter] = gitLetter(f), note = fileNote(f, c.scope);
    const dir = f.path.includes('/') ? f.path.slice(0, f.path.lastIndexOf('/')) : '';
    html += `<button class="r-item c-file${f.key === c.key ? ' on' : ''}" data-key="${esc(f.key)}" title="${esc(f.path)}">
        <span class="c-mark ${mark}">${letter}</span>
        <span class="r-name">${esc(base(f.path))}${dir ? `<span class="c-dir">${esc(dir)}</span>` : ''}</span>
        <span class="c-nums"><span class="add">+${a}</span><span class="del">−${d}</span></span>
        ${note ? `<span class="r-meta">${esc(note)}</span>` : ''}
      </button>`;
  }
  if (view.more) html += `<div class="r-missing">and ${commitsWord(view.more)} more</div>`;
  return html;
}

// The files' changes: every file one after another, or the one picked; in Outgoing, each commit's under its head.
// Lines that weren't in the last view of this tab light up once: what the agent has just written. One part each, with
// its count of lines ({html, lines}), or a part saying why there are none.
function changesBodyParts(c, view) {
  if (view.missing) return [{ html: `<div class="r-missing">${esc(view.missing)}</div>` }];
  const list = viewFiles(view);
  if (!list.length) return [{ html: `<div class="r-missing">${emptyWords(c.scope)}</div>` }];
  const seen = new Set();
  for (const f of list) {
    for (const h of f.hunks || []) for (const l of h.lines) if (l[0] === '+') seen.add(f.key + '\n' + l[1]);
  }
  const before = c.seenScope === c.scope ? c.seen : null;
  const fresh = before ? (f, l) => l[0] === '+' && !before.has(f.key + '\n' + l[1]) : () => false;
  c.seen = seen;
  c.seenScope = c.scope;
  const picked = c.layout === 'one' ? list.filter((f) => f.key === c.key) : list;
  const parts = [];
  let commit = null;
  for (const f of picked.length ? picked : list.slice(0, 1)) {
    if (f.commit && f.commit !== commit) parts.push({ html: commitHeadHTML(commit = f.commit, 'k-head'), lines: 2 });
    parts.push({ html: fileHTML(c, f, fresh), lines: (f.hunks || []).reduce((n, h) => n + h.lines.length + 1, 1) });
  }
  return parts;
}

function fileHTML(c, f, fresh) {
  const [a, d] = fileCount(f), note = fileNote(f, c.scope);
  const slash = f.path.lastIndexOf('/');
  const chips = [f.status === 'new' && !f.untracked && '<span class="c-chip new">New</span>',
                 f.status === 'gone' && '<span class="c-chip gone">Deleted</span>',
                 note && `<span class="c-chip">${esc(note)}</span>`].filter(Boolean).join('');
  const editor = state.editors.apps.find((e) => e.id === state.editors.choice);
  const open = f.status === 'gone' ? '' : `<span class="c-edwrap"><button class="c-open" data-key="${esc(f.key)}">`
    + `${editor ? 'Open in ' + esc(editor.name) : 'Open in Editor'}</button>`
    + `${c.picking === f.key ? pickerHTML(f) : ''}</span>`;
  let body;
  if (f.binary) body = '<div class="c-aside">A file that isn\'t text: its changes can\'t be shown here.</div>';
  else if (f.cut) body = '<div class="c-aside">Too many changes to show them all here. Open the file to see it.</div>';
  else {
    const cols = c.split ? 6 : 4;
    let rows = '';
    const hunks = f.hunks || [];
    hunks.forEach((h, i) => {
      const gap = linesBetween(hunks[i - 1], h);
      const words = `${gap} ${gap === 1 ? 'line' : 'lines'}`;
      if (gap) rows += `<tr class="c-gap"><td colspan="${cols}"><b>${words}</b> unchanged</td></tr>`;
      rows += c.split ? splitHTML(f, h, fresh) : inlineHTML(f, h, fresh);
    });
    body = `<table class="c-lines${c.split ? ' split' : ''}">${rows}</table>`;
  }
  return `<section class="c-block" data-block="${esc(f.key)}"><div class="c-fhead">
      <span class="c-path">${slash > 0 ? `<i>${esc(f.path.slice(0, slash + 1))}</i>` : ''}${esc(f.path.slice(slash + 1))}</span>
      <span class="c-nums"><span class="add">+${thousands(a)}</span><span class="del">−${thousands(d)}</span></span>${chips}
      <span class="c-grow"></span>${open}</div>${body}</section>`;
}

// The lines as git shows them, with nothing between them.
function inlineHTML(f, h, fresh) {
  let old = h.oldStart, now = h.newStart, rows = '';
  for (const line of h.lines) {
    const [sign, text] = line;
    const cls = sign === ' ' ? '' : sign === '+' ? 'add' : 'del';
    rows += `<tr class="${cls}${fresh(f, line) ? ' live' : ''}">`
      + `<td class="c-ln">${sign === '+' ? '' : old}</td><td class="c-ln">${sign === '-' ? '' : now}</td>`
      + `<td class="c-sg">${sign === ' ' ? '' : sign === '-' ? '−' : '+'}</td><td class="c-code">${codeHTML(text, f.path)}</td></tr>`;
    if (sign !== '+') old++;
    if (sign !== '-') now++;
  }
  return rows;
}

function splitHTML(f, h, fresh) {
  const side = (half, mid) => {
    if (!half) return `<td class="c-ln blank${mid}"></td><td class="c-sg blank"></td><td class="c-code blank"></td>`;
    const [sign, text] = half.line;
    const cls = sign === ' ' ? '' : sign === '+' ? 'add' : 'del';
    const mark = sign === ' ' ? '' : sign === '-' ? '−' : '+';
    return `<td class="c-ln ${cls}${mid}">${half.at}</td><td class="c-sg ${cls}">${mark}</td>`
      + `<td class="c-code ${cls}${fresh(f, half.line) ? ' live' : ''}">${codeHTML(text, f.path)}</td>`;
  };
  let rows = '';
  for (const [left, right] of splitRows(h)) rows += `<tr>${side(left, '')}${side(right, ' mid')}</tr>`;
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
    + apps.map((e) => `<button class="c-app" data-editor="${esc(e.id)}" data-key="${esc(f.key)}">`
      + `${esc(e.name)}</button>`).join('')
    + `<div class="c-later">Kept for next time. Change it in the pawn menu, Open With.</div></div>`;
}

// ---- Presses ----

function changesFile(key) {
  const c = state.reading?.changes;
  return viewFiles(c?.views[c.scope]).find((f) => f.key === key);
}

function openInEditor(key, editor) {
  const r = state.reading, f = changesFile(key);
  if (!f) return;
  native({ type: 'openFile', sessionId: r.sessionId, path: f.path, line: firstChangedLine(f),
           ...(editor ? { editor } : {}) });
}

// In one scroll, the file at the top of the view is the one lit in the list; a file picked there is scrolled to.
function showFile(key) {
  const c = state.reading.changes;
  c.key = key;
  c.picking = null;
  if (c.layout === 'one') { redrawChanges(); reader.querySelector('.r-body').scrollTop = 0; return; }
  for (const el of reader.querySelectorAll('.c-file')) el.classList.toggle('on', el.dataset.key === key);
  const find = () => [...reader.querySelectorAll('.c-block')].find((b) => b.dataset.block === key);
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
  if (!current || current === c.key) return;
  c.key = current;
  for (const el of reader.querySelectorAll('.c-file')) el.classList.toggle('on', el.dataset.key === current);
}, true);

core.readerPresses.push(
  ['.c-file[data-key]', (b) => showFile(b.dataset.key)],
  ['.c-tab[data-scope]', (b) => {
    const c = state.reading.changes;
    if (c.scope === b.dataset.scope) return;
    c.scope = b.dataset.scope;
    c.key = null;
    redrawChanges();
  }],
  // A step asks the session's agent, in the app's words, once the app has checked it can go now.
  ['.c-step[data-step]', (b) => {
    if (!b.disabled) native({ type: 'gitStep', sessionId: state.reading.sessionId, step: b.dataset.step });
  }],
  ['.c-ways', (b) => {
    if (b.disabled) return;
    const r = b.getBoundingClientRect();
    native({ type: 'gitWays', sessionId: state.reading.sessionId, x: r.left - 4, y: r.bottom + 4 });
  }],
  ['.c-opt[data-layout]', (b) => {
    const c = state.reading.changes;
    c.layout = b.dataset.layout;
    store.set('changesLayout', c.layout);
    redrawChanges();
    if (c.layout === 'all' && c.key) showFile(c.key);
  }],
  ['.c-opt[data-split]', (b) => {
    const c = state.reading.changes;
    c.split = b.dataset.split === '1';
    store.set('changesSplit', c.split);
    redrawChanges();
  }],
  ['.c-app[data-editor]', (b) => {
    state.reading.changes.picking = null;
    openInEditor(b.dataset.key, b.dataset.editor);
    redrawChanges();
  }],
  ['.c-open[data-key]', (b) => {
    const c = state.reading.changes;
    if (state.editors.choice) return openInEditor(b.dataset.key);
    c.picking = c.picking === b.dataset.key ? null : b.dataset.key;
    redrawChanges();
  }],
);

// ---- The card ----

// What a row's numbers say when pointed at (core.cards): what isn't committed in the checkout, large; how many files,
// and how many are staged and not (a file staged and changed again is in both, as git status lists it).
function changesCardHTML(s) {
  const all = s.changes.all;
  const split = [all.staged?.files && `${thousands(all.staged.files)} staged`,
                 all.unstaged?.files && `${thousands(all.unstaged.files)} not staged`].filter(Boolean).join(', ');
  return `<div class="cc-big"><b class="add">+${thousands(all.added)}</b><b class="del">−${thousands(all.removed)}</b>
      <span>not committed</span></div>
    <div class="cc-lede">${filesWord(all.files)}${split ? ': ' + split : ''}</div>
    <div class="cc-hint">Press to see Changes, Staged and Outgoing.</div>`;
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

// The checkout's numbers, at the end of the work line of the row that speaks for it; pressed, the view. Pointed at,
// their card (not while the reader shows a session: a mode about none of them leaves it); and what pressing them
// would open is asked for now, so it's there by the press.
core.slots.numbers.push((row) => countsHTML(row.s, state.owners.has(row.s.sessionId)));
core.presses.push(['.counts[data-changes]', (counts, e) => { e.preventDefault(); pressCounts(counts.dataset.changes); }]);
core.pointerTargets.push('.counts[data-changes]');
core.swaps.push(':scope > .main > .work .counts');
core.cards.push({
  selector: '.counts[data-changes]',
  key: (counts) => (state.reading?.sessionId ? null : 'changes:' + counts.dataset.changes),
  html(counts) {
    const s = state.last.sessions.find((x) => x.sessionId === counts.dataset.changes);
    return s?.changes?.all ? changesCardHTML(s) : '';
  },
});
core.pointerWatchers.push((el) => {
  const counts = el?.closest('.counts[data-changes]');
  if (counts) prefetchChanges(counts.dataset.changes, 'unstaged');
});
