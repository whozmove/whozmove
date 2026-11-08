// The usage card's page's logic, run outside the app by modules/usage/tests/test.sh: what the card shows from what the
// app found (usage.js), and the vine's growth and reset frame by frame (wait-vine.js). Nothing is drawn.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the card page's scripts and the helpers below use

section('Plan usage');
const HOUR = 3600e3, MINUTE = 60e3;
// What the app sends (modules/usage/app/Usage.m), for a session and a week; clock times in UTC, written the US way, on
// every Mac.
const plan = (session, week, more) => ({ state: 'ok', plan: 'pro', session, week, limits: [], extraUsage: false,
                                        ...more });
const viewOf = (data, now = NOW) => usageView(data, now, 'en-US', 'UTC');
show('time left, 2h 59m', timeLeft(2 * HOUR + 59 * MINUTE));
show('time left, 1d 17h', timeLeft(41 * HOUR + 17 * MINUTE));
show('time left, 2h 5m', timeLeft(2 * HOUR + 5 * MINUTE));
show('time left, 42m', timeLeft(42 * MINUTE));
show('time left, 20 seconds (rounded up)', timeLeft(20e3));
show('time left, none', timeLeft(0));
show('clock time, later today', clockAt(NOW + 2 * HOUR, NOW, 'en-US', 'UTC'));
show('clock time, tomorrow, within 12 hours', clockAt(NOW + 22 * HOUR, NOW, 'en-US', 'UTC'));
show('clock time, in two days', clockAt(NOW + 41 * HOUR, NOW, 'en-US', 'UTC'));
show('clock time, a week off', clockAt(NOW + 6.5 * 24 * HOUR, NOW, 'en-US', 'UTC'));
show('Claude Code not signed in', viewOf({ state: 'signedOut' }).state);
show('no plan\'s numbers (signed in or set up without them)', viewOf({ state: 'other', noPlan: 'signedIn' }).state);
show('no claude on this Mac', viewOf({ state: 'none' }).state);
show('not asked yet', viewOf(null).state);
const earlyView = viewOf(plan({ used: 20, resetsAt: NOW + 4.5 * HOUR }, { used: 8, resetsAt: NOW + 100 * HOUR }));
show('20% half an hour in', { state: earlyView.state, session: [earlyView.session.used, earlyView.session.severity,
                                                            earlyView.session.colour], pace: earlyView.pace });
const ends = (win) => endsText(win, NOW, 'en-US', 'UTC');
const steadyView = viewOf(plan({ used: 30, resetsAt: NOW + 2 * HOUR }, { used: 8, resetsAt: NOW + 100 * HOUR }));
show('30% three hours in: slow', [ends(steadyView.session), steadyView.pace]);
const warnedView = viewOf(plan({ used: 82, resetsAt: NOW + 2 * HOUR + 59 * MINUTE },
                               { used: 30, resetsAt: NOW + 41 * HOUR },
                               { limits: [{ kind: 'session', percent: 82, severity: 'warning' },
                                          { kind: 'weekly_all', percent: 30, severity: 'normal' }] }));
show("82% two hours in, Claude says warning",
  [warnedView.session.severity, warnedView.session.colour, warnedView.week.severity]);
show('82% two hours in: the pace', [ends(warnedView.session), warnedView.pace]);
const evenView = viewOf(plan({ used: 39, resetsAt: NOW + 3 * HOUR }, { used: 8, resetsAt: NOW + 100 * HOUR }));
show('39% two hours in: even, where the notch goes and where it ends up',
  [evenView.session.even, ends(evenView.session), evenView.session.ends, paceKind(evenView.session.pace),
   evenView.pace]);
const freshView = viewOf(plan({ used: 9, resetsAt: NOW + 4 * HOUR + 50 * MINUTE },
                              { used: 8, resetsAt: NOW + 100 * HOUR }));
show('9% ten minutes in: no pace yet', [freshView.session.even, ends(freshView.session), freshView.pace]);
const weekView = viewOf(plan({ used: 30, resetsAt: NOW + 3 * HOUR }, { used: 70, resetsAt: NOW + 84 * HOUR }));
show('the week running out first, the session not', [ends(weekView.week), weekView.pace]);
const slightlyFastView = viewOf(plan({ used: 11, resetsAt: NOW + 4 * HOUR + 2 * MINUTE },
                                     { used: 69, resetsAt: NOW + 2 * 24 * HOUR + 13 * HOUR }));
