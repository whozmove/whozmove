// A side chat, as HTML: its head, the session's live step under it, the conversation, and the box at its foot; and
// Side Chat on a row. Drawn with the kit's pieces and side chat's own classes; everything said is escaped, a reply's
// prose drawn from its Markdown (markdownHTML), and a command in it only ever copied, never run.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The head: whom it's with, and the project it's in, with the reader's ✕.
const sideChatHeadHTML = (name, project) => `<span class="r-title">${esc(name)}</span>`
  + `<span class="r-sub">Side chat · ${esc(project)}</span>`
  + `<button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;

// Under the head: what the session is doing now (sideChatLive), with a dot that works while it does.
const sideChatLiveHTML = (live) => `<div class="sc-live${live.works ? ' works' : ''}"><span class="sc-dot"></span>`
  + `<span class="sc-now">${esc(live.words)}</span></div>`;

// A press under your words, by what it does.
const sideChatActHTML = (act, at) => `<button type="button" class="sc-act" data-sc="${act.act}" data-at="${at}">`
  + `${esc(act.word)}</button>`;

// A code block in a reply, on a line of its own, with Copy ("Copied" a moment once pressed, `copied`); `act`, what its
// Copy does: copyCode for a reply's, asideCopyCode for a side answer's.
const sideChatCodeHTML = (part, at, copied, act = 'copyCode') => `<div class="sc-code"><pre class="perm-detail">`
  + `${esc(part.code)}</pre><button type="button" class="button small" data-sc="${act}" data-at="${at}" `
  + `data-part="${part.n}">${copied ? 'Copied' : 'Copy'}</button></div>`;

// A reply's parts as HTML: prose from its Markdown, each code block with its Copy.
const sideChatPartsHTML = (parts, at, copied, act) => sideChatReply(parts).map((part) => (part.code !== undefined
  ? sideChatCodeHTML(part, at, !!copied[`${at} ${part.n}`], act) : markdownHTML(part.prose))).join('');

// The conversation: each of your words with how far it got and its presses, then its reply under the session's name.
// `copied`: the code blocks whose Copy was just pressed, by `<at> <n>`.
function sideChatLinesHTML(chat, s, name, asks, now, copied = {}) {
  const says = sideChatShown(chat?.says), asides = chat?.asides || [];
  if (!says.length && !asides.length) return `<p class="sc-empty">${esc(sideChatEmpty(s, chat, name))}</p>`;
  // Your words and your side questions, in the order you sent them.
  const lines = says.map((said) => ({ at: said.at, said })).concat(asides.map((aside) => ({ at: aside.at, aside })))
    .sort((a, b) => a.at - b.at);
  return '<div class="sc-lines">' + lines.map(({ said, aside }) => {
    if (aside) return sideChatAsideHTML(aside, s, chat, name, copied, asides.some((one) => one.state === 'asking'));
    const st = sideChatSaid(said, s, chat, name, asks, now);
    const you = `<div class="sc-you${st.held ? ' held' : ''}"><p>${esc(said.words)}</p>`
      + (st.words || st.acts.length ? `<span class="sc-said${st.tone ? ` ${st.tone}` : ''}">${esc(st.words)}`
        + `${st.acts.map((act) => sideChatActHTML(act, said.at)).join('')}</span>` : '')
      + '</div>';
    if (said.state !== 'replied') return you;
    // Its reply, read before Whozmove last started, isn't kept: it's in the session itself.
    if (!sideChatReply(said.reply).length) return you + `<div class="sc-reply"><b>${esc(name)}</b><span class="sc-said">`
      + `Answered in its session, before Whozmove restarted${sideChatActHTML({ act: 'there', word: 'Take Me There' },
        said.at)}</span></div>`;
    return you + `<div class="sc-reply"><b>${esc(name)}</b><div class="sc-reply-text">`
      + `${sideChatPartsHTML(said.reply, said.at, copied)}</div></div>`;
  }).join('') + '</div>';
}

// A side question, filled as your words are but quieter, "Without interrupting" first, and how far it got; answered,
// its answer under "A copy of <name>", with Add to Message and Copy. Each is one group, which VoiceOver names as
// unseen by the session.
function sideChatAsideHTML(aside, s, chat, name, copied = {}, busy = false) {
  const st = sideChatAsideSaid(aside, s, chat, name, busy), label = esc(sideChatAsideLabel(name));
  const acts = st.acts.map((act) => sideChatActHTML(act, aside.at)).join('');
  const answered = aside.state === 'answered';
  const you = `<div class="sc-you sc-aside" role="group" aria-label="${label}"><p><span class="sc-mark">Without `
    + `interrupting</span> ${esc(aside.question)}</p>`
    + (!answered && (st.words || acts) ? `<span class="sc-said">${esc(st.words)}${acts}</span>` : '') + '</div>';
  if (!answered) return you;
  return you + `<div class="sc-reply sc-aside" role="group" aria-label="${label}"><b>A copy of ${esc(name)}</b>`
    + `<div class="sc-reply-text">${sideChatPartsHTML(aside.answer, aside.at, copied, 'asideCopyCode')}</div>`
    + `<span class="sc-said">${acts}</span></div>`;
}

// The box at the foot: the field, Ask Without Interrupting, and Send, each with the way forward in its own place when
// it can't (`before`, Send's; `askBefore`, Ask's). An ended session has no Ask Without Interrupting: Send's place says
// what to do. Send's own button says when your words go in (sideChatSendWord). The way you chose last (`way`, from
// sideChatWayNow) is the dark button, and Return goes that way: Ask Without Interrupting is dark only when it's chosen
// and can go, and Send's place whenever it isn't (sideChatUnder moves it as you choose, without drawing this again).
function sideChatBoxHTML(s, chat, name, before, askBefore = sideChatAskBefore(s, chat, name), way = 'send') {
  const room = sideChatRoom(sideChatOpening(s, chat)), cant = before?.way, darkSend = way === 'send',
    darkAsk = way === 'ask' && !askBefore;
  const ask = askBefore?.gone ? ''
    : askBefore?.way ? `<button type="button" class="button small" data-sc="${askBefore.act}"`
      + `${askBefore.at ? ` data-at="${askBefore.at}"` : ''} title="${esc(askBefore.why)}">`
      + `${esc(askBefore.way)}</button>`
    : `<button type="button" class="button small${darkAsk ? ' main' : ''}" data-sc="ask" disabled `
      + `title="${esc(askBefore?.why || sideChatAskTip(name))}" `
      + `aria-keyshortcuts="${darkAsk ? 'Enter' : 'Alt+Enter'}">Ask Without Interrupting</button>`;
  return `<div class="sc-box"><div class="sc-box-row"><input class="field small q-type sc-field" maxlength="${room}" `
    + `placeholder="Message ${esc(name)}${askBefore ? '' : ', or ask without interrupting'}…" `
    + `aria-label="Your words to ${esc(name)}">${ask}`
    + (cant ? `<button type="button" class="button small${darkSend ? ' main' : ''}" data-sc="${before.act}"`
      + `${before.act === 'copyAndGo' ? ' disabled' : ''}>${esc(cant)}</button>`
      : `<button type="button" class="button small${darkSend ? ' main' : ''}" data-sc="send" disabled `
        + `aria-keyshortcuts="${darkSend ? 'Enter' : 'Alt+Enter'}">${esc(sideChatSendWord(s, chat))}</button>`)
    + '</div><span class="sc-goes"></span></div>';
}

// The line under the box: why a press just now couldn't act (`refused`); why words are back in it, with the way past;
// else, while Return asks without interrupting (`way`, from sideChatWayNow), what it will ask, or why it can't just
// now, and with nothing written yet why Send's place can't send (Copy and Go's why among them); else why nothing can
// go in from here, or how they'll go; else exactly what will go in; and, with nothing written yet, why nothing can be
// asked without interrupting (but while a side question is answered, which its line in the chat says).
function sideChatUnderHTML(s, chat, name, words, back, before, askBefore = sideChatAskBefore(s, chat, name),
                           refused = '', way = 'send') {
  if (refused) return `<span class="sc-why">${esc(refused)}.</span>`;
  if (back) return `<span class="sc-why">${esc(back.why)} Your words are back in the box.</span>`
    + (back.way ? ` <button type="button" class="sc-act" data-sc="${back.act}">${esc(back.way)}</button>` : '');
  // With Ask the dark button, Send's words would say where Return doesn't go: the line speaks for Ask instead.
  if (way === 'ask') {
    const said = (words || '').trim();
    if (said && askBefore?.why) return `<span class="sc-why">${esc(askBefore.why)}.</span>`;
    if (said) return esc(`Asks without interrupting: ${said}`);
    return before?.why ? `<span class="sc-why">${esc(before.why)}</span>` : '';
  }
  if (before?.why) return `<span class="sc-why">${esc(before.why)}</span>`;
  if (!(words || '').trim() && askBefore?.why && askBefore.act !== 'askStop') {
    return `<span class="sc-why">${esc(askBefore.why)}.</span>`;
  }
  const goes = sideChatGoes(s, chat, words);
  return `${before?.note ? `<span class="sc-note">${esc(before.note)}.</span> ` : ''}${esc(goes)}`;
}

// Side Chat, the bar at a row's far edge (the row part's edge slot): a button with no words, named for a screen
// reader. While a reply waits it lights the bar in your move's colour (`lit`), and while its chat is the one open it
// keeps it lit (`keep`), pressed for a screen reader.
function sideChatEdgeHTML(sid, name, unseen, open) {
  const edge = sideChatEdge(unseen, name);
  return `<button type="button" class="sc-edge${edge.reply ? ' lit' : ''}${open ? ' keep' : ''}" `
    + `data-sc-open="${esc(sid)}" aria-label="${esc(edge.label)}" aria-pressed="${open}"></button>`;
}
