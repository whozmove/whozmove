// The map beside the list: Storage's reader mode, about none of the sessions, with three tabs: Clean up
// (clean-view.js), the Map and Keys (keys-view.js). On the map, rings round the folder you're in, what's in it beside
// them, biggest first, with ＋ to collect it or what keeps it from going; and what's collected, under them, until Move
// to Trash, which asks once. The app measures the disk and sends a folder at a time (showFolder), and moves what's
// collected to the Trash, each checked again (storageTrashed).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const MAP_READER_WIDTH = 784;
const MAP_PLUS_ICON = '<svg viewBox="0 0 12 12" aria-hidden="true">'
  + '<path d="M6 2.2v7.6M2.2 6h7.6" stroke="currentColor" '
  + 'stroke-width="1.6" stroke-linecap="round"></path></svg>';
const MAP_TICK_ICON = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.6 6.3 5 8.6l4.4-5" fill="none" '
  + 'stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"></path></svg>';
// How long a folder asked for can take before the map says it's opening, in ms: the first look inside a folder can
// take a moment, and one that comes quicker than this shouldn't flicker.
const MAP_OPENING_AFTER = 150;
// How the map moves, in ms. A step in or out (mapStep): the rest of the old rings and the middle's words fade, then the
// piece pressed grows into the middle, and once it's there the folder's own rings and the middle's words come in; going
// out, the middle shrinks back into its piece the same way, the folder it's in coming in round it. The shape eases
// out; its colour keeps near its own till late. And ＋: what the foot said goes first, the name lifts off its row, then it comes in along the foot to its
// place there, and its chip comes in round it once it has landed.
const MAP_RINGS_GO_MS = 160, MAP_GROW_AFTER = 100, MAP_GROW_MS = 420, MAP_RINGS_IN_MS = 240;
const MAP_GROW_EASE = 'cubic-bezier(.33, 1, .68, 1)';  // 1 - (1 - p)³, as mapGrowFrames eases the shape
// The moving piece keeps near its own colour as long as it can: in, till late; out, from early. So the map is never
// left to the middle's faint colour while the rings change.
const MAP_TINT_EASE = 'cubic-bezier(.55, 0, 1, .45)', MAP_RINGS_FROM = 0.45;
const MAP_SAID_GO_MS = 120, MAP_LIFT_MS = 160, MAP_LAND_AFTER = 140, MAP_LAND_MS = 300, MAP_CHIP_IN_MS = 150;

moduleState({
  storage: null,  // whether Storage is on, and how its measuring is going (setStorage)
  map: null,      // the folder shown, as the app sent it (showFolder)
});
// What the map shows now: its tab (map or clean), the folder asked for, and the one being opened in place of the
// folder shown (`{id, name, shown}`, shown once it has taken a moment), what the pointer is on, what's collected and
// whether Move to Trash is asking, and what the last move said (in green when all of it went); the measure it last
// started over for, the first pass it last asked Clean up again for, and when the folders agents work in last changed,
// as the app said; whether a row's Allow Access (or Keys' Allow Full Disk Access) has been pressed, and Install for
// Apple's developer tools; what was drawn last (its tab and folder), so a new one fades in; the step in or out a
// folder is drawn with (mapStep, showFolder, mapGrow); and what ＋ was pressed beside, to land at the foot once the
// foot is drawn (mapLand).
const mapPage = { view: 'clean', asked: 0, opening: null, pointed: null, tray: [], confirm: false, askedAt: 0,
                  said: null, allWent: false, resetFor: null, busyAt: 0, usualFor: null, allowAsked: false,
                  toolsAsked: false, drawn: null, step: null, landing: null };

const mapReading = () => state.reading?.mode === 'storage' && !state.reading.closing;
const mapItem = (id) => state.map?.kids.find((k) => k.id === id);

// ---- Drawing ----

