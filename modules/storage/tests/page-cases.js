// Storage's page, run outside the app by modules/storage/tests/test.sh: the line under the header (disk-line.js), the
// map's plain functions (map.js: sizes, the rings, finding a part, what's collected) and Clean up's (clean.js). Nothing
// is drawn on a page.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the panel page's scripts and the helpers below use

section('The line above the list');
const disk = (fields) => ({ show: true, tone: 'low', head: '18 GB left · full in about 6 days',
                            sub: 'Know your storage', ...fields });
show('low', diskLineHTML(disk()));
show('nearly out', diskLineHTML(disk({ tone: 'severe', head: '3.2 GB left on your Mac',
                                       sub: 'Builds and sessions may fail' })));
show('not showing', diskLineHTML(disk({ show: false })));
show('nothing said yet', diskLineHTML(null));
show('words escaped', diskLineHTML(disk({ head: '<b>18 GB</b> left', sub: 'A & B' })));
show('the map ready, while it’s closed', storageLineHTML(disk(), { on: true, ready: true }, false));
show('the map ready, while it’s open: the disk’s line', storageLineHTML(disk(), { on: true, ready: true }, true));
show('the map ready, with room to spare', storageLineHTML(disk({ show: false }), { on: true, ready: true }, false));
show('nothing ready', storageLineHTML(disk({ show: false }), { on: true, ready: false }, false));

section('Sizes, as Finder says them');
show('sizes', [0, 999, 1000, 450000, 999999, 1000000, 994999999, 995000000, 4400000000, 9949999999, 9950000000,
               18400000000, 460000000000].map(mapSize));

section('The rings');
const part = (id, size, fields) => ({ id, name: `part ${id}`, size, folder: true, ...fields });
const sampleView = { id: 0, name: 'Disk', size: 1000, path: [{ id: 0, name: 'Disk' }], kids: [
  part(1, 600, { kids: [part(11, 300, { kids: [part(111, 200)] }), part(12, 200), { id: null, name: '3 small items',
                                                                                     size: 100, rest: true }] }),
  part(2, 250, { kids: [part(21, 250)] }),
  part(3, 100, { grey: true }),
  part(4, 2),  // too thin to draw
  part(5, 0, { unread: true, grey: true }),
  { id: null, name: '9 small items', size: 48, rest: true },
] };
const arcs = mapArcs(sampleView);
show('pieces', arcs.map((a) => `${a.part.name} ring ${a.depth} from ${a.a0.toFixed(3)} to ${a.a1.toFixed(3)}, `
  + mapTint(a)));
show('a piece of the first ring', mapArcPath(0, Math.PI / 2, ...mapRadii(1)));
show('a whole ring', mapArcPath(0, Math.PI * 2, ...mapRadii(2)));
show('nothing measured', mapArcs(null));
// A piece growing into the middle as its folder opens (mapGrowPath): the piece itself at the start, a wider piece of a
// ring closing in on the middle halfway, the middle at the end; and a piece further out, from its own ring.
const growing = { a0: Math.PI / 4, a1: Math.PI / 2, depth: 1 };
show('growing, at the start: the piece itself', mapGrowPath(growing, 0) === mapArcPath(Math.PI / 4, Math.PI / 2,
                                                                                        ...mapRadii(1)));
show('growing, halfway', mapGrowPath(growing, 0.5));
show('growing, nearly round', mapGrowPath(growing, 0.95));
show('growing from a piece nearly all the way round: a ring, its hole closing', mapGrowPath({ a0: 0, a1: Math.PI * 2
  - 0.05, depth: 1 }, 0.9));
show('growing, at the end: the middle', mapGrowPath(growing, 1));
show('growing from the second ring, at the start', mapGrowPath({ ...growing, depth: 2 }, 0) === mapArcPath(
  Math.PI / 4, Math.PI / 2, ...mapRadii(2)));
// A step in or out (mapStep): which way, and from which ring the piece that moves is.
{
  const folder = (id, size, kids = []) => ({ id, name: `f${id}`, size, folder: true, kids });
  const deep = folder(4, 2), inner = folder(3, 6, [deep]), side = folder(5, 4), top = folder(2, 10, [inner, side]);
  const view = (f) => ({ id: f.id, name: f.name, size: f.size, kids: f.kids });
  const step = (was, now) => { const s = mapStep(was && view(was), view(now)); return s ? `${s.down ? 'in' : 'out'}, `
    + `ring ${s.arc.depth}` : 'no step'; };
  const disk = folder(1, 20, [top, folder(6, 10)]);
  show('a step: one in', step(disk, top));
  show('a step: two in, a piece on the second ring', step(disk, inner));
  show('a step: one out', step(top, disk));
  show('a step: two out, a crumb above the one above', step(inner, disk));
  show('a step: the same folder again', step(top, top));
  show('a step: across to another branch', step(inner, side));
  show('a step: nothing shown before', step(null, disk));
}

