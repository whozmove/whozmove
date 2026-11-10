// The panel's back, a page of its own on the back of the glass (app/BackPage.m): the apps, four across, Settings
// first, as a phone's home screen has them, and under them, Whozmove's own tools, whose pages lead with what they do,
// and say what macOS has to allow only once it's needed. Settings, as a phone's are: cards of rows each with its tile,
// its name and what it's set to; each choice's page, and each app's: what Whozmove does with it, its switches, its
// cards (how something Whozmove needs there stands, with a button for it), what macOS lets Whozmove do with it, and
// Open.
// Pressing an app or a row brings its page in, and ‹ goes back a page, or, on the apps, turns the panel back to the
// list, its left edge sinking in. The header has the list's buttons in the same places: rows where the four squares
// are, which turn the panel back to the list the other way round, and the chevron, which folds it into the cat,
// turning back first. The app says how everything is set (setApps), that the panel is back on its list side
// (turned), and where the pointer is (backPointer), as its window is never the one you type in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const bk = {
  apps: [],        // as the app sends them: { id, name, does, icon, open, tool, card, hint,
                   // permission: { kind, use, state }, switches, statuses }
  settings: [],    // as the app sends them: { key, kind, title, glyph, group, page, style, foot, on or value, choices }
  // The pages you've come through, the apps first: 'apps', 'settings', a choice's page as 'set:' and its name, an
  // app's as 'app:' and its id, one of its lists as 'list:', its app's id and the list's key, and a page one of its
  // rows opens as 'sub:', its app's id and the row's key.
  stack: ['apps'],
  // On a list's page: what's ticked; when its question was asked (0 while it isn't); a line about one that can't be
  // ticked, pressed or left out ({text, way, id}); and until when the pointer has held what the last press did.
  ticked: new Set(),
  askedAt: 0,
  note: null,
  saidHeldUntil: 0,
  saidDropped: 0,   // when the said line a tick, a pick or a question dropped was said
  saidShownAt: 0,
  pointer: null,   // where the pointer is on the page, or null
  allowed: {},     // the tools whose card's Allow has been pressed, by id: what to do in System Settings shows then
  // A choice pressed whose change shows first, before and after, until Keep It or Change: { app, key, value }.
  confirm: null,
};

const ROWS_ICON = '<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><path d="M4.4 2.6h6.2M4.4 6h6.2'
  + 'M4.4 9.4h6.2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"></path>'
  + '<circle cx="1.6" cy="2.6" r=".75"></circle><circle cx="1.6" cy="6" r=".75"></circle><circle cx="1.6" cy="9.4" '
  + 'r=".75"></circle></svg>';
const BACK_ICON = '<svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M10 3 5 8l5 5" '
  + 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"></path></svg>';
const TICK_ICON = '<svg width="11" height="11" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8.5 6.4 12 13 4.5" '
  + 'fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"></path></svg>';
const MORE_ICON = '<svg width="8" height="12" viewBox="0 0 8 12" aria-hidden="true"><path d="M2 1.5 6.5 6 2 10.5" '
  + 'fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"></path></svg>';

// The marks on Settings' tiles, by the name a setting gives (its glyph), each drawn on its tile's colour (back.css);
// and Settings' own among the apps, a gear, dark on silver as a Mac's Settings app is.
const GLYPHS = {
  settings: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill-rule="evenodd" fill="currentColor" d="M11.2 2.4'
    + 'A9.6 9.6 0 0 1 12.8 2.4L13.4 4.2A7.9 7.9 0 0 1 14.6 4.5L16 3.3A9.6 9.6 0 0 1 17.4 4.1L17.1 6.0'
    + 'A7.9 7.9 0 0 1 17.9 6.8L19.8 6.5A9.6 9.6 0 0 1 20.6 7.9L19.4 9.4A7.9 7.9 0 0 1 19.7 10.5L21.5 11.2'
    + 'A9.6 9.6 0 0 1 21.5 12.8L19.7 13.4A7.9 7.9 0 0 1 19.4 14.6L20.6 16.0A9.6 9.6 0 0 1 19.8 17.4L17.9 17.1'
    + 'A7.9 7.9 0 0 1 17.1 17.9L17.4 19.8A9.6 9.6 0 0 1 16 20.6L14.6 19.4A7.9 7.9 0 0 1 13.4 19.7L12.8 21.5'
    + 'A9.6 9.6 0 0 1 11.2 21.5L10.5 19.7A7.9 7.9 0 0 1 9.4 19.4L7.9 20.6A9.6 9.6 0 0 1 6.5 19.8L6.8 17.9'
    + 'A7.9 7.9 0 0 1 6 17.1L4.1 17.4A9.6 9.6 0 0 1 3.3 16.0L4.5 14.6A7.9 7.9 0 0 1 4.2 13.4L2.4 12.8'
    + 'A9.6 9.6 0 0 1 2.4 11.2L4.2 10.5A7.9 7.9 0 0 1 4.5 9.4L3.3 7.9A9.6 9.6 0 0 1 4.1 6.5L6 6.8'
    + 'A7.9 7.9 0 0 1 6.8 6.0L6.5 4.1A9.6 9.6 0 0 1 7.9 3.3L9.4 4.5A7.9 7.9 0 0 1 10.5 4.2ZM6.8 12.0'
    + 'a5.2 5.2 0 1 1 10.4 0a5.2 5.2 0 1 1 -10.4 0Z"></path>'
    + '<circle cx="12" cy="12" r="2.4" fill="currentColor"></circle></svg>',
  look: '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="5.6" fill="none" stroke="currentColor" '
    + 'stroke-width="1.6"></circle><path d="M8 2.4a5.6 5.6 0 0 1 0 11.2z" fill="currentColor"></path></svg>',
  list: '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M4.4 2.6h6.2M4.4 6h6.2M4.4 9.4h6.2" fill="none" '
    + 'stroke="currentColor" stroke-width="1.5" stroke-linecap="round"></path><circle cx="1.6" cy="2.6" r=".9" '
    + 'fill="currentColor"></circle><circle cx="1.6" cy="6" r=".9" fill="currentColor"></circle><circle cx="1.6" '
    + 'cy="9.4" r=".9" fill="currentColor"></circle></svg>',
  keys: '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.8" y="4" width="12.4" height="8" rx="1.8" fill="none" '
    + 'stroke="currentColor" stroke-width="1.5"></rect><path d="M4.6 7h.01M7 7h.01M9.4 7h.01M11.6 7h.01M5.4 9.6h5.2" '
    + 'stroke="currentColor" stroke-width="1.5" stroke-linecap="round"></path></svg>',
  file: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M4 1.8h5l3 3v9.4H4z" fill="none" stroke="currentColor" '
    + 'stroke-width="1.5" stroke-linejoin="round"></path><path d="M6.2 8.6h3.6M6.2 11h3.6" stroke="currentColor" '
    + 'stroke-width="1.4" stroke-linecap="round"></path></svg>',
  chat: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3.2 2.6h9.6a1.4 1.4 0 0 1 1.4 1.4v5.6a1.4 1.4 0 0 1-1.4 '
    + '1.4H8.2L5 13.6V11H3.2a1.4 1.4 0 0 1-1.4-1.4V4a1.4 1.4 0 0 1 1.4-1.4z" fill="none" stroke="currentColor" '
    + 'stroke-width="1.5" stroke-linejoin="round"></path><path d="M5 5.6h6M5 8h4" stroke="currentColor" '
    + 'stroke-width="1.4" stroke-linecap="round"></path></svg>',
  gauge: '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2.8 11.4a5.2 5.2 0 0 1 10.4 0M8 11.4 10.5 7.6" fill="none" '
    + 'stroke="currentColor" stroke-width="1.6" stroke-linecap="round"></path><circle cx="8" cy="11.4" r="1.1" '
    + 'fill="currentColor"></circle></svg>',
  ticket: '<svg viewBox="0 0 16 16" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.6" '
    + 'stroke-linejoin="round" d="M2.5 4.5h11v2a1.5 1.5 0 0 0 0 3v2h-11v-2a1.5 1.5 0 0 0 0-3z"></path></svg>',
};

