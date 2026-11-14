// What a side chat says: a conversation with one session beside its main one, your words, how far each got and its
// replies. Plain functions over a session as the list has it and its chat as the app keeps it (setSideChats): drawn
// by side-chat-view.js, checked by tests/page-cases.js.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// A chat, as the app keeps it for a session: { says, asides, askWhyNot, agent, hook, older, frame, front, idleWay }.
// `says` is what you sent, oldest first, each { at, words, state, how, doneAt, late, reply, repliedAt, why, where,
// way, fromAside (a side question sent with Send's words) }; `asides`, what you asked without interrupting, oldest
// first, each { at, question, state, answer, answeredAt, resetsAt, sentAt }, kept in the app's memory only;
// `askWhyNot`, why nothing can be asked without interrupting now ({ why }),
// or null; `agent`, the name of the agent it's asked through ("" when there's none); `hook`,
// whether the session runs Whozmove's hook that hands words in between its steps, and `older`, whether it doesn't
// because it started before the hook went in; `frame`, the words that open yours while it works, as the hook hands
// them in; `front`, the terminal its session is in when that's the app in front; `idleWay`, why nothing can be typed
// into it while it's idle, when nothing can ({ kind: 'cantType', host } or { kind: 'twice' }).

// The most you may write, the words that open yours included (the app's own limit).
const SIDE_CHAT_MOST = 600;

// Whom the chat is with, as its head and its lines name the session: its name on the team, its own, or its folder's.
const sideChatName = (s) => s?.team?.name || s?.name || base(s?.cwd || '') || 'The session';

// Whether a session has ended: a terminal session with no process. A Claude Desktop conversation keeps none while it
// sits idle, and still takes your words, written in its message box once it's open: it never has.
const sideChatEnded = (s) => !s || (s.status === 'closed' && !sideChatDesktop(s));

// Whether Side Chat is offered on a session's row: only while it's listed and running, or a Claude Desktop
// conversation, not while it's still being started (a pending row) nor once it has ended.
const sideChatOffered = (s) => !!s && !s.pending && (sideChatDesktop(s) || (!sideChatEnded(s) && s.pid > 0));

// Whether the session is working (asking for your OK counts: it's in the middle of its turn).
const sideChatWorks = (s) => s?.status === 'busy' || s?.status === 'waiting';
const sideChatDesktop = (s) => s?.entrypoint === 'claude-desktop';

// What Send's own button says, by when your words go in: the same words the failed side question's press offers, so
// that press is named for exactly what it does now. While the session waits on your answer they go in after you've
// answered; while it works, at the end of its current step if its hook hands them in, else when its turn ends; when
// it's idle, there's nothing to wait for.
function sideChatSendWord(s, chat) {
  if (s?.ask && !sideChatEnded(s)) return 'Send After You Answer';
  if (sideChatWorks(s)) return chat?.hook ? 'Send After This Step' : 'Send After Its Turn';
  return 'Send';
}

// The words that open yours, shown before you send: while it works and its hook hands them in, the hook's (typed at
// its prompt, your words go in without them); then those of the view the chat is drawn in, if it names what they're
// about (`opening`). And how many characters your own may have after them.
const sideChatOpening = (s, chat, opening = '') => (sideChatWorks(s) && chat?.hook ? chat.frame || '' : '') + opening;
const sideChatRoom = (opening) => Math.max(0, SIDE_CHAT_MOST - opening.length);

// What's said before you press, under the box: why nothing can go in from here, with the way forward in Send's place
// ({ why, way, act }), or a note on how they'll go ({ note }), or null when there's nothing to say.
function sideChatBefore(s, chat, name) {
  if (sideChatEnded(s)) return { why: 'Its session has ended: open it again, and your words can go in',
                                            way: `Open ${name} Again`, act: 'openAgain' };
  const works = sideChatWorks(s), idleWay = chat?.idleWay;
  if (!works && idleWay?.kind === 'cantType') return { why: `Whozmove can’t type into ${idleWay.host}: Copy and Go `
    + `copies your words and brings ${name}’s window forward`, way: 'Copy and Go', act: 'copyAndGo' };
  // While it works, its hook hands your words in, so another copy can't take them; at its prompt, keys could.
  if (!works && idleWay?.kind === 'twice') return { why: `${name} is open in two places: close the other copy, and `
    + 'your words can go in', way: 'Close the Other Copy', act: 'closeCopy' };
  // Without its agent's hook, words wait for its turn to end; `older` once that's because it started before the hook.
  if (works && !chat?.hook) return { note: sideChatDesktop(s) ? `Claude Desktop takes your words once ${name}’s turn `
    + 'ends' : chat?.older ? `${name} started before this update: your words go in when its turn ends`
    : `Your words go in when ${name}’s turn ends` };
  if (!works && sideChatDesktop(s)) return { note: 'Sending brings Claude Desktop forward' };
  return null;
}

