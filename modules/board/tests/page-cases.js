// The team board's part of the page, run outside the app by test.sh: where each job stands, who's on what, the goals as
// tiles, what's done this week, the kinds of what needs you and how many are in One Task, what Take Me There opens, and
// what Glance, a goal and a job's card say.
// Every name here is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

const DAY = 24 * 60;
// Jobs as the team module gives them (TeamFacts): one under way says where it is (`underWay`: you, waiting or work),
// the team module's rule, which tests/rows.sh checks; one without it reads as at work.
const flow = (at, you = false, kind) => ({
  steps: [{ id: 'plan', word: 'Plan', you: true, kind: 'approve' }, { id: 'build', word: 'Build', you: false },
          { id: 'test', word: 'Your try', you: true, kind: 'try' }, { id: 'merge', word: 'Merge', you: false }],
  at, ...(you ? { you: true, underWay: 'you' } : { underWay: 'work' }), ...(kind ? { kind } : {}),
});
const kinds = [['try', 'Try'], ['pick', 'Pick'], ['approve', 'Approve'], ['answer', 'Answer'], ['run', 'Run'],
               ['do', 'Do'], ['seen', 'Seen']].map(([kind, word]) => ({ kind, word }));
const jobs = [
  { id: 'search', title: 'Search box', stage: 'test', priority: 'p0', stageAt: min(30), goal: 'launch',
    member: 'Wren', session: 's-wren', part: 'docs', ...flow('test', true, 'try'), short: 'Try the search box',
    ask: 'Try it on a page with a hundred results', holdsUp: ['sync'], now: true },
  { id: 'sync', title: 'Faster sync', stage: 'build', priority: 'p1', stageAt: min(5), goal: 'launch',
    member: 'Wren', session: 's-wren', part: 'docs', ...flow('build') },
  { id: 'covers', title: 'Album covers', stage: 'look', priority: 'p2', stageAt: min(50), goal: 'speed',
    member: 'Moss', session: 's-moss', part: 'covers', you: true, underWay: 'you', kind: 'pick',
    now: true },
  { id: 'fonts', title: 'Font picker', stage: 'plan', priority: 'p1', stageAt: min(10), member: 'Bea',
    session: 's-bea', part: 'fonts', ...flow('plan', true), now: true },
  { id: 'later', title: 'Later', stage: 'queued', priority: 'p1', stageAt: min(300), goal: 'speed', member: 'Moss' },
  { id: 'aside', title: 'Set aside', stage: 'parked', priority: 'p1', stageAt: min(600), goal: 'speed' },
  { id: 'banner', title: 'Old banner', stage: 'done', priority: 'p1', stageAt: 0, goal: 'launch', doneAt: min(2 * DAY),
    member: 'Wren' },
  { id: 'logo', title: 'First logo', stage: 'done', priority: 'p1', stageAt: 0, goal: 'launch', doneAt: min(9 * DAY) },
];
const team = { project: '/Users/you/shop', lead: { session: 's-atlas', name: 'Atlas' },
               chief: { session: 's-atlas', name: 'Atlas' },
               goals: [{ id: 'launch', name: 'Spring launch', due: 'Fri' }, { id: 'speed', name: 'Faster pages' },
                       { id: 'how-we-work', name: 'How we work', work: true }],
               queue: [{ id: 'try-search', job: 'search', priority: 'p0', title: 'Search box' },
                       { id: 'gone', job: 'nothing-like-it', priority: 'p1' },
                       { id: 'pick-covers', job: 'covers', priority: 'p2', title: 'Album covers' }], jobs };
const sessions = (...ids) => ids.map((sessionId) => ({ sessionId, status: 'idle' }));
const stopped = (...ids) => ids.map((sessionId) => ({ sessionId, status: 'closed' }));

section('Where a job stands (board.js)');
for (const job of jobs) show(`${job.id} (${job.stage})`, boardWhere(job, NOW));
show('the counts', boardCounts(jobs, NOW));

section('Goals as tiles');
show('with goals: one a goal, numbered, then How we work with no number, then the jobs under none',
     boardTiles(team).map((t) => ({ key: t.key, name: t.name, due: t.due, n: t.n, jobs: t.jobs.map((j) => j.id) })));
show('without goals: one tile of every job, with no number', boardTiles({ ...team, goals: [] })
  .map((t) => [t.key, t.name, t.n, t.jobs.length]));
show('every job under a goal: no tile for none', boardTiles({ ...team, jobs: jobs.filter((j) => j.goal) })
  .map((t) => t.key));
const five = ['a', 'b', 'c', 'd', 'e'].map((id) => ({ id, name: `Goal ${id}` }));
show('five goals, numbered 1 to 5, no tints', boardTiles({ ...team, goals: five }).map((t) => [t.name, t.n, t.tint]));
show('How we work between goals in the file: still after them, still no number',
     boardTiles({ ...team, goals: [five[0], { id: 'how', name: 'How we work', work: true }, five[1]] })
       .map((t) => [t.name, t.n]));
show('no team', boardTiles(null).map((t) => [t.key, t.jobs.length]));

section('Who\'s on what');
const who = (t) => boardMembers(t, NOW).map((m) => ({ name: m.name, part: m.part, now: m.now.id, you: m.you,
                                                     moving: m.moving, next: m.next, jobs: m.jobs.map((j) => j.id) }));
show('each member with a job under way, in the order of their first job; the job its row speaks for; the others counted',
     who(team));
