// The panel's back, a page of its own on the back of the glass (app/BackPage.m): the apps Whozmove works with, four
// across, and each one's page: what Whozmove does with it, its switches, its cards (how something Whozmove needs there
// stands, with a button for it), what macOS lets Whozmove do with it, and Open.
// Pressing an app brings its page in, and ‹ goes back to the apps. The header has the list's buttons in the same places:
// rows where the four squares are, which turn the panel back to the list, and the chevron, which folds it into the cat,
// turning back first. The app says which apps there are and how each is set (setApps), that the panel is back on its
// list side (turned), and where the pointer is (backPointer), as its window is never the one you type in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const bk = {
  apps: [],        // as the app sends them: { id, name, does, icon, open, permission: { kind, use, state }, switches,
                   // statuses }
  page: null,      // the app whose page shows, by its id, or null for the apps
  pointer: null,   // where the pointer is on the page, or null
};

const ROWS_ICON = '<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><path d="M4.4 2.6h6.2M4.4 6h6.2'
  + 'M4.4 9.4h6.2" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"></path>'
  + '<circle cx="1.6" cy="2.6" r=".75"></circle><circle cx="1.6" cy="6" r=".75"></circle><circle cx="1.6" cy="9.4" '
  + 'r=".75"></circle></svg>';
const BACK_ICON = '<svg width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><path d="M10 3 5 8l5 5" '
  + 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"></path></svg>';
const TICK_ICON = '<svg width="11" height="11" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8.5 6.4 12 13 4.5" '
  + 'fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"></path></svg>';

// After a switch is pressed, the page isn't drawn again until its knob has slid across (controls.css's .3s): until
// then, what changed is changed in place, and the rest (a switch that comes or goes with it) follows.
const SLIDE_MS = 320;
let drawnAfter = 0, drawLater = null;

const backEl = document.getElementById('back');
const headEl = backEl.querySelector('header'), bodyEl = backEl.querySelector('.b-body');
const appOf = (id) => bk.apps.find((a) => a.id === id);
const calm = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---- Drawing ----

// An app's icon, taken from the app itself; for one with none of its own (git), a tile with the branch mark the
// panel's rows show, or its first letter.
function iconHTML(app, size) {
  if (app.icon) return `<img class="b-icon" src="${esc(app.icon)}" width="${size}" height="${size}" alt="">`;
  return `<span class="b-mark" style="width: ${size}px; height: ${size}px"><i>${app.id === 'git' ? BRANCH_ICON
    : esc(initialOf(app.name))}</i></span>`;
}

// The list's header, turned over: where you are at its left, then the same buttons in the same places, with ＋'s
// place left empty.
function headHTML() {
  const app = appOf(bk.page);
  const where = app ? `<button class="b-back" data-home="1" title="Back to your apps">${BACK_ICON}</button>`
      + `<span class="b-title">${iconHTML(app, 16)}<b>${esc(app.name)}</b></span>`
    : '<span class="b-title"><b>Apps</b></span>';
  return `${where}<span class="add-new b-slot" aria-hidden="true"></span>`
    + `<span class="apps" data-turn="1" title="Your sessions">${ROWS_ICON}</span>`
    + `<span class="chev" data-fold="1" title="Collapse">${CHEVRON_ICON}</span>`;
}

function homeHTML() {
  const tiles = bk.apps.map((app) => `<div class="b-tile" data-app="${esc(app.id)}" role="button">`
    + `${iconHTML(app, 44)}<b>${esc(app.name)}</b></div>`).join('');
  return `<div class="b-grid">${tiles}</div>`;
}

// One of an app's cards (statusView): its heading over it where it has one, how it stands, and its button.
function statusHTML(v) {
  return (v.section ? `<div class="b-sec">${esc(v.section)}</div>` : '')
    + `<div class="b-card"><div class="b-perm${v.ok ? ' ok' : ''}"><span class="b-words"><b>${esc(v.title)}</b>`
    + (v.note ? `<i>${esc(v.note)}</i>` : '') + `</span><span class="b-state">${v.ok ? TICK_ICON : ''}${esc(v.said)}`
    + '</span></div>' + (v.button ? `<div class="b-more"><button class="button" data-status="${esc(v.key)}"`
    + `${v.waits ? ' disabled' : ''}>${esc(v.button)}</button></div>` : '') + '</div>';
}

function appHTML(app) {
  const switches = app.switches.map((s) => `<div class="b-switch${s.enabled === false ? ' off' : ''}" `
    + `data-key="${esc(s.key)}" role="switch" aria-checked="${!!s.on}"><span class="b-words"><b>${esc(s.title)}</b>`
    + `<i>${esc(s.help)}</i></span>${SWITCH}</div>`).join('');
  const statuses = (app.statuses || []).map(statusView).filter(Boolean).map(statusHTML).join('');
  const p = permissionView(app);
  const permission = p ? `<div class="b-sec">Privacy &amp; Security</div><div class="b-card"><div class="b-perm `
    + `${p.state}"><span class="b-words"><b>${esc(p.name)}</b><i>${esc(p.use)}</i></span><span class="b-state">`
    + `${p.state === 'allowed' ? TICK_ICON : ''}${esc(p.said)}</span></div>`
    + (p.note ? `<p class="b-note">${esc(p.note)}</p>` : '')
    + (p.settings ? '<div class="b-more"><button class="button" data-privacy="1">Open System Settings</button></div>'
      : '') + '</div>' : '';
  const open = app.open ? `<div class="b-more"><button class="button" data-open="1">Open ${esc(app.name)}</button>`
    + '</div>' : '';
  return `<div class="b-hero">${iconHTML(app, 40)}<p class="b-does">${esc(app.does)}</p></div>`
    + `${switches ? `<div class="b-card">${switches}</div>` : ''}${statuses}${permission}${open}`;
}