// After a switch or a choice is pressed, the page isn't drawn again until its knob has slid across, or its tick moved
// (controls.css's .3s): until then, what changed is changed in place, and the rest (a name that changes with it, a
// switch that comes or goes) follows.
const SLIDE_MS = 320;
let drawnAfter = 0, drawLater = null;

const backEl = document.getElementById('back');
const headEl = backEl.querySelector('header'), bodyEl = backEl.querySelector('.b-body');
const trayEl = backEl.querySelector('.b-tray');
const appOf = (id) => bk.apps.find((a) => a.id === id);
const calm = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const here = () => bk.stack[bk.stack.length - 1];
const appHere = () => here().startsWith('app:') ? appOf(here().slice(4)) : null;
// The page one of an app's rows opens, when that's where the back is ('sub:', its app's id and the row's key): {app,
// row}, or null.
function subHere() {
  if (!here().startsWith('sub:')) return null;
  const rest = here().slice(4), at = rest.indexOf(':'), app = appOf(rest.slice(0, at));
  const row = app && pageRowOf(app, rest.slice(at + 1));
  return row ? { app, row } : null;
}
// The app whose page, or page within it, is here.
const appOfHere = () => appHere() || subHere()?.app || null;
// The list whose page is here, with its app's id: {appId, list}, or null.
function listHere() {
  if (!here().startsWith('list:')) return null;
  const [, appId, key] = here().split(':'), list = listOf(bk.apps, appId, key);
  return list ? { appId, list } : null;
}

// ---- Drawing ----

// An app's icon, taken from the app itself; for one with none of its own, a tile with the mark the panel shows it by
// (git's branch, Storage's disk), or its first letter.
const MARKS = { git: BRANCH_ICON, storage: DISK_ICON };
function iconHTML(app, size) {
  if (app.icon) return `<img class="b-icon" src="${esc(app.icon)}" width="${size}" height="${size}" alt="">`;
  // A tool with a mark of Settings' (its glyph): that mark, on its colour.
  if (GLYPHS[app.glyph]) return `<span class="b-mark" style="width: ${size}px; height: ${size}px"><i class="b-glyph g-${esc(app.glyph)}">`
    + `${GLYPHS[app.glyph]}</i></span>`;
  return `<span class="b-mark" style="width: ${size}px; height: ${size}px"><i>${MARKS[app.id]
    || esc(initialOf(app.name))}</i></span>`;
}

// A setting's tile: its mark in white on its colour, as a phone's settings have them.
const tileHTML = (glyph) => `<span class="b-glyph g-${esc(glyph)}">${GLYPHS[glyph] || ''}</span>`;

// The list's header, turned over: where you are at its left, after ‹ (a page back, or from the apps, back to the
// list), then the same buttons in the same places, with ＋'s place left empty.
function headHTML() {
  const app = appHere(), sub = subHere(), page = here().startsWith('set:') ? here().slice(4) : null;
  const back = bk.stack.length > 1 ? `<button class="icon-button b-back" data-pop="1" title="Back">${BACK_ICON}</button>`
    : `<button class="icon-button b-back" data-turn="left" title="Your sessions">${BACK_ICON}</button>`;
  const listed = listHere();
  const title = app ? `${iconHTML(app, 16)}<b>${esc(app.name)}</b>` : sub ? `<b>${esc(sub.row.title)}</b>`
    : listed ? `<b>${esc(listed.list.title)}</b>`
    : `<b>${esc(page || (here() === 'settings' ? 'Settings' : 'Apps'))}</b>`;
  return `${back}<span class="b-title">${title}</span><span class="icon-button add-new b-slot" aria-hidden="true"></span>`
    + `<span class="icon-button apps" data-turn="right" title="Your sessions">${ROWS_ICON}</span>`
    + `<span class="icon-button chev" data-fold="1" title="Collapse">${CHEVRON_ICON}</span>`;
}