show('without the team module\'s mark: its first job under way', who({ jobs: jobs.map(({ now, ...j }) => j) }));
show('two waiting on you and one moving: the marked one, the rest counted once each',
     who({ jobs: [{ id: 'a', member: 'Ivo', stage: 'build', stageAt: min(9) },
                  { id: 'b', member: 'Ivo', stage: 'test', you: true, underWay: 'you', stageAt: min(3), now: true },
                  { id: 'c', member: 'Ivo', stage: 'look', you: true, underWay: 'you', stageAt: min(2) },
                  { id: 'd', member: 'Ivo', stage: 'queued', stageAt: min(1) }] }));
show('no one under way: none listed', who({ jobs: jobs.filter((j) => ['queued', 'parked', 'done'].includes(j.stage)) }));

section('Done this week, the one done last first');
const doneJobs = [...jobs, { id: 'zine', title: 'Zine', stage: 'done', doneAt: min(30), member: 'Moss' }];
show('this week only, newest first', boardDone({ jobs: doneJobs }, NOW).map((j) => j.id));
show('nothing this week', boardDone({ jobs: jobs.filter((j) => j.stage !== 'done') }, NOW));

section('The kinds of what needs you, in One Task\'s order, and how many are in One Task');
show('try, pick, and one with no kind the file gives', boardKinds(team, kinds, NOW));
show('seen is a kind too', boardKinds({ jobs: [{ id: 'news', stage: 'look', you: true, underWay: 'you', kind: 'seen' }] },
                                       kinds, NOW));
show('nothing needs you', boardKinds({ jobs: jobs.filter((j) => !j.you) }, kinds, NOW));
show('in One Task: the lead\'s picks whose job waits on you, each job once', boardInOneTask(team, NOW));
show('…a pick named twice counts once', boardInOneTask({ ...team, queue: [...team.queue, team.queue[0]] }, NOW));
show('…no queue', boardInOneTask({ ...team, queue: undefined }, NOW));

section('What Take Me There opens');
show('its member, listed', boardTakeMe(jobs[0], team, sessions('s-wren', 's-atlas')));
show('its member stopped: carried on', boardTakeMe(jobs[0], team, stopped('s-wren')));
show('its member not in the list: the lead', boardTakeMe(jobs[0], team, sessions('s-atlas')));
show('…the lead stopped: carried on', boardTakeMe(jobs[0], team, stopped('s-atlas')));
show('neither in the list', boardTakeMe(jobs[0], team, sessions('s-other')));
show('no one has it yet: the lead', boardTakeMe(jobs[5], team, sessions('s-atlas')));
const seat = (sessionId, name, extra = {}) => ({ sessionId, status: 'idle', team: { role: 'member', name, ...extra } });
const atlas = (...leads) => ({ sessionId: 's-atlas', status: 'idle', team: { role: 'lead', name: 'Atlas', leads } });
show('a new conversation holds its seat: that one, not the recorded', boardTakeMe(jobs[0], team,
     [...sessions('s-wren', 's-atlas'), seat('s-wren-2', 'Wren')]).session);
show('…the recorded one gone: the seat holder alone', boardTakeMe(jobs[0], team,
     [...sessions('s-atlas'), seat('s-wren-2', 'Wren')]).session);
show('…none running there: the recorded one, stopped, carried on', boardTakeMe(jobs[0], team,
     [...sessions('s-atlas'), { ...seat('s-wren', 'Wren'), status: 'closed' }]));
show('two members of one name: the one the lead leads', boardTakeMe(jobs[0], team,
     [atlas('s-wren-b'), seat('s-wren-a', 'Wren'), seat('s-wren-b', 'Wren')]).session);
show('…only another team\'s listed: the lead, with why', boardTakeMe(jobs[0], team,
     [atlas('s-wren'), seat('s-wren-b', 'Wren')]));
show('…the lead not listed: neither, the recorded one', boardTakeMe(jobs[0], team,
     [...sessions('s-wren'), seat('s-wren-a', 'Wren'), seat('s-wren-b', 'Wren')]).session);
show('a duplicate in the folder: not taken', boardTakeMe(jobs[0], team,
     [...sessions('s-atlas'), { sessionId: 's-wren-3', status: 'idle',
       team: { inFolderOf: 'Wren', duplicate: true, earlier: false, seat: 'Wren' } }, seat('s-wren-2', 'Wren')]).session);
show('a member of another name: not taken', boardTakeMe(jobs[0], team,
     [...sessions('s-wren', 's-atlas'), seat('s-moss', 'Moss')]).session);
show('a lead without a name', boardTakeMe(jobs[0], { ...team, lead: { session: 's-atlas' } }, sessions()));

section('Many jobs, and their order');
const many = Array.from({ length: 240 }, (_, i) => ({ id: `j${i}`, title: `Job ${i}`, stage: 'queued',
                                                       priority: i % 3 ? 'p1' : 'p2', stageAt: min(i) }));
const shown = boardShown(many, false);
show('240 up next: the first shown, then Show All', [shown.jobs.length, shown.more]);
show('Show All pressed', boardShown(many, true).jobs.length);
show('done this week shows fewer before Show All', boardShown(many, false, BOARD_DONE_SHOWN).jobs.length);
show('the most pressing first, then the one that\'s sat longest', boardOrder(jobs.slice(0, 6)).map((j) => j.id));
show('done: the one done last first', boardOrder(jobs.filter((j) => j.stage === 'done')).map((j) => j.id));
show('a member\'s jobs by where they stand', boardByWhere(jobs.filter((j) => j.member === 'Moss'), NOW).map((j) => j.id));

