// What the panel's back shows, from what the app sends (app/AppsModule.m): Settings' cards and pages, and the settings
// once one is pressed; what an app's permission says, its cards, its groups, the apps' switches and choices once one is
// pressed, and a tool's card. Plain functions, checked by modules/apps/tests/test.sh.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Where in System Settings ▸ Privacy & Security each permission is.
const PERMISSION_NAMES = { accessibility: 'Accessibility', automation: 'Automation',
                           fullDiskAccess: 'Full Disk Access' };

// What an app's page says of what macOS lets Whozmove do with it: the permission's name and what it's for, and how it
// stands (`state`): allowed; denied, offering System Settings, where it's changed; not asked about yet (Automation,
// which macOS asks about the first time); can't be told while the app isn't open (Automation again); or not checked
// yet, which says nothing. Null for an app with nothing to allow.
function permissionView(app) {
  const p = app.permission;
  if (!p || !PERMISSION_NAMES[p.kind]) return null;
  const state = ['allowed', 'denied', 'ask', 'closed'].includes(p.state) ? p.state : 'unknown';
  const said = { allowed: 'Allowed', denied: 'Not allowed', ask: 'Not asked yet', closed: `Open ${app.name} to check`,
                 unknown: '' }[state];
  // Denied, it says what to turn on in System Settings: Whozmove itself in Accessibility's list or Full Disk Access's,
  // or the app under Whozmove in Automation's. Full Disk Access's list can still leave Whozmove out, so it says how to
  // add it there.
  const turnOn = p.kind === 'automation' ? `Turn on ${app.name} under Whozmove there.`
    : p.kind === 'fullDiskAccess' ? 'Turn on Whozmove there. Not in the list? Press + under it and choose Whozmove.'
    : 'Turn on Whozmove there.';
  const note = state === 'ask' ? 'macOS asks the first time Whozmove needs it.' : state === 'denied' ? turnOn : '';
  return { name: PERMISSION_NAMES[p.kind], use: p.use || '', state, said, note, settings: state === 'denied' };
}

// What one of an app's cards shows (a module's AppStatus, as the app sends it): its heading, and over the card the
// heading of its part of the page where it has one; a word or two on how it stands, with a tick while all's well; a
// line under its heading; and its button, if it has one now, which waits while what a press set going is under way.
// Null for one with no heading.
function statusView(s) {
  if (!s || !s.key || !s.title) return null;
  return { key: String(s.key), title: String(s.title), section: s.section || null, said: s.said || '',
           note: s.note || '', ok: !!s.ok, button: s.button || null, waits: !!(s.button && s.busy) };
}

