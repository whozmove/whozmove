// Plan usage: from what the app found (app/Usage.m) to what the usage strip shows: each window's bar, colour and time
// left, the pace, and whether you're waiting for the session limit to reset.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Plain functions: they take what they need (`now` among it) and change nothing, so tests/panel.sh checks every case.

// How long a Claude plan's usage windows run: the session (five hours from your first message) and the week. The
// strip works out its pace from them.
const SESSION_WINDOW_MS = 5 * 3600 * 1000, WEEK_WINDOW_MS = 7 * 24 * 3600 * 1000;

// What the strip shows, from the app's data: { state, session, week, pace }.
// - state: 'hidden' (nothing to show: no `claude` here, signed in with an API key or another provider, not asked
//   yet), 'signin' (Claude Code isn't signed in), 'ok', or 'wait' (the session limit is reached and resets later;
//   not while extra usage is on, as then the limit doesn't stop you).
// - session, week: { used, colour, severity, resetsAt, left } for each window. A window whose reset has passed reads 0%
//   with no time left until the app asks again, so a limit that's over never shows as reached.
// - pace: a sentence when the session (or else the week) is on course to hit its limit before it resets; else null.
function usageView(data, now, locale, timeZone) {
  if (data?.state === 'signedOut') return { state: 'signin' };
  if (data?.state !== 'ok') return { state: 'hidden' };
  const limits = Array.isArray(data.limits) ? data.limits : [];
  const session = usageWindow(data.session, limits.find((l) => l.kind === 'session'), now);
  const week = usageWindow(data.week, limits.find((l) => l.kind === 'weekly_all'), now);
  const waiting = session.used >= 100 && session.left > 0 && !data.extraUsage;
  const pace = waiting ? null
    : paceNote(session, SESSION_WINDOW_MS, 'the session limit', now, locale, timeZone)
      || paceNote(week, WEEK_WINDOW_MS, 'the weekly limit', now, locale, timeZone);
  return { state: waiting ? 'wait' : 'ok', session, week, pace };
}

// One window: how much is used, its colour, and when it resets. Claude's own word for how worrying a bar is
// (severity) sets the colour, as Claude colours its own; without one, 75% is a warning and 100% the limit.
function usageWindow(win, limit, now) {
  const resetsAt = win?.resetsAt || limit?.resetsAt || 0;
  const over = resetsAt > 0 && resetsAt <= now;
  const used = over ? 0 : Math.max(0, Math.min(100, Math.round(win?.used ?? limit?.percent ?? 0)));
  const severity = over ? 'normal' : usageSeverity(limit?.severity, used);
  return { used, severity, colour: GAUGE[severity], resetsAt: over ? 0 : resetsAt, left: over ? 0 : resetsAt - now };
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

// The hours left next to Session in the one-line row: the nearest hour ("3h" for 2h 59m), in minutes under an hour.
function hoursLeft(ms) {
  if (!(ms > 0)) return '';
  const minutes = Math.ceil(ms / 60000);
  if (minutes < 60) return `${minutes}m`;
  return minutes >= 1440 ? `${Math.round(minutes / 1440)}d` : `${Math.round(minutes / 60)}h`;
}

// The clock time something happens, in the Mac's own way of writing times: "3:00 PM" today or within the next 12 hours
// (it can only be the next one), "Fri 9:00 AM" later this week, "Mar 3, 9:00 AM" further off. `locale` and `timeZone`
// are for tests; the page leaves them out.
function clockAt(at, now, locale, timeZone) {
  if (!(at > 0)) return '';
  const time = new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', timeZone }).format(at);
  const day = (t) => new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone })
    .format(t);
  if (day(at) === day(now) || (at > now && at - now < 12 * 3600 * 1000)) return time;
  const far = at - now >= 6 * 24 * 3600 * 1000;
  const date = new Intl.DateTimeFormat(locale, far ? { month: 'short', day: 'numeric', timeZone }
                                                   : { weekday: 'short', timeZone }).format(at);
  return `${date}${far ? ',' : ''} ${time}`;
}

// Whether a window is on course to hit its limit before it resets, going by how fast it has filled so far: "At this
// pace you'll hit the session limit around 4:40 PM." Not in its first ten minutes, when a single burst would read as a
// pace.
function paceNote(win, windowMs, name, now, locale, timeZone) {
  if (!(win.left > 0) || win.used >= 100 || win.used <= 0) return null;
  const elapsed = windowMs - win.left;
  if (elapsed < 10 * 60 * 1000) return null;
  const perMs = win.used / elapsed, hitAt = now + (100 - win.used) / perMs;
  if (hitAt >= win.resetsAt) return null;
  return `At this pace you'll hit ${name} around ${clockAt(hitAt, now, locale, timeZone)}.`;
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
