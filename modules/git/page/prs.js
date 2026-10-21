// The pull requests a session raised or worked on, on its row's work line, and the card one pointed at shows.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

/* The pull-request icon is GitHub's Octicon git-pull-request, from https://github.com/primer/octicons, under this
   licence:

   MIT License

   Copyright (c) 2026 GitHub Inc.

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. */
// Octicon git-pull-request.
const PR_ICON = '<svg width="11" height="11" viewBox="0 0 16 16"><path fill="currentColor" '
  + 'd="M1.5 3.25a2.25 2.25 0 1 1 3 2.122v5.256a2.251 2.251 0 1 1-1.5 0V5.372A2.25 2.25 0 0 1 1.5 3.25Z'
  + 'm5.677-.177L9.573.677A.25.25 0 0 1 10 .854V2.5h1A2.5 2.5 0 0 1 13.5 5v5.628a2.251 2.251 0 1 1-1.5 0V5'
  + 'a1 1 0 0 0-1-1h-1v1.646a.25.25 0 0 1-.427.177L7.177 3.427a.25.25 0 0 1 0-.354Z'
  + 'M3.75 2.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Zm0 9.5a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z'
  + 'm8.25.75a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Z"/></svg>';

const MAX_PRS = 3;

// The PRs a row shows: the open ones this session created or worked on, and those whose state couldn't be checked;
// merged and closed ones are left out.
function shownPRs(s) {
  return (s.prs || []).filter((p) => p.state === 'OPEN' || p.state === 'UNKNOWN');
}

// Open PRs this session created or worked on. Hidden while GitHub is still being asked, dimmed when
// their state couldn't be checked (UNKNOWN).
function prsHTML(s) {
  const open = shownPRs(s);
  if (!open.length) return '';
  const rows = open.slice(0, MAX_PRS).map((p) => {
    const cls = ['pr', p.isDraft ? 'draft' : '', p.state === 'UNKNOWN' ? 'pending' : ''].join(' ');
    return `<div class="${cls}" data-url="${esc(p.url)}">${PR_ICON}<span class="num">#${esc(p.number)}</span>`
      + `<span class="pt">${esc(p.title || p.repo)}</span></div>`;
  });
  if (open.length > MAX_PRS) rows.push(`<div class="pr more">+${open.length - MAX_PRS} more open</div>`);
  return `<div class="prs">${rows.join('')}</div>`;
}

function findPR(url) {
  for (const s of state.last.sessions) for (const p of s.prs || []) if (p.url === url) return p;
  return null;
}

// The card a PR pointed at shows: its state, where it is, how long ago it was opened, its title, its author and
// its size.
function prCardHTML(p) {
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

// At the start of the work line, after Create PR when there's that.
core.slots.workStart.push((row) => prsHTML(row.s));
core.presses.push(['.pr[data-url]', (pr) => native({ type: 'openPR', url: pr.dataset.url })]);
core.pointerTargets.push('.pr[data-url]');
core.cards.push({
  selector: '.pr[data-url]',
  key: (pr) => 'pr:' + pr.dataset.url,
  html(pr) {
    const p = findPR(pr.dataset.url);
    return p ? prCardHTML(p) : '';
  },
});
core.starts.push(() => {
  // An author's picture that doesn't load leaves its place empty rather than showing a broken image.
  document.getElementById('card').addEventListener('error', (e) => {
    if (e.target.matches?.('.avatar')) e.target.style.visibility = 'hidden';
  }, true);
});