// The apps, four across, each its icon and its name, Settings first, then Whozmove's own tools under them.
function homeHTML() {
  const tiles = (list) => list.map((app) => `<div class="b-tile" data-go="app:${esc(app.id)}" role="button">`
    + `${iconHTML(app, 44)}<b>${esc(app.name)}</b>${typeof app.hint === 'string' && app.hint
      ? `<i class="b-hint">${esc(app.hint)}</i>` : ''}</div>`).join('');
  const apps = bk.apps.filter((app) => !app.tool), tools = bk.apps.filter((app) => app.tool);
  return '<div class="b-grid"><div class="b-tile" data-go="settings" role="button"><span class="b-glyph b-big '
    + `g-settings">${GLYPHS.settings}</span><b>Settings</b></div>${tiles(apps)}</div>`
    + (tools.length ? `<div class="caps b-sec b-tools">Tools</div><div class="b-grid">${tiles(tools)}</div>` : '');
}

// A tool's tone, as its bar's level (the kit's bar): anything else is normal.
const BAR_LEVELS = { low: 'warning', severe: 'limit' };

// What a tool's module shows on its page above its switches: a figure, a bar and a few lines (Storage's free space),
// its buttons, and last, what it can't do without its permission, with the button that allows it.
function cardHTML(app) {
  const c = cardView(app.card);
  if (!c) return '';
  return `<div class="b-card b-figures${c.tone ? ` ${c.tone}` : ''}"><div class="b-figure"><b>${esc(c.figure)}</b>`
    + `${c.of ? `<span>${esc(c.of)}</span>` : ''}</div>`
    + (c.bar === null ? '' : `<span class="bar ${BAR_LEVELS[c.tone] || 'normal'} b-bar">`
      + `<i style="width: ${(c.bar * 100).toFixed(1)}%"></i></span>`)
    + c.lines.map((line) => `<p class="b-line">${esc(line)}</p>`).join('')
    + (c.actions.length ? `<div class="b-actions">${c.actions.map((a) => `<button class="button small${a.main ? ' main' : ''}" `
      + `data-action="${esc(a.id)}">${esc(a.title)}</button>`).join('')}</div>` : '')
    + (c.need ? `<div class="b-need"><p>${esc(c.need)}${bk.allowed[app.id] ? ` ${esc(permissionView(app)?.note || '')}`
      : ''}</p><button class="button small" data-privacy="1">Allow `
      + `${esc(PERMISSION_NAMES[app.permission?.kind] || '')}</button></div>` : '') + '</div>';
}

const footHTML = (lines) => lines.length ? `<p class="b-foot">${lines.map(esc).join(' ')}</p>` : '';

// Settings: its cards, a page's row with what's picked there and ›, an app's page's row with its tile, what it says
// there and ›, a switch's row with its switch.
function settingsHTML() {
  const goes = (go, tile, row) => `<div class="b-row" data-go="${esc(go)}" role="button">${tile}`
    + `<span class="b-name">${esc(row.title)}</span><span class="b-value">${esc(row.value)}</span>`
    + `<span class="b-chev">${MORE_ICON}</span></div>`;
  return settingsCards(bk.settings).map((card) => '<div class="b-card b-set">' + card.rows.map((row) => row.page
    ? goes(`set:${row.page}`, tileHTML(row.glyph), row)
    : row.app ? (appOf(row.app) ? goes(`app:${row.app}`, `<span class="b-row-icon">${iconHTML(appOf(row.app), 22)}`
      + '</span>', row) : '')
    : `<div class="b-row" data-set="${esc(row.key)}" role="switch" aria-checked="${row.on}">${tileHTML(row.glyph)}`
      + `<span class="b-name">${esc(row.title)}</span>${SWITCH}</div>`).join('') + `</div>${footHTML(card.foot)}`)
    .join('');
}

const NEW_TAG = ' <span class="tag new">New</span>';

// One choice on a card, as Settings' pages and an app's groups both draw them: an app's icon where it's an app, its
// name (New after it, where it's new) over its line where it has one, and a tick on the one picked. `data` says what
// pressing it picks; one that can't be pressed now isn't.
function choiceRowHTML(c, picked, data, off) {
  const name = `${esc(c.name)}${c.isNew ? NEW_TAG : ''}`;
  return `<div class="b-row b-choice" ${data} role="radio" aria-checked="${picked}"`
    + `${off || c.enabled === false ? ' aria-disabled="true"' : ''}>`
    + (c.icon ? `<span class="b-row-icon"><img class="b-icon" src="${esc(c.icon)}" width="22" height="22" alt="">`
      + '</span>' : '')
    + (c.help ? `<span class="b-words"><b>${name}</b><i>${esc(c.help)}</i></span>` : `<span class="b-name">${name}</span>`)
    + `<span class="b-tick">${TICK_ICON}</span></div>`;
}

// A choice's page: each of its choices on it, under its name when there's more than one, the one picked ticked, and its
// line under it, with a button under that when it offers a way forward. Looks are each a small panel, in the colours
// that look has now, with a round pick under it.
function choicesHTML(page) {
  const entries = settingsPage(bk.settings, page);
  return entries.map((entry) => {
    const heading = entries.length > 1 ? `<div class="caps b-sec">${esc(entry.title)}</div>` : '';
    const choices = entry.choices || [];
    const pick = (c) => `data-pick="${esc(entry.key)}" data-id="${esc(c.id)}" role="radio" `
      + `aria-checked="${c.id === entry.value}"${c.enabled === false ? ' aria-disabled="true"' : ''}`;
    const body = entry.style === 'looks'
      ? `<div class="b-looks">${choices.map((c) => `<div class="b-look" ${pick(c)}>`
        + `<span class="b-preview p-${esc(c.id)}"><i class="p-head"><b></b></i><i class="p-line"><b class="p-turn">`
        + '</b><s></s><u></u></i><i class="p-line"><b class="p-busy"></b><s></s><u></u></i><i class="p-line">'
        + `<b class="p-done"></b><s></s><u></u></i></span><span class="b-look-name">${esc(c.name)}</span>`
        + '<span class="tickbox round"></span></div>').join('')}</div>`
      : choices.map((c) => choiceRowHTML(c, c.id === entry.value,
                                         `data-pick="${esc(entry.key)}" data-id="${esc(c.id)}"`)).join('');
    const button = entry.button ? `<div class="b-more"><button class="button small" data-setting-button="${esc(entry.key)}">`
      + `${esc(entry.button)}</button></div>` : '';
    return heading + (choices.length ? `<div class="b-card">${body}</div>` : '')
      + footHTML(entry.foot ? [entry.foot] : []) + button;
  }).join('');
}

