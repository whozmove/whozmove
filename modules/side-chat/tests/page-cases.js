// The side chat's part of the page, run outside the app by test.sh: what it says before you send, how far your words
// got, its replies, and Side Chat on the row (side-chat-words.js), and the HTML they're drawn as (side-chat-view.js).
// Nothing is drawn on a screen.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

const FRAME = 'The user sent this from Whozmove while you were working: ';
const wren = (fields) => session({ sessionId: 'wren', name: 'Wren', cwd: '/work/checkout', ...fields });
const working = wren({ status: 'busy', activity: 'Running tests · checkout.spec.ts' });
const asking = wren({ status: 'waiting', ask: { id: 'a1', tool: 'Bash', input: { command: 'npm run migrate' } } });
const idle = wren({ status: 'idle' });
const ended = wren({ status: 'closed', pid: 0 });
const desktop = wren({ status: 'idle', entrypoint: 'claude-desktop' });
const chat = (fields) => ({ says: [], hook: true, frame: FRAME, front: '', idleWay: null, agent: 'Claude Code',
                            ...fields });
const said = (state, fields) => ({ at: min(3), words: 'Do the smaller migration first.', state, ...fields });
const says = (s, c, one, asks = '') => {
  const st = sideChatSaid(one, s, c, 'Wren', asks, NOW);
  return `${st.words}${st.held ? ' (held)' : ''}${st.tone ? ` [${st.tone}]` : ''}`
    + `${st.acts.length ? ` · ${st.acts.map((a) => a.word).join(' | ')}` : ''}`;
};

section('Whom it\'s with');
show('its name', sideChatName(wren()));
show('a team member\'s name first', sideChatName(wren({ team: { role: 'member', name: 'Ivy' } })));
show('no name: its folder\'s', sideChatName(session({ name: '', cwd: '/work/rq' })));
show('not listed', sideChatName(undefined));

section('Before you send: why nothing can go in, or how it will');
show('working, with the hook: nothing to say', sideChatBefore(working, chat(), 'Wren'));
show('idle in a terminal it can type into: nothing to say', sideChatBefore(idle, chat(), 'Wren'));
show('its session has ended', sideChatBefore(ended, chat(), 'Wren'));
show('not listed any more', sideChatBefore(undefined, chat(), 'Wren'));
show('idle in Terminal', sideChatBefore(idle, chat({ idleWay: { kind: 'cantType', host: 'Terminal' } }), 'Wren'));
show('working in Terminal: the hook hands words in, nothing typed',
     sideChatBefore(working, chat({ idleWay: { kind: 'cantType', host: 'Terminal' } }), 'Wren'));
show('idle, open in two places', sideChatBefore(idle, chat({ idleWay: { kind: 'twice' } }), 'Wren'));
show('working, open in two places: the hook hands words in', sideChatBefore(working, chat({ idleWay: { kind: 'twice' } }),
                                                                           'Wren'));
show('working, its agent with no hook yet', sideChatBefore(working, chat({ hook: false }), 'Wren'));
show('working, started before this update', sideChatBefore(working, chat({ hook: false, older: true }), 'Wren'));
show('working in Claude Desktop, with no hook', sideChatBefore(wren({ status: 'busy', entrypoint: 'claude-desktop' }),
                                                               chat({ hook: false }), 'Wren'));
show('idle in Claude Desktop', sideChatBefore(desktop, chat(), 'Wren'));

section('What goes in, shown whole under the box');
show('nothing written', sideChatGoes(working, chat(), '  '));
show('working: the words that open yours, then yours', sideChatGoes(working, chat(), 'Do the smaller migration first.'));
show('idle: yours alone, typed', sideChatGoes(idle, chat(), 'Do the smaller migration first.'));
show('working, started before this update: yours alone, at its turn\'s end',
     sideChatGoes(working, chat({ hook: false }), 'Keep the old table.'));
show('room for your own words while it works', sideChatRoom(sideChatOpening(working, chat())));
show('room while it\'s idle', sideChatRoom(sideChatOpening(idle, chat())));
show('nearly full: how much is left', sideChatGoes(working, chat(), 'x'.repeat(500)).slice(-28));

section('How far your words got (Take Back always first, so Send Now never comes in its place)');
show('waiting while it works', says(working, chat(), said('held')));
show('…a side question sent with Send\'s words: when it goes in',
     says(working, chat(), said('held', { fromAside: true })));
show('waiting while it asks first', says(asking, chat(), said('held'), 'Wants to run a command'));
show('waiting, started before this update', says(working, chat({ hook: false }), said('held')));
show('its turn ended, no hook: going in by themselves', says(idle, chat({ hook: false }), said('held')));
show('its turn ended, its tab is the one you\'re on', says(wren({ status: 'idle', focused: true }), chat({ hook: false }),
                                                          said('held')));
show('its turn ended, its terminal in front', says(idle, chat({ hook: false, front: 'Ghostty' }), said('held')));
show('its turn ended, in a terminal Whozmove can\'t type into',
     says(idle, chat({ hook: false, idleWay: { kind: 'cantType', host: 'Terminal' } }), said('held')));
