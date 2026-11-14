// Side chat on the page: Side Chat on a session's row opens its chat beside the list, in the reader's place (a mode of
// parts/pane), with the cursor in its box. What each chat holds is the app's (setSideChats); what it says and how it's
// drawn, side-chat-words.js's and side-chat-view.js's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({
  sideChats: {},       // each session's chat, as the app keeps it (setSideChats), by session
  sideChatDrafts: {},  // what you've written in each session's box, kept while its chat isn't the one open
  sideChatWay: {},     // per session, the way you chose last, 'ask' or 'send' (Send until you choose); in memory
  sideChatSeen: {},    // when you last saw each session's chat: open beside the list, or in its tab
  sideChatOpenAt: {},  // when you last had each session's chat open beside the list: where side answers show
  sideChatWhy: {},     // why words are back in a session's box, by session: { why, way, act }
  sideChatRefused: {}, // why a press in a session's chat just now couldn't act, by session, until you type
  sideChatTaken: {},   // words put back in a box, by `<session> <at>`, so each is put back once
  sideChatCopied: {},  // the reply's code blocks whose Copy was just pressed, by `<at> <n>`
  sideChatAloud: {},   // when the newest reply or side answer said to VoiceOver came, by session
});

// As wide as a conversation reads well, with nothing down its side.
const SIDE_CHAT_WIDTH = 380;
// How long a code block's Copy says Copied.
const SIDE_CHAT_COPIED_MS = 2000;

const sideChatShownKey = (sid, at) => `sidechat:${sid}:${at}`;
// Stop's, and the press with Send's words under a failed question, the session second, so they go with it (shownFor,
// forgetGone) and stay while it's listed.
const sideChatStopKey = (sid, at) => `sidechat:${sid}:stop:${at}`;
const sideChatTurnKey = (sid, at) => `sidechat:${sid}:turn:${at}`;
// When the bar first showed beside a session's request, question or plan: Side Chat's own, never the card's.
const sideChatBesideKey = (sid, askId) => `sidechat:${sid}:beside:${askId}`;
const sideChatReading = () => state.reading?.mode === 'sideChat' && !state.reading.closing;
const sideChatOf = (sid) => state.sideChats[sid] || { says: [] };
const sideChatAsks = (s) => (s?.ask ? core.agent.askLine?.(s.ask) || '' : '');

// When you last saw a session's chat: its chat open, or its tab, kept after you've left it (sideChatSeenIn), so a
// reply read there never turns unread again.
const sideChatSeenAt = (s) => sideChatSeenIn(state.sideChatSeen[s.sessionId], s);
const sideChatOpenSeen = (s) => state.sideChatOpenAt[s.sessionId] || 0;
// With each update: being in a session's tab counts as having seen its chat then, kept.
core.updating.push((sessions) => {
  for (const s of sessions || []) state.sideChatSeen[s.sessionId] = sideChatSeenIn(state.sideChatSeen[s.sessionId], s);
});

// ---- Where it's drawn ----

// A session's chat is drawn in its own window beside the list (the reader's Side Chat mode), or in another view that
// shows it (core.sessionChat, One Task's talk under a task). Each place is marked with its session (`data-sc-chat`), so
// its presses, keys and what you type find their session there, never from what the reader shows; a box drawn in
// another view also carries the words that open yours there (`data-sc-opening`), and takes that view's room
// (`sc-hosted`).
const sideChatPlaceOf = (el) => el?.closest?.('[data-sc-chat]') || null;
const sideChatSession = (sid) => (state.last.sessions || []).find((x) => x.sessionId === sid)
  || (state.reading?.sessionId === sid ? readerSession() : undefined);
// The box of a session's chat drawn now, if any: the place holding its field.
const sideChatBoxOf = (sid) => [...reader.querySelectorAll('[data-sc-chat]')]
  .find((el) => el.dataset.scChat === sid && el.querySelector('.sc-field')) || null;