show('the week a little over even, the session slow: the week says when it runs out',
  [paceKind(slightlyFastView.week.pace), ends(slightlyFastView.week), slightlyFastView.pace]);
show('time to the reset, said as such beside "out …"', [resetsText(weekView.week), resetsText(weekView.session)]);
show('the week, six hours in: no pace yet',
  ends(viewOf(plan({ used: 30, resetsAt: NOW + 3 * HOUR }, { used: 9, resetsAt: NOW + 162 * HOUR })).week));
show('where it ends up, written', [{ pace: 0.6, ends: 60 }, { pace: 1.1, ends: 100, outAt: NOW + 4 * HOUR },
  { pace: 1.7, ends: 100, outAt: NOW + HOUR }, { pace: 1.5, ends: 100, outAt: NOW + 40 * HOUR },
  { pace: null }].map(ends));
show('pace kinds', [0.6, 0.85, 1.2, 1.21, null].map(paceKind));
show('the session using the most today', [heaviestLine({ name: 'site-redesign', share: 17, tokens: 744210 }),
  heaviestLine({ name: 'docs', share: 52, tokens: 0 }), heaviestLine(null)]);
show('tokens written', [0, 900, 999, 1000, 744210, 999499, 999500, 1200000, 12000000].map(tokensText));
show('82% with no severity from Claude',
  viewOf(plan({ used: 82, resetsAt: NOW + 3 * HOUR }, { used: 30, resetsAt: NOW + 41 * HOUR })).session.severity);
show("90% and a word past warning",
  viewOf(plan({ used: 90, resetsAt: NOW + 3 * HOUR }, { used: 30, resetsAt: NOW + 41 * HOUR },
              { limits: [{ kind: 'session', percent: 90, severity: 'critical' }] })).session.severity);
const atLimitPlan = plan({ used: 100, resetsAt: NOW + 20 * MINUTE }, { used: 30, resetsAt: NOW + 41 * HOUR });
show('at the session limit', viewOf(atLimitPlan).state);
show('at the limit with extra usage on: no wait', viewOf({ ...atLimitPlan, extraUsage: true }).state);
const afterReset = viewOf(atLimitPlan, NOW + 21 * MINUTE);
show('the limit has just reset: 0% until the app asks again',
  [afterReset.state, afterReset.session.used, afterReset.session.left]);
show('while waiting, hours off', backLine(2 * HOUR, NOW, NOW + 2 * HOUR, 'en-US', 'UTC'));
show('while waiting, the last hour', backLine(42 * MINUTE, NOW, NOW + 42 * MINUTE));
show('while waiting, the last minute', backLine(9e3, NOW, NOW + 9e3));
show('how far through the wait',
  [waitProgress(NOW - HOUR, NOW + HOUR, NOW), waitProgress(NOW, NOW + HOUR, NOW + 2 * HOUR)]);
// The folded card: which window its colour shows, how far, in which colour, and the words on it.
const edgeOf = (data, now = NOW) => edgeView(viewOf(data, now), now, 'en-US', 'UTC');
show('folded, both windows calm: the session', edgeOf(plan({ used: 34, resetsAt: NOW + 4 * HOUR + 10 * MINUTE },
                                                              { used: 12, resetsAt: NOW + 123 * HOUR })));
show('folded, the session getting close', edgeOf(plan({ used: 82, resetsAt: NOW + 2 * HOUR + 59 * MINUTE },
                                                          { used: 30, resetsAt: NOW + 41 * HOUR })));
show('folded, the week the one running low', edgeOf(plan({ used: 20, resetsAt: NOW + 4 * HOUR + 30 * MINUTE },
                                                             { used: 92, resetsAt: NOW + 28 * HOUR })));
show('folded, both close: the session', edgeOf(plan({ used: 80, resetsAt: NOW + 2 * HOUR },
                                                      { used: 90, resetsAt: NOW + 28 * HOUR })));
show('folded, at the session limit', edgeOf(plan({ used: 100, resetsAt: NOW + 2 * HOUR },
                                                  { used: 61, resetsAt: NOW + 54 * HOUR })));
show('folded, at the limit, the last hour', edgeOf(plan({ used: 100, resetsAt: NOW + 42 * MINUTE },
                                                         { used: 61, resetsAt: NOW + 54 * HOUR })).time);
