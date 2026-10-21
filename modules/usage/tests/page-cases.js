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
show('signed in with an API key or another provider', viewOf({ state: 'other' }).state);
show('no claude on this Mac', viewOf({ state: 'none' }).state);
show('not asked yet', viewOf(null).state);
const earlyView = viewOf(plan({ used: 20, resetsAt: NOW + 4.5 * HOUR }, { used: 8, resetsAt: NOW + 100 * HOUR }));
show('20% half an hour in', { state: earlyView.state, session: [earlyView.session.used, earlyView.session.severity,
                                                            earlyView.session.colour], pace: earlyView.pace });
const steadyView = viewOf(plan({ used: 30, resetsAt: NOW + 2 * HOUR }, { used: 8, resetsAt: NOW + 100 * HOUR }));
show('30% three hours in: on course, no note', steadyView.pace);
const warnedView = viewOf(plan({ used: 82, resetsAt: NOW + 2 * HOUR + 59 * MINUTE },
                               { used: 30, resetsAt: NOW + 41 * HOUR },
                               { limits: [{ kind: 'session', percent: 82, severity: 'warning' },
                                          { kind: 'weekly_all', percent: 30, severity: 'normal' }] }));
show("82% two hours in, Claude says warning",
  [warnedView.session.severity, warnedView.session.colour, warnedView.week.severity]);
show('82% two hours in: the pace', warnedView.pace);
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
                                                         { used: 61, resetsAt: NOW + 54 * HOUR })).detail);
show('folded, a window just reset: no time left', edgeOf(atLimitPlan, NOW + 21 * MINUTE));

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