// Drawn again wherever a chat shows: in its own window or another view, both in the reader.
const sideChatRedraw = () => { if (state.reading && reader.querySelector('[data-sc-chat]')) drawReader(); };
// Having it in front counts as seeing it: a reply read there no longer lights its row's bar or counts at the edge.
function sideChatSaw(sid, now) {
  state.sideChatSeen[sid] = now;
  state.sideChatOpenAt[sid] = now;
}

// ---- Drawing ----

function drawSideChat() {
  const r = state.reading, s = readerSession(), sid = r.sessionId, chat = sideChatOf(sid), now = Date.now();
  const name = sideChatName(s);
  sideChatPutBack(sid, chat, name);
  putHTML(reader.querySelector('.r-head'), sideChatHeadHTML(name, s ? projectOf(s).name : ''));
  putHTML(reader.querySelector('.r-src'), sideChatLiveHTML(sideChatLive(s, name, sideChatAsks(s))));
  const body = reader.querySelector('.r-body');
  // A reply coming in scrolls the conversation to it only while you're at its foot: what you're reading stays put.
  const atFoot = body.scrollHeight - body.scrollTop - body.clientHeight < 30;
  if (sideChatLines(body, s, sid, chat, name, now, false) && atFoot) body.scrollTop = body.scrollHeight;
  sideChatFoot(reader.querySelector('.r-answer'), s, sid, chat, name, '', false);
  sideChatSaw(sid, now);
  r.ready = true;
  fitReader();
}

// The conversation, into `el`: your words, its replies, your side questions and their answers, and at its foot the
// session's step while it works; beside it, out of sight, what VoiceOver says of a new reply or side answer. Put in once
// for each session, the conversation alone drawn again as it changes. Whether anything changed.
function sideChatLines(el, s, sid, chat, name, now, hosted) {
  let page = el.querySelector(':scope > .sc-page');
  if (!page || page.dataset.scChat !== sid) {
    el.innerHTML = `<div class="sc-page${hosted ? ' sc-hosted' : ''}" data-sc-chat="${esc(sid)}"></div>`
      + '<span class="sc-say said-aloud" aria-live="polite"></span>';
    delete el.dataset.drawn;
    page = el.querySelector(':scope > .sc-page');
    // What was there before you came isn't news: only what comes in while it's in front is said.
    state.sideChatAloud[sid] = Math.max(state.sideChatAloud[sid] || 0, sideChatNewest(chat));
  }
  const aloud = sideChatSayAloud(chat, state.sideChatAloud[sid] || 0, name);
  if (aloud) {
    state.sideChatAloud[sid] = aloud.at;
    setText(el.querySelector(':scope > .sc-say'), aloud.words);
  }
  // In another view, with no head of its own, what Send waits on ends the conversation (sideChatHostedLive).
  const lines = `${sideChatLinesHTML(chat, s, name, sideChatAsks(s), now, state.sideChatCopied)}`
    + (hosted ? sideChatHostedLiveHTML(sideChatHostedLive(s, name, sideChatAsks(s))) : '')
    + '<div class="sc-work"></div>';
  // When each Send Now first showed, for its press (justShown).
  for (const said of sideChatShown(chat.says)) {
    const key = sideChatShownKey(sid, said.at);
    if (sideChatSaid(said, s, chat, name, '', now).acts.some((a) => a.act === 'sendNow')) state.shownAt[key] ??= now;
    else delete state.shownAt[key];
  }
  // When a side question's Stop, and its Send's words, first showed, for their presses, as Send Now's.
  const askBefore = sideChatAskBefore(s, chat, name), busy = (chat.asides || []).some((one) => one.state === 'asking');
  for (const aside of chat.asides || []) {
    const key = sideChatStopKey(sid, aside.at), turn = sideChatTurnKey(sid, aside.at);
    if (askBefore?.act === 'askStop' && askBefore.at === aside.at) state.shownAt[key] ??= now;
    else delete state.shownAt[key];
    const offered = sideChatAsideSaid(aside, s, chat, name, busy).acts.some((a) => a.act === 'waitTurn');
    if (offered) state.shownAt[turn] ??= now;
    else delete state.shownAt[turn];
  }
  let changed = putHTML(page, lines);
  // At the conversation's foot while it works, the line its row shows, in its reply's place: drawn again only when
  // what it says changes, its time ticking (tickTimes) in between.
  const work = page.querySelector('.sc-work'), key = sideChatWorkKey(s, name);
  if (work.dataset.key !== key) {
    // Drawn in another view, still: there it sits in a scroller under that view's sticky bars, where a shine would
    // be painted again every frame.
    work.innerHTML = key ? workLineHTML(s, now, { label: name, still: hosted }) : '';
    work.dataset.key = key;
    changed = true;
  }
  tickTimes(work, now);
  // A side question being asked: the same line in its answer's place, under the copy's name, the same way.
  for (const asking of page.querySelectorAll('.sc-aside-work')) {
    const aside = (chat.asides || []).find((one) => String(one.at) === asking.dataset.at);
    const askingKey = sideChatAsideWorkKey(aside, name);
    if (asking.dataset.key !== askingKey) {
      asking.innerHTML = askingKey ? sideChatAsideWorkHTML(aside, name, now, hosted) : '';
      asking.dataset.key = askingKey;
      changed = true;
    }
    tickTimes(asking, now);
  }
  return changed;
}