// Drawn again only where it changed. What a switch's press changes (its state, and whether the others can be pressed)
// is changed in place, so its knob slides rather than the page being drawn again under it; anything more is drawn once
// the knob has slid.
function draw() {
  if (bk.page && !appOf(bk.page)) bk.page = null;  // its app has gone from this Mac
  const head = headHTML(), body = bk.page ? appHTML(appOf(bk.page)) : homeHTML();
  if (headEl.dataset.drawn !== head) headEl.innerHTML = headEl.dataset.drawn = head;
  const shape = (html) => html.replace(/ aria-checked="\w+"/g, '').replace(/b-switch off/g, 'b-switch');
  if (bodyEl.dataset.drawn !== body) {
    const same = bodyEl.dataset.drawn && shape(bodyEl.dataset.drawn) === shape(body);
    const wait = drawnAfter - Date.now();
    if (same || wait > 0) {
      const app = appOf(bk.page);
      for (const el of bodyEl.querySelectorAll('.b-switch[data-key]')) {
        const s = app?.switches.find((x) => x.key === el.dataset.key);
        el.setAttribute('aria-checked', String(!!s?.on));
        el.classList.toggle('off', s?.enabled === false);
      }
      if (same) bodyEl.dataset.drawn = body;
      else {
        clearTimeout(drawLater);
        drawLater = setTimeout(draw, wait);
      }
    } else {
      bodyEl.innerHTML = body;
      bodyEl.dataset.drawn = body;
    }
  }
  // A card's button set waiting by its press waits only for as long as the app says it does.
  const app = appOf(bk.page);
  for (const el of bodyEl.querySelectorAll('[data-status]'))
    el.disabled = !!statusView(app?.statuses?.find((s) => s.key === el.dataset.status))?.waits;
  markPointed();
}

// Another page of the back: what was there goes as the new one comes in, fading and lifting 3px, as the panel's do.
function go(page) {
  if (page === bk.page) return;
  bk.page = page;
  drawnAfter = 0;
  draw();
  bodyEl.scrollTop = 0;
  if (!calm()) bodyEl.animate([{ opacity: 0, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }],
                              { duration: 300, easing: 'cubic-bezier(.2, .8, .2, 1)' });
}

// What the pointer is on, marked as the panel's are (.is-hover): only what a press does something on.
const POINTED = '.b-tile, .b-switch:not(.off), .button:not(:disabled), .b-back, header .apps, header .chev';
function markPointed() {
  const at = bk.pointer, on = at ? document.elementFromPoint(at.x, at.y)?.closest(POINTED) : null;
  document.querySelectorAll('.is-hover').forEach((el) => { if (el !== on) el.classList.remove('is-hover'); });
  on?.classList.add('is-hover');
}

// ---- Presses ----

// A switch: it changes at once, and the app is told, which says how the apps are set now.
function press(key) {
  const apps = afterPress(bk.apps, bk.page, key);
  if (!apps) return;
  bk.apps = apps;
  drawnAfter = Date.now() + SLIDE_MS;
  draw();
  const on = appOf(bk.page).switches.find((s) => s.key === key).on;
  native({ type: 'appsSwitch', app: bk.page, key, on });
}

// mousedown, as the panel's are: the page can be drawn again between a press and its release.
backEl.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  e.preventDefault();
  const hit = (selector) => e.target.closest(selector);
  let el;
  if (hit('[data-turn]')) return native({ type: 'appsTurnBack' });
  if (hit('[data-fold]')) return native({ type: 'appsFold' });
  if (hit('[data-home]')) return go(null);
  if ((el = hit('.b-tile[data-app]'))) return go(el.dataset.app);
  if ((el = hit('.b-switch[data-key]'))) return press(el.dataset.key);
  // A card's button waits from the press until the app says how it went.
  if ((el = hit('[data-status]'))) {
    if (el.disabled) return;
    el.disabled = true;
    return native({ type: 'appsAction', app: bk.page, key: el.dataset.status });
  }
  if (hit('[data-open]')) return native({ type: 'appsOpen', app: bk.page });
  if (hit('[data-privacy]')) return native({ type: 'appsPrivacy', app: bk.page });
});

// ---- What the app calls ----

// The apps, in their order, and the panel's look from its Look menu, for the colours that match the panel's own.
window.setApps = (apps, look) => {
  bk.apps = Array.isArray(apps) ? apps : [];
  document.documentElement.dataset.look = look || 'grey';
  draw();
};

// Back on its list side: out of sight now, the back goes back to the apps for the next time it's turned over.
window.turned = (on) => {
  if (on) return;
  bk.page = null;
  bk.pointer = null;
  draw();
  bodyEl.scrollTop = 0;
};

// Where the pointer is on the page, from its top-left corner, or null once it has gone.
window.backPointer = (at) => {
  bk.pointer = at && Number.isFinite(at.x) && Number.isFinite(at.y) ? at : null;
  markPointed();
};