// One of an app's cards (statusView): its heading over it where it has one, how it stands, and its button.
function statusHTML(v) {
  return (v.section ? `<div class="caps b-sec">${esc(v.section)}</div>` : '')
    + `<div class="b-card"><div class="b-perm${v.ok ? ' ok' : ''}"><span class="b-words"><b>${esc(v.title)}</b>`
    + (v.note ? `<i>${esc(v.note)}</i>` : '') + `</span><span class="b-state">${v.ok ? TICK_ICON : ''}${esc(v.said)}`
    + '</span></div>' + (v.button ? `<div class="b-more"><button class="button small" data-status="${esc(v.key)}"`
    + `${v.waits ? ' disabled' : ''}>${esc(v.button)}</button></div>` : '') + '</div>';
}

// One of an app's switches: its name (New after it, where it's new) over its line, and its switch, dimmed while it can't
// be pressed.
const switchHTML = (s, off) => `<div class="b-switch${off ? ' off' : ''}" data-key="${esc(s.key)}" role="switch" `
  + `aria-checked="${!!s.on}"><span class="b-words"><b>${esc(s.title)}${s.isNew ? NEW_TAG : ''}</b>`
  + `<i>${esc(s.help)}</i></span>${SWITCH}</div>`;

// One of the rows in a group on an app's page (groupsView): a switch; a row opening a page of its own; a choice drawn
// as one row, with the Mac's menu of its choices; a choice's rows, after the one above them that can't be pressed,
// which may stand alone, with nothing to pick under it; or a part of the day, its name over its line, and its two
// ends, each pressed for its menu of times.
// Each end's button is named with the row's name and which end it is, so VoiceOver, which can land on one by itself,
// says what it's for; the "to" between them is then only for the eye.
function groupRowHTML(row) {
  if (row.kind === 'switch') return switchHTML(row, row.off);
  // A row opening a page of its own: its name, what it's set to, and ›.
  if (row.kind === 'page')
    return `<div class="b-row"${row.off ? ' aria-disabled="true"'
      : ` data-go="sub:${esc(appOfHere()?.id || '')}:${esc(row.key)}"`} role="button"><span class="b-name">${esc(row.title)}</span>`
      + `<span class="b-value">${esc(row.said)}</span><span class="b-chev">${MORE_ICON}</span></div>`;
  // A choice drawn as one row: its name over its line, and the one picked on a button opening the Mac's menu of them.
  if (row.kind === 'choice' && row.menu) {
    // None of them picked (what was picked has gone): the button asks for one.
    const said = row.choices.find((c) => c.id === row.value)?.name || 'Choose…';
    return `<div class="b-span${row.off ? ' off' : ''}"><span class="b-words"><b>${esc(row.title)}</b>`
      + `${row.fixed?.help ? `<i>${esc(row.fixed.help)}</i>` : ''}</span><button class="button small b-menu" `
      + `data-menu="${esc(row.key)}" aria-label="${esc(`${row.title}: ${said}`)}"${row.off ? ' disabled' : ''}>`
      + `<span class="b-menu-name">${esc(said)}</span><span class="caret">${CHEVRON_ICON}</span></button></div>`;
  }
  if (row.kind === 'choice')
    return (row.fixed ? `<div class="b-row b-choice b-fixed" aria-disabled="true"><span class="b-words">`
      + `<b>${esc(row.fixed.name)}</b><i>${esc(row.fixed.help)}</i></span></div>` : '')
      + (!row.choices.length ? '' : `<div class="b-picks" role="radiogroup" aria-label="${esc(row.title)}">`
        + `${row.choices.map((c) => choiceRowHTML(c, c.id === row.value,
          `data-choice="${esc(row.key)}" data-id="${esc(c.id)}"`, row.off)).join('')}</div>`)
      + confirmHTML(row);
  const end = (which, said) => `<button class="button small b-time" data-time="${esc(row.key)}" data-end="${which}"`
    + ` aria-label="${esc(`${row.title}, ${which} ${said}`)}"${row.off ? ' disabled' : ''}>${esc(said)}</button>`;
  return `<div class="b-span${row.off ? ' off' : ''}"><span class="b-words"><b>${esc(row.title)}</b>`
    + `${row.help ? `<i>${esc(row.help)}</i>` : ''}</span><span class="b-ends">${end('from', row.from)}`
    + `<span aria-hidden="true">to</span>${end('to', row.to)}</span></div>`;
}

// What picking a choice would change, under its choices while it's the one pressed: before and after, what to be
// careful of and what stays, then Keep It, which leaves it as it is, and Change, which picks it.
function confirmHTML(row) {
  const c = bk.confirm, said = c && c.app === appOfHere()?.id && c.key === row.key ? row.confirms?.[c.value] : null;
  if (!said) return '';
  const line = (k, text) => `<div class="b-ba-line"><span class="b-ba-k">${k}</span><span>${esc(text)}</span></div>`;
  return `<div class="b-ba" role="group" aria-label="${esc(`${row.title}: before and after`)}">`
    + line('Before', said.before) + line('After', said.after)
    + (said.warn ? `<div class="b-ba-warn">${esc(said.warn)}</div>` : '')
    + (said.keep ? `<div class="b-ba-keep">${esc(said.keep)}</div>` : '')
    + '<div class="b-ba-btns"><button class="button small quiet" data-confirm="keep">Keep It</button>'
    + '<button class="button small main" data-confirm="change">Change</button></div></div>';
}

// An app's groups, each its heading (with Important after it, for one that matters more than most) over a card of its
// rows and its line under the card; then, while what's on the page isn't as recommended, the button that puts it back.
const IMPORTANT_TAG = ' <span class="tag b-imp">Important</span>';
function groupsHTML(app) {
  return groupsView(app).map((g) => (g.title ? `<div class="caps b-sec">${esc(g.title)}${g.important ? IMPORTANT_TAG : ''}`
    + '</div>' : '')
    + (g.rows.length ? `<div class="b-card b-group">${g.rows.map(groupRowHTML).join('')}</div>` : '')
    + footHTML(g.foot ? [g.foot] : [])).join('')
    + (app.recommended === false ? '<div class="b-more"><button class="button small" data-recommended="1">Use the '
      + 'Recommended Settings</button></div>' : '');
}