// The box, into `el`: put in once for each session, keeping what you've written in it (by session, so the same element
// drawn for another session shows that one's words, and the first's are kept); then Send, or the way forward in its
// place, and the line under it, drawn again as things change. `opening`, the words that open yours where it's drawn,
// kept on its mark, so a press sends what its line showed. Emptying the element is all it takes to stop showing it.
function sideChatFoot(el, s, sid, chat, name, opening, hosted) {
  const before = sideChatBefore(s, chat, name);
  const askBefore = sideChatAskBefore(s, chat, name), ask = `${askBefore?.act || ''} ${askBefore?.why || ''}`;
  // Send says when your words go in, which changes as the session starts or stops working or waits on you.
  const send = sideChatSendWord(s, chat);
  let place = el.querySelector(':scope > [data-sc-chat]');
  if (!place || place.dataset.scChat !== sid || place.dataset.scOpening !== opening
      || el.dataset.way !== (before?.act || '') || el.dataset.ask !== ask || el.dataset.send !== send) {
    const field = place?.querySelector('.sc-field'), had = field && document.activeElement === field;
    el.innerHTML = `<div class="sc-place${hosted ? ' sc-hosted' : ''}" data-sc-chat="${esc(sid)}" `
      + `data-sc-opening="${esc(opening)}">${sideChatBoxHTML(s, chat, name, before, askBefore,
                                                               sideChatWayNow(state.sideChatWay[sid], askBefore),
                                                               opening)}</div>`;
    el.dataset.way = before?.act || '';
    el.dataset.ask = ask;
    el.dataset.send = send;
    place = el.querySelector(':scope > [data-sc-chat]');
    const fresh = place.querySelector('.sc-field');
    fresh.value = state.sideChatDrafts[sid] || '';
    // Drawn again as a side question starts or ends: the cursor stays in the box where it was, for the same session.
    if (had && field.closest('[data-sc-chat]')?.dataset.scChat === sid) fresh.focus({ preventScroll: true });
  }
  sideChatUnder(place, s, sid, chat, name, before, askBefore);
}