section('Finding what was pressed');
const parts = [{ id: 1, name: 'a file' }, { id: 2, name: 'a folder', kids: [{ id: 3, name: 'a file in it' },
               { id: 4, name: 'a folder in it', kids: [] }] }, { id: null, name: '3 small items', rest: true }];
show('a file after a file', mapFind(parts, 3)?.name);
show('a folder', mapFind(parts, 2)?.name);
show('a folder further in', mapFind(parts, 4)?.name);
show('a part that isn’t there', mapFind(parts, 9));
show('nothing shown yet', mapFind(undefined, 1));
show('the way to a folder', mapTrail(parts, 2)?.map((p) => p.name));
show('the way to a folder further in', mapTrail(parts, 4)?.map((p) => p.name));
show('the way to a part that isn’t there', mapTrail(parts, 9));

section('Collecting for the Trash');
// Parts by id, a digit for each level: 1 is in the disk (0), 11 and 12 are in 1, 111 and 112 in 11, 1111 in 111.
const item = (id) => ({ id, name: `part ${id}`, size: 10 });
const at = (id) => [0, ...[...String(id)].slice(0, -1).map((_, i) => Number(String(id).slice(0, i + 1)))];
const press = (tray, id) => mapToggle(tray, item(id), at(id));
const says = (tray) => tray.map((t) => `${t.id}${t.out.length ? ` but ${t.out.map((o) => o.id).join(', ')}` : ''}`
  + ` (${mapFrees(t)})`);
let tray = press([], 11);
show('one', says(tray));
tray = press(tray, 12);
show('another beside it', says(tray));
show('the same again: put back', says(press(tray, 11)));
show('the folder they’re in: it takes them in', says(press(tray, 1)));
let big = [{ ...item(11), size: 30, within: [0, 1], out: [] }];
show('a folder collected whole: what’s in it shows as collected', [111, 112, 1111].map((id) =>
  !!mapHolder(big, id, at(id))));
big = press(big, 111);
show('one of its parts pressed: taken out, the folder keeps the rest', says(big));
show('… and what’s in that part isn’t collected now', [111, 1111, 112].map((id) => !!mapHolder(big, id, at(id))));
show('something in the part taken out, pressed: collected on its own', says(press(big, 1111)));
show('the part taken out, pressed again: back in the folder', says(press(press(big, 1111), 111)));
show('the folder, pressed: put back, and what was taken out of it with it', says(press(big, 11)));
let deep = press([{ ...item(11), size: 30, within: [0, 1], out: [] }], 1111);
show('a part further in taken out', says(deep));
show('then the part holding it: that one taken out, not both', says(press(deep, 111)));

section('Clean up');
const cleanSample = { groups: [
  { id: 'built', items: [{ id: 'built:3', size: 5e9, on: true }, { id: 'built:4', size: 2e9, on: false },
                         { id: 'built:5', size: 1e9, on: true, lock: { says: 'Claude Code is working in busy now' } }] },
  { id: 'tools', items: [{ id: 'brew', size: 3e9, on: true, command: 'brew cleanup --prune=all' },
                         { id: 'docker', size: 0, on: false, command: 'docker image prune -a -f',
                           lock: { says: 'Docker isn’t running: open it to see what it can free' } }] },
] };
const idsOf = (set) => [...set].sort();
let startTicks = cleanTicks(cleanSample, new Set(), new Set());
show('ticked to start with: what can go and says so', idsOf(startTicks));
show('what it adds up to', cleanSums(cleanSample, startTicks));
const seenBefore = new Set(cleanItems(cleanSample).map((item) => item.id));
show('a new list: what you unticked stays unticked, what you ticked stays ticked',
     idsOf(cleanTicks(cleanSample, new Set(['built:4']), seenBefore)));
const cleanMore = { groups: [...cleanSample.groups, { id: 'models', items: [{ id: 'folder:9', size: 4e9, on: false },
                                                                { id: 'folder:10', size: 1e9, on: true }] }] };
show('…and what joins a list already shown comes unticked, ticked or not as it says',
     idsOf(cleanTicks(cleanMore, startTicks, seenBefore)));
show('the first list: what’s new comes ticked as it says', idsOf(cleanTicks(cleanMore, new Set(), new Set())));
show('something that can’t go now: unticked', idsOf(cleanTicks(cleanSample, new Set(['built:5']), seenBefore)));
show('what it did: some in the Trash, a tool’s command, one stayed', cleanSaid({ freed: 8e9, trashed: 5e9,
  cleaned: ['npm’s cache', 'Homebrew’s old downloads'], failed: [{ id: 'docker', name: 'Docker’s images',
  why: 'It stopped with an error.' }] }, 3));