section('What the board draws (board-view.js)');
state.last = { now: NOW, sessions: sessions('s-wren', 's-atlas') };
state.board = { teams: [team, { project: '/Users/you/zines', jobs: [] }], kinds };
core.readerModes.oneTask = {};
show('Glance', boardGlanceHTML(team));
show('what needs you, with One Task in the panel', boardYouHTML(team));
delete core.readerModes.oneTask;
show('…without One Task: no press, only how many are in it', boardYouHTML(team));
show('…nothing needs you', boardYouHTML({ ...team, jobs: jobs.filter((j) => !j.you) }));
show('who\'s on what, no one under way', boardTeamHTML({ ...team, jobs: jobs.filter((j) => j.stage === 'queued') }));
boardPage.member = 'Wren';
show('a member pressed: its other jobs under it, by where they stand, without its name', boardTeamHTML(team));
boardPage.member = null;
const crowd = { ...team, jobs: Array.from({ length: 15 }, (_, i) => ({ id: `c${i}`, title: `Job ${i}`, stage: 'build',
                                                                       stageAt: min(i), member: `M${i}` })) };
show('15 members under way: 12, then Show All', (boardTeamHTML(crowd).match(/class="bd-member/g) || []).length
  + ' · ' + /Show All 15/.test(boardTeamHTML(crowd)));
const busy = { ...crowd, jobs: Array.from({ length: 15 }, (_, i) => ({ id: `b${i}`, title: `Job ${i}`,
                                                                       stage: i ? 'queued' : 'build', stageAt: min(i),
                                                                       member: 'Ivo' })) };
boardPage.member = 'Ivo';
show('a member\'s 14 other jobs opened: 12, then Show All', (boardTeamHTML(busy).match(/data-board-job=/g) || []).length
  + ' · ' + /Show All 14/.test(boardTeamHTML(busy)));
boardPage.member = null;
show('markup in a member\'s name and part is shown as text',
     boardMemberHTML({ name: '<i>Wren</i>', part: '<b>docs</b>', now: jobs[1], you: 0, moving: 0, next: 0,
                       jobs: [jobs[6]] }, team, new Map()));
show('a member with no other jobs: nothing to press',
     boardMemberHTML({ name: 'Bea', part: 'fonts', now: jobs[3], you: 0, moving: 0, next: 0, jobs: [] }, team,
                     new Map()));
show('a tile with jobs that need you: named as well as drawn', boardTileHTML(boardTiles(team)[0]));
show('a tile with no jobs', boardTileHTML({ key: 'goal:empty', name: 'Empty', n: 3, jobs: [] }));
show('How we work\'s tile: no number', boardTileHTML(boardTiles(team).find((t) => t.key === 'goal:how-we-work')));
const sevenDone = boardDoneHTML({ jobs: Array.from({ length: 7 }, (_, i) => ({ id: `d${i}`, title: `Done ${i}`,
                                                                             stage: 'done', doneAt: min(i) })) });
show('done this week past 5: 5, then Show All', `${(sevenDone.match(/data-board-job=/g) || []).length} · `
  + /Show All 7/.test(sevenDone));
show('nothing done this week: left out', boardDoneHTML({ jobs: jobs.filter((j) => j.stage !== 'done') }));
show('Glance\'s head, with one team that has a lead', boardHeadHTML(team));
state.board = { teams: [team, { project: '/Users/you/zines', lead: { session: 's-bea', name: 'Bea' }, jobs: [] }],
                kinds };
show('the kit\'s chips: a team pressed in the head', boardHeadHTML(team).match(/<button class="[^"]*chip[^"]*"[^>]*>/g));
state.board = { teams: [team, { project: '/Users/you/zines', jobs: [] }], kinds };
boardPage.job = 'search';
show('a job\'s card, its member running', boardCardHTML(team));
state.last = { now: NOW, sessions: sessions() };
show('…its member not in the list, nor the lead', boardCardHTML(team));
state.last = { now: NOW, sessions: stopped('s-atlas') };
show('…the lead stopped: Open Atlas Again', boardCardHTML(team));
boardPage.job = 'banner';
show('a done job\'s card', boardCardHTML(team));
boardPage.job = null;
show('a long title on a line', boardLineHTML({ id: 'long', title: 'A title that goes on '.repeat(8).trim(),
                                               stage: 'build', priority: 'p1', stageAt: min(3) }, team));
show('a name that is markup is shown as text', boardLineHTML({ id: 'x', title: '<b>Bold</b>', stage: 'build',
                                                               priority: 'p1', member: '<i>Wren</i>' }, team));

section('Up next (board.js)');
// boardUpNext as the page calls it, with the gear's words (the usage module's, core.gear.words), and `off` while Usage
// Gear is off in Settings.
const upNext = (team, gear, sessions, working, goal, now, letInAt, off) => boardUpNext(team, gear, sessions, working,
                                                                                      goal, now, letInAt,
                                                                                      core.gear.words, off);
// The lead's queued jobs, each with its place in the lead's order (the team module's, across every led team).
const qjobs = [...jobs.map((j) => (j.id === 'later' ? { ...j, place: 3 } : j)),
               { id: 'gift', title: 'Gift cards', stage: 'queued', priority: 'p0', goal: 'launch', member: 'Wren',
                 stageAt: min(90), place: 1 },
               { id: 'carts', title: 'Saved carts', stage: 'queued', priority: 'p1', goal: 'launch',
                 stageAt: min(80), place: 2 }];
const qteam = { ...team, jobs: qjobs };
const working = [{ sessionId: 's-wren', status: 'busy', statusUpdatedAt: min(20) },
                 { sessionId: 's-atlas', status: 'busy', statusUpdatedAt: min(40) },
                 { sessionId: 's-mine', name: 'landing-page', cwd: '/Users/you/landing', status: 'busy',
                   statusUpdatedAt: min(5) },
                 { sessionId: 's-bea', status: 'busy', statusUpdatedAt: min(2) },
                 { sessionId: 's-moss', status: 'idle', statusUpdatedAt: min(1) }];
// Who's working, as the app counts them (Work's SessionWorking): here, the sessions busy.
const countedOf = (list) => list.filter((x) => x.status === 'busy').map((x) => x.sessionId);
// The gear's facts as the usage module gives them, `room` as its GearCounts works it out.
const gearOf = (gear, counted, over = [], more = {}) => ({ gear, atWork: counted.length, counted, over,
                                                          room: gear == null ? null : Math.max(0, gear - counted.length),
                                                          ...more });
const said = (q) => ({ line: q.line, says: q.says, empty: q.empty, rows: q.rows.map((r) => `${r.n ?? '–'} ${r.who} · `
  + `${r.what}${r.job ? ` [${core.teamJob.priorityWord(r.job.priority)}]` : ''} · ${r.says}`) });
const four = ['s-atlas', 's-wren', 's-mine', 's-bea'];
show('no gear: the list\'s sessions at work, by when their turn began, then the queued jobs by place; no line, nothing '
     + 'let in', said(upNext(qteam, null, working, countedOf(working), 'all', NOW)));
show('gear 5, 4 working: the first queued let in, then the line',
     said(upNext(qteam, gearOf(5, four), working, countedOf(working), 'all', NOW)));
show('gear 3, 4 working: the line after 3, the one whose turn began last over it, then what waits',
     said(upNext(qteam, gearOf(3, four, ['s-bea']), working, countedOf(working), 'all', NOW)));
show('no gear set yet: no line, nothing let in', said(upNext(qteam, gearOf(null, four), working, countedOf(working), 'all', NOW)));
show('Usage Gear off: no gear and no limit, so every queued job is let in, with no line',
     said(upNext(qteam, null, working, countedOf(working), 'all', NOW, undefined, true)));
show('at the session\'s limit: the line stays, nothing let in',
     said(upNext(qteam, gearOf(6, four, [], { limit: true }), working, countedOf(working), 'all', NOW)));
show('a session the gear counts that isn\'t listed', said(upNext(qteam, gearOf(2, ['s-gone']), [], [], 'all', NOW)));
show('one goal: its working and queued, no line, a job let in saying so',
     said(upNext(qteam, gearOf(5, four), working, countedOf(working), 'goal:launch', NOW)));
show('Other: the jobs under no goal', said(upNext(qteam, gearOf(5, four), working, countedOf(working), 'none', NOW)));
show('a goal with nothing in it now', said(upNext(qteam, null, working, countedOf(working), 'goal:how-we-work', NOW)));
show('on hold, done and waiting on you aren\'t queued: none listed',
     upNext(qteam, null, [], [], 'all', NOW).rows.map((r) => r.job.id));
show('nothing waits', said(upNext({ ...team, jobs: jobs.filter((j) => j.stage !== 'queued') }, null, working,
                                       countedOf(working), 'all', NOW)));
show('nobody working and nothing waits', said(upNext({ ...team, jobs: [] }, null, [], [], 'all', NOW)));
show('a lead without a name', said(upNext({ ...qteam, lead: { session: 's-atlas', name: '' } },
                                                 gearOf(5, four), working, countedOf(working), 'all', NOW)).rows.slice(0, 5));
// A team whose file names the session you talk to (`front`), which the team module makes its chief, under the name
// its row shows: at work, it says Chief, and the one running the team behind it its name alone; that one still starts
// the jobs, as Take Me There opens.
const fronted = { ...qteam, chief: { session: 's-desk', name: 'The desk' } };
const withDesk = [...working, { sessionId: 's-desk', status: 'busy', statusUpdatedAt: min(50),
                                team: { role: 'front', name: 'Desk', shown: 'The desk', chief: true } }];
show('the session you talk to at work: Chief; the one running the team, its name alone; it still starts the jobs',
     said(upNext(fronted, gearOf(6, [...four, 's-desk']), withDesk, countedOf(withDesk), 'all', NOW)).rows.slice(0, 7));
show('…the heads name the chief', boardChiefSays(fronted));
show('…the one running the team without a name: never "the chief", as the session you talk to is',
     said(upNext({ ...fronted, lead: { session: 's-atlas', name: '' } }, gearOf(6, [...four, 's-desk']), withDesk,
                 countedOf(withDesk), 'all', NOW)).rows.filter((r) => /Gift|^– the/.test(r)));
show('…Take Me There beside Not started still opens the one running the team',
     boardOpensLead(fronted, sessions('s-atlas', 's-desk')));
const room = (at) => upNext(qteam, gearOf(5, four), working, countedOf(working), 'all', NOW,
                                 new Map([['gift', at], ['carts', min(30)]]));
show('let in 9 minutes ago: not yet Not started', room(min(9)).rows.find((r) => r.job?.id === 'gift').says);
show('let in 10 minutes ago and still queued: Not started', room(min(10)).rows.find((r) => r.job?.id === 'gift').says);
show('when each was let in, handed back: one no longer let in left out', [...room(min(10)).letInAt]);
show('let in just now: from now', [...upNext(qteam, gearOf(5, four), working, countedOf(working), 'all', NOW).letInAt]);
show('two teams led: the room is shared, by place, so this team\'s first is second and waits',
     said(upNext({ ...qteam, jobs: qjobs.map((j) => (j.place ? { ...j, place: j.place + 1 } : j)) },
                      gearOf(5, four), working, countedOf(working), 'all', NOW)).rows.slice(4));
show('a job with no place goes last', upNext({ ...qteam, jobs: qjobs.map((j) => (j.id === 'gift'
  ? { ...j, place: undefined } : j)) }, null, [], [], 'all', NOW).rows.map((r) => r.job.id));
show('the goals down the side: All goals, the goals, How we work, Other, each with how many are working',
     boardUpNextShelf(qteam, gearOf(5, four), working, countedOf(working), NOW));
show('no goals: no side list', boardUpNextShelf({ ...qteam, goals: [] }, null, working, countedOf(working), NOW));
show('what Take Me There opens beside Not started: the lead', boardOpensLead(team, sessions('s-atlas')));
show('…the lead stopped', boardOpensLead(team, stopped('s-atlas')));
show('…the lead not in the list', boardOpensLead(team, sessions('s-wren')));
show('…a lead without a name, not in the list', boardOpensLead({ lead: { session: 's-x', name: '' } }, []));

show('a working member with a job waiting on you and one moving: the moving one',
     said(upNext({ ...qteam, jobs: [{ ...jobs[0] }, { ...jobs[1], goal: 'speed' }] }, null,
                      [{ sessionId: 's-wren', status: 'busy' }], ['s-wren'], 'all', NOW)).rows);
show('…and with only the one waiting on you: that one',
     said(upNext({ ...qteam, jobs: [jobs[0]] }, null, [{ sessionId: 's-wren', status: 'busy' }], ['s-wren'], 'all',
                      NOW)).rows);
// The page never reads who's working from a status: it lists the ids the app counted, by SessionWorking.
const odd = [{ sessionId: 's-wren', status: 'busy', ask: { id: 'r1' }, statusUpdatedAt: min(9) },
             { sessionId: 's-moss', status: 'idle', compacting: true, statusUpdatedAt: min(8) },
             { sessionId: 's-bea', status: 'idle', background: [{ id: 'b1' }], statusUpdatedAt: min(7) }];
show('without the gear: a session waiting for your OK isn\'t listed, one compacting and one with agents in the '
     + 'background are, as the app counts them', said(upNext(qteam, null, odd, ['s-bea', 's-moss'], 'all', NOW))
  .rows.filter((r) => !r.includes('Up next')));
show('the line in words, for VoiceOver', upNext(qteam, gearOf(5, four), working, countedOf(working), 'all', NOW).lineSays);
show('a counted session not in the list: not listed, so nothing to press',
     upNext(qteam, gearOf(2, ['s-gone']), [], [], 'all', NOW).rows[0].listed);

section('What the board shows for a goal, and which rows slide as it changes');
const tilesNow = boardTiles(team);
show('Glance, with the rest of the board', boardGoalShown(null, tilesNow, true));
show('Glance, without it: All goals', boardGoalShown(null, tilesNow, false));
show('a goal that\'s there', boardGoalShown('goal:launch', tilesNow, false));
show('a goal gone from the file: Glance, or All goals', [boardGoalShown('goal:gone', tilesNow, true),
                                                        boardGoalShown('goal:gone', tilesNow, false)]);
const kept = (was, now) => [...boardKept(was, now)].sort();
show('one gone, one come: the rest slide', kept(['a', 'b', 'c'], ['a', 'c', 'd']));
show('one moved up past two: it goes and comes, the two slide', kept(['a', 'b', 'c', 'd'], ['a', 'd', 'b', 'c']));
show('two swapped: one of them slides', kept(['a', 'b'], ['b', 'a']));
show('nothing in both', kept(['a'], ['b']));

section('Up next drawn (board-view.js)');
// Without the gear first: the usage module's is set aside, and a stand-in takes its place below.
const theGear = core.gear;
core.gear = null;
state.last = { now: NOW, sessions: working };
state.board = { teams: [qteam], kinds, on: false, working: countedOf(working) };
show('All goals, without the gear', boardQueueHTML(qteam, 'all'));
show('its head, with Show Team Board off: no ‹', boardQueueHeadHTML(qteam));
show('its goals down the shelf', boardQueueShelfHTML(qteam, 'all'));
show('a goal opened', boardQueueHTML(qteam, 'goal:launch'));
state.last = { now: NOW, sessions: sessions('s-atlas') };
state.board.working = [];
show('nobody working and nothing waits: Take Me There to the lead', boardQueueHTML({ ...team, jobs: [] }, 'all'));
state.last = { now: NOW, sessions: [] };
show('…the lead not in the list: why', boardQueueHTML({ ...team, jobs: [] }, 'all'));
state.board.working = countedOf(working);
state.last = { now: NOW, sessions: [...working, { sessionId: 's-atlas', status: 'idle' }] };
state.last = { now: NOW, sessions: working };
// The gear, as the usage module gives it (core.gear), in a stand-in.
let gearFacts = gearOf(5, four);
core.gear = { ...theGear, facts: () => gearFacts,
              line: (f) => ({ says: `${f.atWork} working`, over: f.over.length ? ` · ${f.over.length} over the gear` : '' }),
              whyLine: () => 'Room to go faster' };
state.board.on = true;
boardPage.letIn.set(qteam.project, new Map([['gift', min(12)]]));
show('with the gear: its line, why and where to change the gear, the line among the rows, Not started with Take Me '
     + 'There', boardQueueHTML(qteam, 'all'));
show('its head, with Show Team Board on and the gear: ‹ back to Glance, and no seats, as the usage card sets the gear',
     boardQueueHeadHTML(qteam));
show('a goal opened, with the gear: no line, the note says why, and the job it let in says so',
     boardQueueHTML(qteam, 'goal:launch'));
gearFacts = gearOf(3, four, ['s-bea']);
show('over the gear: said on its row, and on the gear\'s line', boardQueueHTML(qteam, 'all'));
gearFacts = gearOf(5, four, [], { limit: true });
show('at the session\'s limit: the gear\'s line and why, but not where to change it, as the card hides its seats',
     boardQueueHTML(qteam, 'all'));
gearFacts = gearOf(null, four);
show('no gear set yet: the gear\'s line and why, then that nothing is let in until a seat is pressed',
     boardQueueHTML(qteam, 'all'));
boardPage.letIn.clear();
state.reading = null;
gearFacts = gearOf(5, four);
boardTrackLetIn();
show('Up next closed: when the gear let a job in is kept all the same, for Not started',
     [...boardPage.letIn.get(qteam.project)].map(([id]) => id));
core.gear = theGear;
boardPage.letIn.clear();
// Usage Gear off, as the app says it (setGear's `off`).
setGear(null, false, true);
show('Usage Gear off in Settings: in the gear\'s line\'s place, that nothing limits what starts; every queued job let in',
     boardQueueHTML(qteam, 'all'));
setGear(null, false, false);
boardPage.letIn.clear();
show('markup in a name is shown as text', boardQueueRowHTML({ key: 's:x', kind: 'working', session: 'x', n: null,
                                                               who: '<i>Wren</i>', what: '<b>x</b>', says: 'Moving' },
                                                             qteam, true));

const ladder = { ...team, jobs: ['critical', 'p0', 'p1', 'p2', 'someday'].map((priority, i) => (
  { id: `lad${i}`, title: `Job ${priority}`, stage: 'queued', priority, place: i + 1 })) };
show('the priority chip: Critical and P0 in the colour of something to do now, P1 plain, P2 quiet, and a priority the '
     + 'ladder doesn\'t have as P1', upNext(ladder, null, [], [], 'all', NOW).rows
  .map((r) => boardQueueRowHTML(r, ladder, true).match(/bd-prio[^>]*>[^<]*/)[0]));
const chipOf = (html) => html.match(/bd-prio[^>]*>[^<]*/)?.[0] || 'no chip';
show('every job the board lists shows its priority: a stage\'s or a member\'s line, a done one, and its card',
     [boardLineHTML({ ...jobs[0], priority: 'p0' }, team), boardLineHTML({ ...jobs[0], priority: 'p2' }, team, '', false),
      boardLineHTML({ ...jobs[0], priority: 'critical', stage: 'done', doneAt: NOW - 60000 }, team)].map(chipOf));
show('…the job a member is on, in Who\'s on what', chipOf(boardMemberHTML({ name: 'Wren', part: 'search',
  now: { ...jobs[0], priority: 'critical' }, jobs: [], you: 0, moving: 0, next: 0 }, team, new Map())));
boardPage.job = jobs[0].id;
show('…and the job\'s card', chipOf(boardCardHTML({ ...team, jobs: [{ ...jobs[0], priority: 'p1' }] })));
boardPage.job = null;
show('…a member\'s step that waits on you: in the do-now colour for Critical and P0, your move\'s for P1 and P2; a '
     + 'moving one as ever', [['critical', 'plan'], ['p0', 'plan'], ['p1', 'plan'], ['p2', 'plan'], ['critical', 'build']]
  .map(([priority, at]) => boardMemberHTML({ name: 'Bea', part: 'fonts', now: { ...jobs[0], priority, stage: at, ...flow(at, at === 'plan') },
    jobs: [], you: 0, moving: 0, next: 0 }, team, new Map()).match(/bd-step [^"]*/)[0]));
show('…the do-now mark on a job that waits on you: Critical and P0, not P1',
     ['critical', 'p0', 'p1'].map((priority) => boardLineHTML({ ...jobs[0], priority }, team).match(/bd-mark[^"]*/)[0]));
show('a counted session not in the list: words only, nothing to press',
     boardQueueRowHTML({ key: 's:gone', kind: 'working', session: 'gone', n: null, who: 'A session',
                         what: 'Your session', says: 'Moving', listed: false }, qteam, true));
state.board.on = false;
show('the team gone from the file, with Show Team Board off: Up next in the head', boardHeadHTML(null));

section('Up next or Team Board on the chief\'s title line');
state.board.on = false;
show('Show Team Board off: Up next', core.slots.brief.map((f) => f({ s: { sessionId: 's-atlas' }, brief: true })).join(''));
state.board.on = true;
show('Show Team Board on: Team Board', core.slots.brief.map((f) => f({ s: { sessionId: 's-atlas' }, brief: true })).join(''));
show('a member', core.slots.brief.map((f) => f({ s: { sessionId: 's-wren' }, brief: true })).join(''));
const shownTeams = state.board.teams, shownLast = state.last;
const brief = (sessionId) => core.slots.brief.map((f) => f({ s: { sessionId }, brief: true })).join('');
state.board.teams = [{ ...team, chief: { session: 's-desk', name: 'Desk' } }];
state.last = { now: NOW, sessions: sessions('s-desk', 's-atlas') };
show('with a session you talk to: on its line', brief('s-desk'));
show('…and not on the one running the team', brief('s-atlas'));
// Which line carries it (boardLineFor): the chief's while it's in the list; else the lead's (its conversation ended, or
// a new one isn't in the file yet), so Up next always has a way in.
const withFront = { ...team, chief: { session: 's-desk', name: 'Desk' } };
show('which line: the session you talk to, while it\'s in the list',
     boardLineFor(withFront, sessions('s-desk', 's-atlas')));
show('…that session not in the list: the one running the team', boardLineFor(withFront, sessions('s-atlas')));
show('…no session you talk to: the one running the team', boardLineFor(team, sessions('s-atlas')));
show('…a team nobody leads: none', boardLineFor({ project: '/Users/you/zines', jobs: [] }, sessions('s-atlas')));
state.board.teams = shownTeams;
state.last = shownLast;

section('Show Team Board turned off');
// The reader's close itself is the pane's (its own cases); here, only that the board asks for it.
const closeTheReader = closeReader;
let closed = 0;
closeReader = () => { closed++; };
const drawTheReader = drawReader;
let drawn = 0;
drawReader = () => { drawn++; };
state.reading = { mode: 'board' };
setBoard([team], kinds, true);
show('ticked: an open board is drawn again, not closed', [closed, drawn]);
setBoard([team], kinds, false);
show('turned off: still told the teams, for Up next, and drawn again (Glance turns to All goals), not closed',
     [closed, drawn, state.board.teams.length, state.board.on]);
state.reading = null;
setBoard([team], kinds, false);
show('turned off with no board open: nothing drawn', drawn);
closeReader = closeTheReader;
drawReader = drawTheReader;

section('Stages: a step that waits its turn, and the strip under What\'s moving');
// A flow whose step after a review waits its turn, with nobody working on the job, until it's tried.
const QA_STEPS = [{ id: 'plan', word: 'Plan', you: true, kind: 'approve' }, { id: 'build', word: 'Build', you: false },
                  { id: 'review', word: 'Review', you: false },
                  { id: 'ready', word: 'Ready to try', you: false, waits: true },
                  { id: 'trying', word: 'Trying', you: true, kind: 'try' }];
const qa = (id, at, fields = {}) => {
  const step = QA_STEPS.find((s) => s.id === at);
  return { id, title: `Job ${id}`, stage: at, steps: QA_STEPS, at, priority: 'p1', stageAt: min(30),
           underWay: step.you ? 'you' : step.waits ? 'waiting' : 'work', ...(step.you ? { you: true } : {}),
           ...(step.waits ? { waits: true } : {}), ...fields };
};
const qaJobs = [
  qa('r1', 'ready', { size: 'big', effort: 'low', stageAt: min(40), member: 'Wren' }),
  qa('r2', 'ready', { size: 'small', effort: 'high', stageAt: min(20), member: 'Moss' }),
  qa('r3', 'ready', { priority: 'critical', size: 'big', stageAt: min(5) }),
  qa('r4', 'ready', { size: 'small', effort: 'low', stageAt: min(10) }),
  qa('r5', 'ready', { stageAt: min(60) }),
  qa('t1', 'trying', { priority: 'p0', kind: 'try', member: 'Bea' }),
  qa('b1', 'build', { member: 'Wren', now: true }),
  // Another flow: a word between two this team's flows have already placed, and words none has.
  { id: 'd1', title: 'Job d1', stage: 'design', priority: 'p1', stageAt: min(8), at: 'design',
    steps: [{ id: 'plan', word: 'Plan' }, { id: 'design', word: 'Design' }, { id: 'build', word: 'Build' }] },
  { id: 's1', title: 'Job s1', stage: 'sketch', priority: 'p2', stageAt: min(8), at: 'sketch',
    steps: [{ id: 'sketch', word: 'Sketch' }, { id: 'look', word: 'Look', you: true, kind: 'pick' }] },
  { id: 'q1', title: 'Job q1', stage: 'queued', priority: 'p1', stageAt: min(3) },
  { id: 'n1', title: 'No steps', stage: 'build', priority: 'p1', stageAt: min(3) },
];
const qaTeam = { ...team, goals: [], queue: [], jobs: qaJobs };
show('a job at a step that waits its turn: waiting; one at a step on you still needs you',
     ['r1', 't1', 'b1', 'n1'].map((id) => `${id}: ${boardWhere(qaJobs.find((j) => j.id === id), NOW)}`));
show('the counts: waiting apart from moving', boardCounts(qaJobs, NOW));
show('its words: its step\'s own, else Waiting', [boardWhereWord('waiting', qaJobs[0]),
                                               boardWhereWord('waiting', { steps: [], at: 'x' })]);
show('who\'s on what: Wren on the job it builds, its waiting job among its others but not counted; Moss, with only a '
     + 'job waiting its turn, isn\'t on anything', boardMembers(qaTeam, NOW)
  .map((m) => `${m.name}: ${m.now.id} · ${m.you}/${m.moving}/${m.next} · ${m.jobs.map((j) => j.id)}`));
show('a member\'s jobs by where they stand: waiting after moving',
     boardByWhere(qaJobs.filter((j) => ['r1', 'b1', 'q1'].includes(j.id)), NOW).map((j) => j.id));
const st = (stages) => stages.map((s) => `${s.word}${s.you ? ' (you)' : ''}${s.waits ? ' (waits)' : ''}: `
  + s.jobs.map((j) => j.id).join(' '));
show('the stages: a word per step with jobs at it, in the flows\' order (Design between Plan and Build, a flow of its '
     + 'own last), each in the board\'s order; queued and stepless jobs left out', st(boardStages(qaTeam, NOW)));
show('…the order inside one: the most pressing, then the smallest, then the least work, then the longest there',
     boardOrder(qaJobs.filter((j) => j.at === 'ready'))
       .map((j) => `${j.id} ${j.priority} ${j.size || '-'} ${j.effort || '-'}`));
show('…without size or effort: as before, the most pressing, then the longest there',
     boardOrder(qaJobs.filter((j) => j.at === 'ready').map(({ size, effort, ...j }) => j)).map((j) => j.id));
show('…a word it doesn\'t know sorts as medium',
     boardOrder([qa('x', 'ready', { size: 'huge', stageAt: min(1) }),
                 qa('y', 'ready', { size: 'big', stageAt: min(2) }),
                 qa('z', 'ready', { size: 'medium', stageAt: min(3) })]).map((j) => j.id));
show('…the ladder: Critical, then P0, P1 and P2, and a priority it doesn\'t know with P1',
     boardOrder(['p2', 'p1', 'someday', 'p0', 'critical'].map((priority, i) => qa(`l${i}`, 'ready', { priority })))
       .map((j) => `${j.id} ${j.priority}`));
show('no job under way at a step: no stages', boardStages({ jobs: qaJobs.filter((j) => j.stage === 'queued') }, NOW));
show('the stage open, while it has jobs', boardStageShown('Ready to try', boardStages(qaTeam, NOW)));
show('…gone from the strip: it folds', boardStageShown('Review', boardStages(qaTeam, NOW)));

section('The strip drawn (board-view.js)');
state.last = { now: NOW, sessions: [] };
state.board = { teams: [qaTeam], kinds, on: true, working: [] };
boardPage.stage = null;
boardPage.all = new Set();
show('the hero: how many wait their turn beside up next and on hold', boardHeroHTML(qaTeam));
show('…none waiting: not said', boardHeroHTML(team));
show('what they wait for: all at one step, its word; at two, or a step with no word, waiting their turn; one, its turn',
     [boardWaitingSays(qaJobs, NOW),
      boardWaitingSays([...qaJobs, { ...qaJobs[0], id: 'p1', steps: QA_STEPS.map((s) => (s.id === 'ready'
        ? { ...s, word: 'Passed' } : s)) }], NOW),
      boardWaitingSays([{ ...qaJobs[0], steps: [] }], NOW), boardWaitingSays([{ ...qaJobs[0], steps: [] },
                                                                               { ...qaJobs[1], steps: [] }], NOW)]);
show('a tile with jobs waiting: drawn grey in its bar, and said', boardTileHTML({ key: 'all', name: 'All tasks',
                                                                                 jobs: qaJobs }));
show('closed: a chip each, with its count, said whole to VoiceOver', boardStagesHTML(qaTeam));
show('no job at a step: no strip', boardStagesHTML({ ...qaTeam, jobs: qaJobs.filter((j) => j.stage === 'queued') }));
show('one stage: one chip', boardStagesHTML({ ...qaTeam, jobs: [qaJobs[0]] }));
const pressStage = core.readerPresses.find(([sel]) => sel === '[data-board-stage]')[1];
const drawTheReader2 = drawReader;
drawReader = () => {};
pressStage({ dataset: { boardStage: 'Ready to try' } });
show('pressed: its jobs under the strip, in the board\'s order, and the line saying that order',
     boardStagesHTML(qaTeam));
show('…a waiting job\'s line says its step', boardLineHTML(qaJobs[0], qaTeam));
pressStage({ dataset: { boardStage: 'Ready to try' } });
show('pressed again: folded', [boardPage.stage, /bd-stage-jobs/.test(boardStagesHTML(qaTeam))]);
pressStage({ dataset: { boardStage: 'Trying' } });
show('open, and the stage empties: it folds', [/bd-stage-jobs/.test(boardStagesHTML({ ...qaTeam,
  jobs: qaJobs.filter((j) => j.at !== 'trying') })), boardPage.stage]);
pressStage({ dataset: { boardStage: 'Build' } });
const noSteps = boardStagesHTML({ ...qaTeam, jobs: qaJobs.filter((j) => j.stage === 'queued') });
show('open, and every job leaves the steps: no strip, and it folds, so it never comes back open by itself',
     [noSteps, boardPage.stage, /aria-pressed="true"/.test(boardStagesHTML(qaTeam))]);
const manyReady = { ...qaTeam, jobs: Array.from({ length: 15 }, (_, i) => qa(`m${i}`, 'ready', { stageAt: min(i) })) };
boardPage.stage = 'Ready to try';
show('open with 15 jobs: 12, then Show All', `${(boardStagesHTML(manyReady).match(/data-board-job=/g) || []).length} · `
  + /data-board-all="stage:Ready to try">Show All 15/.test(boardStagesHTML(manyReady)));
boardPage.all.add('stage:Ready to try');
show('…Show All pressed: all 15', (boardStagesHTML(manyReady).match(/data-board-job=/g) || []).length);
const manyWords = { ...qaTeam, jobs: Array.from({ length: 14 }, (_, i) => ({ id: `w${i}`, title: `Job ${i}`,
  stage: `s${i}`, at: `s${i}`, priority: 'p1', stageAt: min(1),
  steps: Array.from({ length: 14 }, (__, k) => ({ id: `s${k}`, word: `Step ${k}` })) })) };
boardPage.stage = null;
show('14 stages: 12 chips, then Show All', `${(boardStagesHTML(manyWords).match(/data-board-stage=/g) || []).length} · `
  + /data-board-all="stages">Show All 14/.test(boardStagesHTML(manyWords)));
boardPage.all.add('stages');
show('…Show All pressed: all 14', (boardStagesHTML(manyWords).match(/data-board-stage=/g) || []).length);
const longWord = { ...qaTeam, jobs: [{ ...qaJobs[0], steps: QA_STEPS.map((s) => (s.id === 'ready'
  ? { ...s, word: 'Waiting for a try on <b>the</b> preview' } : s)) }] };
show('a long word, and markup in it: shown as text, cut by its style, said whole', boardStagesHTML(longWord));
show('Glance: the strip under What\'s moving, before who\'s on what',
     boardGlanceHTML(qaTeam).replace(/<div class="bd-sec"><div class="bd-sec-h">Goals.*$/, '…')
       .match(/class="bd-(hero|sec-h)"[^>]*>[A-Z0-9a-z’ ]*/g));
boardPage.job = 'r1';
show('a waiting job\'s card: its step for how long',
     boardCardHTML(qaTeam).match(/<div class="card-head">.*?<\/div>/)[0]);
boardPage.job = null;
boardPage.stage = null;
boardPage.all = new Set();
drawReader = drawTheReader2;