// The buttons and the line under the box, as what's in it changes: `place`, the box's mark.
function sideChatUnder(place, s, sid, chat, name, before = sideChatBefore(s, chat, name),
                       askBefore = sideChatAskBefore(s, chat, name)) {
  const field = place?.querySelector('.sc-field');
  if (!field) return;
  const opening = place.dataset.scOpening || '';
  field.maxLength = sideChatRoom(sideChatOpening(s, chat, opening));
  // Send, Copy and Go in its place, and Ask Without Interrupting take a press only with words in the box.
  for (const button of place.querySelectorAll('[data-sc="send"], .sc-box-row [data-sc="copyAndGo"]'))
    button.disabled = !field.value.trim();
  const ask = place.querySelector('[data-sc="ask"]');
  if (ask) ask.disabled = !field.value.trim() || !!askBefore;
  // The dark button is the way you chose last, and Return goes that way: moved here rather than by drawing the box
  // again, so the words being written stay. Send's place is the box row's last button (Copy and Go and the like
  // among them); Ask's own ways (Stop, Take Me There) are never dark, so with Ask chosen while Stop shows in Ask's
  // place, neither button is.
  const way = sideChatWayNow(state.sideChatWay[sid], askBefore);
  const sendPlace = place.querySelector('.sc-box-row > .button:last-child');
  if (ask) {
    ask.classList.toggle('main', way === 'ask');
    ask.setAttribute('aria-keyshortcuts', way === 'ask' ? 'Enter' : 'Alt+Enter');
  }
  if (sendPlace) {
    sendPlace.classList.toggle('main', way === 'send');
    if (sendPlace.dataset.sc === 'send') {
      sendPlace.setAttribute('aria-keyshortcuts', way === 'send' ? 'Enter' : 'Alt+Enter');
    }
  }
  putHTML(place.querySelector('.sc-goes'), sideChatUnderHTML(s, chat, name, field.value, state.sideChatWhy[sid],
                                                              before, askBefore, state.sideChatRefused[sid], way,
                                                              opening));
}

// Words the app put back (taken back, or they couldn't go in) go into the box once, before what's there, with why.
function sideChatPutBack(sid, chat, name) {
  for (const said of chat.says || []) {
    const key = `${sid} ${said.at}`;
    if (!SIDE_CHAT_BACK.includes(said.state) || state.sideChatTaken[key]) continue;
    state.sideChatTaken[key] = true;
    const draft = state.sideChatDrafts[sid];
    state.sideChatDrafts[sid] = draft ? `${said.words} ${draft}` : said.words;
    const back = sideChatBack(said, name);
    if (back) state.sideChatWhy[sid] = back;
    else delete state.sideChatWhy[sid];
    const field = sideChatBoxOf(sid)?.querySelector('.sc-field');
    if (field) field.value = state.sideChatDrafts[sid];
    // They're in the box now: the app lets them go, so they're never put back twice.
    native({ type: 'sideChatPutBack', sessionId: sid, at: said.at });
  }
}

// ---- Presses ----

// Side Chat, the bar at a row's far edge: opens its chat beside the list, the cursor in its box, or closes it where
// it's open.
function sideChatPress(button, e) {
  // A button's own press would take the cursor straight back out of the box.
  e?.preventDefault();
  const sid = button.dataset.scOpen;
  // The bar stays beside a row's card, and takes a press only once it has been seen a moment beside the session's
  // request, question or plan, as the card's own buttons do (justShown, by the time the bar first showed beside it):
  // one arrives by itself, so the row can grow just as you press. Compact, Switch model? and Deploy's set-up open from
  // your own press on the row, so they don't wait.
  const ask = state.last.sessions.find((x) => x.sessionId === sid)?.ask;
  if (ask && justShown(sideChatBesideKey(sid, ask.id))) return;
  toggleReader(sid, null, 'sideChat');
  // Its bar kept lit and pressed as you press, where the list's next drawing would only say so up to a second later.
  const open = sideChatReading() && state.reading.sessionId === sid;
  for (const b of document.querySelectorAll('.sc-edge[data-sc-open]')) {
    const on = open && b.dataset.scOpen === sid;
    b.classList.toggle('keep', on);
    b.setAttribute('aria-pressed', `${on}`);
  }
  if (!open) return;
  wantKeyboard(true);
  const field = reader.querySelector('.sc-field');
  field?.focus({ preventScroll: true });
  field?.setSelectionRange(field.value.length, field.value.length);
}

