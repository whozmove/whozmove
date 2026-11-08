// Messages, drawn: its head with how many messages there were in the last two days and this week's that didn't reach
// a lead; its filters and who the channel is narrowed to; the inbox strip, what each inbox's session hasn't read yet,
// in the order it reads them; and the channel, every message oldest first, each with who sent it to whom, its tag
// (a kept one's priority), what it answers, its words (drawn as the reader draws Markdown, escaped first) and where it
// stands. What's decided is inbox-words.js's; nothing drawn here answers, lets in or sends anything.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The head: its title, how many in two days and this week's counts, and ✕. Kept short, so this week's counts fit at
// the view's width; should every kind of count be there and the line be cut, pointing at it shows it whole.
function mxHeadHTML(ctx, data) {
  const close = `<button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
  const sub = data ? [`${ctx.list.length} in two days`, mxWeekWords(data.counts)].filter(Boolean).join(' · ') : '';
  return `<span class="r-title">Messages</span><span class="r-sub" title="${esc(sub)}">${esc(sub)}</span>${close}`;
}

// What stays at the top as the channel scrolls: the filters, and the inbox strip.
function mxTopHTML(view, ctx, inboxes) {
  return `<div class="mx-top">${mxFiltersHTML(view, ctx)}${mxStripHTML(mxStrip(inboxes, view, ctx))}</div>`;
}

// All, Waiting and Not Delivered, each with how many there are where they're counted, the one shown pressed; and,
// narrowed to one agent or a pair, a chip naming them whose × goes back to everyone.
function mxFiltersHTML(view, ctx) {
  const counts = mxCounts(view, ctx);
  const chip = (filter, words, n) => `<button class="tag chip mx-filter" data-mx-filter="${filter}" `
    + `aria-pressed="${view.filter === filter}">${words}${n ? ` <span class="mx-n">${n}</span>` : ''}</button>`;
  const who = mxNarrowedTo(view, ctx);
  const back = who ? `<button class="tag chip outline mx-back" data-mx-back="1" aria-label="Show every session’s `
    + `messages">${esc(view.pair ? who : `${who}’s messages`)} <span class="mx-x">×</span></button>` : '';
  return `<div class="mx-filters">${chip('all', 'All')}${chip('waiting', 'Waiting', counts.waiting)}`
    + `${chip('lost', 'Not Delivered', counts.lost)}${back}</div>`;
}

// A kept message's priority, as a tag: Urgent firm, Question and Report grey, Note an outline. None for a plain one.
function mxTagHTML(m) {
  const p = m.kept?.priority;
  return MX_PRIORITY_WORDS[p] ? `<span class="tag mx-tag ${p}">${MX_PRIORITY_WORDS[p]}</span>` : '';
}

// The inbox strip: each inbox with messages its session hasn't read, in the order it reads them; a press on one goes
// to it in the channel.
function mxStripHTML(strip) {
  return strip.map((inbox) => `<div class="mx-inbox"><div class="mx-inbox-head"><b>${esc(inbox.name)}’s inbox</b> · `
    + `${mxToRead(inbox.items.length)}, most pressing first</div><ol>${inbox.items.map((m) => `<li><button `
    + `class="mx-inbox-item" data-mx-go="${esc(m.id)}">${mxTagHTML(m)}<span class="mx-what">`
    + `${esc(mxPartyName(m.from))}: ${esc(mxFirstWords(m.text, 90))}</span><span class="mx-at">${mxClock(m.at)}`
    + '</span></button></li>').join('')}</ol></div>`).join('');
}

// A sender's or receiver's name, which a press narrows the channel to: its name, and in brackets which one it is where
// two share it ("Wren (ended)", "Wren (shop)"), so it never reads as part of the line. One with no session (an address
// no session listens at) can't be pressed.
function mxWhoHTML(p, ctx) {
  const known = p?.session && ctx.names.get(p.session);
  const which = known?.which ? ` <span class="mx-which">(${esc(known.which)})</span>` : '';
  if (!known) return `<span class="mx-who">${esc(mxPartyName(p))}</span>`;
  return `<button class="mx-who" data-mx-who="${esc(p.session)}">${esc(known.name)}${which}</button>`;
}

// One message: who to whom, its tag and what it's about, the time; what it answers; its words, clipped to three lines
// with Show All, and where they were cut; and where it stands.
function mxMessageHTML(m, ctx, page) {
  const answers = ctx.byId.get(ctx.answers.get(m.id));
  const re = answers ? `<button class="mx-re" data-mx-go="${esc(answers.id)}">↳ answers `
    + `${esc(mxName(answers.from, ctx))}: ${esc(mxFirstWords(answers.text, 48))}</button>` : '';
  const about = m.kept?.about ? `<span class="mx-about">${esc(m.kept.about)}</span>` : '';
  const clipped = mxLong(m.text) && !page.more.has(m.id);
  const more = clipped ? `<button class="mx-more" data-mx-more="${esc(m.id)}">Show All</button>` : '';
  const cut = m.cut ? '<div class="mx-cut">Cut at 8,000 characters</div>' : '';
  const cls = `mx${page.lit === m.id ? ' lit' : ''}${page.fresh?.has(m.id) ? ' mx-new' : ''}`;
  return `<div class="${cls}" data-mx-id="${esc(m.id)}"><div class="mx-headline">${mxWhoHTML(m.from, ctx)}`
    + `<span class="mx-to">to</span>${mxWhoHTML(m.to, ctx)}${mxTagHTML(m)}${about}`
    + `<span class="mx-at">${mxClock(m.at)}</span></div>${re}`
    + `<div class="md mx-text${clipped ? ' clipped' : ''}">${markdownHTML(m.text)}</div>${more}${cut}`
    + `${mxStateHTML(m, ctx)}</div>`;
}

// Where it stands: its words, in grey (nothing for you), muted once read, green once answered, or in the colour of
// what's gone wrong for one that never got there; a press on an answer goes to the reply; Copy for words that never
// got there, which the app copies from what it holds.
function mxStateHTML(m, ctx) {
  const where = mxWhere(m, ctx);
  if (!where) return '';
  const words = where.go ? `<button class="mx-go" data-mx-go="${esc(where.go)}">${esc(where.words)}</button>`
    : `<span>${esc(where.words)}</span>`;
  const copy = where.copy ? `<button class="button small mx-copy" data-mx-copy="${esc(m.id)}">Copy</button>` : '';
  return `<div class="mx-state${where.tone ? ' ' + where.tone : ''}">${words}${copy}</div>`;
}

// The channel: every message the view shows, oldest first, with a line where the day changes; or what it says with
// none.
function mxChannelHTML(view, ctx, facts, page) {
  const shown = mxShown(view, ctx);
  // Without an agent that records its messages, the channel says first that only an inbox's show, unless that's all it
  // says.
  const note = mxNoAgent(facts) && ctx.list.length ? `<div class="mx-note">${esc(MX_NO_AGENT)}</div>` : '';
  if (!shown.length) {
    const back = view.agent || view.pair
      ? ' <button class="mx-go" data-mx-back="1">Show every session’s messages</button>' : '';
    return `<div class="mx-channel">${note}<div class="mx-empty">${esc(mxEmptyWords(view, ctx, facts))}${back}</div>`
      + '</div>';
  }
  let day = null;
  const lines = shown.map((m) => {
    const word = mxDayWord(m.at, ctx.now);
    const line = word !== day ? `<div class="mx-day">${word}</div>` : '';
    day = word;
    return line + mxMessageHTML(m, ctx, page);
  });
  return `<div class="mx-channel">${note}${lines.join('')}</div>`;
}
