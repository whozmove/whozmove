// Hover: what's under the pointer is highlighted, and a PR pointed at shows its card.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Everything hover-related follows one pointer position that the app polls and sends (hoverAt, hoverEnd).
// Neither :hover nor mouse events are used: the panel is rarely the focused window, so WebKit's own hover goes
// stale, and the list is rebuilt every second.
const HOVER_TARGETS = ['.row', '.pr[data-url]', '.add', '.chev', '.group.toggle', '.project', '.pick', '#ask button',
                       '.perm button', '.opt', '.q-close'];

const card = document.getElementById('card');
// An author's picture that doesn't load leaves its place empty rather than showing a broken image.
card.addEventListener('error', (e) => {
  if (e.target.matches?.('.avatar')) e.target.style.visibility = 'hidden';
}, true);

function findPR(url) {
  for (const s of state.last.sessions) for (const p of s.prs || []) if (p.url === url) return p;
  return null;
}

function cardHTML(p) {
  const state = p.state === 'UNKNOWN' ? ['unknown', 'Unknown'] : p.isDraft ? ['draft', 'Draft'] : ['open', 'Open'];
  const opened = p.createdAt ? ago(Date.now() - Date.parse(p.createdAt)) : '';
  const login = p.author?.login;
  const stats = p.additions == null ? '' : `<span class="c-stats">
        <span class="c-diff"><span class="add">+${p.additions}</span> <span class="del">−${p.deletions}</span></span>
        <span class="c-files">${p.changedFiles} file${p.changedFiles === 1 ? '' : 's'}</span></span>`;
  return `<div class="c-top">
        <span class="pill ${state[0]}">${PR_ICON}${state[1]}</span>
        <span class="c-ref">${esc(p.repo)} #${esc(p.number)}</span>
        ${opened ? `<span class="c-time">${opened === 'now' ? 'just now' : opened + ' ago'}</span>` : ''}
      </div>
      <div class="c-title">${esc(p.title || p.url)}</div>
      <div class="c-foot">
        ${login ? `<img class="avatar" src="https://github.com/${encodeURIComponent(login)}.png?size=40">`
                  + `<span>${esc(login)}</span>` : ''}
        ${stats}
      </div>`;
}

// Below the PR when the panel can grow to fit it, otherwise above.
function placeCard(anchor) {
  const r = anchor.getBoundingClientRect();
  const h = card.offsetHeight;
  let top = r.bottom + 4;
  if (top + h + 8 > state.panelMax) top = Math.max(6, r.top - h - 4);
  card.style.top = top + 'px';
  state.cardBottom = Math.ceil(top + h + 8);
}

function showCard(url) {
  const anchor = prUnderPointer();
  const p = findPR(url);
  if (!anchor || anchor.dataset.url !== url || !p) return;
  state.cardUrl = url;
  card.innerHTML = cardHTML(p);
  card.hidden = false;
  placeCard(anchor);
  reportHeight();
}

function hideCard() {
  if (!state.cardUrl) return;
  state.cardUrl = null;
  card.hidden = true;
  reportHeight();
}

function prUnderPointer() {
  // The card itself isn't found: it takes no pointer events.
  const el = state.pointer && document.elementFromPoint(state.pointer.x, state.pointer.y);
  return el?.closest('.pr[data-url]') || null;
}

function syncHover() {
  document.querySelectorAll('.is-hover').forEach((n) => n.classList.remove('is-hover'));
  const el = state.pointer && document.elementFromPoint(state.pointer.x, state.pointer.y);
  for (const target of HOVER_TARGETS) el?.closest(target)?.classList.add('is-hover');
  state.hoverCtx = el?.closest('.ctx[data-ctx]')?.dataset.ctx || null;
  for (const ring of document.querySelectorAll('.ctx[data-ctx]'))
    ring.classList.toggle('open', ring.dataset.ctx === state.hoverCtx || !!state.compactOpen[ring.dataset.ctx]);
  const anchor = el?.closest('.pr[data-url]');
  const url = anchor?.dataset.url || null;

  if (url && url === state.cardUrl) { clearTimeout(state.cardTimer); placeCard(anchor); return; }
  clearTimeout(state.cardTimer);
  if (url) state.cardTimer = setTimeout(() => showCard(url), state.cardUrl ? 60 : 300);
  else if (state.cardUrl) state.cardTimer = setTimeout(hideCard, 150);
}

function pointerAt(x, y) { state.pointer = { x, y }; syncHover(); }
function pointerGone() { state.pointer = null; syncHover(); }
