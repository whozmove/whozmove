// Plan usage: from what the app found (app/Usage.m) to what the usage card shows: each window's bar, colour, time left
// and where it ends up at this pace, the line under the rows, whether you're waiting for the session limit to reset,
// what the card shows while it's folded, and every word of your gear (app/Gear.m works out its numbers).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need (`now` among it) and change nothing, so tests/panel.sh checks every case.

// How long a Claude plan's usage windows run: the session (five hours from your first message) and the week. The
// strip works out its pace from them.
const SESSION_WINDOW_MS = 5 * 3600 * 1000, WEEK_WINDOW_MS = 7 * 24 * 3600 * 1000;
// How long each window runs before its pace is shown: before then a single burst would read as a pace.
const SESSION_SETTLE_MS = 20 * 60 * 1000, WEEK_SETTLE_MS = 12 * 3600 * 1000;
// A pace from this far under 1× up to 1× counts as even: the window lasts about until it resets. Any pace over 1× is
// fast, however slightly, as the window then runs out before it resets.
const PACE_EVEN = 0.2;

// What the strip shows, from the app's data: { state, session, week, pace }.
// - state: 'hidden' (nothing to show: no plan's numbers, nothing to ask, or not asked yet), 'signin' (Claude Code
//   isn't signed in), 'ok', or 'wait' (the session limit is reached and resets later; not while extra usage is on, as
//   then the limit doesn't stop you).
// - session, week: { used, known, colour, severity, resetsAt, left, even, pace, ends, outAt } for each window. A
//   window whose reset has passed reads 0% with no time left until the app asks again, so a limit that's over never
//   shows as reached. `known` is whether the answer has a reading for it at all (usageWindow's). `even`, `pace`,
//   `ends` and `outAt` are windowPace's.
// - pace: the line under the rows (paceLine's), or null.
function usageView(data, now, locale, timeZone) {
  if (data?.state === 'signedOut') return { state: 'signin' };
  if (data?.state !== 'ok') return { state: 'hidden' };
  const limits = Array.isArray(data.limits) ? data.limits : [];
  const session = usageWindow(data.session, limits.find((l) => l.kind === 'session'), now);
  const week = usageWindow(data.week, limits.find((l) => l.kind === 'weekly_all'), now);
  Object.assign(session, windowPace(session, SESSION_WINDOW_MS, SESSION_SETTLE_MS, now));
  Object.assign(week, windowPace(week, WEEK_WINDOW_MS, WEEK_SETTLE_MS, now));
  const waiting = session.used >= 100 && session.left > 0 && !data.extraUsage;
  const pace = waiting ? null : paceLine(session, week, now, locale, timeZone);
  return { state: waiting ? 'wait' : 'ok', session, week, pace };
}

// One window: how much is used, whether the answer has a reading for it, its colour, and when it resets. Claude's own
// word for how worrying a bar is (severity) sets the colour, as Claude colours its own; without one, 75% is a warning
// and 100% the limit. Claude Code's answer can leave a window out altogether (the week without the five-hour session,
// say): with no number for it, its own or in the limits, it has no reading (`known` false), which isn't a reading of
// 0%, so its bar is empty and its words say so (percentText, resetsText). A window whose reset has passed still has a
// reading: it reads 0% until the app asks again.
function usageWindow(win, limit, now) {
  const known = Number.isFinite(win?.used) || Number.isFinite(limit?.percent);
  const resetsAt = known ? win?.resetsAt || limit?.resetsAt || 0 : 0;
  const over = resetsAt > 0 && resetsAt <= now;
  const said = Number.isFinite(win?.used) ? win.used : limit?.percent;
  const used = over || !known ? 0 : Math.max(0, Math.min(100, Math.round(said)));
  const severity = over || !known ? 'normal' : usageSeverity(limit?.severity, used);
  return { used, known, severity, colour: GAUGE[severity], resetsAt: over ? 0 : resetsAt,
           left: over ? 0 : resetsAt > 0 ? resetsAt - now : 0 };
}

function usageSeverity(said, used) {
  if (used >= 100) return 'limit';
  if (said === 'normal' || said === 'warning') return said;
  if (said) return 'limit';  // a word past "warning" (critical, exceeded): it's at its limit
  return used >= 75 ? 'warning' : 'normal';
}