show('…while it works, started before this update',
     says(working, chat({ hook: false, idleWay: { kind: 'cantType', host: 'Terminal' } }), said('held')));
show('…copied with Copy and Go', says(idle, chat({ hook: false, idleWay: { kind: 'cantType', host: 'Terminal' } }),
                                       said('copied', { doneAt: min(1) })));
show('its turn ended in Claude Desktop', says(desktop, chat({ hook: false }), said('held')));
show('its session ended while they waited', says(ended, chat(), said('held')));
show('handed to its hook', says(working, chat(), said('handed')));
show('Take Back pressed once they were on their way', says(working, chat(), said('handed', { late: 'handed' })));
show('typed at its prompt', says(idle, chat(), said('typing')));
show('typed in', says(idle, chat(), said('typed', { doneAt: NOW })));
show('sent in Claude Desktop', says(desktop, chat(), said('typed', { doneAt: min(2) })));
show('read between steps', says(working, chat(), said('read', { how: 'step', doneAt: NOW })));
show('read as its turn ended', says(working, chat(), said('read', { how: 'turnEnd', doneAt: min(9) })));
show('Take Back pressed once it had read them', says(working, chat(), said('read', { how: 'step', doneAt: NOW,
                                                                                     late: 'read' })));
show('replied, after reading them between steps', says(working, chat(), said('replied', { how: 'step', doneAt: min(14) })));
show('it stopped before reading them', says(idle, chat(), said('stopped')));
show('it stopped before reading them, in Terminal', says(idle, chat({ idleWay: { kind: 'cantType', host: 'Terminal' } }),
                                                         said('stopped')));
show('it finished without a reply', says(idle, chat(), said('noReply')));

section('Words put back in the box');
show('taken back: no why', sideChatBack(said('takenBack'), 'Wren'));
show('its session ended first', sideChatBack(said('ended'), 'Wren'));
show('Whozmove restarted first', sideChatBack(said('restarted'), 'Wren'));
show('couldn\'t be typed in, with the way past', sideChatBack(said('refused', { where: 'iTerm2',
  why: 'Its Python API is off', way: 'Turn It On' }), 'Wren'));
show('couldn\'t be typed in, no reason given', sideChatBack(said('refused'), 'Wren'));
show('what the conversation shows of them', sideChatShown([said('read'), said('ended'), said('held'), said('restarted'),
                                                           said('takenBack')])
  .map((one) => one.state).join(', '));

section('A reply');
show('prose and a command, each in its place', sideChatReply([{ prose: 'Okay: the smaller migration first.' },
  { code: 'npm run migrate -- --dry-run', lang: 'sh' }, { prose: '' }, { prose: 'Then I carry on.' }]));
show('nothing usable', sideChatReply(null));

section('Side Chat on the row');
show('offered on a running session\'s row', sideChatOffered(working));
show('not on a session still being started', sideChatOffered(wren({ pending: true, pid: 0 })));
show('not on one that has ended', sideChatOffered(ended));
const desktopIdle = wren({ status: 'closed', pid: 0, entrypoint: 'claude-desktop' });
show('on a Claude Desktop conversation sitting idle with no process', sideChatOffered(desktopIdle));
show('…which hasn\'t ended: before you send', sideChatBefore(desktopIdle, chat(), 'Wren'));
show('…under its head', sideChatLive(desktopIdle, 'Wren', ''));
const replied = chat({ says: [said('replied', { repliedAt: min(2) }), said('replied', { repliedAt: min(1) })] });
show('no reply waiting', sideChatEdge(sideChatUnseen(chat(), 0), 'Wren'));
show('a reply you haven\'t seen', sideChatEdge(sideChatUnseen(replied, min(5)), 'Wren'));
show('when the newest came', sideChatUnseen(replied, min(5)) === min(1));
show('seen since', sideChatEdge(sideChatUnseen(replied, min(1)), 'Wren'));
const inTab = sideChatSeenIn(0, wren({ focused: true, seenAt: min(0.5) }));
show('in its tab since the reply came: seen', sideChatEdge(sideChatUnseen(replied, inTab), 'Wren'));
show('…and still seen once you\'ve left its tab', sideChatEdge(sideChatUnseen(replied,
  sideChatSeenIn(inTab, wren({ focused: false, seenAt: min(0.5) }))), 'Wren'));
show('in its tab before the reply came: not seen', sideChatEdge(sideChatUnseen(replied,
  sideChatSeenIn(0, wren({ focused: true, seenAt: min(3) }))), 'Wren'));

section('What\'s new, for notifications');
show('a reply you haven\'t seen', sideChatNews(working, replied, min(5)));
show('…with its words as one line', sideChatNews(working, chat({ says: [said('replied', { repliedAt: min(1),
  reply: [{ prose: 'Yes: it is **search-v2** now.\n\nThe old one stays.' }] })] }), min(5)));