// The line under the box while you write: exactly what will go in, the words that open yours included, and how much
// room is left once it's nearly full. Nothing while the box is empty.
function sideChatGoes(s, chat, words, about = '') {
  const said = (words || '').trim();
  if (!said) return '';
  const opening = sideChatOpening(s, chat, about), left = sideChatRoom(opening) - said.length;
  return `Goes in as: ${opening}${said}${left < 60 ? ` · ${Math.max(0, left)} characters left` : ''}`;
}

// When something happened, as a line says it: "just now", else how long ago ("14m").
const sideChatWhen = (ms) => (ago(ms) === 'now' ? 'just now' : ago(ms));

// What's said under your words by how far they've got, and the presses that go with it: { words, tone, held, acts },
// each act { act, word }, Take Back always first, so a press meant for it never lands on a Send Now that has only just
// come in its place. `tone` is 'wait' while they wait (your move's colour), 'read' once it has them, 'no' when they
// didn't go in. `asks`, what the session asks first, as its row says it; `now`, the time. Take Back until it has
// read them; pressed too late, the app says so (`late`), and so does this.
function sideChatSaid(said, s, chat, name, asks, now) {
  const back = { act: 'takeBack', word: 'Take Back' }, sendNow = { act: 'sendNow', word: 'Send Now' };
  const desktop = sideChatDesktop(s), when = sideChatWhen(now - (said.doneAt || said.at));
  switch (said.state) {
    case 'held':
      if (sideChatEnded(s)) return { words: 'Its session has ended', tone: 'no', held: true,
                                                acts: [back] };
      if (s.ask) return { words: `${name} asks first${asks ? `: ${asks}` : ''}. Answer it on its row, and your words `
        + 'go after', tone: 'wait', held: true, acts: [{ act: 'show', word: 'Show It' }, back] };
      // A side question sent with Send's words (`fromAside`) says when it goes in, as its press promised. Without the
      // hook, a terminal Whozmove can't type into never takes them, so it says what you'll do once its turn ends.
      if (sideChatWorks(s)) return { words: chat?.hook ? (said.fromAside ? `Goes in once ${name}’s step ends`
        : 'Waiting for its current step to end')
        : chat?.idleWay?.kind === 'cantType' ? `Whozmove can’t type into ${chat.idleWay.host}: once ${name}’s turn `
          + 'ends, copy your words and paste them there' : `Goes in when ${name}’s turn ends`, tone: 'wait',
      held: true, acts: [back] };
      // Its turn has ended with your words still here: they go in by themselves only into a terminal that isn't the
      // app in front, and not into the tab you're on; Claude Desktop comes forward only for your press. A terminal
      // Whozmove can't type into never takes them, so they wait for you to copy them there.
      if (desktop) return { words: 'Waits for your Send Now, which brings Claude Desktop forward', tone: 'wait',
                            held: true, acts: [back, sendNow] };
      if (chat?.idleWay?.kind === 'cantType') return { words: `Whozmove can’t type into ${chat.idleWay.host}: copy `
        + 'your words and go there', tone: 'wait', held: true,
      acts: [back, { act: 'copyAndGo', word: 'Copy and Go' }] };
      if (s.focused) return { words: `${name}’s tab is in front: waits for your Send Now`, tone: 'wait', held: true,
                              acts: [back, sendNow] };
      if (chat?.front) return { words: `${chat.front} is in front: waits for your Send Now`, tone: 'wait', held: true,
                                acts: [back, sendNow] };
      return { words: 'Going in…', tone: 'wait', held: true, acts: [back] };
    case 'handed':
      return { words: said.late === 'handed' ? `Already on its way to ${name}` : `Going to ${name}…`, tone: 'wait',
               acts: said.late ? [] : [back] };
    case 'typing': return { words: 'Going in…', tone: 'wait', acts: [] };
    case 'typed': return { words: `${desktop ? 'Sent in Claude Desktop' : 'Typed in'} · ${when}`, tone: '', acts: [] };
    // Copied with Copy and Go: Whozmove no longer holds them, so they go in only as you paste them.
    case 'copied': return { words: `Copied for you to paste · ${when}`, tone: '', acts: [] };
    case 'read':
    case 'replied':
      return { words: `${said.how === 'turnEnd' ? 'Read as its turn ended · it carried on' : said.how === 'typed'
        ? `${desktop ? 'Sent in Claude Desktop' : 'Typed in'}` : 'Read between steps'} · ${when}${said.late === 'read'
        ? ` · ${name} has read this already` : ''}`, tone: 'read', acts: [] };
    case 'stopped':
      return { words: `${name} stopped before reading this`, tone: 'no',
               acts: [back, chat?.idleWay?.kind === 'cantType' ? { act: 'copyAndGo', word: 'Copy and Go' } : sendNow] };
    case 'noReply': return { words: `${name} finished without a reply`, tone: '',
                             acts: [{ act: 'there', word: 'Take Me There' }] };
    default: return { words: '', tone: '', acts: [] };
  }
}