function appHTML(app) {
  const switches = app.switches.map((s) => switchHTML(s, s.enabled === false)).join('');
  const statuses = (app.statuses || []).map(statusView).filter(Boolean).map(statusHTML).join('');
  // A tool's page leads with what it does: its permission comes up only in its card, once it's needed.
  const p = app.tool ? null : permissionView(app);
  const permission = p ? `<div class="caps b-sec">Privacy &amp; Security</div><div class="b-card"><div class="b-perm `
    + `${p.state}"><span class="b-words"><b>${esc(p.name)}</b><i>${esc(p.use)}</i></span><span class="b-state">`
    + `${p.state === 'allowed' ? TICK_ICON : ''}${esc(p.said)}</span></div>`
    + (p.note ? `<p class="b-note">${esc(p.note)}</p>` : '')
    + (p.settings ? '<div class="b-more"><button class="button small" data-privacy="1">Open System Settings</button>'
      + '</div>' : '') + '</div>' : '';
  const open = app.open ? `<div class="b-more"><button class="button small" data-open="1">Open ${esc(app.name)}</button>`
    + '</div>' : '';
  // Each of its lists, a row with its count that opens its page, under its switches.
  const lists = (app.lists || []).map((list) => `<div class="b-card"><div class="b-row" data-go="list:${esc(app.id)}:`
    + `${esc(list.key)}" role="button"><span class="b-name">${esc(list.title)}</span><span class="b-value">`
    + `${list.loading ? '' : esc(String(list.count ?? ''))}</span><span class="b-chev">${MORE_ICON}</span></div></div>`)
    .join('');
  return `<div class="b-hero">${iconHTML(app, 40)}<p class="b-does">${esc(app.does)}</p></div>${cardHTML(app)}`
    + `${switches ? `<div class="b-card">${switches}</div>` : ''}${groupsHTML(app)}${lists}`
    + `${statuses}${permission}${open}`;
}

// A list's page: its line, then each section, under its title, a card of its items: one that can be ticked with its
// box, one that can't with its box dimmed and why on its line, and the rest with their buttons. While it's being read,
// or with nothing in it, it says so.
function listHTML(list) {
  const intro = list.intro ? `<p class="b-foot">${esc(list.intro)}</p>` : '';
  if (list.loading) return `${intro}<p class="b-foot b-list-wait">${esc(list.loading)}</p>`;
  const sections = list.sections || [];
  if (!sections.length) return `${intro}<p class="b-foot b-list-wait">${esc(list.empty || '')}</p>`;
  return intro + sections.map((section) => `<div class="caps b-sec">${esc(section.title)}</div><div class="b-card">`
    + (section.items || []).map((item) => (section.tickable
      ? `<div class="b-row b-pickable${item.why ? ' b-cant' : ''}" data-tick="${esc(item.id)}" `
        + `data-item="t:${esc(item.id)}" role="checkbox" `
        + `aria-checked="${bk.ticked.has(item.id)}"><span class="tickbox"></span><span class="b-words"><b>`
        + `${esc(item.title)}</b><i>${esc(item.why || item.line || '')}</i></span></div>`
      : `<div class="b-perm b-listed" data-item="l:${esc(item.id)}"><span class="b-words"><b>${esc(item.title)}</b>`
        + `<i>${esc(item.line || '')}</i>`
        + `</span>${(item.buttons || []).map((b, i) => `<button class="button small${i ? ' quiet' : ''}" `
          + `data-list-key="${esc(b.key)}" data-ids="${esc(item.id)}">${esc(b.title)}</button>`).join('')}</div>`))
      .join('') + `</div>${section.foot ? `<p class="b-foot">${esc(section.foot)}</p>` : ''}`).join('');
}

// Under a list's page, standing still as it scrolls: what the last press did, for a while; else the question its
// button asks; else what's ticked, with its button for the marked ones and its own. Under that, a line about one that
// can't be ticked, with its way forward.
function trayHTML(list, now) {
  const tray = list.tray || {}, said = list.said;
  let line;
  if (listSaidShows(said, bk.saidHeldUntil, now, bk.saidDropped)) {
    line = `<div class="tray"><span class="tray-said">${esc(said.text)}</span>${(said.buttons || []).map((b) =>
      `<button class="button small quiet" data-list-key="${esc(b.key)}" data-ids="${esc((b.ids || []).join(' '))}" `
      + `data-fresh="said">${esc(b.title)}</button>`).join('')}</div>`;
  } else {
    const { ticked } = listTicks(list, bk.ticked), asked = bk.askedAt && listAsk(list, ticked);
    if (asked) {
      line = `<div class="tray b-asking"><span class="tray-ask"><b>${esc(asked.title)}</b><i>${esc(asked.words)}</i>`
        + '</span><button class="button small" data-tray="cancel" data-fresh="ask">Cancel</button>'
        + `<button class="button small main" data-tray="go" data-fresh="ask">${esc(tray.action)}</button></div>`;
    } else {
      const pick = listPick(list, bk.ticked);
      line = `<div class="tray"><span class="tray-said">${ticked.length ? `<b>${ticked.length} ticked</b>`
        : esc(tray.hint || '')}</span>`
        + (pick ? `<button class="button small quiet" data-tray="pick">${esc(pick.title)}</button>` : '')
        + `<button class="button small main" data-tray="ask"${ticked.length ? '' : ' disabled'}>${esc(tray.action)}`
        + '</button></div>';
    }
  }
  const note = bk.note ? `<p class="b-tray-note"><span>${esc(bk.note.text)}</span>${bk.note.way
    ? `<button class="button small quiet" data-list-key="${esc(bk.note.way.key)}" data-ids="${esc(bk.note.id)}">`
      + `${esc(bk.note.way.title)}</button>` : ''}</p>` : '';
  return line + note;
}

const bodyHTML = () => appHere() ? appHTML(appHere()) : subHere() ? groupsHTML({ groups: subHere().row.groups })
  : listHere() ? listHTML(listHere().list)
  : here().startsWith('set:') ? choicesHTML(here().slice(4)) : here() === 'settings' ? settingsHTML() : homeHTML();