// A press in a session's chat, wherever it's drawn: its session, its box and the words that open yours there come from
// the place's mark (`place`, for a key in its box; else the one the press is in).
function sideChatAct(act, b, place = sideChatPlaceOf(b)) {
  const sid = place?.dataset.scChat, at = Number(b?.dataset.at);
  if (!sid) return;
  const s = sideChatSession(sid), box = sideChatBoxOf(sid), opening = box?.dataset.scOpening || '';
  const field = box?.querySelector('.sc-field'), words = field?.value.trim() || '';
  const chat = sideChatOf(sid), name = sideChatName(s), aside = (chat.asides || []).find((one) => one.at === at);
  const under = () => sideChatUnder(box, s, sid, chat, name);
  // What goes with words and questions sent from here: the words that open them, only where there are some.
  const opened = opening ? { opening } : {};
  const emptied = () => {
    field.value = '';
    delete state.sideChatDrafts[sid];
    delete state.sideChatWhy[sid];
    delete state.sideChatRefused[sid];
  };
  // Words put in the box for you to read and send, the cursor at their end.
  const filled = (text) => {
    if (!field) return;
    field.value = text;
    state.sideChatDrafts[sid] = text;
    delete state.sideChatWhy[sid];
    delete state.sideChatRefused[sid];
    wantKeyboard(true);
    field.focus({ preventScroll: true });
    field.setSelectionRange(text.length, text.length);
  };
  if (act === 'send') {
    // ⌥Return reaches here with Ask the dark button, whatever Send's place shows: a can't says why, under the box,
    // where the line speaks for Ask meanwhile.
    const cant = sideChatBefore(s, chat, name);
    if (cant?.way && words) state.sideChatRefused[sid] = cant.why;
    if (!words || cant?.way) return under();
    native({ type: 'sideChatSend', sessionId: sid, words, ...opened });
    // Only a press that goes sets the way, so a refused or empty one leaves the dark button where it was.
    state.sideChatWay[sid] = 'send';
    emptied();
  } else if (act === 'ask') {
    // Return with Ask chosen, or ⌥Return with Send dark, reaches here whatever Ask Without Interrupting's place shows
    // (Stop while a copy still answers): a can't says why, under the box.
    const cant = sideChatAskBefore(s, chat, name);
    if (cant?.why && words) state.sideChatRefused[sid] = cant.why;
    if (!words || cant) return under();
    native({ type: 'sideChatAsk', sessionId: sid, question: words, ...opened });
    state.sideChatWay[sid] = 'ask';
    emptied();
  } else if (act === 'askAgain') {
    // Asked again with the words that opened it where it was first asked, wherever Ask Again is pressed; one with no
    // room for them is put in your box instead, to shorten and ask, never dropped.
    const cant = sideChatAskBefore(s, chat, name);
    if (cant?.why) state.sideChatRefused[sid] = cant.why;
    if (!aside || cant) return under();
    const room = sideChatRoom(aside.opening || '');
    if (aside.question.length > room) {
      filled(sideChatQuestionInBox(aside.question, field?.value || '', room));
      return drawReader();
    }
    native({ type: 'sideChatAsk', sessionId: sid, question: aside.question,
             ...(aside.opening ? { opening: aside.opening } : {}) });
  } else if (act === 'askStop') {
    // Stop ends a question you've just asked: a press only once it's been seen a moment, as Send Now's.
    if (justShown(sideChatStopKey(sid, at))) return;
    native({ type: 'sideChatAskStop', sessionId: sid, at });
  } else if (act === 'addAnswer') {
    if (!aside) return;
    const draft = field?.value || '', added = sideChatAddAnswer(aside.question, aside.answer, draft,
                                                                sideChatRoom(sideChatOpening(s, chat, opening)));
    if (added === draft) {
      state.sideChatRefused[sid] = 'No room left in the box for the answer: send or shorten what’s there first';
      return under();
    }
    // The answer goes into your box for Send to pass on, so Send becomes the way: Return then sends it, never asks a
    // copy again.
    state.sideChatWay[sid] = 'send';
    filled(added);
  } else if (act === 'waitTurn') {
    // The question sent the normal way, as Send sends it, so the session itself sees it: a press only once it's been
    // seen a moment, as Send Now's, and only where Send could go, else why not under the box. One too long to go after
    // the words that open yours is put in your box instead, to shorten and send.
    if (!aside || aside.sentAt || justShown(sideChatTurnKey(sid, at))) return;
    const cant = sideChatBefore(s, chat, name);
    if (cant?.way) {
      state.sideChatRefused[sid] = cant.why;
      return under();
    }
    // A press on Send's own words is choosing Send, as a press on Send is. The app sends it with the words that opened
    // it where it was asked, so its room is counted with those.
    state.sideChatWay[sid] = 'send';
    const room = sideChatRoom(sideChatOpening(s, chat, aside.opening || ''));
    if (aside.question.length > room) {
      filled(sideChatQuestionInBox(aside.question, field?.value || '', room));
      return drawReader();
    }
    native({ type: 'sideChatSend', sessionId: sid, words: aside.question, aside: at });
  } else if (act === 'asideCopy' || act === 'asideCopyQuestion') {
    native({ type: 'sideChatAsideCopy', sessionId: sid, at, what: act === 'asideCopy' ? 'answer' : 'question' });
  } else if (act === 'asideCopyCode') {
    const key = `${at} ${Number(b.dataset.part)}`, now = Date.now();
    native({ type: 'sideChatAsideCopy', sessionId: sid, at, what: 'code', part: Number(b.dataset.part) });
    state.sideChatCopied[key] = now;
    setTimeout(() => {
      if (state.sideChatCopied[key] !== now) return;
      delete state.sideChatCopied[key];
      sideChatRedraw();
    }, SIDE_CHAT_COPIED_MS);
  } else if (act === 'copySignIn') {
    native({ type: 'sideChatCopySignIn', sessionId: sid });
  } else if (act === 'getAgent') {
    native({ type: 'sideChatGetAgent', sessionId: sid });
  } else if (act === 'takeBack') {
    native({ type: 'sideChatTakeBack', sessionId: sid, at });
  } else if (act === 'sendNow') {
    // Send Now types your words in: a press only once it's been seen a moment, as a card's buttons take one.
    if (justShown(sideChatShownKey(sid, at))) return;
    native({ type: 'sideChatSendNow', sessionId: sid, at });
  } else if (act === 'copyAndGo') {
    // Words that couldn't go in, from the box or the conversation, copied as they'd go in, for you to paste there.
    if (at) native({ type: 'sideChatCopy', sessionId: sid, at });
    else if (words) {
      native({ type: 'sideChatCopy', sessionId: sid, words, ...opened });
      emptied();
    } else return;
    if (s) openSession(s);
  } else if (act === 'copyCode') {
    const key = `${at} ${Number(b.dataset.part)}`, now = Date.now();
    native({ type: 'sideChatReplyCopy', sessionId: sid, at, part: Number(b.dataset.part) });
    state.sideChatCopied[key] = now;
    setTimeout(() => {
      if (state.sideChatCopied[key] !== now) return;
      delete state.sideChatCopied[key];
      sideChatRedraw();
    }, SIDE_CHAT_COPIED_MS);
  } else if (act === 'show') {
    if (s?.ask) waitingBring({ id: s.ask.id, sid });
  } else if (act === 'there' || act === 'openAgain') {
    if (s) openSession(s);
  } else if (act === 'closeCopy') {
    native({ type: 'closeCopy', sessionId: sid });
  } else if (act === 'wayPast') {
    native({ type: 'wayPast', sessionId: sid });
    delete state.sideChatWhy[sid];
  } else if (act === 'accessibility') {
    // Words Claude Desktop couldn't take for want of the permission: its pane in System Settings.
    native({ type: 'sideChatAccessibility' });
    delete state.sideChatWhy[sid];
  }
  drawReader();
}