show('what it did: two parts of one item stayed, counted once', cleanSaid({ freed: 2e9, trashed: 2e9,
  cleaned: ['Built files'], failed: [{ id: 'built:a', name: 'cache', why: 'x' }, { id: 'built:a', name: 'tmp',
  why: 'y' }] }, 1));
show('what it did: a tool’s command only', cleanSaid({ freed: 3e9, trashed: 0, cleaned: ['Homebrew'], failed: [] },
                                                     1));
show('what it did: nothing', cleanSaid({ freed: 0, trashed: 0, cleaned: [], failed: [] }, 0));
show('each step’s words', ['waiting', 'moving', 'trashed', 'running', 'done'].map((state) => cleanStepWords({ state })
  .word));
show('one that stayed: why, and what to do', cleanStepWords({ state: 'stayed', why: 'Claude Code is working in busy now',
                                                            then: 'Clean Up again once it’s done' }));
show('one that stayed, its why saying what to do already', cleanStepWords({ state: 'stayed',
  why: 'The map was measured again since: look at the list again' }));
show('how far it has got', [cleanGoing({ a: { state: 'waiting' }, b: { state: 'moving' } }),
  cleanGoing({ a: { state: 'trashed' }, b: { state: 'stayed' }, c: { state: 'running' } })]);

section('Clean up as it shows: first, ready at once, and its foot');
const usualList = { usual: true, tools: false, groups: [{ id: 'caches', title: 'Your tools’ caches',
  says: 'Downloaded again when they’re needed', items: [{ id: 'folder:/u/.npm', name: 'npm’s cache', where: '~/.npm',
                                                          size: 2.1e10, on: true }] }] };
state.cleanUp = null;
show('before the usual places are measured: looking, and Clean Up there but off', [cleanBodyHTML(), cleanFootHTML()]);
state.cleanUp = usualList;
cleanPage.ticked = cleanTicks(usualList, new Set(), new Set());
cleanPage.seen = new Set(cleanItems(usualList).map((item) => item.id));
show('the usual places, the map still measured: projects’ built files said to come, and Clean Up with its amount',
     [cleanBodyHTML(), cleanFootHTML()]);
cleanPage.turnedOn = true;
show('opened by the press that turned Storage on: it says so, with Turn Off', cleanOnHTML());
cleanPage.turnedOn = false;
state.cleanUp = { usual: true, tools: false, groups: [] };
show('nothing in the usual places: the map, for the rest, and never Clean Up 0 GB',
     [cleanBodyHTML(), cleanFootHTML()]);
const withProjects = { usual: false, tools: false, groups: [...usualList.groups, { id: 'projects',
  title: 'Your projects’ built files', says: 'Built again the next time you build', items: [{ id: 'built:/u/code/app',
  name: 'node_modules', where: 'app · not changed in over a year', size: 8e9, on: true }] }] };
state.cleanUp = withProjects;
cleanPage.ticked = cleanTicks(withProjects, cleanPage.ticked, cleanPage.seen);
show('projects’ built files join at the foot, unticked: Clean Up keeps its amount', [idsOf(cleanPage.ticked),
                                                                                    cleanFootHTML()]);
Object.assign(cleanPage, { ticked: new Set(), said: 'Cleaned up 21 GB.', allWent: true, hadProjects: false });
show('cleaned before they came: the foot says how much they add', cleanFootHTML());
Object.assign(cleanPage, { said: null, allWent: false, seen: new Set() });
state.cleanUp = null;
state.cleanUp = usualList;
Object.assign(cleanPage, { cleaning: true, steps: { 'folder:/u/.npm': { id: 'folder:/u/.npm', state: 'moving' } } });
show('while it cleans: the row says its step, has no tick to press, and the foot how far it has got',
     [cleanRowHTML(usualList.groups[0].items[0]), cleanFootHTML()]);
window.cleanProgress({ id: 'folder:/u/.npm', state: 'stayed', why: 'npm is using it', then: 'Quit npm, then Clean Up '
  + 'again' });
show('one that stayed says why and what to do, in place of where it is', cleanRowHTML(usualList.groups[0].items[0]));
Object.assign(cleanPage, { cleaning: false, steps: {} });
window.cleanProgress({ id: 'folder:/u/.npm', state: 'trashed' });
show('a step told once cleaning is over: nothing', cleanPage.steps);
// What went stays on the list, each where it was when Clean Up was pressed, a group that all went too, with no box,
// until the disk is measured again (or Storage closes). Made-up items.
const two = { usual: false, tools: false, scannedAt: 5, groups: [
  { id: 'caches', title: 'Your tools’ caches', says: 'Downloaded again', items: [
    { id: 'a', name: 'npm’s cache', where: '~/.npm', size: 3e9, on: true },
    { id: 'b', name: 'Yarn’s cache', where: '~/Library/Caches/Yarn', size: 2e9, on: true },
    { id: 'c', name: 'Support files', where: '~/Library/Developer', size: 1e9, on: true }] },
  { id: 'xcode', title: 'Xcode', says: 'Built again', items: [
    { id: 'd', name: 'Xcode’s built files', where: '~/Library/Developer/Xcode/DerivedData', size: 9e9, on: true },
    { id: 'e', name: 'playground', where: '~/code/playground', size: 1e9, on: false }] }] };
