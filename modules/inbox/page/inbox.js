// Messages beside the list (core.readerModes.messages), opened from Working on Whozmove ▸ Show Messages: every message
// your sessions sent each other in the last two days, one channel. The app sends them only while it's open
// (messagesOpen, messagesClosed): all of them as it opens, then only what's new or changed (setMessages). Presses
// narrow it to one agent or a pair, filter it, go to a message, show a long one whole, or have the app copy the words
// of one that never got there (messagesCopy, by its id: the page never sends words). Nothing here lets a message in or
// answers one: a held message is let in on its receiver's row, and an inbox is read by its own session.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What Messages shows: the filter (all, waiting or lost), the agent it's narrowed to and the pair, by session; the
// messages shown whole; the one lit, for a moment, after a press went to it; the ones new since the last draw, which
// come in the panel's way; those drawn so far (none before the first draw, so nothing comes in then); whether the
// channel was scrolled to its foot, where it stays as messages come; and whether the app is sending.
const mxPage = { filter: 'all', agent: null, pair: null, more: new Set(), lit: null, fresh: null, seen: null,
                 atFoot: true, open: false, lights: 0 };
const MX_WIDTH = 410;
// The tallest the channel makes the panel: past it, it scrolls, as a chat does.
const MX_TALLEST = 600;
// How long a message a press went to stays lit.
const MX_LIT_MS = 1600;

const mxReading = () => state.reading?.mode === 'messages' && !state.reading.closing;

// The app stops sending once Messages is out of sight.
function mxLeft() {
  if (!mxPage.open) return;
  mxPage.open = false;
  native({ type: 'messagesClosed' });
}

function mxDraw() {
  const r = state.reading, data = state.messages;
  const ctx = mxContext(data?.list, data?.facts?.now || state.last?.now || Date.now());
  // An agent or pair no longer among the messages (gone from the two days) goes, so the view is never narrowed to
  // nobody.
  if (mxPage.agent && !ctx.names.has(mxPage.agent)) mxPage.agent = null;
  if (mxPage.pair && !mxPage.pair.every((s) => ctx.names.has(s))) mxPage.pair = null;
  putHTML(reader.querySelector('.r-head'), mxHeadHTML(ctx, data));
  const body = reader.querySelector('.r-body');
  if (!data || (data.facts?.reading && !ctx.list.length)) {
    putHTML(reader.querySelector('.r-src'), '');
    delete body.dataset.drawn;
    readerWait(body, 'Reading the last two days…');
  } else {
    putHTML(reader.querySelector('.r-src'), mxTopHTML(mxPage, ctx, data.inboxes));
    // What's new since the last draw comes in the panel's way, unless motion is reduced; nothing does as it opens.
    mxPage.fresh = mxPage.seen && !calm.matches
      ? new Set(ctx.list.map((m) => m.id).filter((id) => !mxPage.seen.has(id))) : null;
    mxPage.seen = new Set(ctx.list.map((m) => m.id));
    const atFoot = mxPage.atFoot || body.scrollTop + body.clientHeight >= body.scrollHeight - 4;
    if (putHTML(body, mxChannelHTML(mxPage, ctx, data.facts, mxPage)) && atFoot && !mxPage.lit) mxFoot(body);
    mxPage.atFoot = false;
  }
  r.ready = true;
  fitReader();
  syncHover();
}

// The channel scrolled to its foot, where the newest message is.
function mxFoot(body) {
  body.scrollTop = body.scrollHeight;
}

// A press went to a message: shown in the channel (everything, if the view hid it), scrolled to and lit a moment.
function mxGo(id) {
  const data = state.messages;
  const ctx = mxContext(data?.list, data?.facts?.now || Date.now());
  if (!ctx.byId.has(id)) return;
  if (!mxShown(mxPage, ctx).some((m) => m.id === id)) Object.assign(mxPage, { filter: 'all', agent: null, pair: null });
  mxPage.lit = id;
  const lights = ++mxPage.lights;
  drawReader();
  reader.querySelector(`.mx[data-mx-id="${CSS.escape(id)}"]`)?.scrollIntoView({ block: 'center' });
  setTimeout(() => {
    if (lights !== mxPage.lights) return;
    mxPage.lit = null;
    if (mxReading()) drawReader();
  }, MX_LIT_MS);
}

// A name pressed: the channel narrows to that agent's messages; with one agent shown, another's name narrows it to the
// two of them, and its own takes the pair away again.
function mxWho(session) {
  if (!mxPage.agent) mxPage.agent = session;
  else if (session !== mxPage.agent) mxPage.pair = [mxPage.agent, session];
  else mxPage.pair = null;
  mxPage.atFoot = true;
  drawReader();
}

core.readerModes.messages = {
  sessionless: true,
  width: () => MX_WIDTH,
  draw: mxDraw,
  // As tall as the channel, up to MX_TALLEST, past which it scrolls.
  contentHeight: (page) => Math.min(page?.offsetHeight || 0, MX_TALLEST),
  // Opened afresh each time, on every session's messages, at the foot; the app sends them all now.
  shown() {
    Object.assign(mxPage, { filter: 'all', agent: null, pair: null, more: new Set(), lit: null, fresh: null,
                            seen: null, atFoot: true, open: true });
    native({ type: 'messagesOpen' });
  },
  // Every mode is reset as the reader turns to another: only Messages' own turning away stops the app sending.
  reset(r) {
    if (r.mode === 'messages') mxLeft();
  },
  closed: mxLeft,
  // Laid out at its width as the panel grows: the channel that was at its foot stays there.
  laidOut() {
    const body = reader.querySelector('.r-body');
    if (body && !mxPage.lit && body.scrollTop + body.clientHeight >= body.scrollHeight - body.clientHeight / 2)
      mxFoot(body);
  },
  cls: 'k-messages',
};

// The messages, each inbox with what it hasn't read, this week's counts and how the read stands; `whole` for all of
// them (as Messages opens), else only those new or changed, laid over what's here.
window.setMessages = (messages, inboxes, counts, facts, whole) => {
  const held = state.messages;
  state.messages = { list: mxTake(held?.list, messages, whole || !held), inboxes: inboxes || [], counts: counts || {},
                     facts: facts || {} };
  if (mxReading()) drawReader();
};

// Working on Whozmove ▸ Show Messages, ticked: Messages opens, or stays as it is if it's open.
window.openMessages = () => {
  if (!mxReading()) openReader(null, null, 'messages');
};

// Unticked: Messages closes, if it's what the reader shows.
window.closeMessages = () => {
  if (mxReading()) closeReader();
};

core.readerPresses.push(
  ['[data-mx-filter]', (el) => { mxPage.filter = el.dataset.mxFilter; mxPage.atFoot = true; drawReader(); }],
  ['[data-mx-who]', (el) => mxWho(el.dataset.mxWho)],
  ['[data-mx-back]', () => { Object.assign(mxPage, { agent: null, pair: null, atFoot: true }); drawReader(); }],
  ['[data-mx-go]', (el) => mxGo(el.dataset.mxGo)],
  ['[data-mx-more]', (el) => { mxPage.more.add(el.dataset.mxMore); drawReader(); }],
  // The app copies the words it holds for that message: the page never sends them.
  ['[data-mx-copy]', (el) => native({ type: 'messagesCopy', id: el.dataset.mxCopy })],
);