core.presses.push(['.sc-edge[data-sc-open]', sideChatPress]);
core.readerPresses.push(['[data-sc-chat] [data-sc]', (b) => { if (!b.disabled) sideChatAct(b.dataset.sc, b); }]);
core.pointerTargets.push('.sc-edge', '#reader [data-sc-chat] .sc-act', '#reader [data-sc-chat] .button:not(:disabled)');

// What you write is kept as you type, by session, so drawing it again keeps it; Return goes the way you chose last
// (the dark button), ⌥Return the other way. Esc in its own window closes the chat, keeping it, whatever's in the box;
// drawn in another view, Esc leaves the box, the view staying open. The box takes Esc itself.
reader.addEventListener('input', (e) => {
  const place = e.target.matches?.('.sc-field') ? sideChatPlaceOf(e.target) : null;
  if (!place) return;
  const sid = place.dataset.scChat, s = sideChatSession(sid);
  state.sideChatDrafts[sid] = e.target.value;
  delete state.sideChatWhy[sid];
  delete state.sideChatRefused[sid];
  sideChatUnder(place, s, sid, sideChatOf(sid), sideChatName(s));
});
reader.addEventListener('keydown', (e) => {
  const place = e.target.matches?.('.sc-field') ? sideChatPlaceOf(e.target) : null;
  if (!place || e.isComposing || e.keyCode === 229) return;
  const sid = place.dataset.scChat, s = sideChatSession(sid), name = sideChatName(s);
  const act = sideChatKeyAct(e, sideChatWayNow(state.sideChatWay[sid], sideChatAskBefore(s, sideChatOf(sid), name)));
  if (act === 'ask' || act === 'send') {
    e.preventDefault();
    sideChatAct(act, null, place);
  } else if (act === 'close') {
    e.preventDefault();
    e.stopPropagation();
    e.target.blur();
    if (place.classList.contains('sc-hosted')) wantKeyboard(false);
    else closeReader();
  }
});