// Time left as the strip shows it, rounded up to the minute: "1d 17h", "2h 05m", "42m"; '' when there's none.
function timeLeft(ms) {
  if (!(ms > 0)) return '';
  const minutes = Math.ceil(ms / 60000);
  if (minutes >= 1440) return `${Math.floor(minutes / 1440)}d ${Math.floor((minutes % 1440) / 60)}h`;
  if (minutes >= 60) return `${Math.floor(minutes / 60)}h ${String(minutes % 60).padStart(2, '0')}m`;
  return `${minutes}m`;
}

// What a row says in place of a reset time for a window with no reading.
const NO_READING = 'no reading';

// A window's percent as its row, the folded card and the wait strip write it: "40%", or a dash for a window with no
// reading, so it never reads as 0% used.
function percentText(win) {
  return win.known ? `${win.used}%` : '–';
}

// What the folded card shows (card.js): the window nearer its limit (the session, unless the week's colour says the
// week is further on, or the session has no reading and the week has one), how much of it is used and in which
// colour, and the words on it when it slides out: that window's name and time left (at the session limit, when it's
// back), then the other window's name and percent, a dash if that window has no reading. { window, label, used,
// usedText, colour, back, time, after, other: { label, used, usedText } }: `time` is the words after the percent and
// `after` what follows them ("left", or nothing while it's back or there is no time).
function edgeView(view, now, locale, timeZone) {
  const rank = { normal: 0, warning: 1, limit: 2 };
  const isWeek = view.session.known !== view.week.known ? !view.session.known
    : rank[view.week.severity] > rank[view.session.severity];
  const [shown, other] = isWeek ? [view.week, view.session] : [view.session, view.week];
  const back = view.state === 'wait' && !isWeek;
  let time = timeLeft(shown.left);
  if (back) {
    const line = backLine(view.session.left, now, view.session.resetsAt, locale, timeZone);
    time = line[0].toLowerCase() + line.slice(1);
  }
  const after = back || !time ? '' : 'left';
  return { window: isWeek ? 'week' : 'session', label: isWeek ? 'Week' : 'Session', used: shown.used,
           usedText: percentText(shown), colour: shown.colour, back, time, after,
           other: { label: isWeek ? 'Session' : 'Week', used: other.used, usedText: percentText(other) } };
}

// Where a move of the pointer from `from` to `at` (points in the card's page, y running down) went down across the
// line y = `edge`: the point just above that line on the way, { x, y: edge - 1 }, or null when it didn't (no `from`,
// `from` not above the line, or `at` not on or below it). The app looks at the pointer only 25 or 60 times a second,
// so a quick hand going down from the panel's list onto the folded card crosses the band along the panel's edge
// between two looks, and is never seen in it: the card slides out for it as if it had been (cardPointer in card.js).
function edgeCrossing(from, at, edge) {
  if (!from || !(from.y < edge) || !(at?.y >= edge)) return null;
  const y = edge - 1;
  return { x: Math.round(from.x + (at.x - from.x) * (y - from.y) / (at.y - from.y)), y };
}

// The clock time something happens, in the Mac's own way of writing times: "3:00 PM" today, "Fri 9:00 AM" on another
// day this week (tomorrow too, so it's never taken for today), "Mar 3, 9:00 AM" further off. `locale` and `timeZone`
// are for tests; the page leaves them out.
function clockAt(at, now, locale, timeZone) {
  if (!(at > 0)) return '';
  const time = new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).format(at);
  const day = (t) => new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone })
    .format(t);
  if (day(at) === day(now)) return time;
  const far = at - now >= 6 * 24 * 3600 * 1000;
  const date = new Intl.DateTimeFormat(locale, far ? { month: 'short', day: 'numeric', timeZone }
                                                   : { weekday: 'short', timeZone }).format(at);
  return `${date}${far ? ',' : ''} ${time}`;
}

// How fast a window is being used: { even, pace, ends, outAt }. `even` is how much of its time has gone, from 0 to 1,
// which is how much would be used by now if it were spent evenly (the notch on the slid-out card); null with no time
// left, or at 100%. `pace` is how much is used over that, so 1 spends it evenly, using it up right as it resets; above
// 1 it runs out first, below some goes unused. `ends` is the percent it reaches by its reset at this pace, at most 100,
// and `outAt` when it reaches 100 before then, else null. All but `even` are null until the window has run for
// `settleMs`.
function windowPace(win, windowMs, settleMs, now) {
  if (!(win.left > 0) || win.used >= 100) return { even: null, pace: null, ends: null, outAt: null };
  const elapsed = Math.max(0, Math.min(windowMs, windowMs - win.left));
  const even = elapsed / windowMs;
  if (elapsed < settleMs) return { even, pace: null, ends: null, outAt: null };
  const pace = win.used / 100 / even;
  return { even, pace, ends: Math.min(100, Math.round(win.used / even)),
           outAt: pace > 1 ? now + (100 - win.used) / (win.used / elapsed) : null };
}

