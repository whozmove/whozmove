// The notifications module's decider, plain functions checked by its page cases: what each place shows now and what
// waits. The line under the header gets the app's notices and the page senders', most urgent first; beside the
// folded panel, the notices naming a session come out as that session's chat, in the order they came; Whozmove
// beside the panel at its edge counts them; and where each place is in sight. At night (quiet hours) each says only
// what's urgent.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// How much each level needs you, most first, as the core has them (core.noticeLevels): something stops or waits without
// you; something to do when you can; nothing to do.
const NOTICE_RANK = Object.fromEntries(core.noticeLevels.map((level, i) => [level, i]));

// --- The line under the header ---

// The notices, ranked: the most urgent first; among equals, the one showing (`shown`, its id), then the one that came
// first (the app's in the order it sends them, then the page senders').
function noticesRanked(notices, shown) {
  const order = new Map(notices.map((n, i) => [n.id, i]));
  return [...notices]
    .sort((a, b) => NOTICE_RANK[a.level] - NOTICE_RANK[b.level] || (b.id === shown) - (a.id === shown)
      || order.get(a.id) - order.get(b.id));
}

// Whether something of this level may be said now: anything by day; at night (quiet hours), only what's urgent, the
// rest waiting for the morning. The line and the chats beside the folded panel both go by it.
const noticeMaySay = (level, night) => !night || level === 'urgent';

// What may be said on the line now (`view` as noticeLine has it): at night, what's urgent, what answers something you
// just did (`answersYou`), and the one showing as they began, so nothing goes from under you. The rest waits for the
// morning, and isn't counted till then.
function noticesSaid(notices, view) {
  return notices.filter((n) => noticeMaySay(n.level, view.night) || n.answersYou || n.id === view.shown);
}

// What the line shows, and how many more wait (its +N). `view` is { shown, front, frontWith, typing, night }: the id
// showing now; the one stepped to with +N, and the ids listed when it was, as it stays until it goes or something
// urgent that wasn't there comes; whether you're typing in the panel or have a card open, when only something urgent
// comes in, or the one you stepped to; and whether it's quiet hours.
// Returns { line, more, front, frontWith }, the line null when nothing shows.
function noticeLine(notices, view) {
  const ranked = noticesRanked(noticesSaid(notices, view), view.shown);
  let front = ranked.find((n) => n.id === view.front) || null;
  const frontWith = new Set(view.frontWith || []);
  if (front && ranked.some((n) => n.level === 'urgent' && !frontWith.has(n.id))) front = null;
  let line = front || ranked[0] || null;
  if (view.typing && line && line.id !== view.shown && line.level !== 'urgent' && line !== front)
    line = ranked.find((n) => n.id === view.shown) || null;
  return { line, more: ranked.length - (line ? 1 : 0), front: front?.id || null,
           frontWith: front ? [...frontWith] : [] };
}

// +N pressed: the next waiting after the one showing, urgent or not (at night, only what's urgent), in the order
// they're ranked, and after the last, back to the first. Returns the new { front, frontWith } for noticeLine.
function noticeNext(notices, view) {
  const ranked = noticesRanked(noticesSaid(notices, view), null);
  if (!ranked.length) return { front: null, frontWith: [] };
  const i = ranked.findIndex((n) => n.id === view.shown);
  return { front: ranked[(i + 1) % ranked.length].id, frontWith: ranked.map((n) => n.id) };
}

// A page sender's notice put away (`away`, as the app keeps it: what made it new then, or { since, at, awayFor }):
// whether it's away still at `now`, said as `since`.
function noticeAwayStill(away, since, now) {
  if (away && typeof away === 'object')
    return away.since === since && !(away.awayFor > 0 && now - away.at >= away.awayFor * 1000);
  return away === since;
}

// --- Where each place is in sight ---

// Each place says whether it would be seen now (`places`: { line, beside, edge }, from each one's inSight()), and the
// app whether the panel is (`shown`: not hidden from the menu bar; `parked`: flicked off the screen's edge). The line
// and the chats beside the folded panel are in sight only on the screen; the edge, only while the panel is away.
function noticeSight(places, { shown, parked }) {
  const there = shown && !parked;
  return { line: there && !!places.line, beside: there && !!places.beside, edge: !!parked && !!places.edge };
}

// --- Beside the folded panel ---

// What the place beside the folded panel shows is a notice naming a session, as that session's row (its `session`):
// each row here is one, { id, sid, news, level, line, at, on, evenSeen, outFor }, `news` its since (null for nothing
// new), `on` its sender saying you're looking at what it's about (seenNow), `evenSeen` that it comes out all the same
// (evenWhenSeen), and `outFor` how long it's out at most, in seconds. What's been seen is kept by its id (a case's row
// may leave it out: its session's id then).
const seenKey = (x) => x.id ?? x.sid;