show('folded, a window just reset: no time left', edgeOf(atLimitPlan, NOW + 21 * MINUTE));
// An answer with the week but no five-hour window: the session has no reading, which is not 0%. Its row says "–" and
// "no reading" (and has no clock time for pointing at it to swap in: usage.css keeps it still, checked below), the line
// under the rows goes by the week, and the folded card shows the week.
const weekOnly = plan(undefined, { used: 40, resetsAt: NOW + 84 * HOUR },
                      { limits: [{ kind: 'weekly_all', percent: 40 }] });
const weekOnlyView = viewOf(weekOnly);
const rowSaid = (win) => ({ known: win.known, percent: percentText(win), bar: win.used,
                           ends: win.even == null ? '' : endsText(win, NOW, 'en-US', 'UTC'), left: resetsText(win),
                           clock: clockAt(win.resetsAt, NOW, 'en-US', 'UTC') });
show('the week but no session: the state, and the session with no reading',
  [weekOnlyView.state, weekOnlyView.session.used, weekOnlyView.session.known, weekOnlyView.session.resetsAt,
   weekOnlyView.session.left, weekOnlyView.session.pace]);
show('the week but no session: the session\'s row, and the week\'s',
     [rowSaid(weekOnlyView.session), rowSaid(weekOnlyView.week)]);
show('the week but no session: the line under the rows goes by the week (40% of 3.5 days in)', weekOnlyView.pace);
show('the week but no session, the week going fast: its sentence, though the session is unknown',
  viewOf(plan(undefined, { used: 70, resetsAt: NOW + 84 * HOUR })).pace);
show('the week but no session, the week\'s pace not known yet: nothing under the rows',
  viewOf(plan(undefined, { used: 9, resetsAt: NOW + 162 * HOUR })).pace);
show('the week but no session: folded, the week is shown and the session\'s percent is a dash', edgeOf(weekOnly));
show('the session but no week: the session\'s row, the week\'s row, folded',
  [rowSaid(viewOf(plan({ used: 34, resetsAt: NOW + 4 * HOUR + 10 * MINUTE }, undefined)).week),
   edgeOf(plan({ used: 34, resetsAt: NOW + 4 * HOUR + 10 * MINUTE }, undefined))]);
show('neither window has a reading: both read a dash, nothing under the rows',
  [edgeOf(plan(undefined, undefined)), viewOf(plan(undefined, undefined)).pace]);
show('the session known only by the limits list is a reading',
  rowSaid(viewOf(plan(undefined, { used: 40, resetsAt: NOW + 84 * HOUR },
                      { limits: [{ kind: 'session', percent: 12, resetsAt: NOW + 4 * HOUR }] })).session));
show('a session that really is at 0%: it reads 0% and its time, as before', (() => {
  const zero = viewOf(plan({ used: 0, resetsAt: NOW + 4 * HOUR }, { used: 40, resetsAt: NOW + 84 * HOUR }));
  return { row: rowSaid(zero.session), folded: edgeView(zero, NOW, 'en-US', 'UTC') };
})());
show('the wait strip beside a week with no reading', percentText(viewOf(plan(
  { used: 100, resetsAt: NOW + 2 * HOUR }, undefined)).week));
// The pointer going down onto the folded card: the app looks at it only so often, so a quick hand crosses the panel's
// edge (UC_TOP down the card's page) between two looks, and the card slides out as if it had been seen just above the
// edge where it crossed.
const crossing = (from, at) => edgeCrossing(from, at, UC_TOP);
show('a quick hand down from the list, across the edge: where it crossed',
  crossing({ x: 180, y: -60 }, { x: 190, y: 45 }));
show('a slow hand, seen in the band already, crossing the edge', crossing({ x: 150, y: 21 }, { x: 152, y: 25 }));
show('from beside the card\'s window, above the edge', crossing({ x: 400, y: 4 }, { x: 280, y: 34 }));
show('going up: no crossing', crossing({ x: 200, y: 40 }, { x: 200, y: 10 }));
show('stopping short of the edge: no crossing', crossing({ x: 200, y: -60 }, { x: 200, y: 20 }));
show('no look before: no crossing', crossing(undefined, { x: 190, y: 45 }));
// A press on the open card has to reach what's on its strip (the gear's seats, Sign in), and pointing at it has to find
// what it's on; an empty box drawn over the strip takes both. jsc can't hit-test, so the rule they rest on is checked
// here: each layer drawn over the open strip lets presses and the pointer through, the gear's tip over its line too (it
// keeps its words after the pointer leaves), and the box, the ring and the notch over the seats.
const cardStyle = read('modules/usage/page/usage.css') + read('modules/usage/page/gear.css');
// The rule for `selector`, from its line to its closing brace, or null when the card's styles have none.
const ruleOf = (selector) => {
  const start = cardStyle.split('\n').find((line) => line.startsWith(selector + ' {'));
  if (!start) return null;
  const from = cardStyle.indexOf(start);
  return cardStyle.slice(from, cardStyle.indexOf('}', from));
};
const letsThrough = (selector) => ruleOf(selector) && /pointer-events:\s*none/.test(ruleOf(selector));
show("what's drawn over the open card lets presses and the pointer through to it",
  Object.fromEntries(['.uc-face', '.uc-travel', '.uc-shade', '.u-gear-tip', '.u-box', '.u-ring', '.u-rec']
    .map((selector) => [selector, letsThrough(selector)])));