const rowsOf = () => [...cleanBodyHTML().matchAll(/<b class="caps">([^<]*)<\/b>|<b>([^<]*)<\/b>(?:<i>[^<]*<\/i>)?<\/span><span class="clean-size">([^<]*)/g)]
  .map((m) => m[1] ? `[${m[1]}]` : `${m[2]}: ${m[3]}`);
state.cleanUp = two;
cleanPage.ticked = new Set(['a', 'b', 'c', 'd']);
Object.assign(cleanPage, { cleaning: true, order: two, went: {}, steps: { a: { id: 'a', state: 'moving' },
  b: { id: 'b', state: 'waiting' }, c: { id: 'c', state: 'running' }, d: { id: 'd', state: 'waiting' } } });
show('while it cleans: those cleaned keep their tick with nothing to press, the rest rest, and a step that’s going shines',
     cleanBodyHTML().match(/<div class="clean-row[^>]*>|<span class="clean-size">(<span class="shining">)?[^<]*/g));
const storageWas = state.storage;
state.storage = { on: true, scannedAt: 1 };
show('…and Measure Again waits', mapMeasuredHTML().match(/<button[^>]*>/g));
cleanPage.cleaning = false;
show('…and once it’s done, it can be pressed', mapMeasuredHTML().match(/<button[^>]*>/g));
cleanPage.cleaning = true;
state.storage = storageWas;
Object.assign(cleanPage.steps, { a: { id: 'a', state: 'trashed' }, b: { id: 'b', state: 'stayed', why: 'Yarn is using it' },
  c: { id: 'c', state: 'trashed' }, d: { id: 'd', state: 'trashed' } });
show('how far it has got, one stayed: said apart from what’s done', cleanGoing(cleanPage.steps));
show('one that stayed: “Stayed” where its size was, its line only why and what to do', cleanStepWords(cleanPage.steps.b));
cleanPage.cleaning = false;
window.showCleanUp({ ...two, groups: [{ ...two.groups[0], items: [two.groups[0].items[1]] },
                                      { ...two.groups[1], items: [two.groups[1].items[1]] }] });
show('after: each row where it was, what went saying so', rowsOf());
show('…with no box to see on what went, its room kept', cleanBodyHTML().match(/<div class="clean-row[^>]*><span class="tickbox[^"]*"/g));
Object.assign(cleanPage, { cleaning: true, order: two, went: {}, steps: { a: { id: 'a', state: 'trashed' },
  b: { id: 'b', state: 'trashed' }, c: { id: 'c', state: 'trashed' } } });
state.cleanUp = two;
cleanPage.cleaning = false;
window.showCleanUp({ ...two, groups: [two.groups[1]] });
show('a group that all went keeps its place and every row', rowsOf());
window.showCleanUp({ ...two, groups: [two.groups[1]], scannedAt: 99 });
show('…until the disk is measured again', [Object.keys(cleanPage.went), cleanPage.order]);
Object.assign(cleanPage, { steps: {}, went: {}, order: null, cleaning: false, ticked: new Set() });
show('what was done, in the Trash: Finder named once', cleanSaid({ cleaned: ['npm’s cache'], trashed: 2e9, freed: 2e9 }, 1));
state.cleanUp = usualList;
state.cleanUp = usualList;
cleanPage.ticked = new Set();
state.storage = { ...(state.storage || {}), scanning: true };
show('Clean up’s count while the disk is still measured: so far', mapTabsHTML().match(/<span class="map-tab-count">[^<]*/)[0]);
state.storage = { ...state.storage, scanning: false };
show('…and once it’s measured', mapTabsHTML().match(/<span class="map-tab-count">[^<]*/)[0]);
state.cleanUp = null;
show('the tabs: Clean up first', mapTabsHTML().match(/data-map-view="\w+"/g));
mapPage.view = 'keys';
show('on Keys, the head’s × is the kit’s icon button, as on the other tabs', mapHeadHTML().match(/<button[^>]*>/g));
mapPage.view = 'clean';
show('how far a measure has got, against what’s in use', [mapProgress(1.42e11, { total: 4.94e11, free: 1.8e10 }),
  mapProgress(8.2e8, { total: 4.94e11, free: 1.8e10 }), mapProgress(1.42e11, null)]);

section('The map’s rows: ＋ only where something can go, and the one way to allow Full Disk Access');
// A part that can go, one an agent keeps, the small items, and Desktop, unread for want of Full Disk Access. Made up.
const rowsView = { id: 2, name: 'home', size: 60, path: [{ id: 0, name: 'disk' }, { id: 2, name: 'home' }], kids: [
  { id: 21, name: 'code', size: 30, folder: true, kids: [] },
  { id: 22, name: 'busy', size: 20, folder: true, kids: [], lock: { kind: 'agent', says: 'Claude Code is working in busy now' } },
  { id: null, name: '4 small items', size: 10, rest: true },
  { id: 23, name: 'Desktop', size: 0, folder: true, unread: true, grey: true, allow: true,
    lock: { kind: 'unread', says: 'Allow Full Disk Access to look inside' } }] };
const rowEnds = () => [...mapListHTML(rowsView).matchAll(/<div class="map-item((?: [a-z]+)*)".*?<b>([^<]*)<\/b>(?:<small>([^<]*)<\/small>)?(<button[^>]*>[^<]*<\/button>)?<\/span>.*?(<button class="icon-button map-add[^>]*>)/g)]
  .map((m) => `${m[2]}${m[1]}: ${m[3] || '—'} · ${m[4] || 'no Allow'} · ${m[5]}`);
show('a ＋ only on what can go, the kit’s ＋ hidden on the rest, Allow Access under the unread row’s reason', rowEnds());
mapPage.allowAsked = true;
show('once Allow Access is pressed, the row says what to do in System Settings, listed or not', rowEnds()[3]);
mapPage.allowAsked = false;

section('The rings, collected further out');
// A folder collected whole, 11, holds 111 and 112; 111 holds 1111. Pieces further out are checked against the folders
// between them and the middle.
const ringView = { id: 1, name: 'one', size: 40, path: [{ id: 0, name: 'disk' }, { id: 1, name: 'one' }], kids: [
  { id: 11, name: 'a', size: 30, folder: true, kids: [
    { id: 111, name: 'b', size: 20, folder: true, kids: [{ id: 1111, name: 'c', size: 20 }] },
    { id: 112, name: 'd', size: 10 }] },
  { id: 12, name: 'e', size: 10 }] };
const ringIn = (tray) => mapArcs(ringView).map((arc) => `${arc.part.id}${mapHolder(tray, arc.part.id,
  [0, 1, ...arc.within]) ? ' collected' : ''}`);
const whole = [{ id: 11, name: 'a', size: 30, within: [0, 1], out: [] }];
show('a folder collected whole: everything in it, all the way out', ringIn(whole));
show('with a part taken back out: that part, and what’s in it, aren’t', ringIn(mapToggle(whole, { id: 111, name: 'b',
  size: 20 }, [0, 1, 11])));

section('Keys: how soon each needs you, what counts, and the line above the list');
const keysFound = (fields) => ({ lookedAt: 0, closed: [], keys: [
  { id: 'a', group: 'commit', left: false, name: 'Anthropic', masked: 'sk-ant-…fcAA' },
  { id: 'b', group: 'files', name: 'npm', masked: 'npm_…j37H' },
  { id: 'c', group: 'pushed', left: true, name: 'GitHub', masked: 'ghp_…oL8g' },
  { id: 'd', group: 'pushed', left: true, sample: true, name: 'Generic api key', masked: '…3f9c' }], ...fields });
show('each key’s band, by its group in a look from before the app said', keysFound().keys.map((key) =>
  `${key.id}: ${keysBand(key)}`));
show('the app’s band comes first: an ended token on GitHub is soon', keysBand({ group: 'pushed', band: 'soon' }));
show('what counts: all but the sample', keysCounted(keysFound()).map((key) => key.id));
show('keys found: the line speaks only of those that left or are about to', keysLineWords(keysFound()));
show('one that left', keysLineWords(keysFound({ keys: [keysFound().keys[2]] })));
show('one about to leave', keysLineWords(keysFound({ keys: [keysFound().keys[0]] })));
show('only on this Mac: nothing on the line', keysLineWords(keysFound({ keys: [keysFound().keys[1]] })));
show('only a sample on GitHub: nothing on the line', keysLineWords(keysFound({ keys: [keysFound().keys[3]] })));
show('put away for all of them: nothing to say', keysLineWords(keysFound({ closed: ['a', 'c'] })));
show('put away, then another found: it says them all', keysLineWords(keysFound({ closed: ['a'] })));
show('its × puts away only the keys it spoke for, not the one only on this Mac', keysLineWords(keysFound()).ids);
show('none found', keysLineWords(keysFound({ keys: [] })));
show('it couldn’t look: nothing on the line', keysLineWords(keysFound({ stopped: 'No Betterleaks' })));
show('nothing told yet', keysLineWords(null));
const sentKey = (id) => ({ id, group: 'claude', left: true, name: 'OpenAI', masked: 'sk-…Qx7d' });
show('all of them left: to replace now', keysLineWords(keysFound({ keys: [keysFound().keys[2], sentKey('e')] })));
show('two places: both named, most exposed first', keysLineWords(keysFound({ keys: [keysFound().keys[0],
  sentKey('e'), sentKey('f')] })));
show('three places: the most exposed, and how many more are elsewhere', keysLineWords(keysFound({ keys: [
  ...keysFound().keys, sentKey('e')] })));
show('every place: still two parts', keysLineWords(keysFound({ keys: [...keysFound().keys, sentKey('e'),
  { id: 'g', group: 'ai', left: true, name: 'Anthropic', masked: 'sk-ant-…p2Rw' }] })));
show('one the app says needs you now, of a place the line doesn’t name: said to be elsewhere', keysLineWords(
  keysFound({ keys: [sentKey('e'), { id: 'h', group: 'files', band: 'now', name: 'npm', masked: 'npm_…k8Tz' }] })));
show('a dozen sent to Claude: the head fits the line', keysLineWords(keysFound({ keys: Array.from({ length: 12 },
  (_, i) => sentKey(`s${i}`)) })).head);

section('Keys: whether a key looks real');
const DAY = 86400000;
for (const real of ['sample', 'said', 'made', 'id', 'test', 'shape', 'kept', 'typed', 'sent', 'file', undefined]) {
  show(real || 'not said', keysReal({ real }, 0));
}
show('a sign-in token past its own end date', keysReal({ real: 'ended', ends: 0 }, 90 * DAY));

section('Keys: where a key is, in one sentence, and place by place');
const copies = ['main', ...Array.from({ length: 31 }, (_, i) => `wt${i + 1}`)];
const sampleKey = { id: 's', rule: 'generic-api-key', group: 'pushed', places: [
  ...copies.flatMap((copy) => [24, 67].map((line) => ({ group: 'pushed', file: `/u/code/${copy}/tests/api.expected.txt`,
    line, project: 'harbor', copy, inProject: 'tests/api.expected.txt', commit: '9e8f7a6', can: ['open'] }))),
  { group: 'pushed', file: '/u/code/harbor/tests/api.expected.txt', line: 24, project: 'harbor', copy: 'main',
    inProject: 'tests/api.expected.txt', commit: '4d5c6b7', can: ['open'] },
  { group: 'commit', file: '/u/code/harbor/tests/api.expected.txt', line: 24, project: 'harbor', copy: 'main',
    inProject: 'tests/api.expected.txt', commit: 'a1b2c3d', can: ['open'] }] };
show('a sample in every copy of a project, and in 3 commits', keysWhere(sampleKey));
show('its places: one line for the file', keysSpots(sampleKey).map(keysSpotSays));
const history = (lines) => ({ id: 'h', rule: 'curl-auth-header', group: 'files', places: lines.map((line) => ({
  group: 'files', file: '/u/.zsh_history', line, history: true, where: `~/.zsh_history:${line} · your shell history`,
  can: ['open'] })) });
show('your shell history, on 4 lines', keysWhere(history([1204, 1311, 1876, 2210])));
show('its lines, said', keysSpots(history([1204, 1311, 1876, 2210])).map(keysSpotSays));
show('one line', keysWhere(history([12])));
show('your shell’s settings: where every terminal gets it from', keysWhere({ rule: 'anthropic-api-key', places: [{
  group: 'files', file: '/u/.zshrc', line: 7, startup: true, where: '~/.zshrc:7 · your shell’s settings',
  can: ['open', 'private'] }] }));
show('three lines', keysSpots(history([8, 9, 31])).map(keysSpotSays));
show('a sign-in file others can read', keysWhere({ rule: 'readable', masked: '~/.docker/config.json',
  places: [{ group: 'readable', file: '/u/.docker/config.json', where: 'Other accounts on this Mac can read it' }] }));
const sent = { id: 'c', rule: 'anthropic-api-key', group: 'claude', places: [
  { group: 'claude', how: 'sent', where: 'Your message in a Claude Code conversation in ~/code/atlas',
    file: '/u/t.jsonl', can: ['conversation', 'clear'] },
  { group: 'claude', how: 'sent', where: 'Claude Code’s history of your messages, for ~/code/atlas',
    file: '/u/history.jsonl' }] };
show('sent to Claude, and in its history of your messages', keysWhere(sent));
show('a commit not pushed yet, in a worktree', keysWhere({ places: [{ group: 'commit', file: '/u/code/shop-fix/.env',
  line: 3, project: 'shop', copy: 'shop-fix', inProject: '.env', commit: 'b2c3d4e', can: ['open'] }] }));
show('a download', keysWhere({ places: [{ group: 'files', downloads: true, file: '/u/Downloads/service.json',
  line: 1, where: '~/Downloads/service.json:1', can: ['trash', 'open'] }] }));
show('only in a commit not pushed yet: take it out before you push', keysWhere({ places: [{ group: 'commit',
  file: '/u/code/shop/pay.ts', line: 1, project: 'shop', copy: 'main', inProject: 'pay.ts', commit: 'c3d4e5f',
  can: ['open'] }] }));
show('a merged line’s press acts on its main copy', (() => { const spot = keysSpots({ places: [
  { file: '/u/code/shop-fix/app.ts', line: 3, project: 'shop', copy: 'shop-fix', inProject: 'app.ts', group: 'pushed' },
  { file: '/u/code/shop/app.ts', line: 3, project: 'shop', copy: 'main', inProject: 'app.ts', group: 'pushed' }] })[0];
  return `${spot.index}: ${spot.place.file}`; })());
show('what it’s set as', keysNamed({ places: [{}, { named: { as: 'GITHUB_TOKEN' } }] }));
show('the host it’s the password for', keysNamed({ places: [{ named: { for: 'db.example.dev' } }] }));
show('the host it’s sent to', keysNamed({ places: [{ named: { to: 'api.example.dev' } }] }));
show('nothing said', keysNamed({ places: [{}] }));
show('a remote’s address', keysWhere({ places: [{ group: 'files', remote: 'origin', project: 'shop', copy: 'main',
  checkout: '/u/code/shop', where: 'shop · the address of its remote origin', can: [] }] }));

section('Keys: what each place’s line offers');
const keyWith = () => ({ id: 'k' });
const spotOf = (place) => keysSpots({ places: [place] })[0];
show('a .env line: Open at the Line, and no Trash', keysSpotHTML(keyWith(), spotOf({ project: 'shop', copy: 'main',
  inProject: '.env', file: '/u/code/shop/.env', line: 1, group: 'files', can: ['open'],
  keep: 'Not in git yet: take the key out before it’s committed' })));
show('a download that’s nothing but the key: Open at the Line still; the Trash is in its ⌄',
  keysSpotHTML(keyWith(), spotOf({ where: '~/Downloads/service.json:1', file: '/u/Downloads/service.json', line: 1,
                                   group: 'files', downloads: true, can: ['trash', 'open'] })));
show('a file with no line: Show in Finder', keysSpotHTML(keyWith(), spotOf({ where: '~/.ssh/id_ed25519',
  file: '/u/.ssh/id_ed25519', group: 'readable', can: ['private', 'reveal'] })));
show('a conversation: Open the Conversation', keysSpotHTML(keyWith(), spotOf({ where: 'Your message in a Claude Code '
  + 'conversation in ~/code/shop', file: '/u/t.jsonl', group: 'claude', can: ['conversation', 'clear'],
  keep: 'Claude Code keeps it' })));
show('nothing to press: what to do, in a few words', keysSpotHTML(keyWith(), spotOf({ project: 'shop', copy: 'main',
  remote: 'origin', where: 'shop · the address of its remote origin', group: 'files', can: [],
  keep: 'In the remote’s address: take the token out of it' })));
show('in code type: a path; as words: a sentence or a remote', [
  { project: 'shop', copy: 'main', inProject: 'src/pay.ts', file: '/u/code/shop/src/pay.ts', line: 1, group: 'files' },
  { where: '~/.zsh_history:12 · your shell history', file: '/u/.zsh_history', line: 12, history: true, group: 'files' },
  { where: '/etc/app.conf:3', file: '/etc/app.conf', line: 3, group: 'files' },
  { where: 'Your message in a Claude Code conversation in ~/code/atlas', file: '/u/t.jsonl', group: 'claude' },
  { project: 'shop', copy: 'main', remote: 'origin', where: 'shop · the address of its remote origin',
    group: 'files' }].map((place) => { const spot = spotOf(place); return `${keysAtIsPath(spot) ? 'code' : 'words'}: `
    + spot.at; }));
keysPage.confirm = { id: 'k', place: 0, file: '/u/Downloads/service.json', at: 0 };
show('Move to Trash picked from the ⌄: asked on the file’s line', keysSpotHTML(keyWith(), spotOf({
  where: '~/Downloads/service.json:1', file: '/u/Downloads/service.json', line: 1, group: 'files', downloads: true,
  can: ['trash', 'open'] })));
keysPage.confirm = null;

section('Keys: a key, as the tab draws it');
const drawn = { id: 'g', rule: 'github-pat', group: 'pushed', left: true, real: 'shape', name: 'GitHub',
  masked: 'ghp_…7Kq2',
  ways: [{ action: 'replace', title: 'Replace at GitHub ↗' }, { action: 'ignore', title: 'Not a Key' }],
  places: [{ group: 'pushed', file: '/u/code/atlas/src/config.ts', line: 12, project: 'atlas', copy: 'main',
             inProject: 'src/config.ts', commit: '4c1d9e2', can: ['open'] }] };
show('a key that has left: red, its fix the main one', keysKeyHTML(drawn));
show('the same, only on this Mac: your move’s colour, its fix a plain one', keysKeyHTML({ ...drawn, group: 'files',
  places: [{ ...drawn.places[0], group: 'files', commit: undefined }] }));
show('a sample: the hollow ring, Not a Key first and quiet', keysKeyHTML({ ...sampleKey, real: 'sample', sample: true,
  name: 'Generic api key', masked: '…3f9c', ways: [{ action: 'ignore', title: 'Not a Key' },
                                                    { action: 'open', title: 'Open at the Line' }] }));
keysPage.open = ['g'];
show('Show Where pressed: its places folded out', keysKeyHTML(drawn));
keysPage.open = [];
show('the lede, with keys to replace now', keysLedeHTML([drawn, { ...drawn, group: 'files' }]));
show('the lede, with none that has left', keysLedeHTML([{ ...drawn, group: 'files' }]));
show('a sample, folded at the foot', keysSamplesHTML([sampleKey]));
show('the foot, for two samples', keysFoldedSays([sampleKey, sampleKey]));
show('the foot, for an id', keysFoldedSays([{ real: 'id' }]));
show('the foot, for two ids', keysFoldedSays([{ real: 'id' }, { real: 'id' }]));
show('the foot, for a sample and an id', keysFoldedSays([sampleKey, { real: 'id' }]));
show('the foot, for one its conversation calls made up', keysFoldedSays([{ real: 'said' }]));
show('the foot, for two', keysFoldedSays([{ real: 'said' }, { real: 'said' }]));
show('the foot, for one made up for a test and one said to be', keysFoldedSays([sampleKey, { real: 'said' }]));
show('the foot, for one said to be made up and an id', keysFoldedSays([{ real: 'said' }, { real: 'id' }]));
show('the foot, for one an agent made', keysFoldedSays([{ real: 'made' }]));
show('the foot, for two agents made and one in a test file', keysFoldedSays([{ real: 'made' }, { real: 'made' },
  { real: 'sample' }]));
show('the lede, with only keys about to leave', keysLedeHTML([{ ...drawn, left: false, group: 'commit' }]));
show('the lede, with an ended token that left, and nothing to do now', keysLedeHTML([{ ...drawn, band: 'soon' }]));
show('Do now’s note: all have left', KEYS_BANDS[0].says([{ left: true }]));
show('Do now’s note: some about to', KEYS_BANDS[0].says([{ left: true }, { left: false }]));
show('Do now’s note: all about to', KEYS_BANDS[0].says([{ left: false }]));
show('When you can’s note, with one that has left but no longer works', KEYS_BANDS[1].says([{ left: true }]));
show('a remote’s address, in every copy, said once', keysSpots({ places: ['main', 'wt1', 'wt2'].map((copy) => ({
  group: 'files', remote: 'origin', project: 'shop', repo: '/u/code/shop/repo', copy, where: 'shop · its remote',
  file: '/u/code/shop/repo/settings', line: 8, can: ['open'] })) }).length);
show('two clones with one name: two places', keysSpots({ places: ['/u/code/api/repo', '/u/tmp/api/repo'].map(
  (repo) => ({ group: 'files', project: 'api', repo, copy: 'main', inProject: '.env', file: `${repo}/env`, line: 1,
               can: ['open'] })) }).length);
state.keys = { lookedAt: 1, keys: [{ id: 'dl', places: [{ file: '/u/Downloads/service.json' }] }] };
window.keysAsk('dl', 0, '/u/Downloads/service.json');
show('Move to Trash from the ⌄: its places are shown, to ask on the file’s line', keysPage.open);
keysPage.open = [];
keysPage.confirm = null;
state.keys = { looking: true, keys: [], soFar: { read: 0, of: 5, found: 0 } };
show('the first look, starting: how far it has got beside the tabs, and none found so far', [keysStatusHTML(),
  keysBodyHTML()]);
state.keys = { looking: true, keys: [drawn, sampleKey], soFar: { read: 2, of: 5, found: 1 } };
show('the first look, two places read: the key found so far, listed', [keysStatusHTML(),
  keysBodyHTML().includes('data-keys-fix="g"')]);
state.keys = { looking: true, lookedAt: 1, keys: [drawn], soFar: { read: 4, of: 5, found: 2 } };
show('a look again, four places read', keysStatusHTML());
state.storage = { on: true, scanning: true, counted: 120e9 };
show('while the disk is measured, Keys’ tab says how far the measuring has got, as the others do',
  keysStatusHTML() === mapMeasuredHTML());
state.storage = null;
state.keys = {};
show('before the first look: that it looks a moment after Whozmove opens', keysBodyHTML());
state.keys = null;