// What of a notice has been seen is kept by where each word came from, the part of it before its ':', so one never
// takes the place of another ('side:40' beside 'reply:9'). Whether `news` is among what's been seen of its notice
// (`seen`, its words apart by spaces), and what's been seen with it, its source's word before it taken out.
const newsSource = (news) => news.slice(0, Math.max(0, news.indexOf(':')));
const newsSeen = (seen, news) => !!news && (seen || '').split(' ').includes(news);
const newsWithSeen = (seen, news) => [...(seen || '').split(' ')
  .filter((was) => was && newsSource(was) !== newsSource(news)), news].join(' ');

// How many of what needs you Whozmove beside the panel at its edge counts (`levels`, each one's level): all of it by
// day, at night only what's urgent, so a reply doesn't flick its ear then.
function edgeCount(levels, night) {
  return levels.filter((level) => noticeMaySay(level, night)).length;
}

// The chat you hold out beside the folded panel by being where it's about: one that was out when you went there from
// the panel (pressing it, or its row), until you leave or the chat goes. `was` is what held before ({ sid, at }, `sid`
// null for none), `opening` the last you went to from the panel ({ sid, at }, the latest of the rows' openedAt, or
// null), `out` what's out now, and `rows` as besideStep has them. Where you were already, nothing holds: what comes out
// even there mustn't keep every other one in. Returns the new { sid, at }.
function besideHold(was, opening, out, rows) {
  const isOut = (sid) => out.some((c) => c.sid === sid);
  if (opening && opening.at !== was?.at) return { sid: isOut(opening.sid) ? opening.sid : null, at: opening.at };
  if (was?.sid && !(isOut(was.sid) && rows.some((r) => r.sid === was.sid && r.on))) return { sid: null, at: was.at };
  return was || { sid: null, at: null };
}

// What's out beside the folded panel and what waits, once the rows have come in again. `chats` is as it was: { out: [{
// sid, id, news, left, outFor, kept, line, at, evenSeen }], queue: [{ sid, news, … }], done: { id: news }, seeded },
// `queue` those waiting, first first, and `done` holding what of each has been seen, so it doesn't come out again.
// `rows` are as above, in the place's order, newest first. A chat out carries its row's line and time while that's its
// news. `rule` says whether the rows have come yet since the page loaded, and what was seen before it (`loaded`),
// whether the panel is open (what it shows counts as seen), whether nothing may come out now (`quiet`), whether it's
// quiet hours (`night`, when only what's urgent comes out), whether you hold one of those out (`holding`), and how many
// may be out (`most`). They come out in the order they came, and wait in it. Returns the new { out, queue, done, seeded
// }, `queue` being those waiting in that order, and which sessions' chats came out and which went.
function besideStep(chats, rows, rule) {
  const done = { ...chats.done }, byId = new Map(rows.map((r) => [r.sid, r]));
  // Before the first rows have come, the page draws with none: nothing is decided, so what was waiting before a
  // restart is counted as there when the page loaded once the rows come, not as new.
  if (!rule.loaded) return { out: chats.out, queue: [], done, seeded: chats.seeded, came: [], went: [] };
  // Seen in the open panel, or there as the page loaded (the app restarted, or a new build put in place): nothing of
  // that comes out.
  if (rule.open || !chats.seeded) {
    for (const r of rows) if (r.news) done[seenKey(r)] = newsWithSeen(done[seenKey(r)], r.news);
    return { out: [], queue: [], done, seeded: true, came: [], went: chats.out.map((c) => c.sid) };
  }
  // One stays out while you're looking at what it's about, whatever it has to say now; otherwise it goes once it has
  // nothing new for you. Something newer in it keeps it out, its time starting again. One out even while you look
  // (evenSeen) goes once what it says changes there to something that isn't: what follows it is in front of you. What's
  // already been seen never keeps one out: a word out before, standing behind the one just gone, lets it go.
  const kept = [], went = [];
  for (const c of chats.out) {
    const r = byId.get(c.sid), key = seenKey(r || c);
    const answered = r && r.on && c.evenSeen && r.news !== c.news && !r.evenSeen;
    if (answered && r.news) done[key] = newsWithSeen(done[key], r.news);
    const news = r?.news && (r.news === c.news || !newsSeen(done[key], r.news)) ? r.news : null;
    // At night, what isn't urgent takes its place without starting its time again, so it isn't said anew.
    const again = news && noticeMaySay(r.level, rule.night);
    const now = news && news !== c.news
      ? { ...c, news, evenSeen: !!r.evenSeen, ...(again ? { outFor: r.outFor, left: r.outFor * 1000 } : {}) } : c;
    // Its line only while that's still its news: kept out by your looking alone, it's the row as it is.
    const said = r?.news === now.news ? { line: r.line, at: r.at } : { line: undefined, at: undefined };
    if (r && !answered && (r.on || news)) kept.push({ ...now, id: r.id, ...said });
    else went.push(c.sid);
  }
  // What's new where you're looking is seen there, but for one out even then; the rest waits.
  const outIds = new Set(kept.map((c) => c.sid)), waiting = [];
  for (const r of rows) {
    const key = seenKey(r);
    if (!r.news || outIds.has(r.sid) || newsSeen(done[key], r.news)) continue;
    if (r.on && !r.evenSeen) done[key] = newsWithSeen(done[key], r.news);
    // At night only what's urgent comes out; the rest isn't seen yet, so it comes out in the morning.
    else if (noticeMaySay(r.level, rule.night))
      waiting.push({ sid: r.sid, id: r.id, news: r.news, line: r.line, at: r.at, evenSeen: !!r.evenSeen,
                     outFor: r.outFor });
  }
  // One waiting keeps its place in the line; what's new joins its end, the oldest first, as the rows are newest first.
  const line = new Map((chats.queue || []).map((q, i) => [q.sid, i]));
  waiting.reverse().sort((a, b) => (line.get(a.sid) ?? line.size) - (line.get(b.sid) ?? line.size));
  if (rule.quiet || rule.holding) return { out: kept, queue: waiting, done, seeded: true, came: [], went };
  // Those out keep their places, so a new one never takes the place of one there, and the first waiting come out after
  // them while there's room; pinned ones stay out, and one that no longer fits goes back in to wait at the line's head.
  let room = rule.most - kept.filter((c) => c.kept).length;
  const out = [], back = [];
  for (const c of kept) (c.kept || room-- > 0 ? out : back).push(c);
  const came = waiting.splice(0, Math.max(0, room));
  out.push(...came.map((w) => ({ ...w, left: w.outFor * 1000, kept: false })));
  went.push(...back.map((c) => c.sid));
  return { out, queue: [...back.map(({ sid, news }) => ({ sid, news })), ...waiting], done, seeded: true,
           came: came.map((w) => w.sid), went };
}