// ---- What it plugs into ----

// Side Chat on the row of every session listed and running (sideChatOffered), the bar at the row's far edge, where
// the chat comes out (the row part's edge slot): nothing on the row's lines.
// Beside a request, question or plan, when it first showed there is kept for its press (sideChatPress).
core.slots.edge.push((row) => {
  if (!sideChatOffered(row.s)) return '';
  if (row.s.ask) state.shownAt[sideChatBesideKey(row.s.sessionId, row.s.ask.id)] ??= Date.now();
  return sideChatEdgeHTML(row.s.sessionId, sideChatName(row.s),
                          sideChatUnseen(sideChatOf(row.s.sessionId), sideChatSeenAt(row.s), sideChatOpenSeen(row.s)),
                          sideChatReading() && state.reading.sessionId === row.s.sessionId);
});

core.readerModes.sideChat = {
  width: () => SIDE_CHAT_WIDTH,
  draw: drawSideChat,
  // Another mode, or another session's chat, draws its own box: this one's goes, so it's put in again on its return.
  reset() {
    reader.querySelector('.r-answer > [data-sc-chat]')?.remove();
  },
  cls: 'k-side-chat',
};

// A session's chat, lent to another view that shows it (One Task's talk under a task): its conversation into `lines`
// and its box into `box`, either left out, each drawn again with every call as the chat changes, never taking the
// cursor. `opening`, the words that open yours there, shown under the box and sent with your words and side questions.
// Everything inside is Side Chat's: its presses, keys, what you type, and having seen it.
core.sessionChat = {
  draw(s, { lines, box, opening = '' } = {}) {
    if (!s?.sessionId) return;
    const sid = s.sessionId, chat = sideChatOf(sid), name = sideChatName(s), now = Date.now();
    sideChatPutBack(sid, chat, name);
    if (lines) sideChatLines(lines, s, sid, chat, name, now, true);
    if (box) sideChatFoot(box, s, sid, chat, name, opening, true);
    sideChatSaw(sid, now);
  },
};

// A reply you haven't seen comes out beside the folded panel and counts at the panel's edge, as any reply does, until
// you've seen it (notifications decides when and where).
core.sessionNews?.push((s) => sideChatNews(s, sideChatOf(s.sessionId), sideChatSeenAt(s), sideChatOpenSeen(s)));

// What's kept per session goes a minute after it has gone from the list.
core.forgotten.keys.push('sideChatDrafts', 'sideChatWay', 'sideChatSeen', 'sideChatOpenAt', 'sideChatWhy',
                         'sideChatRefused', 'sideChatAloud');
core.forgotten.prefixes.push('sidechat');

// Each session's chat, as the app keeps it: each time one changes, and as the page loads.
window.setSideChats = (chats) => {
  state.sideChats = chats && typeof chats === 'object' ? chats : {};
  sideChatRedraw();
  if (!state.sliding && !state.composing) render();
};