show('…a long reply, cut', sideChatNewsLine([{ prose: 'word '.repeat(60) }]));
show('…only a command', sideChatNewsLine([{ code: 'npm test' }]));
for (const [what, prose] of [
  ['…code: its words, a _ in them kept', 'Rename the `user_id` column.'],
  ['…words with _ in them, as written', 'snake_case and file_names stay; so does __init__.py.'],
  ['…bold, its marks out', 'This is **the smaller** one.'],
  ['…emphasis with * and _, their marks out', 'Do *this* first, then _that_.'],
  ['…__bold__ around words', 'It is __very important__ now.'],
  ['…a heading and a quote', '# Plan\n> Keep the old table.'],
]) show(what, sideChatNewsLine([{ prose }]));
show('…a link: its words, not its address',
     sideChatNewsLine([{ prose: 'See [the PR](https://github.example/pr/12) and `npm test`.' }]));
show('seen in its chat or its tab', sideChatNews(working, replied, min(1)));
show('no reply', sideChatNews(working, chat(), 0));
show('its session has ended', sideChatNews(ended, replied, 0));

section('Under the head, and an empty chat');
show('working', sideChatLive(working, 'Wren', ''));
show('working, its step not named yet', sideChatLive(wren({ status: 'busy' }), 'Wren', ''));
show('asking', sideChatLive(asking, 'Wren', 'Wants to run a command'));
show('idle', sideChatLive(idle, 'Wren', ''));
show('ended', sideChatLive(ended, 'Wren', ''));
show('compacting by itself, idle otherwise', sideChatLive(wren({ status: 'idle', compacting: min(1) }), 'Wren', ''));

section('The line its row shows while it works, at the conversation\'s foot');
show('working: there', sideChatWorking(working));
show('working, its step not named yet: there (Thinking)', sideChatWorking(wren({ status: 'busy' })));
show('compacting: there', sideChatWorking(wren({ status: 'idle', compacting: min(1) })));
show('asking for your OK: not there, its head says so', sideChatWorking(asking));
show('idle: not there, its reply in its place', sideChatWorking(idle));
show('ended: not there', sideChatWorking(ended));
// A second on, the line's shine and breath take their offsets from a later clock: still the same line.
const keyNow = sideChatWorkKey(working, 'Wren'), clock = performance.now;
performance.now = () => 1234;
const keyLater = sideChatWorkKey(working, 'Wren');
performance.now = clock;
show('drawn again for a new step, not for a second gone by',
     [keyNow === keyLater,
      sideChatWorkKey(working, 'Wren') !== sideChatWorkKey({ ...working, activity: 'Reading cart.ts' }, 'Wren'),
      sideChatWorkKey(working, 'Wren') !== sideChatWorkKey(working, 'Ivy'),
      sideChatWorkKey(idle, 'Wren')]);