// What to keep for a restart (the app's record): what of each has been seen, and what's out now, as seen, so after a
// restart only what's new comes out; what came while Whozmove was down is new, as what it says differs.
function besideKept(done, out) {
  const kept = { ...done };
  for (const c of out) if (c.news) kept[seenKey(c)] = newsWithSeen(kept[seenKey(c)], c.news);
  return kept;
}

// A chat sent back into the cat (its time ran out, or its × was pressed): what it said counts as seen.
function besideBack(chats, sid) {
  const c = chats.out.find((x) => x.sid === sid);
  if (!c) return chats;
  const key = seenKey(c);
  return { ...chats, out: chats.out.filter((x) => x !== c),
           done: { ...chats.done, [key]: newsWithSeen(chats.done[key], c.news) } };
}

// Of two notices naming one session (each a row, as besideStep has them, and when its since came, `aAt` and `bAt`),
// whether `a` is the one its chat says rather than `b`: the more urgent, then one with something new, then the one
// whose since came last; at that too, the first listed.
function besideOver(a, b, aAt, bAt) {
  return (NOTICE_RANK[a.level] - NOTICE_RANK[b.level] || !!b.news - !!a.news || bAt - aAt) < 0;
}

// The rows beside the folded panel, one for each session, from every notice naming one (`listed`, as besideNotices
// has them): in the place's own order (`sessions`, the ids it can show, each once, leaving out the rest), or the order
// they're listed while it gives none; of two for one session, as besideOver says (`sinceAt`, by id, when each was first
// said as it is; one not kept yet counts as said `now`).
function besideRows(listed, sessions, sinceAt, now) {
  const best = new Map(), came = (r) => (sinceAt[r.id]?.since === r.news ? sinceAt[r.id].at : now);
  for (const row of listed) {
    const other = best.get(row.sid);
    if (!other || besideOver(row, other, came(row), came(other))) best.set(row.sid, row);
  }
  const order = Array.isArray(sessions) ? [...new Set(sessions)] : [...best.keys()];
  return order.filter((sid) => best.has(sid)).map((sid) => best.get(sid));
}

// What's kept as notices naming a session are listed at `now` (`listed`, every one, whichever says its session's
// chat): when each was last listed and when its since came, and, forgotten a minute after it was last listed, what's
// been seen of it. `kept` is { done, listedAt, sinceAt, loadedAt }; returns the new { done, listedAt, sinceAt }.
function besideListed(kept, listed, now) {
  const listedAt = { ...kept.listedAt }, sinceAt = { ...kept.sinceAt };
  for (const { id, news } of listed) {
    listedAt[id] = now;
    if (!sinceAt[id] || sinceAt[id].since !== news) sinceAt[id] = { since: news, at: now };
  }
  const still = (record) => besideForgotten(record, listedAt, kept.loadedAt, now);
  return { done: still(kept.done), listedAt: still(listedAt), sinceAt: still(sinceAt) };
}

// What's been seen of a notice is forgotten a minute after it was last listed (`listedAt`, by id, as of `now`; one
// never listed since the page loaded counts from `loadedAt`), so the record keeps only what may come back.
const BESIDE_FORGET_MS = 60000;
function besideForgotten(done, listedAt, loadedAt, now) {
  return Object.fromEntries(Object.entries(done)
    .filter(([id]) => now - (listedAt[id] ?? loadedAt) <= BESIDE_FORGET_MS));
}