// An app's groups as its page draws them, from what the app sends: each its heading (marked Important, for one that
// matters more than most), its line, and its rows, each a
// switch, a choice of one among a few (its choices, each with its line and New where it's new, the one picked, and a
// row above them that can't be pressed, and what picking each would change, for one that says so first; or, drawn as
// one row, the picked one on a button opening the Mac's menu of them, `menu`), a part of the day (its two ends, as the
// app words them), or a row opening a page of its own (`page`: its title, what it's set to, and its page's groups, as
// the app sends them), with `off` while it can't be pressed now, its own say or its group's. A row of another kind, or
// with no key, is left out.
function groupsView(app) {
  return groupsFrom(app?.groups);
}
function groupsFrom(groups) {
  const words = (v) => (typeof v === 'string' ? v : '');
  return (Array.isArray(groups) ? groups : []).filter((g) => g && typeof g === 'object').map((g) => {
    const dimmed = g.enabled === false;
    const rows = (Array.isArray(g.rows) ? g.rows : []).filter((r) => r && typeof r.key === 'string' && r.key)
      .map((r) => {
        const off = dimmed || r.enabled === false;
        if (r.kind === 'switch') return { kind: 'switch', key: r.key, title: words(r.title), help: words(r.help),
                                          on: !!r.on, isNew: !!r.isNew, off };
        if (r.kind === 'choice') {
          const choices = (Array.isArray(r.choices) ? r.choices : []).filter((c) => c && typeof c.id === 'string')
            .map((c) => ({ id: c.id, name: words(c.name), help: words(c.help), isNew: !!c.isNew,
                           enabled: c.enabled !== false }));
          const fixed = r.fixed && words(r.fixed.name) ? { name: r.fixed.name, help: words(r.fixed.help) } : null;
          // What picking each would change, for those that say so before they're picked: lines only, kept to the
          // choices it has.
          const confirms = {};
          for (const c of choices) {
            const said = r.confirms?.[c.id];
            if (said && words(said.before) && words(said.after))
              confirms[c.id] = { before: said.before, after: said.after, warn: words(said.warn), keep: words(said.keep) };
          }
          return { kind: 'choice', key: r.key, title: words(r.title), choices, value: r.value ?? null, fixed, off,
                   confirms, menu: r.menu === true };
        }
        if (r.kind === 'page') return { kind: 'page', key: r.key, title: words(r.title), said: words(r.said),
                                        groups: Array.isArray(r.groups) ? r.groups : [], off };
        if (r.kind === 'time') return { kind: 'time', key: r.key, title: words(r.title), help: words(r.help),
                                        from: words(r.fromSaid), to: words(r.toSaid), off };
        return null;
      }).filter(Boolean);
    return { title: words(g.title), foot: words(g.foot), important: g.important === true, rows };
  });
}

// Every row in these groups (as groupsFrom has them), and on the pages their rows open, each page's row before its own.
const rowsIn = (groups) => groupsFrom(groups).flatMap((g) => g.rows.flatMap((r) => (r.kind === 'page'
  ? [r, ...rowsIn(r.groups).map((inner) => (r.off ? { ...inner, off: true } : inner))] : [r])));
// The row opening a page of its own, by its key, anywhere on an app's page, or null.
const pageRowOf = (app, key) => rowsIn(app?.groups).find((r) => r.kind === 'page' && r.key === key) || null;

// Every switch on an app's page: its own, then those in its groups, each with whether it can be pressed now.
const switchesOf = (app) => [...(app?.switches || []),
  ...groupsView(app).flatMap((g) => g.rows.filter((r) => r.kind === 'switch')
    .map((r) => ({ key: r.key, on: r.on, enabled: !r.off })))];

// The apps after one of their switches is pressed, one of an app's own or in one of its groups: it turns on or off;
// one in a group of switches (the terminal new conversations open in) turns the others in that group off, in any app,
// and pressed while it's on, it stays. Null when the press changes nothing: a switch that isn't there, can't be pressed
// now, or stays.
function afterPress(apps, appId, key) {
  const pressed = switchesOf(apps.find((a) => a.id === appId)).find((s) => s.key === key);
  if (!pressed || pressed.enabled === false || (pressed.group && pressed.on)) return null;
  const flip = (s) => s.key === key ? { ...s, on: !s.on } : s;
  return apps.map((a) => ({
    ...a,
    switches: a.switches.map((s) => a.id === appId && s.key === key ? { ...s, on: !s.on }
      : pressed.group && s.group === pressed.group ? { ...s, on: false } : s),
    ...(a.id === appId && Array.isArray(a.groups)
      ? { groups: a.groups.map((g) => ({ ...g, rows: (g.rows || []).map((r) => r?.kind === 'switch' ? flip(r) : r) })) }
      : {}),
  }));
}

// The apps after one of an app's choices is picked: that one ticked. Null when the press changes nothing: a choice
// that isn't there, can't be pressed now (its group dimmed), one that isn't among its choices or can't be picked, or
// the one already picked.
function afterChoice(apps, appId, key, value) {
  const app = apps.find((a) => a.id === appId);
  const row = rowsIn(app?.groups).find((r) => r.kind === 'choice' && r.key === key);
  const choice = row?.choices.find((c) => c.id === value);
  if (!row || row.off || !choice || !choice.enabled || row.value === value) return null;
  // Ticked wherever it is: in the app's own groups, or on a page one of their rows opens.
  const ticked = (groups) => groups.map((g) => ({ ...g, rows: (g.rows || []).map((r) => (r?.kind === 'choice'
    && r.key === key ? { ...r, value } : r?.kind === 'page' && Array.isArray(r.groups) ? { ...r, groups: ticked(r.groups) }
    : r)) }));
  return apps.map((a) => a !== app ? a : { ...a, groups: ticked(a.groups) });
}