// Words the app put back in your box, as the line under it says why ({ why, way, act }): its session ended before they
// went in, Whozmove restarted, or they couldn't be typed in (the terminal's own reason, and its way past, if any). Words
// you took back need no why: null.
const SIDE_CHAT_BACK = ['takenBack', 'ended', 'restarted', 'refused', 'notSent'];
function sideChatBack(said, name) {
  if (said.state === 'takenBack') return null;
  if (said.state === 'ended') return { why: `${name}’s session ended before this went in.`, way: `Open ${name} Again`,
                                       act: 'openAgain' };
  if (said.state === 'restarted') return { why: 'Whozmove restarted before this went in.', way: null, act: null };
  if (said.state === 'notSent') return { why: `${said.why || 'It couldn’t go from here'}.`, way: null, act: null };
  const why = /[.!?]$/.test(said.why || '') ? said.why : `${said.why || 'It didn’t go in'}.`;
  return { why: `Can’t type${said.where ? ` into ${said.where}` : ' it in'}. ${why}`, way: said.way || null,
           act: !said.way ? null : said.permission ? 'accessibility' : 'wayPast' };
}

// Over words or a side question sent from a view that named what they're about (`opening`, One Task's task and step),
// those words, quietly, without the colon that led into yours; nothing for those sent from the chat's own window.
const sideChatAboutWords = (said) => (said?.opening || '').replace(/:?\s*$/, '');

// What VoiceOver is told where the chat is drawn: the newest reply or side answer that came after `since`, by who said
// it ("Wren: …", "A copy of Wren: …"), a code block as "A command to copy."; null when nothing new came.
function sideChatSayAloud(chat, since, name) {
  const came = (chat?.says || []).filter((said) => said.state === 'replied' && (said.repliedAt || 0) > since)
    .map((said) => ({ at: said.repliedAt, who: name, parts: said.reply }))
    .concat((chat?.asides || []).filter((aside) => aside.state === 'answered' && (aside.answeredAt || 0) > since)
      .map((aside) => ({ at: aside.answeredAt, who: sideChatCopyName(name), parts: aside.answer })));
  const newest = came.sort((a, b) => b.at - a.at)[0];
  if (!newest) return null;
  const words = sideChatReply(newest.parts).map((part) => (part.code !== undefined ? 'A command to copy.' : part.prose));
  return { at: newest.at, words: `${newest.who}: ${words.join(' ')}` };
}
// When the newest reply or side answer in a chat came, or 0.
const sideChatNewest = (chat) => Math.max(0, ...(chat?.says || []).map((said) => said.repliedAt || 0),
                                          ...(chat?.asides || []).map((aside) => aside.answeredAt || 0));

// What the conversation draws: your words that are still in it, those put back in the box left out.
const sideChatShown = (says) => (says || []).filter((said) => !SIDE_CHAT_BACK.includes(said.state));