// Drawn again only where it changed. What a press changes (a switch's state, the choice picked, whether the others can
// be pressed) is changed in place, so its knob slides and its tick moves rather than the page being drawn again under
// them; anything more is drawn once the knob has slid.
function draw() {
  // A page that has gone (its app from this Mac, its setting from the module) goes back as far as what's still there.
  while (bk.stack.length > 1 && ((here().startsWith('app:') && !appHere()) || (here().startsWith('sub:') && !subHere())
                                 || (here().startsWith('list:') && !listHere())
                                 || (here().startsWith('set:') && !settingsPage(bk.settings, here().slice(4)).length)))
    bk.stack.pop();
  drawTray();
  const head = headHTML(), body = bodyHTML();
  if (headEl.dataset.drawn !== head) headEl.innerHTML = headEl.dataset.drawn = head;
  const shape = (html) => html.replace(/ aria-checked="\w+"/g, '').replace(/b-switch off/g, 'b-switch');
  if (bodyEl.dataset.drawn !== body && !folding) {
    const same = bodyEl.dataset.drawn && shape(bodyEl.dataset.drawn) === shape(body);
    const wait = drawnAfter - Date.now();
    if (same || wait > 0) {
      const now = document.createElement('div');
      now.innerHTML = body;
      const want = now.querySelectorAll('[aria-checked]'), have = bodyEl.querySelectorAll('[aria-checked]');
      if (want.length === have.length) {
        have.forEach((el, i) => {
          el.setAttribute('aria-checked', want[i].getAttribute('aria-checked'));
          if (el.classList.contains('b-switch')) el.classList.toggle('off', want[i].classList.contains('off'));
        });
      }
      if (same) bodyEl.dataset.drawn = body;
      else {
        clearTimeout(drawLater);
        drawLater = setTimeout(draw, wait);
      }
    } else if (!foldLeaving(body)) {
      const page = bodyEl.dataset.page === here() ? itemsIn(bodyEl) : null;
      bodyEl.innerHTML = body;
      bodyEl.dataset.drawn = body;
      bodyEl.dataset.page = here();
      if (page) growArrived(page);
    }
  }
  // A card's button set waiting by its press waits only for as long as the app says it does.
  const app = appHere();
  for (const el of bodyEl.querySelectorAll('[data-status]'))
    el.disabled = !!statusView(app?.statuses?.find((s) => s.key === el.dataset.status))?.waits;
  markPointed();
  backLines();
}

// The line under the back's head (lineUnder, util.js): only while its page is scrolled under it.
function backLines() {
  markLineUnder([headEl], bodyEl.scrollTop);
}
bodyEl?.addEventListener('scroll', backLines, { passive: true });

// A list's rows that a press took off it (moved to the Trash, or put back from it) fold away one after another, their
// words first and then their room, before the page is drawn without them, a section with them when none of it stays;
// rows that came onto it fade in, lifting 3px. However many go, it's over in well under a second: the stagger stops
// growing after a few rows. With reduced motion, the page is just drawn again.
const FOLD_FADE_MS = 120, FOLD_CLOSE_MS = 220, FOLD_STAGGER_MS = 40, FOLD_STAGGERED = 8;
const FOLD_EASE = 'cubic-bezier(.2, .9, .25, 1)';
let folding = false, foldDone = null;
const itemsIn = (root) => new Set([...root.querySelectorAll('[data-item]')].map((el) => el.dataset.item));
function foldLeaving(body) {
  if (calm() || !listHere() || bodyEl.dataset.page !== here()) return false;
  const next = document.createElement('div');
  next.innerHTML = body;
  const stays = itemsIn(next), leaving = [];
  for (const card of bodyEl.querySelectorAll('.b-card')) {
    // Rows already folded are left out, so the page is drawn without them once they have.
    const rows = [...card.querySelectorAll('[data-item]')];
    const going = rows.filter((el) => !stays.has(el.dataset.item) && !el.dataset.folded);
    if (!going.length) continue;
    going.forEach((el) => { el.dataset.folded = '1'; });
    // A section none of whose rows stay goes whole: its heading, its card and the line under it (never the next
    // section's heading).
    const before = card.previousElementSibling, after = card.nextElementSibling;
    if (going.length < rows.length) leaving.push(...going.map((el) => [el]));
    else leaving.push([before?.matches('.b-sec') ? before : null, card, after?.matches('.b-foot') ? after : null]
      .filter(Boolean));
  }
  if (!leaving.length) return false;
  folding = true;
  const fold = (el) => {
    const h = el.offsetHeight;
    el.style.overflow = 'hidden';
    const fade = (part) => part.animate([{ opacity: 1 }, { opacity: 0 }], { duration: FOLD_FADE_MS, fill: 'forwards' });
    if (el.children.length) [...el.children].forEach(fade);
    else fade(el);
    el.animate([{ height: `${h}px` },
                { height: `${h}px`, offset: FOLD_FADE_MS / (FOLD_FADE_MS + FOLD_CLOSE_MS), easing: FOLD_EASE },
                { height: '0px', paddingTop: '0px', paddingBottom: '0px', marginTop: '0px', marginBottom: '0px',
                  borderWidth: '0px' }],
               { duration: FOLD_FADE_MS + FOLD_CLOSE_MS, fill: 'forwards' });
  };
  const delay = (i) => Math.min(i, FOLD_STAGGERED) * FOLD_STAGGER_MS;
  leaving.forEach((els, i) => setTimeout(() => els.forEach(fold), delay(i)));
  // Drawn again on a clock, not as the animations end: a page out of sight may hold them, never the list.
  foldDone = setTimeout(endFold, delay(leaving.length - 1) + FOLD_FADE_MS + FOLD_CLOSE_MS + 20);
  return true;
}
// The fold over, or cut short as the page is left (the page leaving is drawn anew anyway).
function stopFold() {
  clearTimeout(foldDone);
  folding = false;
}
function endFold() {
  stopFold();
  draw();
}
function growArrived(had) {
  if (calm()) return;
  const arrive = (el) => el.animate([{ opacity: 0, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }],
                                    { duration: FOLD_FADE_MS + FOLD_CLOSE_MS, easing: FOLD_EASE });
  for (const el of bodyEl.querySelectorAll('[data-item]')) if (!had.has(el.dataset.item)) arrive(el);
  // A section all of whose rows arrived came with them: its heading and the line under it fade in alike.
  for (const card of bodyEl.querySelectorAll('.b-card')) {
    const rows = [...card.querySelectorAll('[data-item]')];
    if (!rows.length || rows.some((el) => had.has(el.dataset.item))) continue;
    const before = card.previousElementSibling, after = card.nextElementSibling;
    if (before?.matches('.b-sec')) arrive(before);
    if (after?.matches('.b-foot')) arrive(after);
  }
}