// What a tool's card shows (Storage's free space), from what its module sends: its figure, what it's out of, how full
// its bar is (0 to 1, or null for no bar), its tone (low or severe, else none), its lines, its buttons, each with what
// its module calls it, its title, and whether it's the main one, and what it can't do now without its permission
// (`need`, said with a button that allows it). Null with no figure.
function cardView(card) {
  if (!card || typeof card.figure !== 'string' || !card.figure) return null;
  const bar = typeof card.bar === 'number' && isFinite(card.bar) ? Math.min(1, Math.max(0, card.bar)) : null;
  const actions = (Array.isArray(card.actions) ? card.actions : [])
    .filter((a) => a && typeof a.id === 'string' && a.id && typeof a.title === 'string' && a.title)
    .map((a) => ({ id: a.id, title: a.title, main: !!a.main }));
  return { figure: card.figure, of: typeof card.of === 'string' ? card.of : '', bar,
           tone: ['low', 'severe'].includes(card.tone) ? card.tone : '',
           lines: Array.isArray(card.lines) ? card.lines.filter((line) => typeof line === 'string' && line) : [],
           actions, need: typeof card.need === 'string' ? card.need : '' };
}

// The letter drawn on the tile of an app with no icon of its own.
const initialOf = (name) => (String(name || '').trim()[0] || '?').toUpperCase();

// ---- Settings ----

// The page a setting shows on: a choice's own (named by its title), or the one it shares with others (`page`); a switch
// has none, as it's pressed on its row.
const settingPageOf = (entry) => entry.kind === 'choice' ? entry.page || entry.title : null;

// What a choice's row says is picked: its name, "None found" with nothing to pick from, or "Not chosen yet" until one
// is (the editor, which the changes view asks for the first time). Nothing for a switch.
function settingValue(entry) {
  if (entry.kind !== 'choice') return '';
  const choices = entry.choices || [];
  if (!choices.length) return 'None found';
  return choices.find((c) => c.id === entry.value)?.name || 'Not chosen yet';
}

// Settings' cards, in their order (`group`), each its rows in theirs: a switch is a row of its own, the choices on
// one page are one row, named by the page, its mark the first one's, saying what's picked on each (" · " between), and
// a row opening an app's page says what it says there. Under a card, the lines its switches have (a choice's line is on
// its page).
function settingsCards(settings) {
  const cards = [];
  for (const entry of settings || []) {
    let card = cards.find((c) => c.group === entry.group);
    if (!card) cards.push(card = { group: entry.group, rows: [], foot: [] });
    const page = settingPageOf(entry);
    const row = page && card.rows.find((r) => r.page === page);
    if (entry.kind === 'page') {
      if (typeof entry.app === 'string' && entry.app)
        card.rows.push({ app: entry.app, title: entry.title, value: typeof entry.said === 'string' ? entry.said : '' });
    } else if (row) row.value += ` · ${settingValue(entry)}`;
    else if (page) card.rows.push({ page, title: page, glyph: entry.glyph, value: settingValue(entry) });
    else {
      card.rows.push({ key: entry.key, title: entry.title, glyph: entry.glyph, on: !!entry.on });
      if (entry.foot) card.foot.push(entry.foot);
    }
  }
  return cards.sort((a, b) => a.group - b.group);
}

// The choices on one of Settings' pages, in their order.
const settingsPage = (settings, page) => (settings || []).filter((e) => settingPageOf(e) === page);

