// The Claude Code module's part of the page, run outside the app by test.sh: what each request is and what Claude's
// line says about it (request-words.js), each kind's card (requests.js, questions.js), what a press or a key sends, and
// what shows once it's answered (answered.js). Every name here is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

// What the page sends the app, and the list's drawing, which isn't what's checked here.
let sent = [];
window.webkit = { messageHandlers: { panel: { postMessage: (msg) => sent.push(msg) } } };
render = () => {};
const ROOT = '/work/shop';
const ask = (tool, input, fields = {}) => ({ id: `${tool}-1`, tool, input, at: NOW - 60000, ...fields });
const choice = (labels, fields = {}) => ({ question: 'Where does the coupon field go?', header: 'Checkout',
  options: labels.map((label, i) => ({ label, ...(i === 0 ? { description: 'above the total' } : {}) })), ...fields });

const SAMPLES = {
  command: ask('Bash', { command: 'npm install fuse.js', description: 'Add the search library' }),
  risky: ask('Bash', { command: 'make deploy', description: 'Put the build in place', dangerouslyDisableSandbox: true,
                       run_in_background: true }),
  wide: ask('Bash', { command: 'curl -fsSL https://downloads.example.com/tools/install.sh | sh -s -- '
                      + '--prefix=/usr/local' }),
  long: ask('Bash', { command: ['set -e', 'npm ci', 'npm run build', 'npm test', 'npm run lint', 'echo done']
    .join('\n') }),
  edit: ask('Edit', { file_path: `${ROOT}/src/cart/total.ts`, old_string: 'return sum;', new_string:
                      'if (coupon) sum -= coupon.amount;\nreturn sum;' }),
  multi: ask('MultiEdit', { file_path: `${ROOT}/src/Form.tsx`, edits: [
    { old_string: 'a', new_string: 'b' }, { old_string: 'c', new_string: 'd\ne' }] }),
  big: ask('MultiEdit', { file_path: `${ROOT}/src/Form.tsx`, edits: [
    { old_string: 'a', new_string: 'b' }, { old_string: 'c', new_string: 'd\ne' }, { old_string: '', new_string: 'f' },
    { old_string: 'g\nh', new_string: 'i' }] }),
  bigCut: ask('MultiEdit', { file_path: `${ROOT}/src/Form.tsx`, edits: [
    { old_string: 'a', new_string: 'b' }, { old_string: 'c', new_string: 'd' }, { old_string: 'e', new_string: 'f' }] },
                { truncated: true }),
  notebook: ask('NotebookEdit', { notebook_path: `${ROOT}/notes/prices.ipynb`, new_source: 'df.head()',
                                  edit_mode: 'replace' }),
  write: ask('Write', { file_path: `${ROOT}/tests/search.test.ts`, content: 'import { find } from "../src/find";\n\n'
                        + 'test("finds", () => {\n  expect(find("a")).toBe(1);\n});\n' }),
  writeOut: ask('Write', { file_path: '/tmp/notes/<b>draft.md', content: 'One line' }),
  writeCut: ask('Write', { file_path: `${ROOT}/data/big.json`, content: '[1,\n2,\n3' }, { truncated: true }),
  read: ask('Read', { file_path: '/etc/hosts' }),
  fetch: ask('WebFetch', { url: 'https://docs.example.com/coupons', prompt: 'How are coupon codes checked?' }),
  fetchBare: ask('WebFetch', { url: 'https://example.com/' }),
  search: ask('WebSearch', { query: 'coupon codes best practice' }),
  connector: ask('mcp__claude_ai_Claude_Docs__batch', { doc: 'Notes' }),
  plugin: ask('mcp__plugin_engineering_linear__authenticate', {}),
  mcp: ask('mcp__linear__create_issue', { title: 'Coupon field misplaced', team: 'Web', priority: 2,
    description: 'On the checkout page the coupon field sits under the total, where nobody sees it before paying.' }),
  kill: ask('KillShell', { shell_id: 'bash_3' }),
  other: ask('Frobnicate', { level: 3 }),
  plan: ask('ExitPlanMode', { plan: '# Coupon field\n\n1. Move the field above the total\n2. Check the code on blur\n'
    + '3. Show the saving\n4. Test it\n5. Tidy up\n6. Write it down\n7. Ask for a review\n8. Ship it\n'
    + '   1. not a step' }),
  qOne: ask('AskUserQuestion', { questions: [choice(['Above the total', 'Under the total', 'In the basket'])] }),
  qMulti: ask('AskUserQuestion', { questions: [choice(['Cart', 'Checkout', 'Account'], {
    question: 'Which pages get the new header?', header: '', multiSelect: true })] }),
  qSteps: ask('AskUserQuestion', { title: 'Before I start', questions: [choice(['Above', 'Under']),
    { question: 'What should the button say?', kind: 'text', defaultValue: 'Apply' },
    choice(['Mobile', 'Desktop'], { question: 'Which screens?', multiSelect: true })] }),
  qNumber: ask('AskUserQuestion', { questions: [{ question: 'How many products per page?', kind: 'number', min: 12,
                                                 max: 96, step: 12, defaultValue: 24, unit: 'products' }] }),
  planBare: ask('ExitPlanMode', { plan: '# Tidy the cart\n\nMove the coupon code into the basket page.\n\n'
    + 'Keep the old route as a redirect.' }),
  qText: ask('AskUserQuestion', { questions: [{ question: 'What should the shop be called?', kind: 'text',
                                               placeholder: 'A name' }] }),
};