// The command Sign in's line gives you to run yourself is one word as long as its path (an nvm install's,
// '/Users/sample/.nvm/versions/node/v22.11.0/bin/claude', has no space or hyphen to break at), so the line breaks
// anywhere, or it runs under Sign in and past the card's edge. jsc can't lay it out, so its rule is checked.
show("Sign in's line breaks a long command anywhere, inside the card",
  /overflow-wrap:\s*anywhere/.test(ruleOf('.u-signin .notice-text') || ''));
// A row with no reading has no clock time, so pointing at it would slide "no reading" out for an empty space: its rule
// keeps the time left where it is, the clock hidden and the column as wide as the time left. And "no reading" is the
// only words saying why the row is blank, so it's in the grey text is read in, not the reset times' fainter one.
show('a row with no reading: "no reading" in the grey text is read in, and still while pointed at', {
  colour: /color:\s*var\(--muted\)/.test(ruleOf('.u-row.no-reading .u-left') || ''),
  left: /opacity:\s*1/.test(ruleOf('.u-row.no-reading.is-hover .u-left') || ''),
  clock: /opacity:\s*0/.test(ruleOf('.u-row.no-reading.is-hover .u-clock') || ''),
  width: /--left-w/.test(ruleOf('.u-row.no-reading.is-hover .u-time') || '') });

section("The vine's growth and reset (wait-vine.js)");
show('growth at the limit, halfway, at the reset', [0, 0.5, 1].map((p) => {
  const g = vineGrowth(p);
  return { leaves: g.leaves, bud: !!g.bud };
}));
// The session's bar in the normal strip with no time left beside it, as just after a reset, and the strip's heights.
const vineBar = { x0: 72, x1: 278, y: 20 }, vineHeights = { wait: 84, normal: 61 };
const vineAt = (t) => vineFrame(t, vineBar, vineHeights);
const stemEnds = (t) => {
  const s = vineAt(t).stem;
  return s && [s[0], s[s.length - 1]].map((p) => p.map((v) => +v.toFixed(1)));
};
const restEnds = stemEnds(1100), movedEnds = stemEnds(1150);
show('both ends of the stem start moving together (1.1s)',
  [Math.hypot(movedEnds[0][0] - restEnds[0][0], movedEnds[0][1] - restEnds[0][1]) > 0,
   Math.hypot(movedEnds[1][0] - restEnds[1][0], movedEnds[1][1] - restEnds[1][1]) > 0]);
show('and land together on the bar (2.1s)', stemEnds(2100 - 1e-6));
// The bar's right end: the stem's until it lands (its round end reaching 2px further), then the fill's.
const rightEnd = (t) => {
  const f = vineAt(t);
  return f.stem ? f.stem[f.stem.length - 1][0] + 2 : vineBar.x0 + f.fill.width * (vineBar.x1 - vineBar.x0);
};
show('the drain carries on at the speed the stem landed with (px a ms)',
  [(rightEnd(2099.9) - rightEnd(2099.8)) / 0.1, (rightEnd(2100.2) - rightEnd(2100.1)) / 0.1].map((v) => v.toFixed(3)));
let highestLeaf = Infinity;
for (let t = 0; t <= VINE_RESET_MS; t += 5)
  for (const leaf of vineAt(t).leaves)
    if (leaf.opacity > 0.01) highestLeaf = Math.min(highestLeaf, leaf.y - 11 * leaf.scale);
show('no leaf flies into the text lane (above y 32)', highestLeaf >= 32 ? 'clear' : highestLeaf);
let laneEntered = null;
for (let t = 0; t <= VINE_RESET_MS && laneEntered === null; t += 5)
  if (vineAt(t).stem?.some(([, y]) => y < 31)) laneEntered = t;