// A reply as it's shown, from its parts as the app cut it (each {prose} or {code, lang}), whole: the conversation
// scrolls. Each code block keeps its place among the parts (`n`), which its Copy names.
const sideChatReply = (parts) => (Array.isArray(parts) ? parts : []).map((part, n) => (typeof part?.code === 'string'
  ? { code: part.code, lang: String(part.lang || ''), n } : { prose: String(part?.prose || '') }))
  .filter((part) => part.code !== undefined || part.prose);

// When the newest reply came that you haven't seen, or 0: its reply to your words, after `seenAt` (when you last had its
// chat open or were in its tab), or a side question's answer, after `asideSeenAt` (when you last had its chat open:
// its tab doesn't show it).
const sideChatUnseen = (chat, seenAt, asideSeenAt = seenAt) => sideChatAnswers(chat).reduce((newest, one) => (
  one.at > ((one.aside ? asideSeenAt : seenAt) || 0) ? Math.max(newest, one.at) : newest), 0);

// Every reply in a chat, as { at, reply, aside }: when it came, its parts, and whether it was a side question's answer.
const sideChatAnswers = (chat) => (chat?.says || []).filter((said) => said.state === 'replied')
  .map((said) => ({ at: said.repliedAt || 0, reply: said.reply, aside: false }))
  .concat((chat?.asides || []).filter((aside) => aside.state === 'answered')
    .map((aside) => ({ at: aside.answeredAt || 0, reply: aside.answer, aside: true })));

// When you last saw a session's chat, from when it was last kept (`kept`) and the session as listed now: being in its
// tab counts, as the app last saw you there (its `seenAt`), and stays counted after you leave.
const sideChatSeenIn = (kept, s) => Math.max(kept || 0, s?.focused ? s.seenAt || 0 : 0);

// What's new in a session's side chat, for notifications (core.sessionNews): a reply you haven't seen, by when it came,
// as your move to make when you can, or null once you've seen it, in its chat or its tab (`seenAt`), and on a row
// without Side Chat.
// With it, the line its chat beside the folded panel shows in Claude's line's place, and when the reply came.
function sideChatNews(s, chat, seenAt, asideSeenAt = seenAt) {
  const unseen = sideChatOffered(s) ? sideChatUnseen(chat, seenAt, asideSeenAt) : 0;
  if (!unseen) return null;
  const one = sideChatAnswers(chat).find((each) => each.at === unseen);
  return { news: `side:${unseen}`, level: 'soon', line: sideChatNewsLine(one?.reply, one?.aside), at: unseen };
}

// A reply as one line beside the folded panel: "In your side chat: " (or "Asked without interrupting: ", for a side
// question's answer) and its first words, as plain text (sideChatPlain), at most SIDE_CHAT_NEWS_MOST characters, cut
// with "…"; a reply that's only a command says so.
const SIDE_CHAT_NEWS_MOST = 160;
function sideChatNewsLine(reply, aside) {
  const parts = sideChatReply(reply), prose = parts.find((part) => part.prose)?.prose;
  const words = prose ? sideChatPlain(prose) : parts.length ? 'a command to copy' : 'a reply';
  const line = `${aside ? 'Asked without interrupting' : 'In your side chat'}: ${words}`;
  return line.length <= SIDE_CHAT_NEWS_MOST ? line : `${line.slice(0, SIDE_CHAT_NEWS_MOST - 1).trimEnd()}…`;
}