// Each by its own id, its name here.
for (const [name, a] of Object.entries(SAMPLES)) a.id = name;

section('What each request is, and what Claude\'s line says about it');
for (const [name, a] of Object.entries(SAMPLES)) show(name, `${askKind(a)} · ${askLine(a)}`);
show('a question with no topic', askLine(ask('AskUserQuestion', { questions: [{ question: 'Go on?' }] })));
show('a page with no address', askLine(ask('WebFetch', {})));

section('The words about a request');
show('folders: inside the project, at its top, and outside it',
     [folderIn(`${ROOT}/src/cart/total.ts`, ROOT), folderIn(`${ROOT}/README.md`, ROOT), folderIn('/etc/hosts', ROOT),
      folderIn('/work/shopping/a.ts', ROOT)]);
show('lines put in and taken out, over every edit', changeCounts(editsOf(SAMPLES.big)));
show('an empty text has no lines', [lineCount(''), lineCount('a'), lineCount('a\n')]);
show('a connected app', [mcpName('mcp__linear__create_issue'), mcpName('mcp__gh__')]);
print('-- a connected app\'s short message, drawn as words; a long description cut short with Show all, then whole');
const POST = ask('mcp__slack__post_message', { channel: 'web', message: 'Coupons are fixed, try **SPRING10**.' });
print(askHTML(POST, NOW, ROOT));
const ISSUE = ask('mcp__linear__create_issue', { title: 'Coupons', description: ['Expired codes still apply at checkout.',
  'The check runs before the total, so an **expired** code takes money off anyway.', '1. Check `expires_at` first',
  '2. Say why a code was turned down', 'A fix belongs in the check itself, not in the form.'].join('\n') });
ISSUE.id = 'issue';
print(askHTML(ISSUE, NOW, ROOT));
state.askOpen.issue = { description: true };
print(askHTML(ISSUE, NOW, ROOT));
show('which of a tool\'s fields are words to read', [['description', 'x'], ['Body', 'x'], ['query', 'x'],
  ['description', { a: 1 }]].map(([key, v]) => `${key}: ${isProse(key, v)}`));
show('a plan', planOf(SAMPLES.plan));
show('a plan with no heading', planOf(ask('ExitPlanMode', { plan: 'Just do it' })).title);
// A plan as they're often written: its steps' words carried on over indented lines, in bold and code, a nested list
// that isn't a step, and a second numbered list after a heading, its numbers its own.
const LONG_PLAN = ask('ExitPlanMode', { plan: '# **Keep** the `coupon` codes safe\n\n## Steps\n\n'
  + '1. **On the server** (on your yes): check each code\n   before the total, as the basket does\n'
  + '   - not a step\n   - nor this\n2. Log what was <b>tried</b>\n3. Test it\n\n## Open decisions\n\n'
  + '1. **Where the codes live: in the database (recommended)**, or in a file.\n   A file can\'t be changed while it runs.\n'
  + '2. `MAX_TRIES`: 5\n3. Who sees the log\n4. How long it\'s kept\n' });
LONG_PLAN.id = 'longPlan';
show('a plan\'s steps whole, each with its own number', planOf(LONG_PLAN));
show('what a notebook edit does, and to which cell', [{ edit_mode: 'replace', cell_id: '3', cell_type: 'code' },
     { edit_mode: 'insert', cell_id: '3', cell_type: 'markdown' }, { edit_mode: 'insert' }, { edit_mode: 'delete',
       cell_id: '3' }, {}].map(notebookWhat));
show('…a cell taken out puts in no lines', changeCounts(editsOf(ask('NotebookEdit', { edit_mode: 'delete' }))));
show('what each is about, for the line once answered', Object.fromEntries(Object.entries(SAMPLES)
  .map(([name, a]) => [name, askSubject(a)])));
show('what an answer is called', ['allow', 'deny', 'answered', 'skipped', 'dismissed', 'sentBack', 'stopped', 'unknown']
  .map(receiptWords));
show('whether Show all is needed: 3 short lines of 4, 5 lines of 4, and one line too wide for the card',
     [showAllNeeded('a\nb\nc', 4), showAllNeeded('a\nb\nc\nd\ne', 4), showAllNeeded('x'.repeat(WIDE_LINE + 1), 4)]);
show('a number\'s range, and values outside it', [numberRange({ min: 12, max: 96 }), numberRange({ min: 1 }),
     numberRange({ max: 9 }), numberRange({}), ['11', '12', '97', 'x', ''].map((v) => outOfRange({ min: 12, max: 96 },
                                                                                                     v))]);

section('A request that goes by itself if no one answers');
// Don't Wait on Me, on for the session: the hook says when it goes (expiresAt), which the card counts down in whole
// minutes, on a ring that empties over the wait from when it asked. A plan never goes.
const goes = (fields) => ({ id: 'g', tool: 'Bash', input: { command: 'make' }, at: NOW - 60000, ...fields });
show('5 minutes left, 4½, 61 s, 59 s, and past it (its hook just going)',
     [5 * 60000, 4.5 * 60000, 61000, 59000, -1000].map((left) => goesWords(goes({ expiresAt: NOW + left }), NOW)));