show('the row\'s own line, under the session\'s name', workLineHTML(working, NOW, { label: 'Wren' })
  .replace(/style="[^"]*"/g, 'style="…"'));
show('…a name that is markup is shown as text', workLineHTML(working, NOW, { label: '<b>Wren</b>' })
  .replace(/style="[^"]*"/g, 'style="…"'));

section('An empty chat');
show('empty, working, with the hook', sideChatEmpty(working, chat(), 'Wren'));
show('empty, working, with no hook', sideChatEmpty(working, chat({ hook: false }), 'Wren'));
show('empty, idle: straight in', sideChatEmpty(idle, chat({ hook: false }), 'Wren'));
show('empty, idle in Terminal: nothing can go in from here', sideChatEmpty(idle,
  chat({ idleWay: { kind: 'cantType', host: 'Terminal' } }), 'Wren'));
show('empty, idle, open in two places', sideChatEmpty(idle, chat({ idleWay: { kind: 'twice' } }), 'Wren'));

section('As HTML (side-chat-view.js)');
show('the head', sideChatHeadHTML('Wren', 'checkout').replace(CLOSE_ICON, '✕'));
show('a name that is markup is shown as text', sideChatHeadHTML('<b>Wren</b>', 'a&b').replace(CLOSE_ICON, '✕'));
show('the live line, working', sideChatLiveHTML(sideChatLive(working, 'Wren', '')));
show('an empty conversation', sideChatLinesHTML(chat(), working, 'Wren', '', NOW));
show('words waiting, then words read and replied to, a command copied',
     sideChatLinesHTML(chat({ says: [said('replied', { at: min(14), how: 'step', doneAt: min(14), repliedAt: min(13),
       reply: [{ prose: 'Okay: **the smaller** migration first.' }, { code: 'npm run migrate -- --dry-run' }] }),
       said('held', { at: min(1), words: 'And keep <the old> table.' })] }), working, 'Wren', '', NOW,
     { [`${min(14)} 1`]: true }));
show('a reply read before Whozmove last started: in its session', sideChatLinesHTML(chat({ says: [said('replied',
  { how: 'step', doneAt: min(20), repliedAt: min(19) })] }), idle, 'Wren', '', NOW));
show('the box while it works', sideChatBoxHTML(working, chat(), 'Wren', sideChatBefore(working, chat(), 'Wren')));
show('the box in Terminal at idle', sideChatBoxHTML(idle, chat({ idleWay: { kind: 'cantType', host: 'Terminal' } }),
  'Wren', sideChatBefore(idle, chat({ idleWay: { kind: 'cantType', host: 'Terminal' } }), 'Wren')));
show('under the box: what goes in', sideChatUnderHTML(working, chat(), 'Wren', 'Do <it> now.', null, null));
show('under the box: how they\'ll go, with no hook', sideChatUnderHTML(working, chat({ hook: false }), 'Wren', 'Hi.',
  null, sideChatBefore(working, chat({ hook: false }), 'Wren')));
show('under the box: why nothing can go in', sideChatUnderHTML(ended, chat(), 'Wren', 'Hi.', null,
  sideChatBefore(ended, chat(), 'Wren')));
show('under the box: words back in it', sideChatUnderHTML(working, chat(), 'Wren', 'Hi.',
  sideChatBack(said('ended'), 'Wren'), null));
show('Side Chat, the bar at a row\'s far edge: no words, named for a screen reader', sideChatEdgeHTML('wren', 'Wren', 0, false));
show('…with a reply waiting: it lights the bar in your move\'s colour', sideChatEdgeHTML('wren', 'Wren', min(1), false));
show('…while its chat is open: kept lit, and pressed', sideChatEdgeHTML('wren', 'Wren', 0, true));
show('…its name written out for its label', sideChatEdgeHTML('w"1', 'A "quoted" <name>', 0, false));

section('Send says when your words go in');
show('idle: Send', sideChatSendWord(idle, chat()));
show('…Claude Desktop, idle: Send', sideChatSendWord(desktop, chat({ hook: false })));
show('working, with its hook: after this step', sideChatSendWord(working, chat()));
show('working, without its hook: after its turn', sideChatSendWord(working, chat({ hook: false })));
show('waiting on your answer: after you answer', sideChatSendWord(asking, chat()));
show('…without its hook too', sideChatSendWord(asking, chat({ hook: false })));
show('its session has ended: Send', sideChatSendWord(ended, chat()));
show('not listed: Send', sideChatSendWord(undefined, undefined));

section('Asked without interrupting');
const aside = (state, fields) => ({ at: min(4), question: 'Why that file?', state, ...fields });
const answer = [{ prose: 'Because **checkout.ts** holds the cart.' }, { code: 'npm test -- cart' }];
const asked = (one, busy, agent = 'Claude Code', s = working, hook = true) => {
  const st = sideChatAsideSaid(one, s, chat({ agent, hook }), 'Wren', busy);
  return `${st.words}${st.acts.length ? ` · ${st.acts.map((a) => a.word).join(' | ')}` : ''}`;
};
show('Ask Without Interrupting, working, with nothing in the way', sideChatAskBefore(working, chat(), 'Wren'));
show('…idle: asked all the same', sideChatAskBefore(idle, chat(), 'Wren'));
show('…in Terminal at idle, where nothing can be typed: asked all the same',
     sideChatAskBefore(idle, chat({ idleWay: { kind: 'cantType', host: 'Terminal' } }), 'Wren'));
show('…a Claude Desktop conversation: not yet', sideChatAskBefore(desktop, chat(), 'Wren'));
show('…its session has ended: no Ask Without Interrupting at all', sideChatAskBefore(ended, chat(), 'Wren'));
show('…one already being answered: its Stop in Ask\'s place', sideChatAskBefore(working,
  chat({ asides: [aside('answered'), aside('asking', { at: min(1) })] }), 'Wren'));
show('…no Claude Code command on this Mac', sideChatAskBefore(working, chat({ askWhyNot: { why: 'noCommand' } }),
                                                             'Wren'));
show('…another agent\'s command not on this Mac: named for it', sideChatAskBefore(working,
  chat({ askWhyNot: { why: 'noCommand' }, agent: 'Quill' }), 'Wren'));
show('…nothing said yet', sideChatAskBefore(idle, chat({ askWhyNot: { why: 'notStarted' } }), 'Wren'));
show('…its conversation not found', sideChatAskBefore(working, chat({ askWhyNot: { why: 'noConversation' } }), 'Wren'));
show('asking: nothing said, its steps go in its answer\'s place', asked(aside('asking')));
show('…that place, being asked: the line its agent\'s steps go on, under the copy\'s name',
     sideChatAsideHTML(aside('asking'), working, chat(), 'Wren'));
const asideLine = (fields, name = 'Wren') => sideChatAsideWorkHTML(aside('asking', fields), name, NOW)
  .replace(/style="[^"]*"/g, 'style="…"');
show('…its line: Thinking, until its agent says its first step, timed from your press', asideLine({}));
show('…then each step', asideLine({ step: 'Reading cart.ts' }));
show('…a step, or a name, that is markup is shown as text', [asideLine({ step: '<b>cart</b>' }),
                                                             asideLine({}, '<i>Wren</i>')]);
const asideKeyNow = sideChatAsideWorkKey(aside('asking'), 'Wren'), asideClock = performance.now;
performance.now = () => 1234;
const asideKeyLater = sideChatAsideWorkKey(aside('asking'), 'Wren');
performance.now = asideClock;
show('…drawn again for a new step, not for a second gone by; none once it\'s answered, or for none',
     [asideKeyNow === asideKeyLater,
      asideKeyNow !== sideChatAsideWorkKey(aside('asking', { step: 'Reading cart.ts' }), 'Wren'),
      sideChatAsideWorkKey(aside('answered', { answer }), 'Wren'), sideChatAsideWorkKey(undefined, 'Wren')]);
show('answered', asked(aside('answered', { answer, answeredAt: min(3) })));
show('took too long', asked(aside('tooSlow')));
show('didn\'t answer', asked(aside('noAnswer')));
show('an error its provider sent back', asked(aside('apiError')));
show('…sent the normal way, with Send\'s words: says so, no presses', asked(aside('apiError', { sentAt: min(2) })));
show('it wanted to read more than a side question may', asked(aside('wantedTool')));
show('…its presses are Ask Again and Send\'s words for the session now: idle, working with and without its hook, '
     + 'waiting on you',
     [asked(aside('wantedTool'), false, 'Claude Code', idle), asked(aside('wantedTool')),
      asked(aside('wantedTool'), false, 'Claude Code', working, false),
      asked(aside('wantedTool'), false, 'Claude Code', asking)]);
show('your plan\'s limit, until its reset', asked(aside('limit', { resetsAt: Date.UTC(2030, 0, 1, 0, 0) })));
show('your plan\'s limit, no reset said', asked(aside('limit')));
show('signed out', asked(aside('signedOut')));
show('too long to read again', asked(aside('tooLong')));
show('stopped', asked(aside('stopped')));
show('no Claude Code command found when asked', asked(aside('noCommand')));
show('…another agent\'s, and it signed out: each named for it', [asked(aside('noCommand'), false, 'Quill'),
                                                                 asked(aside('signedOut'), false, 'Quill')]);
show('…an agent that hasn\'t said its name: "its agent", capitalised only to open a sentence',
     [sideChatAskBefore(working, chat({ askWhyNot: { why: 'noCommand' }, agent: '' }), 'Wren'),
      asked(aside('noCommand'), false, ''),
      asked(aside('signedOut'), false, '')]);
show('couldn\'t be asked once pressed, what stood in the way having changed', asked(aside('notAsked')));
show('…another being asked now: no Ask Again until it\'s answered', asked(aside('tooSlow'), true));
show('its tip and what VoiceOver says', [sideChatAskTip('Wren'), sideChatAsideLabel('Wren')]);

section('Where the side conversation\'s memory starts');
const answeredAt = (minutes, remembered) => aside('answered', { at: min(minutes), answer, answeredAt: min(minutes - 1),
                                                                ...(remembered === undefined ? {} : { remembered }) });
show('it knew every earlier question: no line', sideChatForgotAbove([answeredAt(9), answeredAt(7, 1),
                                                                     answeredAt(5, 2)]));
show('…it knew the newest one of two: the line above that one', sideChatForgotAbove([answeredAt(9), answeredAt(7, 1),
                                                                                     answeredAt(5, 1)]) === min(7));
show('…none of them: the line above the newest', sideChatForgotAbove([answeredAt(9), answeredAt(7, 1),
                                                                     answeredAt(5, 0)]) === min(5));
show('…an answer that doesn\'t say: no line', sideChatForgotAbove([answeredAt(9), answeredAt(7)]));
show('…one not answered between them doesn\'t count', sideChatForgotAbove([answeredAt(9), aside('tooSlow',
  { at: min(8) }), answeredAt(7, 0)]) === min(7));
show('…drawn once, quiet, above that question', sideChatLinesHTML(chat({ asides: [answeredAt(9), answeredAt(7, 1),
  answeredAt(5, 1)] }), working, 'Wren', '', NOW));

section('Keys in the box');
show('Return sends', sideChatKeyAct({ key: 'Enter' }));
show('⌥Return goes the other way from the dark button: asks without interrupting while Send is dark',
     sideChatKeyAct({ key: 'Enter', altKey: true }));
const askChosen = sideChatWayNow('ask', null), sendChosen = sideChatWayNow('send', null);
show('after pressing Ask Without Interrupting, Return asks', sideChatKeyAct({ key: 'Enter' }, askChosen));
show('after pressing Send, Return sends', sideChatKeyAct({ key: 'Enter' }, sendChosen));
show('⌥Return with Ask dark sends', sideChatKeyAct({ key: 'Enter', altKey: true }, askChosen));
show('⌥Return with Send dark asks', sideChatKeyAct({ key: 'Enter', altKey: true }, sendChosen));
show('the way you chose last: Ask, while it can go', askChosen);
show('…Ask, while a copy is still answering (Stop in its place)',
     sideChatWayNow('ask', sideChatAskBefore(working, chat({ asides: [aside('asking', { at: min(1) })] }), 'Wren')));
show('…Ask, on Claude Desktop: Send is the way', sideChatWayNow('ask', sideChatAskBefore(desktop, chat(), 'Wren')));
show('…Ask, on an ended session: Send is the way', sideChatWayNow('ask', sideChatAskBefore(ended, chat(), 'Wren')));
show('…Ask, with another can\'t in its place: Send is the way',
     sideChatWayNow('ask', sideChatAskBefore(working, chat({ askWhyNot: { why: 'noCommand' } }), 'Wren')));
show('…nothing chosen: Send', sideChatWayNow(undefined, null));
show('Esc closes the chat', sideChatKeyAct({ key: 'Escape' }));
show('any other key: nothing of side chat\'s', sideChatKeyAct({ key: 'a', altKey: true }));

section('Add to Message, and a question put in the box');
show('an empty box: the question and the answer, on one line', sideChatAddAnswer('Why that file?', answer, '', 600));
show('after what you\'ve written, never in its place', sideChatAddAnswer('Why that file?', answer, 'Go on, and', 600));
show('a long question: its first 60 characters', sideChatAddAnswer('Why ' + 'that very long file name '.repeat(5) + '?',
                                                                   answer, '', 600));
const longAnswer = [{ prose: 'A word. '.repeat(200) }];
const filledBox = sideChatAddAnswer('Why that file?', longAnswer, 'Note:', 600);
show('a long answer: cut to the box\'s room', [filledBox.length, filledBox.slice(-12)]);
// Within one character of the room: the cut drops a space that would end the words before its "…".
const workingRoom = sideChatRoom(sideChatOpening(working, chat()));
const workingFill = sideChatAddAnswer('Why that file?', longAnswer, '', workingRoom).length;
show('…the room while it works, after the words that open yours',
     workingFill <= workingRoom && workingFill >= workingRoom - 1);
show('no room left: the box as it was', sideChatAddAnswer('Why that file?', answer, 'x'.repeat(590), 600)
  === 'x'.repeat(590));
show('no answer: the box as it was', sideChatAddAnswer('Why that file?', [], 'Hi', 600));
show('a question too long to send: after what\'s there', sideChatQuestionInBox('Why that file?', 'Also:', 600));
show('…cut to the room', sideChatQuestionInBox('q'.repeat(700), '', 600).length);

section('A side answer you haven\'t seen');
const answeredChat = chat({ asides: [aside('answered', { answer, answeredAt: min(2) })] });
show('its chat closed since it came: the bar lit', sideChatEdge(sideChatUnseen(answeredChat, 0, min(5)), 'Wren'));
show('in its tab since: still not seen, as the tab doesn\'t show it',
     sideChatEdge(sideChatUnseen(answeredChat, min(1), min(5)), 'Wren'));
show('its chat open since: seen', sideChatEdge(sideChatUnseen(answeredChat, 0, min(1)), 'Wren'));
show('for notifications', sideChatNews(working, answeredChat, min(1), min(5)));
show('one still being answered: nothing new', sideChatNews(working, chat({ asides: [aside('asking')] }), 0, 0));

section('Asked without interrupting, as HTML');
show('an empty chat says you can ask without interrupting', sideChatEmpty(working, chat(), 'Wren'));
show('…not on a Claude Desktop conversation', sideChatEmpty(desktop, chat(), 'Wren'));
show('waiting on your answer, with its hook: ask about it first, then your words', sideChatEmpty(asking, chat(), 'Wren'));
show('…without its hook: your words when its turn ends', sideChatEmpty(asking, chat({ hook: false }), 'Wren'));
show('…on a Claude Desktop conversation: no Ask Without Interrupting', sideChatEmpty(wren({ status: 'waiting',
  entrypoint: 'claude-desktop', ask: asking.ask }), chat({ hook: false }), 'Wren'));
show('…where nothing can be asked without interrupting now', sideChatEmpty(asking,
  chat({ askWhyNot: { why: 'noConversation' } }), 'Wren'));
{
  // Stop's and Send's words' first-shown times, kept by the session, so the page's pass that lets go of what's
  // kept for sessions gone a minute keeps them while it's listed (else each pass, with the chat drawn again, would make
  // them only just shown and refuse their presses), and lets them go with it.
  const loadedAt = state.loadedAt, keys = [sideChatStopKey('wren', 1000), sideChatTurnKey('wren', 1000)];
  state.loadedAt = Date.now() - 2 * 60 * 1000;
  for (const key of keys) state.shownAt[key] = Date.now() - 5000;
  forgetGone([working]);
  show('Stop and Send\'s words, after a pass while their session is listed: kept, and pressable',
       keys.map((key) => key in state.shownAt && !justShown(key)));
  state.listedAt.wren = Date.now() - 2 * 60 * 1000;
  forgetGone([]);
  show('…once their session has been gone a minute: let go', keys.map((key) => key in state.shownAt));
  state.loadedAt = loadedAt;
}
{
  // Side Chat's bar beside a request's card: a press only once the request has been seen a moment, so a row that grew
  // just as you pressed opens nothing; a moment later it opens the chat.
  const sessions = state.last?.sessions, reading = state.reading, press = { preventDefault() {} };
  state.last = { ...(state.last || {}), sessions: [asking] };
  const opened = [];
  const toggle = globalThis.toggleReader;
  globalThis.toggleReader = (sid) => opened.push(sid);
  // Only Side Chat's own time is set, as its bar is drawn beside the request: never the card's (Claude Code's).
  core.slots.edge.forEach((edge) => edge({ s: asking }));
  show('the bar drawn beside a request keeps its own time, not the card\'s', [!!state.shownAt[sideChatBesideKey(
    asking.sessionId, 'a1')], 'a1' in state.shownAt]);
  try { sideChatPress({ dataset: { scOpen: asking.sessionId } }, press); } catch (e) {}
  show('the bar pressed as a request comes: nothing opens', opened.length);
  state.shownAt[sideChatBesideKey(asking.sessionId, 'a1')] = Date.now() - 5000;
  try { sideChatPress({ dataset: { scOpen: asking.sessionId } }, press); } catch (e) {}
  show('…a moment after it came: the chat opens', opened.length);
  delete state.shownAt[sideChatBesideKey(asking.sessionId, 'a1')];
  globalThis.toggleReader = toggle;
  state.last = { ...state.last, sessions };
  state.reading = reading;
}
show('your words and your side questions, in the order you sent them', sideChatLinesHTML(chat({
  says: [said('read', { at: min(6), how: 'step', doneAt: min(5) })],
  asides: [aside('answered', { at: min(8), answer, answeredAt: min(7) }), aside('asking', { at: min(2),
    question: 'And <the> tests?' })] }), working, 'Wren', '', NOW, { [`${min(8)} 1`]: true }));
show('a side question that couldn\'t be answered', sideChatAsideHTML(aside('wantedTool'), working, chat(), 'Wren'));
show('…while its session waits on your answer: Send After You Answer', sideChatAsideHTML(aside('wantedTool'), asking,
  chat(), 'Wren'));
show('…once sent the normal way: said under the question, with no copy\'s name over it',
     sideChatAsideHTML(aside('wantedTool', { sentAt: min(2) }), working, chat(), 'Wren'));
show('the box with Ask Without Interrupting', sideChatBoxHTML(working, chat(), 'Wren', null));
show('…Ask Without Interrupting chosen last: it is the dark button, Send is not',
     sideChatBoxHTML(working, chat(), 'Wren', null, null, 'ask'));
show('…Ask chosen while a copy still answers: Stop in Ask\'s place, neither button dark',
  sideChatBoxHTML(working, chat({ asides: [aside('asking')] }), 'Wren', null, undefined, 'ask'));
const inTerminal = chat({ idleWay: { kind: 'cantType', host: 'Terminal' } });
show('…Ask chosen, idle in Terminal: Copy and Go in Send\'s place, not dark',
  sideChatBoxHTML(idle, inTerminal, 'Wren', sideChatBefore(idle, inTerminal, 'Wren'), null, 'ask'));
show('…and under it, nothing written: why Copy and Go', sideChatUnderHTML(idle, inTerminal, 'Wren', '', null,
  sideChatBefore(idle, inTerminal, 'Wren'), null, '', 'ask'));
show('…idle: Send says Send', sideChatBoxHTML(idle, chat(), 'Wren', null));
show('…working without its hook: Send After Its Turn', sideChatBoxHTML(working, chat({ hook: false }), 'Wren', null));
show('…waiting on your answer: Send After You Answer', sideChatBoxHTML(asking, chat(), 'Wren', null));
show('the box while a side question is answered: Stop in Ask\'s place', sideChatBoxHTML(working,
  chat({ asides: [aside('asking')] }), 'Wren', null));
show('the box on a Claude Desktop conversation', sideChatBoxHTML(desktop, chat(), 'Wren',
  sideChatBefore(desktop, chat(), 'Wren')));
show('the box once its session has ended: no Ask Without Interrupting', sideChatBoxHTML(ended, chat(), 'Wren',
  sideChatBefore(ended, chat(), 'Wren')));
show('under the box, nothing written: why nothing can be asked', sideChatUnderHTML(idle,
  chat({ askWhyNot: { why: 'notStarted' } }), 'Wren', '', null, null));
show('…with words written: what goes in', sideChatUnderHTML(idle, chat({ askWhyNot: { why: 'notStarted' } }), 'Wren',
  'Hi.', null, null));
show('…while one is answered: nothing more', sideChatUnderHTML(working, chat({ asides: [aside('asking')] }), 'Wren',
  '', null, null));
show('…Ask the dark button: what Return asks', sideChatUnderHTML(working, chat(), 'Wren', 'Why that file?', null,
  null, null, '', 'ask'));
show('…Ask the dark button while a copy still answers: why it can\'t just now',
  sideChatUnderHTML(working, chat({ asides: [aside('asking')] }), 'Wren', 'And the tests?', null, null, undefined, '',
                    'ask'));
show('…Ask the dark button, nothing written: nothing', sideChatUnderHTML(working, chat(), 'Wren', '', null, null, null,
  '', 'ask'));
show('…a press that couldn\'t act just now: why, first', sideChatUnderHTML(idle,
  chat({ askWhyNot: { why: 'notStarted' } }), 'Wren', 'Hi.', null, null, undefined,
  sideChatAskBefore(idle, chat({ askWhyNot: { why: 'notStarted' } }), 'Wren').why));
show('a failed question while another is answered: no Ask Again', sideChatLinesHTML(chat({
  asides: [aside('tooSlow', { at: min(9) }), aside('asking', { at: min(1) })] }), working, 'Wren', '', NOW));

section('Drawn in another view, with words that open yours there');
const TASK_LINE = 'About your task “Search box” (step 2 of 3): ';
show('the words that open yours: the hook\'s while it works, then the view\'s',
     sideChatOpening(working, chat(), TASK_LINE));
show('…idle: the view\'s alone', sideChatOpening(idle, chat(), TASK_LINE));
show('room for your own words after both', sideChatRoom(sideChatOpening(working, chat(), TASK_LINE)));
show('under the box: what goes in, whole', sideChatUnderHTML(working, chat(), 'Wren', 'Where is it?', null, null, null,
  '', 'send', TASK_LINE));
show('…Ask the dark button: what the copy is asked, whole', sideChatUnderHTML(working, chat(), 'Wren', 'Where is it?',
  null, null, null, '', 'ask', TASK_LINE));
show('the box: its field holds only what fits after them', sideChatBoxHTML(working, chat(), 'Wren', null, null, 'send',
  TASK_LINE).match(/maxlength="\d+"/)[0]);
show('…and keeps its own words, naming nothing of the view\'s', sideChatBoxHTML(working, chat(), 'Wren', null, null,
  'send', TASK_LINE).match(/placeholder="[^"]*"/)[0]);
show('words sent from there, in the chat: what they were about, quietly over them', sideChatLinesHTML(chat({
  says: [said('read', { how: 'step', doneAt: min(2), opening: TASK_LINE, line: `${TASK_LINE}Where is it?`,
                        words: 'Where is it?' })] }), working, 'Wren', '', NOW));
show('…what they were about, without the colon', sideChatAboutWords({ opening: TASK_LINE }));
show('…from the chat\'s own window: nothing over them', sideChatAboutWords(said('read')));

section('What VoiceOver is told, wherever the chat is drawn');
const toldReply = min(1), toldAnswer = min(2);
const told = chat({ says: [said('replied', { repliedAt: toldReply, reply: [{ prose: 'Done.' }, { code: 'npm test', lang: 'sh' }] })],
                    asides: [aside('answered', { answeredAt: toldAnswer, answer: [{ prose: 'It holds the cart.' }] })] });
show('the newest that came: a reply, its command as words', sideChatSayAloud(told, 0, 'Wren'));
show('…a side answer, by the copy', sideChatSayAloud(chat({ asides: told.asides }), 0, 'Wren'));
show('…nothing after the newest', sideChatSayAloud(told, NOW, 'Wren'));
show('when the newest came', sideChatNewest(told) === toldReply);
show('…an empty chat', sideChatNewest(chat()));

section('Words Claude Desktop couldn\'t take for want of the Accessibility permission');
show('why, with its pane as the way', sideChatBack(said('refused', {
  why: 'Whozmove needs the Accessibility permission for this', way: 'Open Accessibility Settings', permission: true,
  where: 'Claude Desktop' }), 'Wren'));
show('…words that couldn\'t go from where the chat was drawn: why, nothing to press', sideChatBack(said('notSent', {
  why: 'Too long to go with what it\'s about: shorten it and send it again' }), 'Wren'));

section('A side question asked from another view');
show('what it was about, quietly over it, as over your words', sideChatAsideHTML(aside('tooSlow', {
  opening: TASK_LINE }), working, chat(), 'Wren'));

section('Drawn in another view: what Send waits on, ending the conversation');
show('while it asks for your OK: what it asks, with Show It', sideChatHostedLiveHTML(sideChatHostedLive(asking, 'Wren',
  'Wants to run a command')));
show('…its session ended: nothing here (under the box says so, with Open Again)', sideChatHostedLive(ended, 'Wren', ''));
show('…working, or idle: nothing (the step line, or the box, says it)', [sideChatHostedLive(working, 'Wren', ''),
  sideChatHostedLive(idle, 'Wren', '')]);

section('Drawn in another view: the working lines still, with no band of light');
const tStillWork = workLineHTML(working, NOW, { label: 'Wren', still: true });
show('the session\'s line: its step\'s words plain, the label still, the time ticking',
     [tStillWork.includes('shining') || tStillWork.includes('glint'), tStillWork.includes('class="claude work still"'),
      tStillWork.includes('data-since'), tStillWork.includes('Running tests')]);
const tStillAside = sideChatAsideWorkHTML(aside('asking', { step: 'Reading cart.ts' }), 'Wren', NOW, true);
show('…a side question\'s line the same', [tStillAside.includes('shining') || tStillAside.includes('glint'),
                                          tStillAside.includes('Reading cart.ts')]);
show('…in Side Chat\'s own window, the band as on the row',
     sideChatAsideWorkHTML(aside('asking', { step: 'Reading cart.ts' }), 'Wren', NOW).includes('glint'));