// Settings once one is pressed: a switch turned on or off, or a choice picked. Null when the press changes nothing: a
// setting that isn't there, a choice that isn't one of its choices or can't be picked now, or the one already picked.
function afterSetting(settings, key, value) {
  const entry = (settings || []).find((e) => e.key === key);
  if (!entry) return null;
  if (entry.kind === 'switch') {
    if (typeof value !== 'boolean' || value === !!entry.on) return null;
    return settings.map((e) => e === entry ? { ...e, on: value } : e);
  }
  const choice = (entry.choices || []).find((c) => c.id === value);
  if (!choice || choice.enabled === false || entry.value === value) return null;
  return settings.map((e) => e === entry ? { ...e, value } : e);
}

// ---- An app's lists (Sessions, on each terminal's page and Claude's) ----

// How long a question's buttons, and the Undo under what a press did, wait before they take a press, as the panel's do
// (its FRESH_MS): a press can't land on what has only just grown under the pointer. And how long what a press did stays
// said, held while the pointer is on it, and a moment more once it leaves.
const LIST_FRESH_MS = 800;
const LIST_SAID_MS = 8000;
const LIST_HELD_MS = 3000;

// The list `key` on the app `appId`'s page, as the app sends it, or null.
const listOf = (apps, appId, key) =>
  (apps || []).find((a) => a.id === appId)?.lists?.find((l) => l.key === key) || null;

// Every item, with whether it can be ticked now: in a section that's ticked, and with no reason it can't (`why`).
function listItems(list) {
  const items = [];
  for (const section of list?.sections || [])
    for (const item of section.items || []) items.push({ ...item, tickable: !!section.tickable && !item.why });
  return items;
}

// What's ticked that still can be, in the list's order; and those that can't any more (it started working, say), each
// {id, title, why, way}, to say why it was left out.
function listTicks(list, ticked) {
  const items = listItems(list), stays = [], leftOut = [];
  for (const item of items) {
    if (!ticked.has(item.id)) continue;
    if (item.tickable) stays.push(item.id);
    else if (item.why) leftOut.push({ id: item.id, title: item.title, why: item.why, way: item.way || null });
  }
  return { ticked: stays, leftOut };
}

// The tray's button for every item with a mark (Tick All Ended): its title, with how many, and the ids it ticks; once
// they're all ticked, its other title, to untick them. Null when no item that can be ticked has the mark.
function listPick(list, ticked) {
  const pick = list?.tray?.pick;
  if (!pick) return null;
  const ids = listItems(list).filter((i) => i.tickable && (i.marks || []).includes(pick.mark)).map((i) => i.id);
  if (!ids.length) return null;
  const all = ids.every((id) => ticked.has(id));
  return { title: all ? pick.untitle : pick.title.replace('{n}', ids.length), ids, all };
}

// The question the tray's button asks first, for the ticked ids: its title, and its words, a note for each mark the
// ticked ones have (how many are still open, how many have replies you haven't read), said for one alone, one of
// several, or many.
function listAsk(list, ids) {
  const ask = list?.tray?.ask;
  if (!ask || !ids.length) return null;
  const items = listItems(list).filter((i) => ids.includes(i.id)), alone = items.length === 1;
  const title = alone ? ask.one.replace('{name}', items[0].title) : ask.many.replace('{n}', items.length);
  const words = [alone ? ask.lead?.one : ask.lead?.many];
  for (const note of ask.notes || []) {
    const n = items.filter((i) => (i.marks || []).includes(note.mark)).length;
    if (n) words.push(alone ? note.alone : n === 1 ? note.one : note.many.replace('{n}', n));
  }
  if (ask.last) words.push(ask.last);
  return { title, words: words.filter(Boolean).join(' ') };
}

// Whether what the last press did is still said: for a while after it's done, and while the pointer has held it, but
// never once something's been ticked or asked since (`dropped`, the time of the one said then).
const listSaidShows = (said, heldUntil, now, dropped = 0) => !!said && said.at !== dropped
  && (now - said.at < LIST_SAID_MS || now < heldUntil);