// A reply's Markdown as the words it reads as, on one line: a heading's leading #s and a quote's leading > go, a link
// keeps its words without its address, and marks that pair up go (`code`, **bold**, *it*, _it_, and __this__ around
// words with a space between), while a mark inside a word stays, so user_id, snake_case and __init__ read as written.
function sideChatPlain(prose) {
  return prose.split('\n').map((line) => line.replace(/^\s*#{1,6}\s+/, '').replace(/^\s*>\s?/, '')).join(' ')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/`([^`\n]+)`/g, '$1')
    .replace(/\*\*(?=\S)([^*]+?)\*\*/g, '$1')
    .replace(/(^|[^\w*])\*(?=\S)([^*]+?)\*(?![\w*])/g, '$1$2')
    .replace(/(^|[^\w])__(?=\S)([^_]*\s[^_]*?)__(?!\w)/g, '$1$2')
    .replace(/(^|[^\w])_([A-Za-z0-9](?:[^_]*?[A-Za-z0-9])?)_(?!\w)/g, '$1$2')
    .replace(/\s+/g, ' ').trim();
}

// Side Chat, the bar at a row's far edge: lit in your move's colour while a reply waits that you haven't seen; what a
// screen reader says for it, whose chat it opens.
const sideChatEdge = (unseen, name) => ({ reply: !!unseen,
                                          label: `Side Chat with ${name}${unseen ? ', a reply waiting' : ''}` });

// The line under the chat's head: what the session is doing now, in a word or two as every state says itself. While
// it works, each step it takes is at the conversation's foot (sideChatWorking), where its reply will come.
function sideChatLive(s, name, asks) {
  if (sideChatEnded(s)) return { words: 'Its session has ended', works: false };
  if (s.ask) return { words: asks || `${name} asks for your OK`, works: true };
  if (s.compacting) return { words: 'Compacting', works: true };
  if (sideChatWorks(s)) return { words: 'Working', works: true };
  return { words: 'Waiting for you', works: false };
}

// Drawn in another view (core.sessionChat), the chat has no head of its own: while the session asks for your OK, the
// same words its head says (sideChatLive) end the conversation, with Show It for its request, so what Send waits on is
// in sight there too. Null otherwise: an ended session is said under the box, with Open Again.
function sideChatHostedLive(s, name, asks) {
  if (sideChatEnded(s) || !s?.ask) return null;
  return { ...sideChatLive(s, name, asks), acts: [{ act: 'show', word: 'Show It' }] };
}

// Whether the conversation ends with the line its row shows while it works (the row part's workLineHTML): "Thinking"
// until its first step, then each step as it runs, or that it's compacting, timed. Not while it asks for your OK,
// which its head says, as its row does in that line's place.
const sideChatWorking = (s) => !sideChatEnded(s) && !s.ask && (s.status === 'busy' || !!s.compacting);

// That line as it reads, so it's drawn again only when what it says changes, its time ticking in between: the row
// part's own line at a fixed time, without the offsets each drawing takes from the clock to keep its shine and its
// label's breath going (its style), which would make every second's drawing a new one.
const sideChatWorkKey = (s, name) => (sideChatWorking(s)
  ? workLineHTML(s, 0, { label: name }).replace(/ style="[^"]*"/g, '') : '');

// Who answers a side question, over its answer: a copy of the session, never the session itself.
const sideChatCopyName = (name) => `A copy of ${name}`;
// While a side question is being asked, its answer's place has the same line under the copy's name, at the chat's
// full width (its own label left out: side-chat.css), one line, a long step ending in "…": "Thinking" until its agent
// says its first step, then each step (its `step`), its time from your press. Drawn again only when what it says
// changes, as the session's own is (sideChatWorkKey). `still` where the chat is drawn in another view: no shine.
const sideChatAsideWorkHTML = (aside, name, now, still = false) => workLineHTML(
  { activity: aside.step || '', lastPromptAt: aside.at }, now, { label: sideChatCopyName(name), still });
const sideChatAsideWorkKey = (aside, name) => (aside?.state === 'asking'
  ? sideChatAsideWorkHTML(aside, name, 0).replace(/ style="[^"]*"/g, '') : '');

// What an empty chat says, over the box: idle, your words go straight in, unless nothing can go in from here, which the
// line under the box says, with the way forward.
function sideChatEmpty(s, chat, name) {
  // While it waits on your answer to a request, a question or a plan: ask about it without interrupting first, where
  // you can.
  if (s?.ask && !sideChatEnded(s)) {
    const first = sideChatAskBefore(s, chat, name) ? ''
      : ` Ask Without Interrupting, and a copy of ${name} answers about it first; ${name} won’t see it.`;
    return `${name} is waiting for your answer on its row.${first} Words you send go in `
      + `${chat?.hook ? 'once you’ve answered, between its steps' : 'when its turn ends'}.`;
  }
  const aside = sideChatAskBefore(s, chat, name) ? ''
    : ` Ask Without Interrupting, and a copy of ${name} answers here; ${name} won’t see it.`;
  if (!sideChatWorks(s)) return sideChatBefore(s, chat, name)?.why ? `Its answers come back here.${aside}`
    : `Words you send here go straight in to ${name}, and its answers come back here.${aside}`;
  return `Words you send here reach ${name} ${chat?.hook ? 'between its steps' : 'when its turn ends'}, and its `
    + `answers come back here.${aside}`;
}

// ---- Asked without interrupting ----

// The name of the agent a session is asked through without interrupting, as the app tells it, for what's said when
// its own command can't be found or it's signed out; "its agent" when it hasn't said, capitalised only to open a
// sentence.
const sideChatAgent = (chat) => chat?.agent || 'its agent';
const sideChatCapital = (words) => words.charAt(0).toUpperCase() + words.slice(1);

// Why nothing can be asked without interrupting now, in the Ask Without Interrupting button's place ({ why, way, act,
// at }), or null when it can. An ended session's way is Send's (Open Again), so Ask Without Interrupting isn't there at
// all; one question at a time, so while one is asked its Stop is in Ask's place (`at`, the question's).
function sideChatAskBefore(s, chat, name) {
  const agent = sideChatAgent(chat);
  if (sideChatEnded(s)) return { why: '', way: null, act: null, gone: true };
  if (sideChatDesktop(s)) return { why: `Not in Claude Desktop yet: ask ${name} there`, way: 'Take Me There',
                                   act: 'there' };
  const asking = (chat?.asides || []).find((aside) => aside.state === 'asking');
  if (asking) return { why: `A copy of ${name} is still answering your last question`, way: 'Stop',
                       act: 'askStop', at: asking.at };
  switch (chat?.askWhyNot?.why) {
    case 'noCommand': return { why: `Asking without interrupting needs ${agent}’s own command, which isn’t on this `
                                 + 'Mac', way: `Get ${agent}`, act: 'getAgent' };
    case 'notStarted': return { why: `Nothing to ask about yet: ${name} hasn’t said anything`, way: null,
                                act: null };
    case 'noConversation': return { why: `Whozmove can’t find ${name}’s conversation to ask a copy of it`,
                                    way: 'Take Me There', act: 'there' };
    default: return null;
  }
}

// The way you chose last, which is the dark button and where Return goes: 'ask' only where you pressed Ask Without
// Interrupting last and Ask's place still is it, or is Stop for a copy still answering (`askBefore`, from
// sideChatAskBefore, null when Ask can go). Everywhere else it's Send, since Return must never go to a button that
// isn't there or can't act: on Claude Desktop, on an ended session, or with any other can't in Ask's place.
function sideChatWayNow(chosen, askBefore) {
  return chosen === 'ask' && (!askBefore || askBefore.act === 'askStop') ? 'ask' : 'send';
}

// What a key in the box does: Return goes the way you chose last (`way`, from sideChatWayNow), so it's the dark
// button's; ⌥Return goes the other way; Esc closes the chat; anything else, nothing of side chat's (null).
function sideChatKeyAct(e, way = 'send') {
  if (e.key === 'Enter') {
    const other = way === 'ask' ? 'send' : 'ask';
    return e.altKey ? other : way;
  }
  return e.key === 'Escape' ? 'close' : null;
}

// The tip on Ask Without Interrupting, and what VoiceOver says for a side question and its answer.
const sideChatAskTip = (name) => `A copy of ${name} answers here. ${name} won’t see this or stop`;
const sideChatAsideLabel = (name) => `Asked without interrupting: ${name} didn’t see this`;

// A clock time, in the Mac's own way of writing one ("3:00 PM"). `locale` and `timeZone` are for tests.
const sideChatClock = (at, locale, timeZone) => (at > 0
  ? new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).format(at) : '');

// What's said in a side question's answer's place by how far it got, with its presses ({ words, acts }, each act
// { act, word }): under the copy's name, but for one sent the normal way, said under the question itself, as the
// copy didn't send it. Being asked, nothing: the line its agent's steps go on is there instead
// (sideChatAsideWorkHTML). Answered, its answer is drawn there, with Add to Message and Copy. None is red: red is for your words to the
// session that didn't go in, and a side question never goes to it. `busy`, another is being asked now: one at a time,
// so no Ask Again until it's answered. The agent it was asked through is the chat's (sideChatAgent). One the copy
// couldn't answer offers Send's own words for the session now (sideChatSendWord, the act `waitTurn`), which sends the
// question the normal way, as Send does, so the session itself sees it and answers once its step ends; once sent
// (`sentAt`), it says so, and your words follow below it.
function sideChatAsideSaid(aside, s, chat, name, busy) {
  const agent = sideChatAgent(chat), turn = { act: 'waitTurn', word: sideChatSendWord(s, chat) };
  const again = busy ? [] : [{ act: 'askAgain', word: 'Ask Again' }], failed = [...again, turn];
  if (aside?.sentAt) return { words: `Sent to ${name}`, acts: [] };
  switch (aside?.state) {
    case 'asking': return { words: '', acts: [] };
    case 'answered': return { words: '', acts: [{ act: 'addAnswer', word: 'Add to Message' },
                                                { act: 'asideCopy', word: 'Copy' }] };
    case 'tooSlow': return { words: 'Took too long', acts: failed };
    case 'noAnswer': return { words: 'Didn’t answer', acts: failed };
    case 'apiError': return { words: `${sideChatCapital(agent)} couldn’t answer just now`, acts: failed };
    case 'notAsked': return { words: 'Couldn’t be asked just then', acts: failed };
    case 'noCommand': return { words: `${sideChatCapital(agent)}’s own command wasn’t found`,
                               acts: [{ act: 'getAgent', word: `Get ${agent}` }] };
    case 'wantedTool': return { words: 'Wanted to read more than a side question may', acts: failed };
    case 'limit': return { words: `Your plan’s limit is reached${aside.resetsAt
      ? ` until ${sideChatClock(aside.resetsAt)}` : ''}`,
                           acts: [{ act: 'asideCopyQuestion', word: 'Copy the Question' }] };
    case 'signedOut': return { words: `${sideChatCapital(agent)} is signed out`,
                               acts: [{ act: 'copySignIn', word: 'Copy the Sign-In Command' }] };
    case 'tooLong': return { words: 'Too long to read again', acts: [turn] };
    case 'stopped': return { words: 'Stopped', acts: again };
    default: return { words: '', acts: [] };
  }
}

// Where the side conversation's memory starts, worked out from the newest answered side question alone: of the n
// answered before it, it knew the newest `remembered` (r), so a quiet line goes above the first of those it knew,
// answered one n − r, or above the newest itself when it knew none; drawn once at most, so a later compaction moves
// it. The `at` of the side question the line goes above, or null for none (it knew them all, or doesn't say).
function sideChatForgotAbove(asides) {
  const answered = (asides || []).filter((aside) => aside.state === 'answered');
  const newest = answered[answered.length - 1], n = answered.length - 1, r = newest?.remembered;
  if (!newest || typeof r !== 'number' || r >= n) return null;
  return answered[n - Math.max(0, r)].at;
}
const sideChatForgotLine = 'A copy no longer knows the questions above';

// A side question's answer as words in your box (Add to Message): "I asked a copy of you “…” and it said: " with its
// first SIDE_CHAT_QUESTION_MOST characters, then the answer as plain text on one line, after what's in the box
// already, never in its place, and cut with "…" to the room the box has (`room`). What's in the box, unchanged, when
// there's no room for even the start.
const SIDE_CHAT_QUESTION_MOST = 60;
function sideChatAddAnswer(question, answer, draft, room) {
  const cut = (words, most) => (words.length <= most ? words : `${words.slice(0, most - 1).trimEnd()}…`);
  const before = (draft || '').trim();
  const head = `${before ? `${before} ` : ''}I asked a copy of you “${cut((question || '').trim(),
                                                                         SIDE_CHAT_QUESTION_MOST)}” and it said: `;
  const words = sideChatReply(answer).map((part) => (part.code !== undefined
    ? `\`${part.code.replace(/\s+/g, ' ').trim()}\`` : sideChatPlain(part.prose))).join(' ');
  if (head.length + 1 > room || !words) return draft || '';
  return head + cut(words, room - head.length);
}

// The question, put in your box after what's there, for the session to answer itself, cut to the box's room: what
// Send's words put there for a question too long to send as it is.
function sideChatQuestionInBox(question, draft, room) {
  const before = (draft || '').trim(), joined = `${before ? `${before} ` : ''}${(question || '').trim()}`;
  return joined.length <= room ? joined : `${joined.slice(0, room - 1).trimEnd()}…`;
}