// Whether a pace is slow, even or fast. Fast is anything over 1×, as a window going faster than that reaches 100%
// before it resets, which matters however little over it is.
function paceKind(pace) {
  if (pace == null) return null;
  return pace > 1 ? 'fast' : pace < 1 - PACE_EVEN ? 'slow' : 'even';
}

// Where a window ends up, as its row writes it beside its percent: "→ 30%", or "out 1:41 PM" going fast ("out in 2d
// 4h" on another day, as a day and a time would leave its bar little room); "–" before it's known.
function endsText(win, now, locale, timeZone) {
  if (win.pace == null) return '–';
  if (paceKind(win.pace) !== 'fast') return `→ ${win.ends}%`;
  const at = clockAt(win.outAt, now, locale, timeZone);
  return /^\d/.test(at) ? `out ${at}` : `out in ${timeLeft(win.outAt - now)}`;
}

// A row's time until its window resets: "2h 59m", or "resets 4d 1h" while the row says when it runs out, so the two
// times beside each other say which is which; "no reading" for a window with no reading, as there's no reset to count
// to; "" with no time left.
function resetsText(win) {
  if (!win.known) return NO_READING;
  const left = timeLeft(win.left);
  return left && paceKind(win.pace) === 'fast' ? `resets ${left}` : left;
}

// The line under the rows: { text, kind }, about the session, or about the week when the week will run out first
// and the session won't; null with nothing to say (no session going). It says what that pace comes to, and what to
// do about it, on a line of its own: fast, that it runs out first (the row says when); even, that it lasts; slow, how
// much would go unused. With no reading for the session there's nothing to say of it, so the line goes by the week
// alone: the week's own sentence once its pace is known, else nothing.
function paceLine(session, week, now, locale, timeZone) {
  if (!session.known) return week.pace == null ? null : paceSays(week, 'week', now, locale, timeZone);
  const runsOut = (win) => win.pace != null && paceKind(win.pace) === 'fast';
  if (runsOut(week) && !runsOut(session)) return paceSays(week, 'week', now, locale, timeZone);
  if (session.pace == null) {
    if (session.even == null) return null;
    return { text: 'Where the session ends up shows 20 minutes in.', kind: null };
  }
  return paceSays(session, 'session', now, locale, timeZone);
}

// A time as one piece of text, never split across two lines of the card ("2h 33m" across a break reads as two
// figures).
function keepWhole(text) {
  return text.replace(/ /g, '\u00a0');
}

function paceSays(win, name, now, locale, timeZone) {
  const kind = paceKind(win.pace);
  // The reset's time: "at 3:45 PM" today, "on Sat 9:12 PM" another day.
  const when = (at) => {
    const c = clockAt(at, now, locale, timeZone);
    return `${/^\d/.test(c) ? 'at' : 'on'} ${keepWhole(c)}`;
  };
  if (kind === 'fast')
    return { text: `Going fast: the ${name} runs out before it resets.\nEase off to make it last.`, kind };
  if (kind === 'slow')
    return { text: `Going slow: about ${100 - win.ends}% of the ${name} would go unused.\nRoom to do more.`, kind };
  return { text: `About even: the ${name} lasts until it resets ${when(win.resetsAt)}.`, kind };
}

// The line at the foot of the open card about the session that has used the most today ({name, share, tokens}, as the
// app found it): its name, then its share of what the sessions used today and how long its conversation is now, which
// each of its replies reads again: { name, rest }, or null with no one to name.
function heaviestLine(heaviest) {
  if (!heaviest?.name) return null;
  const long = heaviest.tokens > 0 ? ` · ${tokensText(heaviest.tokens)} long` : '';
  return { name: heaviest.name, rest: ` uses the most today: ${heaviest.share}%${long}` };
}

// A number of tokens as the card writes it: "900", "744k", "1.2M".
function tokensText(tokens) {
  if (tokens < 1000) return `${Math.round(tokens)}`;
  if (tokens < 999500) return `${Math.round(tokens / 1000)}k`;
  return `${(tokens / 1e6).toFixed(1).replace(/\.0$/, '')}M`;
}