show('waiting on you as ever (no expiresAt), and a plan', [goesWords(goes({}), NOW),
     goesWords(goes({ tool: 'ExitPlanMode', expiresAt: NOW + 60000 }), NOW)]);
show('its ring, over the session\'s whole wait of 5 minutes: 4 left, 30 s left, held to 6 left (full), and past it',
     [goesRing(goes({ expiresAt: NOW + 4 * 60000, waits: 300000 }), NOW),
      goesRing(goes({ expiresAt: NOW + 30000, waits: 300000 }), NOW),
      goesRing(goes({ expiresAt: NOW + 6 * 60000, waits: 300000 }), NOW),
      goesRing(goes({ expiresAt: NOW - 1000, waits: 300000 }), NOW)]);
show('…the list\'s tick sets its fill and minutes as the time goes, and the list isn\'t drawn again for it',
     (() => { const a = (at) => askHTML(goes({ expiresAt: NOW + 4 * 60000, waits: 300000 }), at, ROOT);
              return [drawingOf(a(NOW)) === drawingOf(a(NOW + 61000)),
                      /--left:([\d.]+)/.exec(a(NOW + 61000))[1]]; })());
print(askHTML(goes({ expiresAt: NOW + 4 * 60000, input: { command: 'make', description: 'Build it' } }), NOW, ROOT));
print(askHTML({ ...SAMPLES.qOne, expiresAt: NOW + 90000 }, NOW));

section('Each kind\'s card');
for (const [name, a] of Object.entries(SAMPLES)) print(`-- ${name}\n${askHTML(a, NOW, ROOT)}`);
print('-- a request from a session started before the update, which the panel doesn\'t answer: answered in Claude');
print(askHTML({ ...SAMPLES.command, legacy: true }, NOW, ROOT));
print('-- a command with a long reason, and a long first line: the reason whole as the title, the command whole, ' +
      'wrapped, with no Show all, as it has no more than 4 lines');
print(askHTML(ask('Bash', { description: 'Delete coupons that expired more than 30 days ago from the production '
  + 'database', command: 'psql "$SHOP_DATABASE_URL" -c "DELETE FROM coupons WHERE expires_at < now() - interval '
  + "'30 days'\"\nvacuumdb --table=coupons shop" }), NOW, ROOT));
