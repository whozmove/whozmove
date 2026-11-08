// Clean up's list, as plain functions (clean-view.js draws it): what's ticked as a list comes, and what what's ticked
// adds up to. Checked by modules/storage/tests/page-cases.js.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Every item of the list, as the app sends it (showCleanUp), group by group.
const cleanItems = (list) => (list?.groups || []).flatMap((group) => group.items || []);

// What's ticked once a list comes: what was ticked and is still there and can go; and in the first list, what's ticked
// to start with. `seen` holds the ids shown before, so what you unticked stays unticked, and what joins a list already
// shown (each project's built files, once the map is done) comes unticked, so what Clean Up cleans never grows under a
// press.
function cleanTicks(list, ticked, seen) {
  const next = new Set();
  for (const item of cleanItems(list)) {
    if (!item.lock && (seen.has(item.id) ? ticked.has(item.id) : !seen.size && item.on)) next.add(item.id);
  }
  return next;
}

// What can come back (all that can go), what's ticked of it, how many of the ticked go to the Trash, and the commands
// the others run.
function cleanSums(list, ticked) {
  const sums = { all: 0, ticked: 0, trash: 0, commands: [] };
  for (const item of cleanItems(list)) {
    if (item.lock) continue;
    sums.all += item.size || 0;
    if (!ticked.has(item.id)) continue;
    sums.ticked += item.size || 0;
    if (item.command) sums.commands.push(item.command);
    else sums.trash++;
  }
  return sums;
}

// A row's step while cleaning, as the app tells it (cleanProgress), or waiting before it comes: what shows where its size
// was, and for one that stayed, why and what to do, on its line.
const CLEAN_STEPS = { waiting: 'Waiting', moving: 'Moving to the Trash…', trashed: 'In the Trash',
                      running: 'Running its command…', done: 'Done', stayed: 'Stayed' };
function cleanStepWords(step) {
  const why = step.why ? String(step.why).replace(/\.$/, '') : '';
  const then = step.then ? ` ${String(step.then).replace(/\.$/, '')}.` : '';
  // "Stayed" is said where its size was: its line says only why, and what to do.
  return { word: CLEAN_STEPS[step.state] || CLEAN_STEPS.waiting,
           line: step.state === 'stayed' && why ? `${why}.${then}` : '' };
}

// The groups Clean up shows: the list as it is, or, while what went is shown, as it was when Clean Up was pressed
// (`order`), each item in its place, one that went as it was, one still there as it is now, and one that's gone
// otherwise left out, then what's new since in its group or after; a group with nothing left that went keeps its
// place, and one with nothing at all goes.
function cleanShownGroups(list, order, went) {
  if (!order || !Object.keys(went || {}).length) return list.groups;
  const now = new Map(cleanItems(list).map((item) => [item.id, item]));
  const was = new Set(cleanItems(order).map((item) => item.id));
  const groups = order.groups.map((group) => {
    const fresh = (list.groups.find((each) => each.id === group.id)?.items || []).filter((item) => !was.has(item.id));
    const items = group.items.map((item) => now.get(item.id) || (went[item.id] && went[item.id].item))
      .filter(Boolean).concat(fresh);
    return { ...(list.groups.find((each) => each.id === group.id) || group), items };
  });
  for (const group of list.groups)
    if (!order.groups.some((each) => each.id === group.id)) groups.push(group);
  return groups.filter((group) => group.items.length);
}

// While it cleans, how far it has got: "Cleaning up 8 things · 2 done, 1 stayed".
function cleanGoing(steps) {
  const all = Object.values(steps), stayed = all.filter((s) => s.state === 'stayed').length;
  const done = all.filter((s) => ['trashed', 'done'].includes(s.state)).length;
  const so = [done ? `${done} done` : '', stayed ? `${stayed} stayed` : ''].filter(Boolean).join(', ');
  return `Cleaning up ${all.length === 1 ? '1 thing' : `${all.length} things`}${so ? ` · ${so}` : ''}`;
}

// What cleaning did, in words: how many of what was ticked were cleaned up and how many stayed (each row says why);
// that what went to the Trash takes its space until the Trash is emptied, and how; and what the tools' own commands
// freed.
function cleanSaid(result, count) {
  const cleaned = (result.cleaned || []).length;
  const stayed = new Set((result.failed || []).map((f) => f.id ?? f.name)).size;
  if (!cleaned && !stayed) return 'Nothing was cleaned up.';
  const of = count ? `Cleaned up ${cleaned} of ${count}` : `Cleaned up ${cleaned}`;
  const head = `${of}${stayed ? ` · ${stayed} stayed` : ''}.`;
  const trash = result.trashed ? ` ${mapSize(result.trashed)} is in the Trash. Empty it with Finder ▸ Empty Trash to `
    + 'get the space back.' : '';
  const tools = result.freed > (result.trashed || 0) ? ` Your tools’ own commands freed `
    + `${mapSize(result.freed - (result.trashed || 0))}.` : '';
  return `${head}${trash}${tools}`;
}