// While you wait, the session line: the clock time it's back while that's over an hour off, then the minutes, then
// the seconds.
function backLine(left, now, resetsAt, locale, timeZone) {
  if (left > 59 * 60 * 1000) return `Back at ${clockAt(resetsAt, now, locale, timeZone)}`;
  if (left >= 60 * 1000) return `Back in ${Math.ceil(left / 60000)}m`;
  return `Back in ${Math.max(1, Math.ceil(left / 1000))}s`;
}

// How far through the wait you are, 0 at the limit and 1 at the reset: from when the panel first saw the limit
// (`since`) to the reset.
function waitProgress(since, resetsAt, now) {
  if (!(resetsAt > since)) return 1;
  return Math.max(0, Math.min(1, (now - since) / (resetsAt - since)));
}

// ---- Your gear ----
//
// What the app worked out (setGear; app/Gear.m), as `facts`: { gear (null until your first press), atWork, over (the
// sessions beyond the gear), recommended (null while the week can't be measured), notYet, limit, forecast }.

// The highest gear (GearHighest in app/Gear.m); the lowest is 1.
const GEAR_HIGHEST = 30;
// The seats' words (gear.js draws them): their label; what VoiceOver says for them as a whole, how many are working, as
// only the lit seats show it; and each seat's, which is also what VoiceOver says for it: its gear, whether a session
// working lights it, and whether it's your gear or the recommended one, as only the light, the box and the notch show
// them. How many are working, and how many over the gear, are each said the same wherever they show.
const GEAR_SEATS = {
  label: 'Gear',
  group: (n) => `Gear, ${GEAR_SEATS.working(n)}`,
  working: (n) => `${n} working`,
  over: (n) => `${n} over the gear`,
  seat: (n, yours, recommended, working) => `Gear ${n}${working ? ', a session working' : ''}`
    + `${yours ? ', your gear' : ''}${recommended ? ', recommended' : ''}`,
};
// The gear's words for what shows it beyond the card (core.gear.words): a session working beyond your gear, on its row
// (`overMark`) and where what waits is listed (`overSays`: it carries on, as the gear holds back only queued jobs
// waiting to start); the gear's line among them in words, for VoiceOver (`lineSays`: the first `gear` work). Where the
// gear is changed is gearWhere's, as it says something else with no gear.
const GEAR_WORDS = {
  overMark: 'Over the gear',
  overSays: 'Over the gear · carries on',
  lineSays: (gear) => `Gear ${gear}: the first ${gear} work, the rest wait`,
};

// What whatever shows the gear without its seats says of where it's changed, as the seats are only on the card; with
// no gear, in the gear's line's place, so a queue that never starts says why: with Usage Gear off in Settings (`off`),
// that nothing limits what starts; before your first press, that nothing is let in until then. Null while the gear
// isn't known yet, and at the session's limit, when the card hides its seats.
function gearWhere(facts, off) {
  if (off) return 'Usage Gear is off in Settings, so there\'s no limit on what starts.';
  if (!facts || facts.limit) return null;
  if (facts.gear == null) return 'No gear yet: press a seat on the usage card to let jobs in.';
  return 'Change your gear on the usage card, under the panel: press a seat.';
}

// The gear's line wherever it shows without its seats (core.gear.line: Up next): how many sessions are working,
// { says, over }: "6 working", with " · no gear yet" before your first press, and " · 2 over the gear" while more are
// working than your gear, said in the line's grey, as nothing is stopped for it, and in one piece with its dot, so the
// line wraps before it. On the card the seats show who's working, so its line is seatsLine's.
function gearLine(facts) {
  const none = facts.gear == null ? ` ${keepWhole('· no gear yet')}` : '';
  const over = facts.over?.length ? ` ${keepWhole(`· ${GEAR_SEATS.over(facts.over.length)}`)}` : '';
  return { says: `${GEAR_SEATS.working(facts.atWork)}${none}`, over };
}

// The line over the card's seats: only what the seats don't show by themselves, { says, over }: "No gear yet" before
// your first press, and "2 over the gear" while more are working than your gear, in the line's grey, as nothing is
// stopped for it; nothing otherwise, as each session working lights a seat. The line keeps its place empty, as it's
// where a seat pointed at says what a press there does (gearTip).
function seatsLine(facts) {
  return { says: facts.gear == null ? 'No gear yet' : '',
           over: facts.over?.length ? keepWhole(GEAR_SEATS.over(facts.over.length)) : '' };
}