print('-- a command shown in full, and a big change at its third edit');
state.askOpen[SAMPLES.long.id] = { '': true };
state.askChange[SAMPLES.big.id] = 2;
print(askHTML(SAMPLES.long, NOW, ROOT));
print(askHTML(SAMPLES.big, NOW, ROOT));
show('…past its last edit, the last', /ask-of">([^<]*)</.exec(askHTML({ ...SAMPLES.big, id: 'big-2' }, NOW, ROOT))[1]);
state.askChange['big-2'] = 9;
show('…', /ask-of">([^<]*)</.exec(askHTML({ ...SAMPLES.big, id: 'big-2' }, NOW, ROOT))[1]);
print('-- a plan being sent back, its notes typed, and a single pick\'s box to type in');
state.sendBack[SAMPLES.plan.id] = { text: 'Keep <codes> on the server' };
print(askHTML(SAMPLES.plan, NOW, ROOT));
print('-- a plan that starts at a glance: its few lines (the plans module\'s) in place of its steps');
print(askHTML(ask('ExitPlanMode', { plan: '# Coupon field\n\n## At a glance\n\n'
  + '- **What changes for you:** the coupon field sits above the total, where it\'s seen.\n'
  + '- **You decide:**\n  1. When it\'s checked: as you leave it (recommended), or on Apply. Why: fewer presses.\n'
  + '- **Could go wrong:** a code typed with spaces reads as wrong.\n\n## Steps\n\n1. Move the field\n'
  + '2. Check the code on blur\n3. Show the saving\n4. Test it\n5. Tidy up\n' }), NOW, ROOT));
quizState(SAMPLES.qOne.id).typing = 0;
print(askHTML(SAMPLES.qOne, NOW, ROOT));
show('…"Type an answer" became the box in its own row, with no second box under it',
     (askHTML(SAMPLES.qOne, NOW, ROOT).match(/<input /g) || []).length + ' box, in the row: '
     + /ask-type-opt is-typing"><span class="tag mark">4<\/span><input/.test(askHTML(SAMPLES.qOne, NOW, ROOT)));
{
  const st = quizState(SAMPLES.qOne.id), [, escaped] = core.escapes.find(([sel]) => sel.includes('ask-row-box'));
  st.typed[0] = 'Beside the <b>button</b>';
  escaped({ closest: () => ({ dataset: { ask: SAMPLES.qOne.id } }) });
  show('Esc gives the row back, keeping what was typed, which the row shows faint',
       [st.typing, /ask-kept">([^<]*)</.exec(askHTML(SAMPLES.qOne, NOW, ROOT))?.[1]]);
  st.typed[0] = '   ';
  const bare = /ask-type-opt" data-q="0"><span class="tag mark">4<\/span><span class="([^"]*)">([^<]*)</;
  show('…nothing kept: "Type an answer" again', bare
    .exec(askHTML(SAMPLES.qOne, NOW, ROOT))?.slice(1));
  delete st.typed[0];
}
print('-- several picks, its last row "Type an answer" become the box');
quizState(SAMPLES.qMulti.id).typing = 0;
print(askHTML(SAMPLES.qMulti, NOW, ROOT));
{
  const st = quizState(SAMPLES.qMulti.id);
  st.typing = false;
  st.picks[0] = [0, 2];
  st.typed[0] = 'Footer';
  show('…the ticks and the words typed go together', JSON.stringify(quizAnswers(SAMPLES.qMulti)));
  const ticked = /class="opt on ask-type-opt" data-q="0"><span class="opt-label ask-kept">([^<]*)</;
  show('…and the row, kept, is ticked, its words shown', ticked
    .exec(askHTML(SAMPLES.qMulti, NOW, ROOT))?.[1]);
  st.picks[0] = [];
  delete st.typed[0];
}
print('-- a question whose words have markdown marks: drawn, never shown');
print(askHTML(ask('AskUserQuestion', { questions: [{ question: 'Watch the **reliability** workspace?', header: 'Team',
  options: [{ label: 'Yes, add `reliability`', description: 'Workspace `reliability`, from **main**, <b>checked</b>' },
            { label: 'Not now' }] }] }), NOW, ROOT));
print('-- a number typed outside its range');
quizState(SAMPLES.qNumber.id).typed[0] = '200';
print(askHTML(SAMPLES.qNumber, NOW, ROOT));
delete quizState(SAMPLES.qNumber.id).typed[0];

section('Claude\'s line on a row waiting on you');
const waiting = (a) => /class="claude wait"[^>]*><span class="who">Claude<\/span><span class="what">([^<]*)</
  .exec(chatHTML(session({ status: 'waiting', ask: a }), 'needs', NOW))?.[1];
show('a command, a question, a plan', [waiting(SAMPLES.command), waiting(SAMPLES.qOne), waiting(SAMPLES.plan)]);
show('a request with no tool named', waiting({ id: 'x', input: {} }));

section('Presses and keys');
// A single pick answers with one press, once the card has been seen; a press before that does nothing.
const fake = (classes, data = {}) => ({ dataset: data, disabled: false,
  matches: (sel) => sel.split(',').some((one) => one.trim().split(/(?=[.[])/).every((part) => (part.startsWith('[')
    ? part.slice(6, -1).replace(/^-/, '') in data || part === '[data-o]' && 'o' in data
    : classes.includes(part.slice(1))))) });
// What a press sends, past the hold every press on a request asks for (holdAsk).
const press = (a, button) => {
  sent = [];
  const card = { dataset: { ask: a.id }, matches: (sel) => sel === '.quiz' && a.tool === 'AskUserQuestion' };
  pressRequest(card, { target: { closest: (sel) => (sel === 'button' ? button : null) }, preventDefault() {} });
  return sent.filter((m) => m.type !== 'holdAsk').map((m) => JSON.stringify(m)).join(' ') || 'nothing sent';
};
state.last = { sessions: Object.values(SAMPLES).map((a, i) => session({ sessionId: `s${i}`, ask: a })), now: NOW };
for (const a of Object.values(SAMPLES)) state.shownAt[a.id] = Date.now() - 2000;  // each card seen a while ago
state.shownAt[SAMPLES.qOne.id] = Date.now();
show('a single pick\'s second option, pressed as the card appears',
     press(SAMPLES.qOne, fake(['opt', 'ask-num'], { o: '1' })));
state.shownAt[SAMPLES.qOne.id] = Date.now() - 2000;
show('…pressed once it\'s been seen', press(SAMPLES.qOne, fake(['opt', 'ask-num'], { o: '1' })));
show('…pressed again: the first answer stands', press(SAMPLES.qOne, fake(['opt', 'ask-num'], { o: '0' })));
state.answering = {};
const key = (a, k) => {
  sent = [];
  const did = keyOnRequest({ dataset: { ask: a.id } }, { key: k });
  return `${did} ${sent.map((m) => JSON.stringify(m)).join(' ') || 'nothing sent'}`;
};
show('its keys, once pressed: 3 answers, 4 (after the last) opens the box, 5 and a letter do nothing',
     ['3', '4', '5', 'a'].map((k) => { state.answering = {}; quizState(SAMPLES.qOne.id).typing = false;
                                        const said = key(SAMPLES.qOne, k);
                                        const open = typeof quizState(SAMPLES.qOne.id).typing === 'number';
                                        return `${k}: ${said}${open ? ' (box open)' : ''}`; }));
state.answering = {};
show('several picks\' keys tick and untick: 1, 3, then 1', ['1', '3', '1'].map((k) => { key(SAMPLES.qMulti, k);
  return JSON.stringify(quizState(SAMPLES.qMulti.id).picks[0]); }));
show('…and Submit sends them', press(SAMPLES.qMulti, fake(['perm-allow', 'q-submit'])));
state.answering = {};
{
  // Several questions, one at a time: the pager.
  const a = { ...SAMPLES.qSteps, id: 'qPager' }, st = quizState(a.id);
  state.last.sessions.push(session({ sessionId: 'sPager', ask: a }));
  state.shownAt[a.id] = Date.now() - 2000;
  const seen = () => { state.shownAt[`qpage:${a.id}`] = Date.now() - 2000; };
  const where = () => `${pageAt(a, st) + 1} of 3`;
  const of = (html) => /class="ask-of">([^<]*)</.exec(html)?.[1];
  show('several questions: one at a time, the first in view, its options numbered and only picked, never sent',
       [where(), press(a, fake(['opt', 'ask-num'], { q: '0', o: '1' })), JSON.stringify(st.picks[0])]);
  show('…Next moves on', [press(a, fake(['perm-allow', 'q-next'])), where()]);
  show('…pressed again as the next one appears, nothing: it takes no press for its first moment',
       [press(a, fake(['perm-allow', 'q-next'])), where()]);
  seen();
  print('-- …the second, a typed answer, with ‹ to go back');
  print(askHTML(a, NOW, ROOT));
  show('…Skip leaves it out and moves on; going back, it says so', (() => {
    press(a, fake(['q-pass']));
    const after = where();
    press(a, fake(['icon-button', 'small', 'ask-prev']));
    return [after, of(askHTML(a, NOW, ROOT)), JSON.stringify(quizAnswers(a))];
  })());
  press(a, fake(['icon-button', 'small', 'ask-next']));
  seen();
  print('-- …the last: Submit, with the other answers in a line above it');
  print(askHTML(a, NOW, ROOT));
  show('…its keys: 1 and 2 tick and untick on it, 3 (after its options) opens its box, ← and → move',
       ['1', '2', '1', '3'].map((k) => { const said = key(a, k); return `${k}: ${said} ${JSON.stringify(st.picks[2])}`
                                         + (st.typing === 2 ? ' (box open)' : ''); })
         .concat([key(a, 'ArrowLeft') + ` ${where()}`, key(a, 'ArrowRight') + ` ${where()}`]));
  show('…a key as the question appears does nothing', [key(a, '1'), JSON.stringify(st.picks[2])]);
  state.shownAt[`qpage:${a.id}`] = Date.now() - 200;
  show('…a moment later it picks, though a press would still wait', [key(a, '1'), JSON.stringify(st.picks[2]),
    press(a, fake(['opt', 'ask-num'], { q: '2', o: '0' })), JSON.stringify(st.picks[2])]);
  const bare = { ...SAMPLES.qSteps, id: 'qPagerBare', input: { questions: [choice(['Above']),
    { question: 'Anything else?' }] } };
  state.last.sessions.push(session({ sessionId: 'sBare', ask: bare }));
  quizState(bare.id).at = 1;
  show('…on a choice question with no options, 1 opens its box', [key(bare, '1'), quizState(bare.id).typing]);
  seen();
  st.typing = false;
  show('…Submit sends what was answered, the skipped one left out', press(a, fake(['perm-allow', 'q-submit'])));
  state.answering = {};
}
{
  // The last question of several with none answered: Submit off, and what to do instead.
  const a = { ...SAMPLES.qSteps, id: 'qPagerNone' }, st = quizState(a.id);
  st.at = 2;
  st.typed[1] = '';
  const html = askHTML(a, NOW, ROOT);
  show('several questions, none answered on the last: Submit off, and what to do instead', [
    /q-submit" disabled/.test(html), /class="card-help ask-none">([^<]*)</.exec(html)?.[1]]);
}
{
  // Each choice question of several has Type an answer too, as the number after its options, open for that one alone.
  const a = { ...SAMPLES.qSteps, id: 'qStepsTyped' }, st = quizState(a.id);
  st.at = 2;
  st.typing = 2;
  const html = askHTML(a, NOW, ROOT);
  show('several questions: Type an answer on a choice question, open as its box', [
    /<span class="tag mark">3<\/span><input class="field q-type ask-row-box" data-q="2"/.test(html),
    (html.match(/<input class="field q-type ask-row-box"/g) || []).length]);
  st.typing = false;
  st.at = 0;
  st.typed[0] = 'Beside the button';
  const kept = askHTML(a, NOW, ROOT);
  show('…the first question\'s words kept: its row on, showing them', [/ask-num on ask-type-opt" data-q="0"/.test(kept),
    /ask-kept">([^<]*)</.exec(kept)?.[1]]);
  state.last.sessions.push(session({ sessionId: 'sTyped', ask: a }));
  state.shownAt[a.id] = Date.now() - 2000;
  press(a, fake(['opt', 'ask-num'], { q: '0', o: '1' }));
  show('…a pick on that one-pick question replaces the words, the last press winning', [st.typed[0], st.picks[0]]);
  st.at = 2;
  st.typed[2] = 'Watch';
  press(a, fake(['opt', 'ask-num'], { q: '2', o: '0' }));
  show('…a tick on the several-picks question keeps its words, which go with it', [st.typed[2], st.picks[2],
    JSON.stringify(quizAnswers(a))]);
}
state.answering = {};
show('a number\'s − and +, within its range', ['ask-dec', 'ask-dec', 'ask-inc', 'ask-inc', 'ask-inc'].map((cls) => {
  press(SAMPLES.qNumber, fake([cls])); return quizState(SAMPLES.qNumber.id).typed[0]; }));
show('several questions, one a number typed outside its range: Submit stays off, and its range says why',
     (() => { const a = ask('AskUserQuestion', { questions: [choice(['Above', 'Under']), { question: 'How many?',
                                                    kind: 'number', min: 1, max: 9 }] });
              a.id = 'qStepsNumber';
              const st = quizState(a.id); st.picks[0] = [0]; st.typed[1] = '20'; st.at = 1;
              const html = askHTML(a, NOW, ROOT);
              return [quizAnswered(a, st), /q-submit" disabled/.test(html),
                      /ask-range warn" data-q="1">([^<]*)</.exec(html)?.[1]]; })());
show('…Skip on a typed answer sends none', press(SAMPLES.qText, fake(['q-skip'])));
state.answering = {};
show('× dismisses a question', press(SAMPLES.qText, fake(['icon-button', 'small', 'q-close'])));
state.answering = {};
show('a command\'s Allow once', press(SAMPLES.command, fake(['perm-allow'])));
state.answering = {};
show('Show less on a command shown in full: nothing sent, and it\'s cut short again',
     [press(SAMPLES.long, fake(['button', 'quiet', 'small', 'ask-more'], { part: '' })),
      JSON.stringify(state.askOpen[SAMPLES.long.id])]);
show('Send back… opens the box for notes, and Cancel closes it', ['ask-send', 'ask-say-cancel'].map((cls) => {
  press(SAMPLES.plan, fake(['button', cls])); return JSON.stringify(state.sendBack[SAMPLES.plan.id] ?? null); }));
show('a plan sent back with its notes', (() => {
  state.sendBack[SAMPLES.plan.id] = { text: 'Keep <codes> on the server' };
  sendBack(SAMPLES.plan.id); return `${JSON.stringify(sent.at(-1))} · ${state.answering[SAMPLES.plan.id]}`; })());
state.answering = {};
show('…with no notes, nothing', (() => { sent = []; state.sendBack[SAMPLES.plan.id] = { text: '  ' };
                                         sendBack(SAMPLES.plan.id); return sent.length; })());
print('-- a long plan: its first list\'s 3 steps, as its numbers start again after them, drawn from their markdown, ' +
      'then Read all 7 steps, Send back… and Take me there');
delete state.sendBack[SAMPLES.plan.id];
print(askHTML(LONG_PLAN, NOW, ROOT));
state.last.sessions.push(session({ sessionId: 'sLong', ask: LONG_PLAN }));
state.shownAt[LONG_PLAN.id] = Date.now() - 2000;
show('Read all its steps opens the whole plan in the reader, and Take me there its session: nothing sent', (() => {
  const [realReader, realSession] = [openReader, openSession], went = [];
  openReader = (sid, id, view) => went.push(`reader: ${sid}, ${view}`);
  openSession = (s) => went.push(`session: ${s.sessionId}`);
  const pressed = ['perm-read', 'perm-go'].map((cls) => press(LONG_PLAN, fake(['button', cls])));
  [openReader, openSession] = [realReader, realSession];
  return [...went, ...pressed];
})());
show('a plan of 4 steps or fewer: Read the plan', /perm-read">([^<]*)</.exec(askHTML(ask('ExitPlanMode',
  { plan: '# Short\n\n1. One\n2. Two' }), NOW, ROOT))[1]);
{
  // A plan at a glance whose pick you've changed in the reader (the plans module keeps it, by the request's id).
  const COUPON = ask('ExitPlanMode', { plan: '# Coupon field\n\n## At a glance\n\n- **What changes for you:** the '
    + 'field sits above the total.\n- **You decide:**\n  1. When it\'s checked: as you leave it (recommended), or on '
    + 'Apply.\n\n## Steps\n\n1. Move the field\n' }, { id: 'coupon' });
  state.last.sessions.push(session({ sessionId: 'sCoupon', ask: COUPON }));
  state.shownAt.coupon = Date.now() - 2000;
  core.plans.readerHTML(COUPON.input.plan, { sessionId: 'sCoupon', id: 'coupon', waiting: true });
  state.planPicks.coupon = { 0: 1 };
  state.sendBack.coupon = { text: 'Keep it short' };  // its box opened on the row before the pick changed
  show('a plan whose pick you changed: its row says so, and that your note waits, in place of its box',
       [/You decide<\/span><span class="gl-mt">([^<]*)/.exec(askHTML(COUPON, NOW, ROOT))[1],
        askHTML(COUPON, NOW, ROOT).includes('ask-say-box'),
        /<p class="ask-say-waits">[^<]*<\/p>/.exec(askHTML(COUPON, NOW, ROOT))?.[0],
        /ask-send">Send back…/.test(askHTML(COUPON, NOW, ROOT))]);
  show('…its Return or Send back, from a box drawn before: nothing sent without your picks',
       (sent = [], sendBack('coupon'), sent.length));
  const realNotes = core.planNotes, went = [];
  core.planNotes = (sid) => went.push(`the plan in ${sid}, its box open`);
  show('…and Send back… opens the plan beside the list, its box open, which takes your note from here',
       [press(COUPON, fake(['button', 'ask-send'])), ...went]);
  show('the box beside the list takes your note, and the row no longer has it',
       [core.planRowNotes.take('coupon'), state.sendBack.coupon ?? null,
        /ask-say-waits/.test(askHTML(COUPON, NOW, ROOT))]);
  core.planRowNotes.keep('coupon', 'Keep it short');
  show('…given back as the reader closes unsent: it waits on the row again',
       /<p class="ask-say-waits">[^<]*<\/p>/.test(askHTML(COUPON, NOW, ROOT)));
  delete state.sendBack.coupon;
  core.planNotes = realNotes;
  delete state.planPicks.coupon;
}
print('-- a plan with no steps: its first lines drawn from their markdown');
print(askHTML(ask('ExitPlanMode', { plan: '# Tidy\n\nMove **the coupon** into `basket.ts`.\n- and keep *the* route' }),
              NOW, ROOT));
show('which presses answer (and so leave the keyboard where it was)', [['perm-allow'], ['q-close'], ['opt', 'ask-num'],
  ['opt', 'ask-num', 'ask-type-opt'], ['opt'], ['ask-inc'], ['button', 'ask-more'], ['perm-allow', 'q-next'],
  ['q-pass']].map((classes) => `${classes.at(-1)}: ${pressAnswers({}, { closest: () => fake(classes) })}`));
show('…and on several questions, a numbered option only picks', pressAnswers({ matches: (sel) => sel === '.ask-qSteps' },
  { closest: () => fake(['opt', 'ask-num']) }));
// A single pick drawn twice, on its row and in a view beside the list: Type an answer opens the box in the copy that
// has the keys, wherever it is, else in the list's.
const copyOf = (id, where, focused) => ({ dataset: { ask: id }, querySelector: (sel) => (sel.startsWith('.ask-row-box')
  ? { focus: () => focused.push(where) } : null) });
// Every copy here counts as on the list, and the list has no layout to move (showLeast).
const [realHeld, realAll, realContains, realShowLeast] = [heldCard, list.querySelectorAll, list.contains, showLeast];
list.contains = () => true;
showLeast = () => {};
show('a request drawn twice: the box opened with its copy beside the list holding the keys, another card, and none',
     [SAMPLES.qOne.id, 'other', null].map((heldId) => {
       const focused = [], id = SAMPLES.qOne.id;
       heldCard = () => heldId && copyOf(heldId, heldId === id ? 'beside the list' : 'another card', focused);
       list.querySelectorAll = () => [copyOf('other', 'another row', focused), copyOf(id, 'the list', focused)];
       openTyping(id);
       quizState(id).typing = false;
       return focused.join(', ') || 'none';
     }));
[heldCard, list.querySelectorAll, list.contains, showLeast] = [realHeld, realAll, realContains, realShowLeast];
show('of 3 options, none ticked: 1, 3 and 4 (past them), and a letter',
     ['1', '3', '4', 'a'].map((k) => keyPick(3, true, [], k)));
show('…the first and third ticked: 2 adds it, 3 takes it out', ['2', '3'].map((k) => keyPick(3, true, [0, 2], k)));

section('Once answered');
// The line where the card was, while its request is still listed; one still there after a few seconds offers its
// session.
for (const [name, how] of [['command', 'allow'], ['command', 'deny'], ['qOne', 'answered'], ['qText', 'dismissed'],
                           ['plan', 'sentBack'], ['plan', 'stopped']]) {
  answered(SAMPLES[name].id, how);
  print(`-- ${name}, ${how}\n${receiptHTML(SAMPLES[name], 'r1')}`);
}
answered(SAMPLES.qMulti.id, 'skipped');
print(`-- qMulti, skipped\n${receiptHTML(SAMPLES.qMulti, 'r1')}`);
quizState(SAMPLES.qOne.id).sent = 'Under the total';
show('a question answered names what was sent', /ask-obj">([^<]*)</.exec(receiptHTML(SAMPLES.qOne, 'r1'))[1]);
state.answeredAt[SAMPLES.command.id] = Date.now() - 6000;
print(`-- still there after a few seconds\n${receiptHTML(SAMPLES.command, 'r1')}`);
show('…its Take me there, pressed as it appears, does nothing; once seen, it opens the session', (() => {
  const go = (seenAgo) => {
    state.shownAt[`receipt:${SAMPLES.command.id}`] = Date.now() - seenAgo;
    sent = [];
    const receipt = { dataset: { for: SAMPLES.command.id, receipt: 's0' } };
    core.presses.find(([sel]) => sel === '.ask-receipt .ask-receipt-go')[1](
      { closest: () => receipt }, { preventDefault() {} });
    return sent.map((m) => m.type).join(' ') || 'nothing sent';
  };
  return [go(0), go(2000)];
})());
const cardsFor = (s) => core.rowCards.filter((c) => c.wants({ s })).map((c) => `${c.name} (${c.order})`);
delete state.answering[SAMPLES.read.id];
show('which cards want the row: a request answered, and one not answered', [cardsFor(session({ ask: SAMPLES.command })),
     cardsFor(session({ ask: SAMPLES.read }))]);
// Beside the folded panel (row.chat), the answered line isn't drawn: answering takes the card away and the chat goes
// straight to its height, rather than shrinking again when the request goes. Only once the answer has gone unlanded
// does the line show there too, with the way to its session; the list's row keeps it throughout.
const cardHTML = (chat) => rowCard({ s: session({ ask: SAMPLES.command }), now: NOW, chat });
const lineIn = (chat) => {
  const html = cardHTML(chat);
  if (!html.includes('ask-receipt')) return 'no line';
  return html.includes('Take me there') ? 'line, Take me there' : 'line';
};
state.answeredAt[SAMPLES.command.id] = Date.now() - 1000;
show('answered just now: in the list, then as a chat beside the folded panel', [lineIn(false), lineIn(true)]);
state.answeredAt[SAMPLES.command.id] = Date.now() - 6000;
show('answered a while ago and still there: in the list, then as a chat', [lineIn(false), lineIn(true)]);
// Its row as a chat says the answer is going in, Claude's line saying what you answered and its dot the working one,
// till the app's rows say the request has gone; the list's row still asks, its card's line saying it was answered.
const drawnAs = (chat) => {
  const html = rowHTML(session({ ask: SAMPLES.command }), 'needs', NOW, { chat });
  const line = /<div class="claude ([\w ]*)" data-mode="\w+"><span class="who">Claude<\/span><span class="what">([^<]*)/
    .exec(html);
  const dot = /class="row needs[^"]* answered/.test(html) ? 'working dot' : 'asking dot';
  return `${dot} · ${line?.[1]}: ${line?.[2]}`;
};
answered(SAMPLES.command.id, 'allow');
show('answered just now, Claude\'s line and dot: in the list, then as a chat', [drawnAs(false), drawnAs(true)]);
answered(SAMPLES.command.id, 'deny');
show('…turned down, as a chat', drawnAs(true));
// Late, the chat asks again, the late line under it saying what you answered, so the answer is said once.
state.answeredAt[SAMPLES.command.id] = Date.now() - 6000;
show('…answered a while ago and still there, as a chat', [drawnAs(true), lineIn(true)]);
state.answering = {};

section('What a session you allow answered for this one');
const by = (fields) => ({ by: 'Atlas', title: 'Coupon field', at: NOW - 60000, ...fields });
for (const [name, a] of [
  ['its plan sent back', by({ what: 'sentBack', note: 'Keep <b>codes</b> on the server.' })],
  ['its questions answered', by({ what: 'answered', note: 'Where? “Above the total”' })],
  ['its plan approved', by({ what: 'approved', state: 'approved', planId: 'toolu_p1' })],
  ['its approval not taken', by({ what: 'approved', state: 'notTaken' })],
  ['its approval not settled yet', by({ what: 'approved', state: 'pending' })],
]) print(`-- ${name}\n${answeredForHTML(session({ sessionId: 'af', answeredFor: a }), NOW) || '(nothing)'}`);
const afCard = core.rowCards.find((c) => c.name === 'answeredFor');
show('shown while no request waits, not while one does, and after every other card',
     [afCard.wants({ s: session({ answeredFor: by({ what: 'sentBack', note: 'n' }) }) }),
      afCard.wants({ s: session({ answeredFor: by({ what: 'sentBack', note: 'n' }), ask: SAMPLES.command }) }),
      Math.max(...core.rowCards.filter((c) => c !== afCard).map((c) => c.order)) < afCard.order]);

section('A reply to a message another session sent');
const fromPeer = { lastPrompt: 'Look at the draft', promptFrom: 'Lead', promptFromAddress: '/tmp/cc-socks/7.sock',
                   lastPromptAt: min(6), lastReply: 'Looked: two notes', lastReplyAt: min(5), statusUpdatedAt: min(5) };
const replyKind = (fields) => classify(session({ sessionId: 'p1', ...fields }), NOW, view());
show('known by its address: gone there, not yours to read', replyKind(fromPeer));
show('…by the session that sent it', replyKind({ ...fromPeer, promptFromAddress: undefined, promptFromSession: 'a1' }));
show('…but a name alone isn\'t enough', replyKind({ ...fromPeer, promptFromAddress: undefined }));
show('…nor a reply from before that message', replyKind({ ...fromPeer, lastReplyAt: min(7) }));
show('…and one to your own message is yours', replyKind({ ...fromPeer, promptFrom: undefined }));
show('…a question it asks you itself still waits on you', replyKind({ ...fromPeer, status: 'waiting',
  ask: SAMPLES.command }));
show('…and long after, it never comes to be yours', classify(session({ sessionId: 'p1', ...fromPeer }), NOW + 2 * 864e5,
                                                             view()));
// A reply to you not read yet stays to read when a message from another session comes, and its reply after.
const toYou = session({ sessionId: 'p1', ...fromPeer, promptFrom: undefined, promptFromAddress: undefined });
state.toRead = {};
keepToRead([toYou]);
show('…one to you not read yet is kept', state.toRead.p1 === toYou.lastReplyAt);
const toldPeer = session({ sessionId: 'p1', ...fromPeer, lastPromptAt: min(3), lastReplyAt: min(1) });
keepToRead([toldPeer]);
show('…the reply to the other session after it doesn\'t read it for you', replyKind(toldPeer));
keepToRead([asSent({ ...toldPeer, seenAt: min(0.5) })]);
show('…until you\'ve read it', `${replyKind(asSent({ ...toldPeer, seenAt: min(0.5) }))}, kept: ${'p1' in state.toRead}`);
// One kept before the app knew who sent it goes once that's known, being the same reply.
state.toRead = {};
keepToRead([session({ sessionId: 'p1', ...fromPeer, promptFromAddress: undefined })]);
keepToRead([session({ sessionId: 'p1', ...fromPeer })]);
show('…one to it, kept before its sender was known', `${replyKind(fromPeer)}, kept: ${'p1' in state.toRead}`);
state.toRead = {};

section('A session that has stopped');
show('its row says so, and that a press carries it on',
     endedLineHTML({ s: session({ status: 'closed' }) }).includes('Stopped · press to carry on'));
show('…not while it runs', endedLineHTML({ s: session({ status: 'idle' }) }));
show('…nor once it closed while it waits on someone else, whose own line says it once',
     endedLineHTML({ s: session({ status: 'closed', wait: { closed: true, says: 'Stopped, waiting on #12' } }) }));
show('…but it does for one whose wait isn\'t shown as closed (run again a moment ago)',
     endedLineHTML({ s: session({ status: 'closed', wait: { says: 'Waits on #12' } }) }).includes('Stopped'));