// Its head follows the tab: the disk on the Map and Clean up, and what Keys is about on Keys.
function mapHeadHTML() {
  if (mapPage.view === 'keys') {
    return `<span class="map-head-mark keys">${KEY_ICON}</span><span class="r-title">Storage</span>`
      + '<span class="r-sub">Keys left where they shouldn’t be</span>'
      + `<button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
  }
  const d = state.disk, free = d ? ` · ${mapSize(d.free)} free of ${mapSize(d.total)}` : '';
  return `<span class="map-head-mark">${DISK_ICON}</span><span class="r-title">Storage</span>`
    + `<span class="r-sub">${esc(state.map?.path?.[0]?.name || 'Your disk')}${free}</span>`
    + `<button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
}

// When the disk was measured, or how far the measuring has got, against what's in use, with a bar.
function mapMeasuredHTML() {
  const s = state.storage || {};
  if (s.scanning) {
    const p = mapProgress(s.counted || 0, state.disk);
    return `<span class="map-measured">Measuring… ${esc(p.words)}</span>${p.share === null ? ''
      : `<span class="bar map-progress"><i style="width: ${(p.share * 100).toFixed(1)}%"></i></span>`}`;
  }
  if (!s.scannedAt) return '';
  // While Clean up cleans, measuring again waits: a new map would take away what its rows are saying.
  return `<span class="map-measured">Measured ${storageAgo(s.scannedAt, Date.now())}</span>`
    + (cleanPage.cleaning ? '<button class="button quiet map-again" disabled title="Waits until Clean up is done">'
      + 'Measure Again</button>' : '<button class="button quiet map-again" data-map-again="1">Measure Again</button>');
}

// Before there's a map to show: measuring, about to show the one there is, or none yet.
const mapMeasuringWords = () => (state.storage?.scanning ? 'Measuring your disk. The first time takes a minute or '
  + 'two. You can close the map: a line above your sessions will tell you when it’s ready.'
  : state.storage?.scannedAt ? 'Opening the map…' : 'Nothing measured yet.');

// The three tabs, Clean up first, with how much can come back ("so far" while the disk is still measured, as
// projects' built files join it), and Keys' with how many keys count (all but those most likely made up), in the
// colour of something wrong while one has left this Mac, else your move's, so the two counts never read alike.
function mapTabsHTML() {
  const all = state.cleanUp ? cleanSums(state.cleanUp, cleanPage.ticked).all : 0;
  const counted = keysCounted(state.keys), keys = counted.length;
  const soon = counted.every((key) => keysBand(key) !== 'now') ? ' soon' : '';
  const tab = (view, words) => `<button data-map-view="${view}" aria-pressed="${mapPage.view === view}">${words}`
    + '</button>';
  return `<div class="tabs" role="group">`
    + `${tab('clean', `Clean up${all ? ` <span class="map-tab-count">${mapSize(all)}`
      + `${state.storage?.scanning ? ' so far' : ''}</span>` : ''}`)}`
    + `${tab('map', 'Map')}`
    + `${tab('keys', `Keys${keys ? ` <span class="map-tab-count keys${soon}">${keys}</span>` : ''}`)}</div>`;
}

// Where you are; and a folder further in that's opening, once it has taken a moment, on its way there, shining until
// it comes.
function mapCrumbsHTML(view) {
  const path = view.path || [], trail = mapPage.opening?.shown ? mapPage.opening.trail : [];
  const going = trail.map((name) => `<span class="map-sep">${GO_ICON}</span><span class="map-going">`
    + `${shineHTML(name)}</span>`).join('');
  return path.map((c, i) => (i === path.length - 1 ? `<span class="map-crumb here">${esc(c.name)}</span>`
    : `<button class="button quiet map-crumb" data-map-up="${c.id}">${esc(c.name)}</button>`
      + `<span class="map-sep">${GO_ICON}</span>`)).join('') + going;
}

// The middle: the folder you're in, or what the pointer is on, with its size and its share; or the folder being
// opened, once it has taken a moment.
function mapMiddleHTML(view) {
  if (mapPage.opening?.shown) {
    return `<b>${esc(mapPage.opening.name)}</b><span>${shineHTML('Opening…')}</span>`;
  }
  const p = mapPage.pointed, parent = view.path?.length > 1 ? view.path[view.path.length - 2] : null;
  if (p) {
    const share = view.size ? Math.max(1, Math.round(100 * p.size / view.size)) : 0;
    return `<b>${esc(p.name)}</b><span>${p.unread ? '?' : mapSize(p.size)}</span>`
      + `<i>${p.unread ? "Can't look inside" : `${share}% of ${esc(view.name)}`}</i>`;
  }
  return `<b>${esc(view.name)}</b><span>${mapSize(view.size)}</span>`
    + `<i>${parent ? `Press here for ${esc(parent.name)}` : `${state.disk ? mapSize(state.disk.free) : ''} free`}</i>`;
}

// A piece of the rings, or a part in the list, collected for the Trash: it, or a folder it's in and not taken out of.
const mapPicked = (part, within) => !!mapHolder(mapPage.tray, part.id, within);

function mapRingsHTML(view) {
  const c = MAP_BOX / 2, within = (view.path || []).map((p) => p.id);
  const pieces = mapArcs(view).map((arc) => {
    const [r0, r1] = mapRadii(arc.depth);
    const node = arc.part.id === null ? '' : ` data-map-node="${arc.part.id}"`;
    const picked = mapPicked(arc.part, [...within, ...arc.within]);
    return `<path class="map-seg ${mapTint(arc)}${picked ? ' picked' : ''}"${node} `
      + `d="${mapArcPath(arc.a0, arc.a1, r0, r1)}"></path>`;
  }).join('');
  const parent = view.path?.length > 1 ? view.path[view.path.length - 2] : null;
  return `<div class="map-rings"><svg width="${MAP_BOX}" height="${MAP_BOX}" viewBox="0 0 ${MAP_BOX} ${MAP_BOX}">`
    + `${pieces}<circle class="map-middle${parent ? ' up' : ''}"${parent ? ` data-map-up="${parent.id}"` : ''} `
    + `cx="${c}" cy="${c}" r="${MAP_MIDDLE - 3}"></circle></svg><div class="map-middle-words">${mapMiddleHTML(view)}`
    + '</div></div>';
}

// What's in the folder, biggest first: its colour on the rings, its size and its share, and ＋ to collect it; one
// that can't go keeps the kit's ＋ hidden, so the sizes stay in line, and says what keeps it under its name (small
// items go only with their folder). One unread for want of Full Disk Access has the one way to allow it under its
// reason, and once that's been pressed, what to do where macOS hasn't listed Whozmove, its words wrapping to be read
// whole. The folder being opened says so there instead, once it has taken a moment.
function mapListHTML(view) {
  const within = (view.path || []).map((p) => p.id);
  // Each part's colour is its piece's on the rings: counted in turn, small items taking the colour of the turn
  // they're at.
  let index = 0;
  const items = view.kids.map((k) => {
    const hue = index % 6;
    if (!k.rest) index++;
    const tint = k.grey ? 'grey' : `h${hue}${k.rest ? ' rest' : ''}`;
    const share = view.size ? k.size / view.size : 0;
    const picked = k.id !== null && mapPicked(k, within);
    const end = k.rest || k.lock
      ? `<button class="icon-button map-add none" aria-hidden="true">${MAP_PLUS_ICON}</button>`
      : `<button class="icon-button map-add${picked ? ' in' : ''}" data-map-add="${k.id}" title="${picked ? 'Keep it'
        : 'Collect it for the Trash'}">${picked ? MAP_TICK_ICON : MAP_PLUS_ICON}</button>`;
    const opening = mapPage.opening?.shown && mapPage.opening.id === k.id;
    const asked = k.allow && mapPage.allowAsked
      ? 'In System Settings, turn Whozmove on. Not in the list? Press + under the list there and choose Whozmove.' : '';
    const note = opening ? shineHTML('Opening…') : asked ? esc(asked) : k.lock ? esc(k.lock.says) : '';
    const go = k.folder && !k.unread ? GO_ICON : '';
    const allow = k.allow ? '<button class="button small map-allow" data-map-allow="1">Allow Access</button>' : '';
    return `<div class="map-item${k.lock ? ' locked' : ''}${k.rest ? ' rest' : ''}${k.allow ? ' allow' : ''}"`
      + `${k.id === null ? '' : ` data-map-node="${k.id}"`}><i class="map-swatch ${tint}"></i>`
      + `<span class="map-item-words"><b>${esc(k.name)}</b>${note ? `<small>${note}</small>` : ''}${allow}</span>`
      + `<span class="map-item-size">${k.unread ? '?' : mapSize(k.size)}<span class="bar map-share"><i style="width: `
      + `${(Math.max(0.02, share) * 100).toFixed(1)}%"></i></span></span><span class="map-go">${go}</span>${end}</div>`;
  }).join('');
  return `<div class="map-list"><div class="caps map-list-head"><span>In ${esc(view.name)}</span>`
    + `<span>${mapSize(view.size)}</span></div><div class="map-room"><div class="map-items">${items}</div></div></div>`;
}

function mapBodyHTML() {
  const view = state.map, s = state.storage || {};
  const status = mapPage.view === 'keys' ? keysStatusHTML() : mapMeasuredHTML();
  const top = `<div class="map-top">${mapTabsHTML()}<span class="map-status">${status}</span></div>`;
  if (mapPage.view === 'keys') return `<div class="map">${top}${keysBodyHTML()}</div>`;
  // Keys opens whether the map is on or not; until it is, its two tabs say what turning it on does, with the button
  // that does, the press being the yes.
  if (!s.on) {
    return `<div class="map">${top}<p class="map-empty">Clean up and the map measure your disk’s sizes, never what’s `
      + 'in your files. It takes a minute or two, and stays on this Mac.</p><p class="map-empty">'
      + '<button class="button" data-map-on="1">Map My Disk</button></p></div>';
  }
  if (mapPage.view === 'clean') return `<div class="map">${top}${cleanBodyHTML()}</div>`;
  if (!view) return `<div class="map">${top}<p class="map-empty">${mapMeasuringWords()}</p></div>`;
  // While a checkout here waits for Apple's developer tools (git isn't run before they're there), the way to
  // install them; once that's been pressed, what macOS does next, with Install still there should it be closed.
  const tools = view.tools ? mapToolsHTML() : '';
  // The list beside the rings takes all the height the panel has (storage.css).
  return `<div class="map fills">${top}<div class="map-crumbs">${mapCrumbsHTML(view)}</div>${tools}`
    + `<div class="map-main">${mapRingsHTML(view)}${mapListHTML(view)}</div></div>`;
}

// Under the map: what's collected, each with its ×, its total and Move to Trash; Move to Trash's question; or what the
// last move said.
function mapTrayHTML() {
  const tray = mapPage.tray;
  // Until there's a map, there's nothing to collect.
  if (!state.map && !mapPage.said) return '<div class="tray"></div>';
  if (!tray.length) {
    return `<div class="tray"><span class="tray-said${mapPage.allWent ? ' done' : ''}">${esc(mapPage.said
      || 'Press ＋ beside anything you want gone. It waits here until you move it to the Trash.')}</span></div>`;
  }
  const total = tray.reduce((sum, t) => sum + mapFrees(t), 0);
  const many = tray.length === 1 ? '1 item' : `${tray.length} items`;
  if (mapPage.confirm) {
    return `<div class="tray"><span class="tray-ask"><b>Move ${many} to the Trash?</b><i>${mapSize(total)} comes `
      + 'back once you empty the Trash. Until then, you can put any of it back.</i></span>'
      + '<button class="button" data-map-cancel="1">Cancel</button>'
      + '<button class="button main" data-map-yes="1">Confirm</button></div>';
  }
  // A folder with parts taken back out of it says which, or how many.
  const but = (t) => (!t.out.length ? ''
    : `<i>but ${t.out.length === 1 ? esc(t.out[0].name) : `${t.out.length} parts`}</i>`);
  const chips = tray.map((t) => `<span class="map-chip"><b>${esc(t.name)}</b>${but(t)}`
    + `<span>${mapSize(mapFrees(t))}</span>`
    + `<button class="icon-button small map-chip-x" data-map-unpick="${t.id}" title="Keep it">${CLOSE_ICON}</button>`
    + '</span>').join('');
  return `<div class="tray"><span class="map-chips">${chips}</span><span class="tray-total">${many} · `
    + `<b>${mapSize(total)}</b></span><button class="button main" data-map-trash="1">Move to Trash</button></div>`;
}

function mapDraw() {
  const r = state.reading;
  putHTML(reader.querySelector('.r-head'), mapHeadHTML());
  // What the pointer is on changes only the middle's words, which mapPoint puts right in place; so the map is drawn
  // again only when what's compared, drawn as if nothing were pointed at, has changed, never in the middle of a move.
  const body = reader.querySelector('.r-body'), pointed = mapPage.pointed;
  mapPage.pointed = null;
  const settled = mapBodyHTML();
  mapPage.pointed = pointed;
  if (body.dataset.drawn !== settled) {
    const items = body.querySelector('.map-items'), top = items?.scrollTop || 0;
    body.innerHTML = pointed ? mapBodyHTML() : settled;
    body.dataset.drawn = settled;
    const again = body.querySelector('.map-items');
    if (again && mapPage.keepList) again.scrollTop = top;
    // What the pointer is on stays marked on the rings and in the list (mapPoint), as the pointer hasn't moved.
    if (mapPage.pointed) {
      body.querySelectorAll(`[data-map-node="${mapPage.pointed.id}"]`).forEach((el) => el.classList.add('on'));
    }
    // Another folder, or the other tab, comes in the panel's way: fading in, lifting 3px; a step in or out (mapStep)
    // has its rings move instead (mapGrow), the list beside them coming in so.
    const now = `${mapPage.view}:${state.map?.id ?? ''}`, step = mapPage.step;
    mapPage.step = null;
    if (mapPage.drawn && mapPage.drawn !== now && !calm.matches) {
      body.querySelector(step ? '.map-list' : '.map-main, .clean')?.animate(
        [{ opacity: 0, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }],
        { duration: 300, easing: MORPH_EASE });
    }
    if (step && mapPage.drawn !== now) mapGrow(step);
    mapPage.drawn = now;
  }
  mapPage.keepList = false;
  putHTML(reader.querySelector('.r-answer'), mapPage.view === 'keys' ? keysFootHTML()
    : mapPage.view === 'clean' ? cleanFootHTML() : mapTrayHTML());
  if (mapPage.landing) mapLand(mapPage.landing);
  mapPage.landing = null;
  r.ready = true;
  fitReader();
  syncHover();
}

// ---- Moving ----

// A piece's fill as drawn, to ease the moving one's from its own to the middle's.
const mapFillOf = (el) => { const cs = getComputedStyle(el); return { fill: cs.fill, fillOpacity: cs.fillOpacity }; };

// Kept from sight until let go (`.cancel()`), whatever else animates it: what waits for the moving piece to land.
const mapHeld = (el) => el?.animate([{ opacity: 0 }, { opacity: 0 }], { duration: 60000 });

// The moving piece's shape, frame by frame, `from` and `to` as mapGrowPath's `t`, after MAP_GROW_AFTER, easing out as
// MAP_GROW_EASE does; it stops if the map is drawn again under it.
function mapGrowFrames(el, arc, from, to) {
  const start = performance.now() + MAP_GROW_AFTER;
  const step = (now) => {
    const p = Math.max(0, Math.min(1, (now - start) / MAP_GROW_MS)), e = 1 - (1 - p) ** 3;
    el.setAttribute('d', mapGrowPath(arc, from + (to - from) * e));
    if (p < 1 && el.isConnected) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

// A step in or out of a folder (mapStep), as it's drawn (mapDraw): the old rings and the middle's words, `copy` and
// `words`, laid over the new ones and fading but for what moves. In, the piece pressed (`arc`, on the old rings) grows
// into the middle, its fill becoming the middle's; out, the middle, as a piece of its own, shrinks back into its piece
// of the folder it's in (`arc`, on the new rings). What waits for it is held from sight, and let go in the frame it
// lands, with the copy gone in that frame too; the new rings take no press until then, as they can't be seen. What's
// there before and after moves; the rest fades. Under reduced motion, a cross-fade.
function mapGrow({ arc, down, copy, words: oldWords }) {
  const rings = reader.querySelector('.map-rings'), svg = rings?.querySelector('svg');
  if (!svg) return;
  copy.classList.add('map-was');
  rings.append(copy, ...(oldWords ? [oldWords] : []));
  oldWords?.classList.add('map-was');
  const fade = (el, from, to, ms, delay = 0) => el?.animate([{ opacity: from }, { opacity: to }],
                                                            { duration: ms, delay, fill: 'backwards' });
  const gone = () => { copy.remove(); oldWords?.remove(); };
  if (calm.matches) {
    for (const el of [copy, oldWords]) {
      el?.animate([{ opacity: 1 }, { opacity: 0 }], { duration: MAP_RINGS_IN_MS, fill: 'forwards' });
    }
    fade(svg, 0, 1, MAP_RINGS_IN_MS).finished.then(gone, gone);
    fade(rings.querySelector('.map-middle-words'), 0, 1, MAP_RINGS_IN_MS);
    return;
  }
  const words = rings.querySelector('.map-middle-words'), middle = svg.querySelector('.map-middle');
  const segs = [...svg.querySelectorAll('.map-seg')];
  const fadeOut = (el) => el?.animate([{ opacity: 1 }, { opacity: 0 }],
                                       { duration: MAP_RINGS_GO_MS, fill: 'forwards' });
  svg.style.pointerEvents = 'none';
  fadeOut(oldWords);
  // The moving piece: in, the pressed piece on the copy; out, a new piece drawn on the copy as the middle, in the
  // colour of the piece it lands as.
  const landsOn = down ? null : svg.querySelector(`.map-seg[data-map-node="${arc.part.id}"]`);
  let moving = down ? copy.querySelector(`.map-seg[data-map-node="${arc.part.id}"]`) : null;
  if (!down) {
    moving = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    moving.setAttribute('class', (landsOn?.getAttribute('class') ?? 'map-seg').replace(/\bon\b/, ''));
    moving.setAttribute('d', mapGrowPath(arc, 1));
    copy.appendChild(moving);
  }
  copy.querySelectorAll('.map-seg, .map-middle').forEach((el) => { if (el !== moving) fadeOut(el); });
  // Held till it lands: in, the new middle and its words; out, the piece it lands as. Coming in round it as it moves,
  // so the map is never left empty: in, the folder's own rings from about halfway; out, the rest of the folder's rings
  // and its middle as the shape starts to shrink, and its words once the old ones have gone.
  const held = (down ? [middle, words] : [landsOn]).filter(Boolean).map(mapHeld);
  if (down) segs.forEach((el) => fade(el, 0, 1, MAP_RINGS_IN_MS, MAP_GROW_AFTER + MAP_GROW_MS * MAP_RINGS_FROM));
  else {
    [middle, ...segs.filter((el) => el !== landsOn)].forEach((el) => fade(el, 0, 1, MAP_RINGS_IN_MS, MAP_GROW_AFTER));
    fade(words, 0, 1, MAP_RINGS_IN_MS, MAP_RINGS_GO_MS);
  }
  const land = () => {
    held.forEach((a) => a.cancel());
    gone();
    svg.style.pointerEvents = '';
    if (!down) return;
    words?.animate([{ opacity: 0, transform: 'translate(-50%, calc(-50% + 3px))' },
                    { opacity: 1, transform: 'translate(-50%, -50%)' }],
                   { duration: MAP_RINGS_IN_MS, easing: MORPH_EASE });
  };
  if (!moving) return land();
  moving.classList.remove('on');
  const from = mapFillOf(down ? moving : middle), to = mapFillOf(down ? middle : landsOn ?? moving);
  mapGrowFrames(moving, arc, down ? 0 : 1, down ? 1 : 0);
  moving.animate([from, to], { duration: MAP_GROW_MS, delay: MAP_GROW_AFTER, easing: down ? MAP_TINT_EASE : MAP_GROW_EASE,
                               fill: 'both' })
    .finished.then(land, land);
}

// Where ＋ was pressed, measured before the foot is drawn again (the ＋ press), for mapLand: the item's name on its row
// (a copy of it, its place and look there), and what the foot said before (its line, or Move to Trash's question).
function mapLanding(id, plus) {
  const name = plus.closest('.map-item')?.querySelector('.map-item-words b');
  if (!name) return null;
  const said = reader.querySelector('.r-answer .tray-said, .r-answer .tray-ask'), cs = getComputedStyle(name);
  return { id, name: name.cloneNode(true), rect: name.getBoundingClientRect(), look: { font: cs.font, color: cs.color },
           said: said && { el: said.cloneNode(true), rect: said.getBoundingClientRect() } };
}

// A copy of something laid over the page at `rect`, as wide as that, gone after `ms`, for mapLand: a name in the
// `look` it had ({ font, color }), on one line cut short with "…" as it is there; the foot's line as it was laid out.
function mapFlying(el, rect, ms, look) {
  el.classList.add('map-flying');
  Object.assign(el.style, { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px` },
                look ? { font: look.font, color: look.color, display: 'block', whiteSpace: 'nowrap',
                         overflow: 'hidden', textOverflow: 'ellipsis' } : {});
  document.body.appendChild(el);
  setTimeout(() => el.remove(), ms);
  return el;
}

// ＋'s item, landing in what's collected at the foot. What the foot said before goes first, so the chips' line is clear;
// a copy of the name lifts off its row and fades there, the row's own name coming back in under it; then, measured as
// the foot is by then (a new line of chips included), it comes in at the foot where it left the row, after the chips
// already on its own line, and slides along that line to its place, where its chip comes in round it once it has
// landed. It never crosses the list's words, another chip, or its own. A ＋ pressed again meanwhile lands its own name;
// one still on its way is put where it was going. Under reduced motion, the chip fades in.
function mapLand(landing) {
  document.querySelectorAll('.map-flying').forEach((el) => el.remove());
  const chip = reader.querySelector(`.r-answer [data-map-unpick="${landing.id}"]`)?.closest('.map-chip');
  if (!chip?.querySelector('b')) return;
  if (calm.matches) return chip.animate([{ opacity: 0 }, { opacity: 1 }], { duration: MAP_RINGS_IN_MS });
  if (landing.said) {
    mapFlying(landing.said.el, landing.said.rect, MAP_SAID_GO_MS)
      .animate([{ opacity: 1 }, { opacity: 0 }], { duration: MAP_SAID_GO_MS, fill: 'forwards' });
  }
  mapFlying(landing.name.cloneNode(true), landing.rect, MAP_LIFT_MS, landing.look)
    .animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-3px)' }],
             { duration: MAP_LIFT_MS, easing: 'ease-out', fill: 'forwards' });
  reader.querySelector(`.map-item[data-map-node="${landing.id}"] .map-item-words b`)
    ?.animate([{ opacity: 0 }, { opacity: 1 }], { duration: MAP_LIFT_MS, easing: 'ease-in' });
  const held = mapHeld(chip);
  setTimeout(() => {
    const name = chip.querySelector('b'), lane = reader.querySelector('.r-answer .map-chips');
    if (!chip.isConnected || !name || !lane) return held.cancel();
    const to = name.getBoundingClientRect(), room = lane.getBoundingClientRect(), line = chip.getBoundingClientRect();
    const before = [...lane.querySelectorAll('.map-chip')].filter((c) => c !== chip)
      .map((c) => c.getBoundingClientRect()).filter((r) => Math.abs(r.top - line.top) < 2).map((r) => r.right);
    const from = Math.min(Math.max(landing.rect.left, Math.max(0, ...before) + 8, to.left), room.right - to.width);
    const cs = getComputedStyle(name);
    const flying = mapFlying(landing.name.cloneNode(true), { left: from, top: to.top, width: to.width },
                             MAP_LAND_MS + MAP_CHIP_IN_MS + 40, { font: cs.font, color: cs.color });
    const landed = () => {
      held.cancel();
      if (!chip.isConnected) return flying.remove();
      chip.animate([{ opacity: 0 }, { opacity: 1 }], { duration: MAP_CHIP_IN_MS })
        .finished.then(() => flying.remove(), () => flying.remove());
      name.animate([{ opacity: 0 }, { opacity: 0 }], { duration: MAP_CHIP_IN_MS });
    };
    flying.animate([{ opacity: 0, transform: 'none' }, { opacity: 1, transform: `translateX(${to.left - from}px)` }],
                   { duration: MAP_LAND_MS, easing: MORPH_EASE, fill: 'both' }).finished.then(landed, landed);
  }, MAP_LAND_AFTER);
}

core.readerModes.storage = {
  sessionless: true,
  width: () => MAP_READER_WIDTH,
  // What the map needs, not the room it fills: the list beside the rings takes whatever height the panel has, so the
  // map asks for its rings' height and what's above them. Clean up asks for all it shows.
  contentHeight(page) {
    const main = page?.querySelector('.map-main'), rings = main?.querySelector('.map-rings');
    return main && rings ? page.offsetHeight - main.offsetHeight + rings.offsetHeight : undefined;
  },
  draw: mapDraw,
  // Opening, it asks for the disk and what can come back, and starts with nothing collected. What Clean up last said
  // stays until it's been seen, and says so while it's still cleaning.
  shown() {
    Object.assign(mapPage, { opening: null, pointed: null, tray: [], confirm: false, said: null, allWent: false,
                             resetFor: null, drawn: null });
    cleanPage.confirm = false;
    Object.assign(keysPage, { confirm: null, said: null });
    if (state.storage?.on) {
      mapAsk(0);
      cleanAsk();
    }
    drawStorageLine();
  },
  // Closed, or turned to another mode, the line above the list may say again what it held back while Storage was open
  // (once the reader has moved on).
  closed() {
    cleanPage.turnedOn = false;
    cleanPage.went = {};
    if (!cleanPage.cleaning) cleanPage.steps = {};
    drawStorageLine();
  },
  reset() {
    mapPage.pointed = null;
    setTimeout(drawStorageLine, 0);
  },
  cls: 'k-storage',
};

// Asks the app for a folder. One that isn't the folder shown is being opened: if it takes a moment, the middle says so,
// by its name, from the folder shown, as do its row in the list and, for one further in, the crumbs, until it comes
// (showFolder). What's shown stays as it is meanwhile, the list scrolled where it was.
function mapAsk(id) {
  mapPage.asked = id;
  const shown = state.map, opening = shown && id !== shown.id;
  const trail = opening && mapTrail(shown.kids, id);
  mapPage.opening = opening ? { id, name: shown.path?.find((c) => c.id === id)?.name
    ?? (trail ? trail[trail.length - 1].name : ''), trail: (trail || []).map((p) => p.name), shown: false } : null;
  if (opening) {
    setTimeout(() => {
      if (mapPage.opening?.id !== id || !mapReading()) return;
      mapPage.opening.shown = true;
      mapPage.keepList = true;
      drawReader();
    }, MAP_OPENING_AFTER);
  }
  native({ type: 'storageFolder', id });
}

// Asks the app again for the folder last asked for, as what's in it may have changed (an agent started or stopped work,
// or something left it): the folder shown, or the one being opened, which goes on saying so until it comes. Asking for
// the folder shown instead would leave the one pressed never opening.
function mapAskAgain() {
  native({ type: 'storageFolder', id: mapPage.asked });
}

// ---- The pointer ----

// What the pointer is on, on the rings or in the list, is marked in both, and the middle says what it is: one of the
// folder's own parts, or a piece further out.
function mapPoint(id) {
  const part = id === null ? null : mapFind(state.map?.kids, id);
  if (mapPage.pointed === part) return;
  mapPage.pointed = part;
  reader.querySelectorAll('.map-seg.on, .map-item.on').forEach((el) => el.classList.remove('on'));
  if (part) reader.querySelectorAll(`[data-map-node="${part.id}"]`).forEach((el) => el.classList.add('on'));
  // While a folder is opening, the middle says so whatever the pointer is on, and its shine carries on.
  const words = reader.querySelector('.map-middle-words');
  if (words && state.map && !mapPage.opening?.shown) words.innerHTML = mapMiddleHTML(state.map);
}
core.pointerWatchers.push((el) => {
  if (!mapReading() || !state.map) return;
  const on = el?.closest?.('[data-map-node]');
  mapPoint(on && reader.contains(on) ? Number(on.dataset.mapNode) : null);
});
core.pointerTargets.push('[data-map-on]', '[data-map-allow]', '.map-need .button', '.map-crumb', '.map-middle.up',
  '.map-item', '.map-add:not(.none)',
  '.map-chip-x',
  '.map-again');

// ---- Presses ----

core.readerPresses.push(
  ['[data-map-add]', (el) => {
    const id = Number(el.dataset.mapAdd), item = mapItem(id);
    if (!item || item.lock || item.rest) return;
    const within = (state.map.path || []).map((p) => p.id);
    // Collected (not let go of), its name lands in what's collected at the foot (mapLand), measured from its row now.
    const landing = el.classList.contains('in') ? null : mapLanding(id, el);
    mapPage.tray = mapToggle(mapPage.tray, { id, name: item.name, size: item.size }, within);
    Object.assign(mapPage, { confirm: false, said: null, allWent: false, keepList: true, landing });
    drawReader();
  }],
  ['[data-map-unpick]', (el) => {
    mapPage.tray = mapPage.tray.filter((t) => t.id !== Number(el.dataset.mapUnpick));
    Object.assign(mapPage, { confirm: false, keepList: true });
    drawReader();
  }],
  // The question comes where Move to Trash was: a press on it that comes sooner after it than a press that's seen it
  // (fresh.js's FRESH_MS) doesn't count, so a double click can't answer it. Its time is kept here, not with the
  // sessions' cards, which forget what isn't a session's.
  ['[data-map-trash]', () => {
    mapPage.confirm = true;
    mapPage.askedAt = Date.now();
    drawReader();
  }],
  ['[data-map-cancel]', () => { mapPage.confirm = false; drawReader(); }],
  ['[data-map-yes]', () => {
    if (Date.now() - mapPage.askedAt < FRESH_MS) return;
    // Each collected part by its id, and for a folder with parts taken back out of it, theirs, which stay; and the map
    // they're on, so nothing goes if it's been measured again since.
    const keep = Object.fromEntries(mapPage.tray.filter((t) => t.out.length)
      .map((t) => [t.id, t.out.map((o) => o.id)]));
    native({ type: 'storageTrash', ids: mapPage.tray.map((t) => t.id), keep, measuredAt: state.map?.scannedAt || 0 });
    Object.assign(mapPage, { tray: [], confirm: false, said: 'Moving to the Trash…', allWent: false });
    drawReader();
  }],
  ['[data-map-again]', () => native({ type: 'storageMeasure' })],
  ['[data-map-view]', (el) => {
    if (mapPage.view === el.dataset.mapView) return;
    mapPage.view = ['clean', 'keys'].includes(el.dataset.mapView) ? el.dataset.mapView : 'map';
    if (mapPage.view === 'clean' && state.storage?.on) cleanAsk();
    if (mapPage.view === 'map' && state.storage?.on && !state.map) mapAsk(0);
    drawReader();
  }],
  // While the map is off: Map My Disk turns it on, here, on the tab it's pressed on.
  ['[data-map-on]', () => native({ type: 'storageOn', view: mapPage.view })],
  ['[data-map-allow]', () => {
    mapPage.allowAsked = true;
    native({ type: 'storageAllow' });
    drawReader();
  }],
  // The install module's own: macOS's installer for Apple's developer tools, as Keys offers it too.
  ['[data-map-tools]', () => {
    mapPage.toolsAsked = true;
    native({ type: 'install', action: 'tools' });
    drawReader();
  }],
  ['[data-map-up]', (el) => mapAsk(Number(el.dataset.mapUp))],
  // A folder opens in the middle; anything else shows in Finder.
  ['[data-map-node]', (el) => {
    const part = mapFind(state.map?.kids, Number(el.dataset.mapNode));
    if (!part) return;
    if (part.folder && !part.unread) return mapAsk(part.id);
    if (!part.unread) native({ type: 'storageReveal', id: part.id });
  }],
);

// ---- What the app calls ----

// Whether Storage is on, how its measuring is going, whether the map you were waiting for is ready (the line under the
// header says so), and when the folders agents work in last changed. Turned off, what the map knew is deleted, here
// too, and the map closes. Measured anew, the map starts again from the disk, once, what's shown staying until the new
// disk comes, and what was collected put back, saying so. When agents start or stop work, what's shown is asked for
// again, for its locks. While it's measuring, only how far it has got changes, in place.
window.setStorage = (s) => {
  const wasOn = !!state.storage?.on;
  state.storage = s;
  drawStorageLine();
  if (!s?.on) {
    state.map = state.cleanUp = null;
    Object.assign(mapPage, { opening: null, tray: [], confirm: false, said: null, allWent: false, resetFor: null,
                             allowAsked: false, toolsAsked: false });
    Object.assign(cleanPage, { ticked: new Set(), seen: new Set(), confirm: false, said: null, allWent: false,
                               cleaning: false });
    // Turned off while it's open, the map closes, but Keys stays: it doesn't need the map. Told again that it's off
    // (as agents start or stop work), nothing closes.
    if (mapReading() && wasOn && mapPage.view !== 'keys') closeReader();
    else if (mapReading()) drawReader();
    return;
  }
  if (!mapReading()) return;
  if (!s.scanning && s.scannedAt && s.scannedAt !== state.map?.scannedAt && s.scannedAt !== mapPage.resetFor) {
    const had = mapPage.tray.length > 0 && state.map;
    Object.assign(mapPage, { resetFor: s.scannedAt, tray: [], confirm: false, allWent: false,
                             said: had ? 'The map was measured again: what you collected was put back.' : mapPage.said });
    mapAsk(0);
    cleanAsk();
    return drawReader();
  }
  // The first pass's usual places, measured before the first map: Clean up asks again, to list them.
  if (s.usualAt && s.usualAt !== mapPage.usualFor) {
    mapPage.usualFor = s.usualAt;
    cleanAsk();
  }
  if (s.busyAt && s.busyAt !== mapPage.busyAt) {
    mapPage.busyAt = s.busyAt;
    if (state.map && mapPage.view === 'map') mapAskAgain();
    if (mapPage.view === 'clean') cleanAsk();
  }
  const status = reader.querySelector('.map-status');
  if (status && (state.map || mapPage.view !== 'map')) {
    status.innerHTML = mapPage.view === 'keys' ? keysStatusHTML() : mapMeasuredHTML();
  } else drawReader();
};

// The notice while checkouts wait for Apple's developer tools, the map's and Clean up's: why, and Install (the install
// module's own, as Keys offers it); once pressed, what macOS does next.
function mapToolsHTML() {
  return '<div class="notice boxed map-need"><span class="notice-text">'
    + `${mapPage.toolsAsked ? 'macOS asks whether to install them, in a window of its own. The map looks at your '
      + 'checkouts again once they’re in.' : 'Your checkouts stay where they are until Apple’s developer tools are '
      + 'in, as git can’t say what they hold before then.'}</span>`
    + '<button class="button small" data-map-tools="1">Install</button></div>';
}

// A folder, as asked for (null once it's gone from the map: the disk is shown instead; and no disk, no map).
window.showFolder = (id, view) => {
  if (id !== mapPage.asked || !mapReading()) return;
  mapPage.opening = null;
  if (!view && id !== 0) return mapAsk(0);
  if (!view) {
    state.map = null;
    return drawReader();
  }
  // A step in or out (mapStep), on the map, has its rings move as it's drawn (mapDraw, mapGrow), from a copy of the old
  // rings and the middle's words.
  const step = mapPage.view === 'map' ? mapStep(state.map, view) : null, rings = reader.querySelector('.map-rings');
  const copy = step && rings?.querySelector('svg')?.cloneNode(true);
  mapPage.step = copy ? { ...step, copy, words: rings.querySelector('.map-middle-words')?.cloneNode(true) } : null;
  state.map = view;
  mapPage.pointed = null;
  drawReader();
};

// What moving to the Trash did: what went, and why anything didn't. The folder is asked for again, as it's smaller now.
window.storageTrashed = (result) => {
  const moved = result.moved || [], refused = result.refused || [];
  const went = moved.length ? `Moved ${moved.length === 1 ? moved[0] : `${moved.length} items`} to the Trash: `
    + `${mapSize(result.size || 0)} comes back once you empty it.` : '';
  const kept = refused.map((r) => `${r.name} stayed: ${String(r.why).replace(/\.$/, '')}.`).join(' ');
  mapPage.said = [went, kept].filter(Boolean).join(' ') || 'Nothing moved.';
  mapPage.allWent = !refused.length && moved.length > 0;
  if (state.map) mapAskAgain();
  if (mapReading()) drawReader();
};

// Storage, beside the list, on its tab: Clean up (the low-disk line, and Clean Up on Storage's page on the panel's
// back), the Map (the line saying it's ready, and Open the Map) or Keys (the line about keys), which opens whether the
// map is on or not. `turnedOn` when the press that opened it turned Storage on: Clean up says so, with Turn Off.
window.openStorage = (view, turnedOn) => {
  const keys = view === 'keys';
  if (turnedOn) cleanPage.turnedOn = true;
  else if (!keys && !state.storage?.on) return;
  mapPage.view = keys ? 'keys' : view === 'map' ? 'map' : 'clean';
  if (mapReading()) {
    if (mapPage.view === 'clean') cleanAsk();
    drawStorageLine();
    return drawReader();
  }
  toggleReader(null, null, 'storage');
};