// The seats as gear.js draws them, one for each gear from the lowest to the highest: { end, rec, label, seats },
// `label` what VoiceOver says for them as a whole. `end` is your gear, where the box round its seats ends (0 with none
// set); `rec` the recommended gear, the seat with the notch under it (null while the week can't be measured); each seat
// { to, in, lit, label }: the gear a press on it sets, whether it's in the box, whether a session working lights it,
// and what VoiceOver says for it. Sessions are lit from the first seat on, so those beyond your gear are lit past the
// box; with no gear set, there's no box and the sessions working are lit all the same.
function gearSeats(facts) {
  const end = facts.gear ?? 0, rec = facts.recommended ?? null;
  const seats = Array.from({ length: GEAR_HIGHEST }, (_, i) => ({
    to: i + 1, in: i < end, lit: i < facts.atWork,
    label: GEAR_SEATS.seat(i + 1, i + 1 === facts.gear, i + 1 === rec, i < facts.atWork),
  }));
  return { end, rec, label: GEAR_SEATS.group(facts.atWork), seats };
}

// Why no gear is recommended yet, on a line of its own; null once one is. The week has to go up about 5 points while
// Whozmove watches, with sessions working 2 hours of it, as its percents are whole numbers (kWeekRise and kWeekHours
// in app/Gear.m, their twins).
function gearNotYet(facts) {
  const n = facts.notYet;
  if (!n) return null;
  if (n.reason === 'rise')
    return `Not measurable yet: the week has gone up ${n.rise}% while Whozmove watched; a first reading needs about 5%.`;
  if (n.reason === 'hours')
    return `Not measurable yet: sessions have worked ${n.hours} ${n.hours === 1 ? 'hour' : 'hours'} of the 2 a first ` +
      'reading needs.';
  return "Not measurable yet: Whozmove wasn't watching for most of the last 2 days.";
}

// Where the week ends at the gear set (or else the recommended one, said so, as nothing else then names it), if that
// many sessions work for the hours yours have worked lately: "At gear 8 the week ends near 94%.", or when the week runs
// out and how long before it resets, or when the session runs out first; null with nothing measured.
function gearForecast(facts, now, locale, timeZone) {
  const f = facts?.forecast;
  if (!f) return null;
  const at = (t) => keepWhole(clockAt(t, now, locale, timeZone));
  const gear = facts.gear == null ? `At gear ${f.gear}, the one recommended,` : `At gear ${f.gear}`;
  if (f.sessionRunsOutAt) return `${gear} the session runs out ${at(f.sessionRunsOutAt)}.`;
  if (f.runsOutAt)
    return `${gear} the week ${f.gear === 1 ? 'still ' : ''}runs out ${at(f.runsOutAt)}, ` +
      `${keepWhole(timeLeft(f.resetsAt - f.runsOutAt))} before it resets.`;
  return `${gear} the week ends near ${f.ends}%.`;
}

// The one line under the rows: with a gear set and the week measurable, where the week ends at that gear (in "your
// move" amber when it runs out first); else today's pace (paceLine's). { text, kind }, or null.
function underRows(view, facts, now, locale, timeZone) {
  if (facts?.gear == null || facts.notYet || !facts.forecast) return view.pace;
  const f = facts.forecast;
  return { text: gearForecast(facts, now, locale, timeZone), kind: f.runsOutAt || f.sessionRunsOutAt ? 'fast' : null };
}

// What a seat says while it's pointed at, in the gear line's place, `to` being its gear: with no gear set, where a
// press starts; else what a press makes of the gear, or that it's yours; and at the recommended seat, why it's that
// one: the most the week lasts at, or the session, when the session runs out first at a higher gear (`bound`).
function gearTip(facts, to) {
  const recommended = to === facts.recommended;
  if (facts.gear == null) return recommended ? `Start at gear ${to}, the one recommended` : `Start at gear ${to}`;
  const lasts = facts.bound === 'session' ? 'session' : 'week';
  if (recommended) return `Gear ${to}, recommended: the most that lasts the ${lasts}`;
  return to === facts.gear ? `Your gear: the first ${to} work, the rest wait`
    : `Gear ${to}: the first ${to} work, the rest wait`;
}

// The gear in one line, in every state, for what shows it beyond the card (core.gear.whyLine): at the session's limit,
// that; while the week can't be measured, why; else where the week ends at the gear. Null before anything's known.
function gearWhy(facts, now, locale, timeZone) {
  if (!facts) return null;
  if (facts.limit) return 'The session is at its limit until it resets.';
  return gearNotYet(facts) ?? gearForecast(facts, now, locale, timeZone);
}