const entryFrame = vineAt(laneEntered);
show('the session line is clear before the stem rises into it',
  { at: laneEntered, message: +entryFrame.message.opacity.toFixed(3), right: +entryFrame.right.opacity.toFixed(3) });
const lastFrame = vineAt(VINE_RESET_MS);
show('the last frame is the normal strip', {
  stem: lastFrame.stemShown, flower: lastFrame.flower, fill: lastFrame.fill.width, height: lastFrame.height,
  week: lastFrame.week.opacity, percent: lastFrame.percent.opacity, message: lastFrame.message.opacity,
  right: lastFrame.right.opacity,
});

section('Your gear');
// The facts as the app says them (setGear; app/Gear.m works out the numbers): 6 working, gear 8 recommended, the week
// resetting in 100 hours.
const gearFacts = (more) => ({ gear: null, atWork: 6, counted: ['a', 'b', 'c', 'd', 'e', 'f'], over: [], recommended: 8,
                               notYet: null, limit: false, bound: 'week', checkedAt: NOW,
                               forecast: { gear: 8, ends: 94, resetsAt: NOW + 100 * HOUR }, ...more });
const gearSaid = (facts) => {
  const line = gearLine(facts);
  return { line: line.says + line.over, why: gearNotYet(facts), forecast: gearForecast(facts, NOW, 'en-US', 'UTC') };
};
const roomView = viewOf(plan({ used: 30, resetsAt: NOW + 2 * HOUR }, { used: 38, resetsAt: NOW + 100 * HOUR }));
const under = (facts) => underRows(roomView, facts, NOW, 'en-US', 'UTC');
show('no gear set, measurable: Up next\'s line (core.gear.line), and today\'s pace under the rows',
  [gearSaid(gearFacts()), under(gearFacts())]);
show('set at the recommendation: the forecast under the rows',
  under(gearFacts({ gear: 8 })));
show('set lower: room', under(gearFacts({ gear: 6, forecast: { gear: 6, ends: 79, resetsAt: NOW + 100 * HOUR } })));
show('more working than the gear: Up next\'s line, two over it, in the line\'s grey',
  gearLine(gearFacts({ gear: 8, atWork: 10, over: ['g', 'h'] })));
show('set above what the week carries: when it runs out, and how long before it resets',
  under(gearFacts({ gear: 12, forecast: { gear: 12, ends: 122, resetsAt: NOW + 100 * HOUR,
                                          runsOutAt: NOW + 72 * HOUR } })));
show('the session is the limit', under(gearFacts({
  gear: 10, bound: 'session', recommended: 5,
  forecast: { gear: 10, ends: 99, resetsAt: NOW + 100 * HOUR, sessionRunsOutAt: NOW + 40 * MINUTE } })));
show('even gear 1 runs the week out', under(gearFacts({
  gear: 1, recommended: 1, forecast: { gear: 1, ends: 180, resetsAt: NOW + 100 * HOUR, runsOutAt: NOW + 18 * HOUR } })));
show('the plan carries more than 30: the notch under the last seat', gearSeats(gearFacts({ recommended: 30 })).rec);
const notYet = (n) => gearFacts({ recommended: null, bound: null, forecast: null, notYet: n });
show('not measurable yet: too little rise, with Up next\'s line',
  gearSaid(notYet({ reason: 'rise', rise: 2, hours: 3 })));
show('not measurable yet: too few hours, one', gearNotYet(notYet({ reason: 'hours', rise: 6, hours: 1 })));
show('not measurable yet: too few hours, none', gearNotYet(notYet({ reason: 'hours', rise: 6, hours: 0 })));
show('not measurable yet: not watched', gearNotYet(notYet({ reason: 'watched', rise: 3, hours: 15 })));
show('a gear set while not measurable: today\'s pace under the rows', under({ ...notYet({ reason: 'rise', rise: 2 }),
                                                                              gear: 6 }));
show('nothing working', gearLine(gearFacts({ atWork: 0, counted: [] })).says);
// On the card the seats show who's working, each session lighting one, so the line over them says only what they
// don't: no gear yet, how many are over it, else nothing, keeping its place for what a seat pointed at says.
show('the line over the card\'s seats: no gear yet; a gear set; two over it; nothing working', [
  seatsLine(gearFacts()), seatsLine(gearFacts({ gear: 8 })),
  seatsLine(gearFacts({ gear: 8, atWork: 10, over: ['g', 'h'] })),
  seatsLine(gearFacts({ gear: 8, atWork: 0, counted: [] }))]);