// The tray under a list's page, drawn again only when it changed; hidden on any other page. What the last press did
// is drawn again once its time is up, as nothing else may draw the page then.
let trayLater = null;
function drawTray() {
  const listed = listHere(), now = Date.now();
  trayEl.hidden = !listed;
  const html = listed ? trayHTML(listed.list, now) : '';
  if (trayEl.dataset.drawn !== html) {
    if (/data-fresh="said"/.test(html) && !/data-fresh="said"/.test(trayEl.dataset.drawn || '')) bk.saidShownAt = now;
    trayEl.innerHTML = trayEl.dataset.drawn = html;
  }
  clearTimeout(trayLater);
  const said = listed?.list.said;
  if (listSaidShows(said, bk.saidHeldUntil, now, bk.saidDropped))
    trayLater = setTimeout(draw, Math.max(said.at + LIST_SAID_MS, bk.saidHeldUntil) - now + 50);
}

// Another page of the back, further in or back a page: what was there goes as the new one comes in, fading and
// lifting 3px, as the panel's do. A list's page starts with nothing ticked.
function go(page) {
  if (page?.startsWith('list:') || here().startsWith('list:')) {
    bk.ticked = new Set();
    bk.askedAt = 0;
    bk.note = null;
  }
  bk.confirm = null;
  if (page) bk.stack.push(page);
  else if (bk.stack.length > 1) bk.stack.pop();
  else return;
  stopFold();
  drawnAfter = 0;
  draw();
  bodyEl.scrollTop = 0;
  if (!calm()) bodyEl.animate([{ opacity: 0, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }],
                              { duration: 300, easing: 'cubic-bezier(.2, .8, .2, 1)' });
}

// What the pointer is on, marked as the panel's are (.is-hover): only what a press does something on.
const POINTED = '.b-tile, .b-row[data-go], .b-row[data-set], .b-row[data-pick]:not([aria-disabled]), '
  + '.b-row[data-choice]:not([aria-disabled]), .b-row[data-tick]:not(.b-cant), .b-look:not([aria-disabled]), '
  + '.b-switch:not(.off), .button:not(:disabled), .b-back, header .apps, header .chev';
function markPointed() {
  const at = bk.pointer, on = at ? document.elementFromPoint(at.x, at.y)?.closest(POINTED) : null;
  document.querySelectorAll('.is-hover').forEach((el) => { if (el !== on) el.classList.remove('is-hover'); });
  on?.classList.add('is-hover');
}

// ---- Presses ----

// A setting: it changes at once, and the app is told, which says how everything is set now.
function setSetting(key, value) {
  const settings = afterSetting(bk.settings, key, value);
  if (!settings) return;
  bk.settings = settings;
  drawnAfter = Date.now() + SLIDE_MS;
  draw();
  native({ type: 'appsSetting', key, value });
}

// One of an app's switches: the same way.
function press(key) {
  const app = appOfHere(), apps = app && afterPress(bk.apps, app.id, key);
  if (!apps) return;
  bk.apps = apps;
  drawnAfter = Date.now() + SLIDE_MS;
  draw();
  const on = switchesOf(appOf(app.id)).find((s) => s.key === key).on;
  native({ type: 'appsSwitch', app: app.id, key, on });
}

// One of an app's choices: the same way. One whose change shows first shows its before and after instead, and is
// picked once Change is pressed (`sure`).
function choose(key, value, sure) {
  const app = appOfHere(), apps = app && afterChoice(bk.apps, app.id, key, value);
  if (!apps) return;
  const row = rowsIn(app.groups).find((r) => r.kind === 'choice' && r.key === key);
  if (!sure && row?.confirms?.[value]) {
    bk.confirm = { app: app.id, key, value };
    return draw();
  }
  bk.confirm = null;
  bk.apps = apps;
  drawnAfter = Date.now() + SLIDE_MS;
  draw();
  native({ type: 'appsChoice', app: app.id, key, value });
}

// mousedown, as the panel's are: the page can be drawn again between a press and its release.
backEl.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  const hit = (selector) => e.target.closest(selector);
  let el;
  if ((el = hit('[data-turn]'))) return native({ type: 'appsTurnBack', side: el.dataset.turn });
  if (hit('[data-fold]')) return native({ type: 'appsFold' });
  if (hit('[data-pop]')) return go(null);
  if ((el = hit('[data-go]'))) return go(el.dataset.go);
  if ((el = hit('[data-tick], [data-tray], [data-list-key]'))) return listPressed(el);
  if ((el = hit('[data-set]'))) return setSetting(el.dataset.set, el.getAttribute('aria-checked') !== 'true');
  if ((el = hit('[data-pick]'))) return setSetting(el.dataset.pick, el.dataset.id);
  if ((el = hit('.b-switch[data-key]'))) return press(el.dataset.key);
  if ((el = hit('[data-choice]'))) return choose(el.dataset.choice, el.dataset.id);
  if ((el = hit('[data-confirm]'))) {
    const c = bk.confirm;
    bk.confirm = null;
    if (c && el.dataset.confirm === 'change') return choose(c.key, c.value, true);
    return draw();
  }
  // A choice's menu is the Mac's own, opened by the app at its button, as a time's is.
  if ((el = hit('[data-menu]'))) {
    if (el.disabled) return;
    const r = el.getBoundingClientRect();
    return native({ type: 'appsChoiceMenu', app: appOfHere()?.id, key: el.dataset.menu, x: Math.round(r.left),
                    y: Math.round(r.top) });
  }
  // A time's menu is the Mac's own, opened by the app over the time pressed, its top-left corner where the time's is.
  if ((el = hit('[data-time]'))) {
    if (el.disabled) return;
    const r = el.getBoundingClientRect();
    return native({ type: 'appsTime', app: appOfHere()?.id, key: el.dataset.time, end: el.dataset.end,
                    x: Math.round(r.left), y: Math.round(r.top) });
  }
  if (hit('[data-recommended]')) return native({ type: 'appsUseRecommended', app: appHere()?.id });
  if ((el = hit('[data-setting-button]'))) return native({ type: 'appsSettingButton', key: el.dataset.settingButton });
  // A card's button waits from the press until the app says how it went.
  if ((el = hit('[data-status]'))) {
    if (el.disabled) return;
    el.disabled = true;
    return native({ type: 'appsAction', app: appHere()?.id, key: el.dataset.status });
  }
  if (hit('[data-open]')) return native({ type: 'appsOpen', app: appHere()?.id });
  if ((el = hit('[data-action]'))) return native({ type: 'appsAction', app: appHere()?.id, key: el.dataset.action });
  if (hit('[data-privacy]')) {
    // A tool's Allow: once it's been pressed, its card says what to do in System Settings, where macOS may not have
    // listed Whozmove.
    const app = appHere();
    if (app?.tool && !bk.allowed[app.id]) {
      bk.allowed[app.id] = true;
      draw();
    }
    return native({ type: 'appsPrivacy', app: app?.id });
  }
});

// A press on a list's page: a row ticked, or one that can't be said why of, with its way forward; the tray's buttons;
// and an item's, the note's or what the last press did's, each sent to the app with the ids it's for. The question's
// answers, and Undo under what was done, take no press until they've been there a moment.
function listPressed(el) {
  const listed = listHere();
  if (!listed) return;
  const { appId, list } = listed, now = Date.now();
  const send = (key, ids) => native({ type: 'appsList', app: appId, list: list.key, key, ids });
  if (el.dataset.fresh === 'ask' && now - bk.askedAt < LIST_FRESH_MS) return;
  if (el.dataset.fresh === 'said' && now - bk.saidShownAt < LIST_FRESH_MS) return;
  if (el.dataset.tick) {
    const item = listItems(list).find((i) => i.id === el.dataset.tick);
    if (!item) return;
    if (!item.tickable) {
      bk.note = item.why ? { text: `${item.title} can't be ticked. ${item.why}.`, way: item.way || null, id: item.id }
        : null;
    } else {
      if (bk.ticked.has(item.id)) bk.ticked.delete(item.id);
      else bk.ticked.add(item.id);
      bk.askedAt = 0;
      bk.saidHeldUntil = 0;
      bk.saidDropped = list.said?.at || 0;
      bk.note = null;
    }
    return draw();
  }
  const tray = el.dataset.tray;
  if (tray === 'pick') {
    const pick = listPick(list, bk.ticked);
    for (const id of pick?.ids || []) pick.all ? bk.ticked.delete(id) : bk.ticked.add(id);
    bk.askedAt = 0;
    bk.saidHeldUntil = 0;
    bk.saidDropped = list.said?.at || 0;
    return draw();
  }
  if (tray === 'ask') {
    bk.askedAt = now;
    bk.saidDropped = list.said?.at || 0;
    bk.note = null;
    return draw();
  }
  if (tray === 'cancel') {
    bk.askedAt = 0;
    return draw();
  }
  if (tray === 'go') {
    const { ticked } = listTicks(list, bk.ticked);
    bk.ticked = new Set();
    bk.askedAt = 0;
    bk.saidHeldUntil = 0;
    bk.saidDropped = list.said?.at || 0;
    draw();
    return send(list.tray.actionKey, ticked);
  }
  if (el.dataset.listKey) send(el.dataset.listKey, (el.dataset.ids || '').split(' ').filter(Boolean));
}

// ---- What the app calls ----

// The apps, in their order, the panel's look (for the colours that match the panel's own), and Settings' rows.
window.setApps = (apps, look, settings) => {
  bk.apps = Array.isArray(apps) ? apps : [];
  // On a list's page, one ticked that can't go any more (it started working, say) is unticked, and the line under the
  // tray says why.
  const listed = listHere();
  if (listed && bk.ticked.size) {
    const { ticked, leftOut } = listTicks(listed.list, bk.ticked);
    bk.ticked = new Set(ticked);
    if (leftOut.length) {
      const one = leftOut[0];
      bk.note = { text: `${one.title} is left out. ${one.why}.`, way: one.way, id: one.id };
      if (!ticked.length) bk.askedAt = 0;
    }
  }
  bk.settings = Array.isArray(settings) ? settings : [];
  document.documentElement.dataset.look = look || 'grey';
  draw();
};

// Settings… in the pawn menu: Settings, from whichever page shows, with ‹ back to the apps; called as the panel
// starts turning over too, so it's there as the back comes round.
window.showSettings = () => {
  if (here() === 'settings') return;
  bk.stack = ['apps'];
  go('settings');
};

// Back on its list side: out of sight now, the back goes back to the apps for the next time it's turned over.
window.turned = (on) => {
  if (on) return;
  stopFold();
  bk.stack = ['apps'];
  bk.pointer = null;
  draw();
  bodyEl.scrollTop = 0;
};

// The page to show as the panel turns over to its back, asked from the panel's side (the line above its list says the
// disk is low, and Storage's page has more): there at once, as it's out of sight until the panel has turned.
// The pages the back is on to show an app's: on a page one of its rows opens, when that row is there; else its own.
const showingStack = (id, page) => ['apps', `app:${id}`, ...(page && pageRowOf(appOf(id), page) ? [`sub:${id}:${page}`]
  : [])];
window.showApp = (id, page) => {
  if (!appOf(id)) return;
  stopFold();
  bk.stack = showingStack(id, page);
  drawnAfter = 0;
  draw();
  bodyEl.scrollTop = 0;
};

// Where the pointer is on the page, from its top-left corner, or null once it has gone.
window.backPointer = (at) => {
  bk.pointer = at && Number.isFinite(at.x) && Number.isFinite(at.y) ? at : null;
  markPointed();
  // What the last press did stays said while the pointer is on it, and a moment more once it leaves.
  const on = bk.pointer && !trayEl.hidden
    ? document.elementFromPoint(bk.pointer.x, bk.pointer.y)?.closest('.b-tray') : null;
  if (on && listSaidShows(listHere()?.list.said, bk.saidHeldUntil, Date.now(), bk.saidDropped))
    bk.saidHeldUntil = Date.now() + LIST_HELD_MS;
};