show('VoiceOver: the seats as a whole say how many are working, and a seat that a session working lights says so',
  (({ label, seats }) => [label, ...seats.slice(0, 3).map((s) => s.label)])(
    gearSeats(gearFacts({ gear: 8, atWork: 2 }))));
show('a seat pointed at, with no gear set: where a press starts, at the recommended seat and another',
  [gearTip(gearFacts(), 8), gearTip(gearFacts(), 12), gearTip(notYet({ reason: 'rise', rise: 2 }), 6)]);
show('a seat pointed at with a gear set: another gear, the recommended one, your own',
  [gearTip(gearFacts({ gear: 7 }), 12), gearTip(gearFacts({ gear: 7 }), 8), gearTip(gearFacts({ gear: 7 }), 7),
   gearTip(gearFacts({ gear: 8 }), 8)]);
show('the longest line over the seats: gear 1 with 30 working', seatsLine(gearFacts({
  gear: 1, atWork: 30, counted: Array.from({ length: 30 }, (_, i) => `s${i}`),
  over: Array.from({ length: 29 }, (_, i) => `s${i + 1}`) })));
// The seats as gear.js draws them: in the box up to your gear, lit from the first for each session working, those
// beyond your gear lit past it; written here as one letter a seat: L lit in the box, I in it with room, O lit past it
// (over the gear), . a dot past it.
const seatsSaid = (facts) => {
  const laid = gearSeats(facts);
  return { end: laid.end, rec: laid.rec, seats: laid.seats.map((s) => (s.in ? (s.lit ? 'L' : 'I') : s.lit ? 'O' : '.'))
    .join(''), to: laid.seats.map((s) => s.to).join(',') === Array.from({ length: 30 }, (_, i) => i + 1).join(',') };
};
show('the seats: no gear set, six working', seatsSaid(gearFacts()));
show('the seats: gear 8, six working, room for two', seatsSaid(gearFacts({ gear: 8 })));
show('the seats: gear 5, seven working, two over it', seatsSaid(gearFacts({ gear: 5, atWork: 7 })));
show('the seats: gear 1 and gear 30, nothing working, not measurable (no notch)',
  [seatsSaid({ ...notYet({ reason: 'rise', rise: 2 }), gear: 1, atWork: 0 }),
   seatsSaid({ ...notYet({ reason: 'rise', rise: 2 }), gear: 30, atWork: 0 })]);
show('the seats: more working than there are seats', seatsSaid(gearFacts({ gear: 24, atWork: 33 })).seats);
show('what VoiceOver says for a seat: yours, the recommended one, both, another (gear 5, then 8, recommended 8)',
  [gearSeats(gearFacts({ gear: 5 })).seats, gearSeats(gearFacts({ gear: 8 })).seats]
    .map((seats) => [seats[4].label, seats[7].label, seats[11].label]));
show('the recommended seat pointed at when the session sets it (the week would carry more)',
  [gearTip(gearFacts({ gear: 10, bound: 'session', recommended: 5 }), 5),
   gearTip(gearFacts({ gear: 10, bound: 'week' }), 8)]);
show('with no gear set, the forecast beyond the card names the recommended gear as that (Up next\'s why line)',
  [gearWhy(gearFacts(), NOW, 'en-US', 'UTC'), gearWhy(gearFacts({ gear: 8 }), NOW, 'en-US', 'UTC')]);
const runsOutLine = gearForecast(gearFacts({ gear: 12, forecast: { gear: 12, ends: 122, resetsAt: NOW + 100 * HOUR,
                                                                runsOutAt: NOW + 30 * HOUR } }), NOW, 'en-US', 'UTC');
show('a time is never split across two lines', !/\d (AM|PM)|\d[dhm] \d/.test(runsOutLine) ? 'whole' : runsOutLine);
show('the gear in one line, every state (core.gear.whyLine)', [
  gearWhy(null, NOW, 'en-US', 'UTC'), gearWhy(gearFacts({ limit: true }), NOW, 'en-US', 'UTC'),
  gearWhy(notYet({ reason: 'watched' }), NOW, 'en-US', 'UTC'), gearWhy(gearFacts({ gear: 8 }), NOW, 'en-US', 'UTC')]);
show('where to change it beyond the card, every state (core.gear.words.where): with a gear, none set yet, at the '
     + 'session\'s limit, not known yet, and Usage Gear off', [
  gearWhere(gearFacts({ gear: 8 }), false), gearWhere(gearFacts(), false),
  gearWhere(gearFacts({ gear: 8, limit: true }), false), gearWhere(null, false), gearWhere(null, true)]);
