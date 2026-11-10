// The team module's part of the page, run outside the app by test.sh: the team's groups above the projects, the counts,
// the second line and the tracks it shows, and a row as it draws it (team.js). Every name here is made up.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

load('tests/page-harness.js');  // the stand-ins, the page's scripts and the helpers below use

// The steps of a job, the ones that wait on you marked, and a job at one of them.
const STEPS = [['plan', 'Plan', true, 'approve'], ['build', 'Build', false], ['review', 'Review', false],
               ['test', 'Your try', true, 'try'], ['merge-yes', 'Your yes', true, 'approve'], ['merge', 'Merge', false]]
  .map(([id, word, you, kind]) => ({ id, word, you, ...(kind ? { kind } : {}) }));
const job = (at, fields = {}) => ({ id: 'j1', title: 'Search box', steps: STEPS, at,
                                    you: STEPS.find((st) => st.id === at).you, priority: 'p1', holds: 0,
                                    stageAt: min(30), ...fields });

const lead = session({ sessionId: 'lead', name: 'Atlas', lastReply: 'A long reply about everything at once',
                        lastReplyAt: min(2), statusUpdatedAt: min(2),
                        team: { role: 'lead', name: 'Atlas', chief: true,
                                counts: { waiting: { critical: 1, p0: 1, p1: 2, p2: 3 }, working: 4 } } });
const wren = session({ sessionId: 'wren', name: 'search-box-tab', lastPrompt: 'Make the search box',
                       lastPromptAt: min(6), lastReply: 'The search box is ready to try', lastReplyAt: min(5),
                       statusUpdatedAt: min(5),
                       team: { role: 'member', name: 'Wren', part: 'docs',
                               job: job('test', { short: 'Try the search box', holds: 2,
                                                  ask: 'Try it on a page with a hundred results, and say if it keeps up' }) },
});
const bea = session({ sessionId: 'bea', name: 'Bea', status: 'busy', lastPrompt: 'Send the invoices',
                      lastPromptAt: min(1), statusUpdatedAt: min(1), activity: 'Reading invoice.js',
                      team: { role: 'member', name: 'Bea', part: 'billing', job: job('build') } });
const moss = session({ sessionId: 'moss', name: 'Moss', team: { role: 'member', name: 'Moss', part: 'fonts' } });
const dark = session({ sessionId: 'dark', name: 'dark mode', statusUpdatedAt: min(8),
                       team: { role: 'followed', name: 'dark mode',
                               job: job('merge-yes', { title: 'Dark mode', priority: 'p0' }) } });
const visitor = session({ sessionId: 'visitor', name: 'look around', team: { inFolderOf: 'Wren', history: true } });
const plain = session({ sessionId: 'plain', name: 'tidy photos', lastReply: 'Sorted', lastReplyAt: min(20) });
const everyone = [lead, wren, bea, moss, dark, visitor, plain];
const placeAll = (sessions) => placeRows(sessions.map((s) => ({ s, kind: classify(s, NOW, view()) })), {}, () => false);
// The team's groups, then what it leaves for the projects (`rest`), each as its rows' ids; null with no team listed.
const teamShown = (placed) => {
  const top = teamGroups(placed);
  return top && [...top.groups, { key: 'rest', name: '(the projects)', rows: top.rest }];
};
const outline = (html) => [...html.matchAll(/<div class="project( collapsed)?" data-key="([^"]*)"|data-id="([^"]*)"/g)]
  .map(([, folded, key, id]) => (key ? `[${key}${folded ? ' ›' : ''}]` : id)).join(' ');

section('The groups (teamGroups)');
show('no one of the team listed: none, so the list is its projects alone', teamShown(placeAll([dark, visitor, plain])));
show('the lead on top, then the team, and yours left for the projects',
     teamShown(placeAll(everyone)).map((g) => `${g.name}: ${g.rows.map((p) => p.s.sessionId).join(', ')}`));
show('a group with no rows is left out', teamShown(placeAll([wren, plain])).map((g) => g.name));
const gone = { ...visitor, sessionId: 'gone', status: 'closed' };
const goneOwn = { ...plain, sessionId: 'gone-own', status: 'closed' };
show('an ended session in a member\'s folder isn\'t shown; one running there, and an ended one of yours, are',
     teamShown(placeAll([wren, visitor, gone, goneOwn])).map((g) => `${g.name}: ${g.rows.map((p) => p.s.sessionId)}`));
const goneUnread = { ...gone, sessionId: 'gone-unread', lastReply: 'The fonts are in', lastReplyAt: min(3),
                     statusUpdatedAt: min(3) };
show('…nor is one with a reply you haven\'t read, as that reply isn\'t yours to read; one that asks you something is',
     teamShown(placeAll([wren, gone, goneUnread, { ...goneUnread, sessionId: 'gone-asks', ask: { kind: 'question' } }]))
       .map((g) => `${g.name}: ${g.rows.map((p) => `${p.s.sessionId} (${p.kind})`)}`));
show('…and so is one you\'ve pressed, held where it was, or are on',
     teamShown([...placeAll([wren]), { s: gone, kind: 'idle', held: true },
                 { s: { ...gone, sessionId: 'gone-focused', focused: true }, kind: 'idle' }])
       .map((g) => `${g.name}: ${g.rows.map((p) => p.s.sessionId)}`));
state.owners = new Set(['gone', 'gone-unread']);
show('…and so is one that speaks for its checkout, with its next steps and Deploy, with no dot for its reply',
     teamShown(placeAll([wren, gone, goneUnread]))
       .map((g) => `${g.name}: ${g.rows.map((p) => `${p.s.sessionId} (${p.kind})`)}`));
state.owners = new Set();
// A reply in a conversation that has ended in a member's folder (its earlier one, or one in the lead's or the
// front's) is the member's history, never yours to read, anywhere in the list and in every count of what
// waits on you; one still running there, and one of yours, still waits on you; without the team file, nothing changes.
const whoseMove = (s) => classify(s, NOW, view());
show('a reply you haven\'t read, as whose move it is: ended in a member\'s folder, running there, ended of yours, and '
     + 'ended where no team file says whose folder it is',
     [goneUnread, { ...goneUnread, sessionId: 'here-unread', status: 'idle' },
      { ...goneOwn, sessionId: 'own-unread', lastReply: 'Sorted', lastReplyAt: min(3) },
      { ...goneUnread, sessionId: 'no-file', team: undefined }].map((s) => `${s.sessionId} ${whoseMove(s)}`));
// An earlier reply to you, kept to read when a message from another session came after it (state.toRead), is kept,
// not counted, once the conversation has ended in a member's folder; kept and counted on one running there, and
// without the team file.
const toLead = { promptFrom: 'Atlas', promptFromAddress: '/tmp/atlas.sock', lastPromptAt: min(2), lastReplyAt: min(1) };
const keptOn = [{ ...goneUnread, ...toLead, sessionId: 'kept-gone' },
                { ...goneUnread, ...toLead, sessionId: 'kept-here', status: 'idle' },
                { ...goneUnread, ...toLead, sessionId: 'kept-no-file', team: undefined }];
state.toRead = Object.fromEntries(keptOn.map((s) => [s.sessionId, min(3)]));
keepToRead(keptOn);
show('a reply kept to read, under a later one to another session: whose move it is, and whether it\'s still kept',
     keptOn.map((s) => `${s.sessionId} ${whoseMove(s)} ${s.sessionId in state.toRead ? 'kept' : 'dropped'}`));
const resumed = { ...keptOn[0], status: 'idle' };
keepToRead([resumed]);
show('…and once the ended one is resumed, its reply to you waits on you again', whoseMove(resumed));
// Where the session you talk to, or the lead, runs in the project's own folder, your own conversations are there too:
// one that has ended there isn't the team's history (no `history` from the app), so its reply still waits on you, and
// it's left for its project.
const ownInProject = { ...goneUnread, sessionId: 'own-in-project', team: { inFolderOf: 'Desk' } };
show('an own conversation ended in the project\'s folder, where the session you talk to runs: whose move it is, '
     + 'and its group', [whoseMove(ownInProject), teamShown(placeAll([wren, ownInProject]))
       .map((g) => `${g.name}: ${g.rows.map((p) => `${p.s.sessionId} (${p.kind})`)}`)]);
state.toRead = {};
// Groups the file names for members: after the lead, before the team, in the file's order; one with no place in it
// last; one of yours with a group stays yours.
const inGroup = (s, group, groupAt) => ({ ...s, team: { ...s.team, group, groupAt } });
const named = [lead, inGroup(wren, 'Reviewers', 1), inGroup(moss, 'Reviewers', 1), inGroup(bea, 'Designers', 0),
               { ...plain, sessionId: 'later', team: { role: 'member', name: 'Lark', group: 'Archive' } },
               inGroup(dark, 'Reviewers', 1)];
show('groups the file names, in its order, after the lead, before the team',
     teamShown(placeAll(named)).map((g) => `${g.name} (${g.key}): ${g.rows.map((p) => p.s.sessionId).join(', ')}`));
// A group's name is the file's words: drawn as text, whatever they are, and whole however long (the app clips them).
const fifty = 'A group whose name runs on to fifty characters, ok';
const oddNames = [lead, inGroup(wren, '<b>x</b>', 0), inGroup(bea, fifty, 1)];
const headers = /data-key="([^"]*)"[\s\S]*?<span class="pname">([^<]*)</g;
show('a group\'s name in markup, and a long one, drawn as text in its header',
     [...groupsHTML(teamShown(placeAll(oddNames)), NOW).matchAll(headers)].map(([, key, name]) => `${key} | ${name}`));
// Members the file gives a tag: a tag is only a mark, so each stays in its group, or in Team.
const tagged = (s, tag, shown) => ({ ...s, team: { ...s.team, tag, ...(shown ? { shown } : {}) } });
const withTags = [lead, tagged(wren, 'Product', 'Zed'), tagged(inGroup(bea, 'Designers', 0), 'Design'),
                  tagged(moss, 'Fonts lead', 'Ash'), dark, plain];
show('tagged members stay where they\'d be untagged: in their group, or in Team',
     teamShown(placeAll(withTags)).map((g) => `${g.name}: ${g.rows.map((p) => p.s.sessionId).join(', ')}`));
// The session you talk to, when the file names one apart from the one running the team (`front`): the chief, which the
// app marks, on top, then the one running the team, whatever needs you.
const front = session({ sessionId: 'front', name: 'desk-tab', statusUpdatedAt: min(40),
                        team: { role: 'front', name: 'Desk', shown: 'The desk', chief: true } });
const behind = { ...lead, team: { ...lead.team, chief: false } };
const groupsOf = (sessions) => teamShown(placeAll(sessions))
  .map((g) => `${g.name}: ${g.rows.map((p) => p.s.sessionId).join(', ')}`);
show('the session you talk to on top, then the one running the team, and a tagged member in Team',
     groupsOf([tagged(wren, 'Product', 'Zed'), behind, front, plain]));
show('…the session you talk to not listed: the one running the team on top',
     groupsOf([tagged(wren, 'Product'), behind, plain]));
const otherFront = { ...front, sessionId: 'front-2', team: { ...front.team, name: 'Post', shown: undefined } };
show('two teams, each with a session you talk to: both on top, then each one running a team',
     groupsOf([behind, { ...behind, sessionId: 'lead-2' }, otherFront, front, plain]));
// Behind the session you talk to, the one running the team in the group the file gives it, as a member is, and
// nothing on top but the session you talk to. A file that places Team among its groups (its members' `groupAt`) puts
// it there; without, it comes after them.
const ledFrom = (group, groupAt) => ({ ...behind, team: { ...behind.team, group, groupAt } });
const inTeam = (s, groupAt) => ({ ...s, team: { ...s.team, groupAt } });
show('the one running the team in its group, the session you talk to alone on top',
     groupsOf([front, inGroup(wren, 'Reviewers', 0), ledFrom('Reviewers', 0), inGroup(moss, 'Writers', 2),
               inTeam(bea, 1), plain]));
show('…Team after the groups when the file doesn\'t place it',
     groupsOf([front, inGroup(wren, 'Reviewers', 0), ledFrom('Reviewers', 0), inGroup(moss, 'Writers', 1), bea]));

section('The list with a team (listGroups)');
state.closedProjects['team:team'] = true;
const drawn = groupsHTML(listGroups(placeAll(everyone)), NOW);
show('drawn: the lead with no header, the team folded, hiding all it has, then the projects',
     outline(drawn).replace(/<div class="pinned">/g, ''));
show('…nothing pinned below them, not even a job waiting on you', /class="pinned"/.test(drawn));
show('…each folded header says how many wait on you',
     [...drawn.matchAll(/<div class="project[^"]*" data-key="([^"]*)"[^>]*>([\s\S]*?)<\/div>/g)]
       .map(([, key, head]) => [key, head.match(/<span class="(pneeds[^"]*)">([^<]*)<\/span>/)])
       .map(([key, m]) => `${key}: ${m ? `${m[2]} (${m[1]})` : '-'}`));
show('…and as VoiceOver reads it', [...drawn.matchAll(/aria-label="([^"]*)"/g)].map((m) => m[1])
  .filter((said) => said.includes('folded')));
{
  // A project folds as the team's groups do: an idle row whose job waits on you is hidden too, its header counting it.
  state.closedProjects['/work/fold'] = true;
  const foldedProject = groupsHTML([{ key: '/work/fold', name: 'fold', project: true,
    rows: [{ s: moss, kind: 'idle', waits: true }, { s: plain, kind: 'idle' }] }], NOW);
  delete state.closedProjects['/work/fold'];
  show('a project\'s folded group hides an idle row whose job waits on you too, its header counting it',
       [/class="pinned"/.test(foldedProject), foldedProject.match(/class="pneeds[^"]*">([^<]*)/)?.[1]]);
}
show('…the lead keeps a group header\'s room above it', /<div class="prows bare">/.test(drawn));
show('…no header says how many it has, a project\'s ending in its ＋ slot', /pcount/.test(drawn));
delete state.closedProjects['team:team'];

section('In each group, the order the list placed them');
const DAY = 24 * 60;
const oldAsk = session({ sessionId: 'old-ask', name: 'old ask', lastReplyAt: min(4 * DAY), seenAt: min(4 * DAY - 5),
                         team: { role: 'followed', name: 'old ask',
                                 job: job('merge-yes', { title: 'Old ask', short: 'Say yes' }) } });
const readToday = session({ sessionId: 'read-today', name: 'read today', lastReplyAt: min(60), seenAt: min(30) });
const idleOne = session({ sessionId: 'idle-one', name: 'idle one', lastReplyAt: min(2 * DAY), seenAt: min(2 * DAY - 5) });
const unread = session({ sessionId: 'unread', name: 'unread', lastReplyAt: min(90) });
const askingNow = session({ sessionId: 'asking', name: 'asking', status: 'waiting', statusUpdatedAt: min(120),
                        lastReplyAt: min(120) });
const yours = [readToday, idleOne, oldAsk, unread, askingNow];
const restOf = (placed) => teamGroups([...placeAll([wren]), ...placed]).rest
  .map((p) => `${p.s.sessionId} (${p.kind}${p.waits ? ', waits' : ''})`);
show('as the list places them: newest message first, the idle ones last', placeAll(yours).map((p) => p.s.sessionId));
show('left for the projects in that order: nothing lifted, a job waiting on you marked so its folded project keeps it',
     restOf(placeAll(yours)));
const memberRows = [{ ...wren, sessionId: 'wren-old', lastReplyAt: min(300), statusUpdatedAt: min(300) },
                    { ...bea, status: 'idle', lastReplyAt: min(1), statusUpdatedAt: min(1) }];
show('the team in that order too, a job waiting on you included',
     teamGroups(placeAll(memberRows)).groups.map((g) => `${g.name}: ${g.rows.map((p) => p.s.sessionId)}`));

section('What the lead says (teamCountsHTML)');
const counted = (c) => teamCountsHTML(c).replace(/<i class="tmini (\w+)"><\/i>/g, '($1)')
  .replace(/<[^>]+>/g, ' ')
  .replace(/\s+/g, ' ').trim();
show('some of each', counted(lead.team.counts));
show('a count of none is left out, Critical or not', counted({ waiting: { critical: 0, p1: 2, p2: 0 }, working: 1 }));
show('nothing waiting: only what\'s at work', counted({ waiting: { p1: 0 }, working: 3 }));
show('nothing at work: only what waits', counted({ waiting: { p2: 1 }, working: 0 }));
show('one job waiting: it waits', counted({ waiting: { p1: 1 }, working: 2 }));
show('Critical and P0 add up into the one dot of something to do now', counted({ waiting: { critical: 2, p0: 1 }, working: 0 }));
show('P0 alone: that dot too', counted({ waiting: { p0: 1 }, working: 0 }));
show('nothing', counted({ waiting: {}, working: 0 }));
show('no counts', counted(undefined));
show('in words', teamCountsWords(lead.team.counts));
show('in words, nothing to do now', teamCountsWords({ waiting: { p1: 2 }, working: 0 }));
show('in words, Critical and P0 each named', teamCountsWords({ waiting: { critical: 1, p0: 2, p1: 3 }, working: 4 }));
show('in words, nothing waiting', teamCountsWords({ waiting: {}, working: 3 }));
show('in words, one job waiting', teamCountsWords({ waiting: { critical: 1 }, working: 0 }));
show('in words, nothing', teamCountsWords(undefined));
const idleLead = { ...lead.team, counts: { waiting: { critical: 0, p0: 0, p1: 0, p2: 0 }, working: 0 } };
show('the lead with nothing to count: no line', teamNote(idleLead));
show('…nor counts beside its name while it names what\'s next', rowHTML({ ...lead,
  team: { ...idleLead, next: { short: 'Pick a name', priority: 'p1' } } }, 'seen', NOW).includes('tsum'));

section('The second line (teamNote)');
const said = (note) => note && { ...note, html: note.html.replace(/<svg[\s\S]*?<\/svg>/, '[mark]') };
show('the lead: its counts', teamNote(lead.team).cls);
show('…as its note, with the counts', noteHTML(teamNote(lead.team)));
show('a job waiting on your try: its short, and what it holds up', said(teamNote(wren.team)));
show('…said with the row\'s Deploy at its end', noteHTML(said(teamNote(wren.team)), '[Deploy]'));
show('another module\'s note keeps the Deploy too', noteHTML({ text: 'Deploying: building' }, '[Deploy]'));
show('…its whole ask isn\'t on the row', said(teamNote(wren.team)).html.includes('hundred'));
show('…VoiceOver says its own ask, never passed on by the session leading the team, and it has no tip',
     [teamNote(wren.team, 'wren', (id) => (id === null ? 'Atlas' : '')).html.match(/aria-label="([^"]*)"/)[1],
      /title=/.test(teamNote(wren.team, 'wren', (id) => (id === null ? 'Atlas' : '')).html.split('ask-line-more')[0])]);
show('…without a short: its step\'s word, never the long ask', said(teamNote({ job: job('test', { ask: 'A long note' }) })));
// Its bubble's colour (`look`) and the priority's name first.
const bubble = (note) => `${note.look}: ${note.html.match(/ask-line-priority">([^<]*)/)[1]}`;
show('a P0 one', bubble(teamNote(dark.team)));
show('a Critical one', bubble(teamNote({ job: job('plan', { priority: 'critical' }) })));
show('a P2 one', bubble(teamNote({ job: job('plan', { priority: 'p2' }) })));
show('one with a word the ladder doesn\'t have: plain', bubble(teamNote({ job: job('plan', { priority: 'someday' }) })));
// Its one action, by what its step asks of you: a try's is Deploy (another module's, askAct), else its session; a
// plan's opens the session it waits in, under the plan's icon; the lead's, for what's next, the session it's for.
const act = (note) => note.act && { want: note.act.want, html: note.act.html.replace(/<svg[\s\S]*?<\/svg>/, '[icon]') };
show('…its action: a try\'s', act(teamNote(wren.team, 'wren')));
show('…a plan\'s', act(teamNote({ name: 'Wren', job: job('plan') }, 'wren')));
show('…a step with no kind: to its session', act(teamNote({ name: 'Wren', job: job('plan', {
  steps: STEPS.map((st) => ({ ...st, kind: undefined })) }) }, 'wren')));
show('…a look\'s: the prototype, for a module that shows it beside the list to answer', act(teamNote({ name: 'Wren',
  job: job('plan', { steps: STEPS.map((st) => (st.id === 'plan' ? { ...st, kind: 'pick' } : st)) }) }, 'wren')));
show('…the lead\'s next, for a member: to the member\'s session, by its name',
     act(teamNote({ ...lead.team, next: { short: 'Try the dark theme', priority: 'p1', for: 'wren' } }, 'lead',
                  (id) => (id === 'wren' ? 'Wren' : ''))));
show('…for a member not listed: the lead\'s own session',
     act(teamNote({ ...lead.team, name: 'Atlas', next: { short: 'Try the dark theme', priority: 'p1', for: 'gone' } },
                  'lead', () => '')));
show('a job at work: none', teamNote(bea.team));
show('no job: none', teamNote(moss.team));
// Where its job stands, while nothing of it waits on you: quiet, in a few words, without the row's Deploy.
const standing = (status, kind) => teamStatusNote(status, kind);
show('queued, with words of its own', standing({ stage: 'queued', words: 'after the search box', title: 'Fonts' }));
show('parked, without words: the stage alone, never its title', standing({ stage: 'parked', title: 'Font picker' }));
show('at work, with its short', standing({ stage: 'work', words: 'Pick the fonts', title: 'Fonts' }).html);
show('…at work on a step: the board\'s word for it, never Moving',
     standing({ stage: 'work', word: 'Build', words: 'Pick the fonts' }).html);
const reviewing = { stage: 'work', doing: 'Reviewing', words: 'the list fix' };
show('busy with something apart from its jobs, in the file\'s word for it', standing(reviewing).html);
show('…which only a stage under way takes', standing({ ...reviewing, stage: 'queued' }).html);
show('…and its details', teamStatusCardHTML({ ...moss, team: { ...moss.team, status: reviewing } }, NOW));
show('…as its note', noteHTML(standing({ stage: 'queued', words: 'after the search box' }), ''));
show('words that are markup are shown as text', standing({ stage: 'queued', words: '<b>soon</b>' }).html);
show('…none while the session asks you something itself', standing({ stage: 'queued', words: 'later' }, 'needs'));
show('…none for a stage it doesn\'t know', standing({ stage: 'done' }));
show('waiting its turn: its step\'s own word, quietly', standing({ stage: 'waiting', word: 'Ready to try',
                                                                  title: 'Fonts' }));
show('…with words of its own',
     standing({ stage: 'waiting', word: 'Ready to try', words: 'after the search box' }).html);
show('…a step with no word: Waiting', standing({ stage: 'waiting', title: 'Fonts' }).html);
show('…the board says it in the same words', [core.teamJob.stageWord('waiting'), core.teamJob.stageWord('queued')]);
show('…and a priority in the same words and colours, one it doesn\'t know as P1',
     ['critical', 'p0', 'p1', 'p2', 'someday'].map((p) => `${core.teamJob.priorityWord(p)} ${core.teamJob.doNow(p)}`));
show('a job waiting on you keeps its ask\'s line', said(teamNote({ ...wren.team,
  status: { stage: 'work', words: 'Try the search box', you: true } })).cls);
show('a short that is markup is shown as text', said(teamNote({ job: job('test', { short: '<b>now</b>' }) })).html);
const nextUp = { short: 'Try the dark theme', ask: 'Try the dark theme at night, and say if it\'s easy to read',
                 priority: 'p1', job: 'j7', title: 'Dark theme' };
const leadNext = { ...lead.team, next: nextUp };
show('the lead, naming what\'s next for you: that, as a member\'s ask', said(teamNote(leadNext)));
show('…P0', said(teamNote({ ...leadNext, next: { ...nextUp, priority: 'p0' } })));
show('…said with an end given to it', noteHTML(said(teamNote(leadNext)), '[Deploy]'));

section('A job\'s track (trackHTML)');
show('at the start, waiting on you', trackHTML(job('plan'), 'normal'));
show('waiting on your try, urgent', trackHTML(job('test'), 'urgent'));
show('at work', trackHTML(job('build'), trackNow(job('build'), 'busy')));
const twelve = Array.from({ length: 12 }, (_, i) => ({ id: `s${i}`, word: i === 11 ? 'Done' : `Step ${i + 1}`, you: false }));
show('a board of twelve, at its last step: the same one bar, where it stands said in words',
     trackHTML(job('build', { steps: twelve, at: 's11', you: false }), 'idle'));
show('a track of one step from the row part itself: nothing, wherever it\'s drawn', stepTrackHTML(1, 0, 'normal'));
show('a job of one step: no track, as a track of one says nothing',
     trackHTML(job('build', { steps: [{ id: 'only', word: 'Pick one', you: true }], at: 'only', you: true }), 'normal'));
show('at work, its session idle', trackNow(job('review'), 'idle'));
// A step after review that waits its turn ("Ready to try"): nobody works on the job there.
const readyJob = job('review', { at: 'ready', waits: true, steps: [...STEPS.slice(0, 3),
  { id: 'ready', word: 'Ready to try', you: false, waits: true }, ...STEPS.slice(3)] });
show('waiting its turn: idle, even while its session works on something else', [trackNow(readyJob, 'busy'),
                                                                               trackNow(readyJob, 'idle')]);

section('Its details, rested on (teamCardHTML)');
show('waiting on you', teamCardHTML(wren, NOW));
show('at work', teamCardHTML(bea, NOW));
show('one of yours', teamCardHTML(dark, NOW));
show('waiting its turn: its step, and waiting rather than moving',
     teamCardHTML(session({ sessionId: 'moss', name: 'Moss',
                            team: { role: 'member', name: 'Moss', job: readyJob } }), NOW));
show('a P0 one, its ask in the colour of something to put right', teamCardHTML(session({ sessionId: 'dark',
  name: 'dark mode', team: { role: 'followed', name: 'dark mode',
    job: job('merge-yes', { title: 'Dark mode', priority: 'p0', ask: 'Say yes to merging it today.' }) } }), NOW));

show('a long title: a short head in bold, the rest in the body\'s weight, cut at a word', teamCardHTML(session({
  sessionId: 'long', name: 'grouped list', team: { role: 'followed', name: 'grouped list',
    job: job('plan', { title: ('Grouped list: let the list grow by adding a bit more each time a member joins, and '
      + 'keep its headers where they were, so nothing moves under the pointer while you read it, and grow by adding '
      + 'a bigger room').slice(0, 200) }) } }), NOW));

show('the lead, naming what\'s next for you', teamNextCardHTML({ ...lead, team: leadNext }));
const parkedMoss = { ...moss, team: { ...moss.team, status: { stage: 'parked', words: 'until the fonts land',
                                                              title: 'Font picker', stageAt: min(90) } } };
show('a member whose job is parked: where it stands and for how long, the job, and its words',
     teamStatusCardHTML(parkedMoss, NOW));
show('…P0, with no job named', teamNextCardHTML({ ...lead, team: { ...lead.team,
  next: { short: 'Say yes to the fix', ask: 'Say yes to the crash fix today', priority: 'p0' } } }));
show('…with an ask over 120 characters: its short as the title, the whole ask under it, never cut',
  teamNextCardHTML({ ...lead, team: { ...lead.team, next: { short: 'Try the grouped list', priority: 'p1',
    ask: 'Try the grouped list with a dozen members on a short screen, fold and unfold each group a few times, and say '
      + 'whether the headers stay where they were while you read' } } }));
show('…with no ask: its short', teamNextCardHTML({ ...lead, team: { ...lead.team,
  next: { short: 'Look at the list', priority: 'p2' } } }));

section('A team\'s row (rowHTML)');
// What a row shows, line by line: its classes, then each part's own class.
const lines = (html) => [...html.matchAll(/<(?:div|span) class="([^"]*)"/g)].map(([, cls]) => cls)
  .filter((cls) => /^(row |name|line1|you|claude|perm|card-title|work|step-note|where|tag ttag|tpart|step-track|tag wtag|tsum|time)/
    .test(cls))
  .join(' | ');
const kindNow = (s) => classify(s, NOW, view());
const nameOf = (html) => html.match(/<span class="name">([^<]*)<\/span>/)[1];
show('the lead: Chief, its reply not read yet, and its counts', lines(rowHTML(lead, kindNow(lead), NOW)));
const leadRead = { ...lead, onItAt: min(1) };
show('…its reply read: its counts alone', lines(rowHTML(leadRead, kindNow(leadRead), NOW)));
const withNext = { ...lead, team: leadNext };
show('…naming what\'s next for you: that on its second line, and only Chief beside its name',
     lines(rowHTML(withNext, kindNow(withNext), NOW)));
const nextAsHTML = rowHTML(withNext, kindNow(withNext), NOW);
show('…in the colour of your move, and with a card', /step-note notice inline turn ask-note task ask-normal/.test(nextAsHTML)
     && / tjob/.test(nextAsHTML));
const urgentNext = { ...lead, team: { ...leadNext, next: { ...nextUp, priority: 'p0' } } };
show('…P0: in the colour of something to put right',
     rowHTML(urgentNext, kindNow(urgentNext), NOW).match(/step-note notice inline[^"]*/)[0]);
show('…without it: no card', / tjob/.test(rowHTML(lead, kindNow(lead), NOW)));
show('the session you talk to: the name it shows, Chief beside it, and no second line of the team\'s',
     `${nameOf(rowHTML(front, kindNow(front), NOW))} · ${lines(rowHTML(front, kindNow(front), NOW))}`);
show('…the one running the team behind it: no mark, its reply not read yet, and its counts', lines(rowHTML(behind, kindNow(behind), NOW)));
const taggedLead = { ...behind, team: { ...behind.team, tag: 'lead' } };
show('…with a tag from the file: that, in the same look', lines(rowHTML(taggedLead, kindNow(taggedLead), NOW)));
const designer = tagged(wren, 'Design', 'Juniper');
show('a member with a tag and a shown name: that name, and its tag where its part would be',
     `${nameOf(rowHTML(designer, kindNow(designer), NOW))} · ${lines(rowHTML(designer, kindNow(designer), NOW))}`);
const tagOnly = tagged(bea, 'Design');
show('…a tag and no shown name: its name in the team', `${nameOf(rowHTML(tagOnly, kindNow(tagOnly), NOW))} · `
  + rowHTML(tagOnly, kindNow(tagOnly), NOW).match(/<span class="tag ttag">[^<]*<\/span>/)[0]);
const shownOnly = { ...bea, team: { ...bea.team, shown: 'Bea Billing' } };
show('…a shown name and no tag: that name, and its part', `${nameOf(rowHTML(shownOnly, kindNow(shownOnly), NOW))} · `
  + rowHTML(shownOnly, kindNow(shownOnly), NOW).match(/<span class="tpart">[^<]*<\/span>/)[0]);
const markupTag = tagged(bea, '<b>x</b>', '<i>y</i>');
show('…a tag and a shown name in markup: drawn as text', `${nameOf(rowHTML(markupTag, kindNow(markupTag), NOW))} · `
  + rowHTML(markupTag, kindNow(markupTag), NOW).match(/<span class="tag ttag">[^<]*<\/span>/)[0]);
// What's next changing: the new words count as just shown.
state.shownAt['compact:lead'] = min(10);
rowHTML(withNext, kindNow(withNext), NOW);
show('…what\'s next changing counts as just shown', justShown('compact:lead'));
const asking = { ...lead, status: 'waiting', notice: 'Claude needs your permission' };
show('…but asking you something itself: Claude\'s line says what', lines(rowHTML(asking, kindNow(asking), NOW)));
const dotOf = (s) => rowHTML(s, kindNow(s), NOW).match(/<div class="row ([^"]*)"/)[1];
show('dots: the lead, jobs waiting on you, its reply not read', dotOf(lead));
show('dots: …its reply read, jobs still waiting', dotOf(asSent({ ...lead, seenAt: min(1) })));
show('dots: a member whose job waits on you, its reply not read', dotOf(wren));
show('dots: …its reply read, the job still on its line', dotOf(asSent({ ...wren, seenAt: min(1) })));
show('dots: a member at work keeps its own', dotOf(bea));
show('dots: one of yours whose P0 job waits on you, with no reply', dotOf(dark));
show('dots: a member with nothing waiting', dotOf(moss));
// A row whose job is queued: its line where its job stands, with no Deploy at its end, where an ask to try has it.
const queuedMoss = { ...moss, team: { ...moss.team, status: { stage: 'queued', words: 'after the search box' } } };
core.slots.placeEnd.push(() => '[Deploy]');
show('a member whose job is queued: its line, quiet', lines(rowHTML(queuedMoss, kindNow(queuedMoss), NOW)));
show('…without the row\'s Deploy', rowHTML(queuedMoss, kindNow(queuedMoss), NOW).includes('[Deploy]'));
const tryDeploy = (row) => (row.askWant === 'try' ? '[Try Deploy]' : '');
core.slots.askAct.push(tryDeploy);
show('…where a job waiting on your try has Deploy as its one action, and no other',
     rowHTML(wren, kindNow(wren), NOW).match(/\[(Try )?Deploy\]/g));
core.slots.askAct.pop();
core.slots.placeEnd.pop();
// A member's plan waiting in its tab: its bubble ends in the button that opens the plan beside the list (the reader's,
// askAct 'plan'), and Claude Code's small plan card steps aside; its yes to a merge, with no plan waiting, keeps the
// team's own button, to its session.
const planWren = { ...wren, sessionId: 'plan-wren', status: 'waiting', statusUpdatedAt: min(1),
  ask: { id: 'pw', tool: 'ExitPlanMode', at: min(1), digest: 'd1', input: { plan: '# Search box\n\n1. A box' } },
  team: { ...wren.team, job: job('plan', { short: 'Approve the search plan' }) } };
const planWrenHTML = rowHTML(planWren, kindNow(planWren), NOW);
show('a member\'s plan waiting in its tab: the reader\'s plan button, and no plan card [button, card]',
     [planWrenHTML.includes('data-wr-act="plan-wren"'), planWrenHTML.includes('plan-ask')]);
const yesWren = { ...wren, sessionId: 'yes-wren', team: { ...wren.team, job: job('merge-yes') } };
show('…its yes to a merge, no plan waiting: the team\'s own button, to its session',
     rowHTML(yesWren, kindNow(yesWren), NOW).includes('data-team-go="yes-wren"'));
// A member at work on one job while another waits on your try (the app's `alsoAsks`): the row's track is the job it's
// at, and its line the try's ask, the same bubble as its own job's would be (its priority's name, its words), ending in
// Deploy as its one action; it counts among what waits on you. The job's details open from its track, never from the
// bubble (`talso`), as they're the job at work's.
const teamCard = core.cards.find((c) => c.selector.includes('tstatus')).selector.split(', ');
// Whether the details open from an element with these classes: a selector's last part names classes it must all have.
const opensFrom = (classes) => teamCard.some((sel) => sel.split(/[\s>]+/).at(-1).split('.').filter(Boolean)
  .every((c) => classes.split(' ').includes(c)));
const busyWren = { ...bea, sessionId: 'busy-wren', team: { ...bea.team, name: 'Wren', status: { stage: 'work',
  word: 'Build', job: 'j1' }, alsoAsks: { job: 'j2', title: 'Faster sync', short: 'Try the sync', at: 'test',
  priority: 'p0', kind: 'try' } } };
core.slots.placeEnd.push(() => '[Deploy]');
core.slots.askAct.push(tryDeploy);
const busyWrenHTML = rowHTML(busyWren, kindNow(busyWren), NOW);
show('a member at work with another job waiting on your try: its ask\'s bubble', lines(busyWrenHTML));
show('…its priority\'s name and its words, never "Also waiting on you"',
     [bubble(teamNote(busyWren.team, 'busy-wren')), said(teamNote(busyWren.team, 'busy-wren')).html,
      busyWrenHTML.includes('Also waiting on you')]);
show('…Deploy as its one action, and its track at work', [busyWrenHTML.match(/\[(Try )?Deploy\]/g),
  busyWrenHTML.match(/step-now [^"]*/)[0]]);
const busyNote = busyWrenHTML.match(/<div class="(step-note[^"]*)"/)[1];
show('…its details from the track, never the bubble', [opensFrom('step-track'), busyNote, opensFrom(busyNote)]);
core.slots.askAct.pop();
core.slots.placeEnd.pop();
const planAsk = teamNote({ ...busyWren.team, alsoAsks: { ...busyWren.team.alsoAsks, at: 'plan', kind: 'approve' } },
                         'busy-wren');
show('…a plan\'s: the reader\'s want, and the plan\'s button, to its session, where nothing answers it',
     [act(planAsk), planAsk.act.html.includes(core.taskKinds.act('approve').icon)]);
// …its plan or looks open beside the list, as its own job's would, whether its session has stopped or works on: one
// shape and one press, what opens saying when it's only to read.
show('…a plan\'s or looks\': the want for the reader [plan, look]',
     [teamNote({ ...busyWren.team, alsoAsks: { ...busyWren.team.alsoAsks, at: 'plan', kind: 'approve' } }, 'busy-wren')
       .act.want,
      teamNote({ ...busyWren.team, alsoAsks: { ...busyWren.team.alsoAsks, at: 'plan', kind: 'pick' } }, 'busy-wren')
       .act.want]);
const leftPlan = [{ id: 'sync-plan', kind: 'plan', title: 'Faster sync', at: min(2), status: 'waiting' }];
const stoppedWren = (status, writings = leftPlan) => ({ ...busyWren, sessionId: 'stopped-wren', status,
  statusUpdatedAt: min(1), lastPromptAt: min(3), writings,
  team: { ...busyWren.team, alsoAsks: { ...busyWren.team.alsoAsks, at: 'plan', kind: 'approve' } } });
const stoppedEnd = (status, writings) => {
  // What the list says each row is, as it does before drawing them (state.kinds).
  const kindsBefore = state.kinds, kind = kindNow(stoppedWren(status, writings));
  state.kinds = { 'stopped-wren': kind };
  const html = rowHTML(stoppedWren(status, writings), kind, NOW);
  state.kinds = kindsBefore;
  return html.includes('data-wr-act="stopped-wren"') ? 'the reader\'s plan button'
    : html.includes('data-team-go="stopped-wren"') ? 'to its session' : 'none';
};
show('…its plan left waiting, at its own prompt, idle, in its shell, and working: [reader, reader, reader, reader]',
     ['waiting', 'idle', 'shell', 'busy'].map((status) => stoppedEnd(status)));
show('…working, its newest plan sent back, and approved (the work it\'s doing): [reader, session]',
     [stoppedEnd('busy', [{ ...leftPlan[0], status: 'declined' }]),
      stoppedEnd('busy', [{ ...leftPlan[0], status: 'approved' }])]);
// Working is what the list says of the row: one whose turn has ended while its agents work in the background isn't.
const backgroundWren = { ...stoppedWren('idle', [{ ...leftPlan[0], status: 'declined' }]),
  background: [{ type: 'agent', holds: 1 }] };
const kindsBeforeBackground = state.kinds;
state.kinds = { 'stopped-wren': kindNow(backgroundWren) };
show('…its turn ended, its agents at work in the background, its newest plan sent back: [kind, nothing to read here]',
     [state.kinds['stopped-wren'], rowHTML(backgroundWren, kindNow(backgroundWren), NOW)
       .includes('data-team-go="stopped-wren"')]);
state.kinds = kindsBeforeBackground;
const goAsk = teamNote({ ...busyWren.team, alsoAsks: { ...busyWren.team.alsoAsks, kind: undefined } }, 'busy-wren');
show('…a step with no kind: ↗ to its session', [act(goAsk), goAsk.act.html.includes(OUT_ICON)]);
const bothAsk = teamNote({ ...wren.team, alsoAsks: busyWren.team.alsoAsks }, 'wren');
show('…its own job waiting on you too: its own job\'s ask', [bothAsk.cls, bubble(bothAsk),
  bothAsk.html.match(/ask-line-words">([^<]*)/)[1], bothAsk.act.want]);
const tidyMoss = { ...moss, status: 'busy', statusUpdatedAt: min(0), lastPromptAt: min(0) };
show('…newest first among the team all the same, nothing lifted',
     outline(groupsHTML(listGroups(placeAll([lead, tidyMoss, busyWren])), NOW)));
show('…as without it', outline(groupsHTML(listGroups(placeAll([lead, tidyMoss,
  { ...busyWren, team: { ...busyWren.team, alsoAsks: undefined } }])), NOW)));
show('…a try with no words: where its job stands', stepLine({ s: { ...busyWren, team: { ...busyWren.team,
  alsoAsks: { job: 'j2', short: '' } } }, kind: 'busy', brief: true }));
show('…while the session asks you something itself: its ask still, as its own job\'s would be',
     stepLine({ s: busyWren, kind: 'needs', brief: true }).cls);
// Any other module's note on the row comes first: the status line is asked only after every module's own (rowNotesLast).
core.rowNotes.push((row) => (row.s.sessionId === queuedMoss.sessionId ? { text: 'Deploying: building' } : null));
show('…another note on the row comes first', stepLine({ s: queuedMoss, kind: kindNow(queuedMoss), brief: true }).text);
core.rowNotes.pop();
// A session's own task in One Task (its module's row note): in place of where a member's job stands, a try with
// Deploy as its one action, as the team's ask has; the team's own line, where it has one, comes first.
const lastBefore = state.last;
const ownTask = (sessionId, id) => ({ sessionId, at: min(2), sent: min(2),
                                      task: { id, kind: 'try', title: 'Search on a phone', why: 'w' } });
setTasks([ownTask('moss', 'm1'), ownTask('wren', 'w1'), ownTask('lead', 'l1')], true,
         { try: 'Try', pick: 'Pick', approve: 'Approve', answer: 'Answer', run: 'Run', do: 'Do', seen: 'Seen' });
state.last = { sessions: [queuedMoss, wren, lead], now: NOW };
for (const draw of core.beforeDraw) draw(state.last.sessions);
core.slots.askAct.push(tryDeploy);
const mossTask = rowHTML(queuedMoss, kindNow(queuedMoss), NOW);
show('a member whose job is queued, with a task of its own: the task\'s line in place of its status', lines(mossTask));
show('…with Deploy at its end as its one action, outside the line\'s press',
     /<\/span>\[Try Deploy\]<\/div>/.test(mossTask) && /data-one-task="task:moss:m1"/.test(mossTask));
// The job's details open from the team's own line only (`.step-note.task`, `.step-note.tstatus`).
show('…its job\'s details don\'t open from it', mossTask.match(/<div class="(step-note[^"]*)"/)[1]);
show('a member whose job waits on you, with a task too: the team\'s ask', lines(rowHTML(wren, kindNow(wren), NOW)));
show('the lead with its counts, and a task of its own: its counts, under its reply not read yet', lines(rowHTML(lead, kindNow(lead), NOW)));
core.slots.askAct.pop();
setTasks([], true);
state.last = lastBefore;
for (const draw of core.beforeDraw) draw(state.last?.sessions || []);
show('a member: its name in the team, its part, its track, its time, and its ask, no chat',
     lines(rowHTML(wren, kindNow(wren), NOW)));
show('…named as the team names it, not its tab', nameOf(rowHTML(wren, kindNow(wren), NOW)));
show('a member at work: one line, with its time', lines(rowHTML(bea, kindNow(bea), NOW)));
// What another module puts after the title's words (a stand-in here) sits before the row's gap, so the track keeps
// its place at the line's end.
core.slots.titleEnd.push(() => '<span class="stub-end"></span>');
show('…with another module\'s part after its words: words, that part, the gap, the track, the time',
     [...rowHTML(bea, kindNow(bea), NOW).match(/<div class="line1">[\s\S]*?<\/div>/)[0]
       .matchAll(/<span class="(name|tpart|title-end|title-gap|step-track|time)"/g)].map(([, cls]) => cls).join(' | '));
core.slots.titleEnd.pop();
// The lead's row with the team board's Team Board and Side Chat (their own modules' parts, as the page draws them):
// Team Board after Lead on its title line, and Side Chat in the strip at the row's far edge, off its lines,
// whether it has a second line (its counts) or not; neither moves the time.
state.board = { teams: [{ project: '/Users/you/shop', lead: { session: 'lead', name: 'Atlas' },
                          chief: { session: 'lead', name: 'Atlas' }, jobs: [] }], kinds: [] };
const leadRow = (html) => [...html.matchAll(/<(?:div|span|button)[^>]*? class="([^"]*)"/g)]
  .map(([, cls]) => (cls.startsWith('step-note') ? 'step-note' : cls.split(' ').find((c) => /^(line1|name|ttag|bd-open|title-end|title-gap|sc-edge|time)$/.test(c))))
  .filter(Boolean).join(' | ');
const runningLead = { ...lead, pid: 4242 };
show('the lead\'s row: Lead and Team Board on its title line, Side Chat in its room, off its lines',
     leadRow(rowHTML(runningLead, kindNow(lead), NOW)));
const quietLead = { ...runningLead, team: { ...lead.team, counts: { waiting: {}, working: 0 } } };
show('…with no second line: the same, nothing between its title\'s words and the time',
     leadRow(rowHTML(quietLead, kindNow(quietLead), NOW)));
state.board = null;
show('the row you\'re on: the same, and its bottom line under it', lines(rowHTML({ ...wren, focused: true }, kindNow(wren), NOW)));
const asks = { ...bea, status: 'waiting', ask: { id: 'a1', tool: 'Bash', input: { command: 'make' }, at: min(1) } };
show('a session asking you itself: its card, which says what it asks', lines(rowHTML(asks, kindNow(asks), NOW)));
show('a writing\'s tag after its part, as on any row',
     lines(rowHTML({ ...moss, writings: [{ id: 'w1', kind: 'notes', title: 'Notes', path: '/w/n.md', at: min(3) }] },
                   kindNow(moss), NOW)));
show('one of yours with a job: its track and its ask', lines(rowHTML(dark, kindNow(dark), NOW)));
show('one of yours with a reply not read yet: Claude\'s line', lines(rowHTML(plain, kindNow(plain), NOW)));
show('another session in a member\'s folder: saying whose', lines(rowHTML(visitor, kindNow(visitor), NOW)));
show('…in words', rowHTML(visitor, kindNow(visitor), NOW).match(/<span class="tpart">[^<]*<\/span>/)[0]);
// Another session running in a member's own workspace while one holds its seat: a duplicate, the later one or the
// earlier, saying which session is on the member's row when the app knows its name.
const twin = session({ sessionId: 'twin', name: 'fix tooltips',
                       team: { inFolderOf: 'Wren', duplicate: true, earlier: false, seat: 'search-box-tab' } });
const twinFirst = { ...twin, sessionId: 'twin-first', team: { ...twin.team, earlier: true } };
const twinUnnamed = { ...twin, sessionId: 'twin-unnamed', team: { inFolderOf: 'Wren', duplicate: true, earlier: false } };
show('a duplicate in a member\'s workspace: under yours, its mark and its line',
     lines(rowHTML(twin, kindNow(twin), NOW)));
show('…its mark and its tip', rowHTML(twin, kindNow(twin), NOW).match(/<span class="tpart"[^>]*>[^<]*<\/span>/)[0]);
show('…the earlier of the two: close this one',
     lines(rowHTML(twinFirst, kindNow(twinFirst), NOW)) + ' / '
     + rowHTML(twinFirst, kindNow(twinFirst), NOW).match(/title="[^"]*"/)[0]);
show('…the session on the member\'s row not known by name',
     rowHTML(twinUnnamed, kindNow(twinUnnamed), NOW).match(/title="[^"]*"/)[0]);
show('…its line, a class of its own, quiet, with no Deploy', JSON.stringify(duplicateNote(twin.team)));
core.rowNotes.push((row) => (row.s.sessionId === 'twin' ? { text: 'Deploying: building' } : null));
show('…another module\'s note on the row comes first', stepLine({ s: twin, kind: kindNow(twin), brief: true }).text);
core.rowNotes.pop();
show('…grouped: left for its project', teamShown(placeAll([wren, twin, twinFirst]))
  .map((g) => `${g.name}: ${g.rows.map((p) => p.s.sessionId)}`));
// A chat beside the folded panel: the row whole, as without the team, saying what's new.
const asChat = (s) => rowHTML(s, kindNow(s), NOW, { chat: true });
show('a chat: the lead, its reply, not its counts', lines(asChat(lead)));
show('a chat: one of yours with a reply, the reply', lines(asChat(plain)));
show('a chat: a member, under its name in the team, with no track or ask line', lines(asChat(wren)));
show('…named', nameOf(asChat(wren)));
// The list's row and its chat drawn in turn, as each update draws both: the row's buttons stay as long shown as they
// were, and what the row last showed stays as it was.
rowHTML(wren, kindNow(wren), NOW);
state.shownAt['compact:wren'] = Date.now() - 60000;  // on the page's own clock, a minute ago
const briefBefore = JSON.stringify(state.teamAsks);
asChat(wren);
rowHTML(wren, kindNow(wren), NOW);
asChat(wren);
show('…the list\'s row and its chat in turn: what the row last showed is left as it was',
     JSON.stringify(state.teamAsks) === briefBefore);
show('…and its buttons aren\'t taken as just shown again', !justShown('compact:wren'));
state.shownAt['team-act:wren'] = Date.now() - 60000;
rowHTML(wren, kindNow(wren), NOW);
asChat(wren);
show('…nor its ask\'s button, the chat leaving it as the row drew it', !justShown('team-act:wren')
     && 'team-act:wren' in state.shownAt);
// The ask's button waits to be seen again when it's for another step of the job, though it's drawn in the same place.
const wrenAt = (at) => ({ ...wren, team: { ...wren.team, job: { ...wren.team.job, at, short: undefined } } });
rowHTML(wrenAt('plan'), kindNow(wren), NOW);
state.shownAt['team-act:wren'] = Date.now() - 60000;
rowHTML(wrenAt('plan'), kindNow(wren), NOW);
const stillSeen = !justShown('team-act:wren');
rowHTML(wrenAt('merge-yes'), kindNow(wren), NOW);
show('…its ask\'s button for another step: [seen while it stays, just shown once it moves on]',
     [stillSeen, justShown('team-act:wren')]);
// And when a member at work has another of its jobs waiting on you, when that's another job, though its button is the
// same.
const busyAt = (job) => ({ ...busyWren, team: { ...busyWren.team,
  alsoAsks: { ...busyWren.team.alsoAsks, job, at: 'plan', kind: 'approve' } } });
rowHTML(busyAt('j2'), kindNow(busyWren), NOW);
state.shownAt['team-act:busy-wren'] = Date.now() - 60000;
rowHTML(busyAt('j2'), kindNow(busyWren), NOW);
const busySeen = !justShown('team-act:busy-wren');
rowHTML(busyAt('j3'), kindNow(busyWren), NOW);
show('…the other job\'s button for another job: [seen while it stays, just shown once it changes]',
     [busySeen, justShown('team-act:busy-wren')]);
// A second line that's new: what's on it counts as just shown.
state.shownAt['compact:moss'] = min(10);  // any of the row's first-shown times
rowHTML(moss, kindNow(moss), NOW);
const asked = { ...moss, team: { ...moss.team, job: job('test') } };
rowHTML(asked, kindNow(asked), NOW);
show('a second line coming: what is on the row counts as just shown', justShown('compact:moss'));
// A note coming on a row with a part at its note's end (Deploy, say): what's on the row counts as just shown, once.
const ending = (row) => (row.s.sessionId === 'bea' ? '[end]' : '');
core.slots.placeEnd.push(ending);
rowHTML(bea, kindNow(bea), NOW);
state.shownAt['compact:bea'] = 1;  // long ago, by the page's own clock
state.stepNotes.bea = { text: 'Deploying: building', at: Date.now() };
show('a note coming with a part at its end: what is on the row counts as just shown',
     rowHTML(bea, kindNow(bea), NOW).includes('[end]') && justShown('compact:bea'));
state.shownAt['compact:bea'] = 1;
rowHTML(bea, kindNow(bea), NOW);
show('…drawn again with it: not any more', justShown('compact:bea'));
delete state.stepNotes.bea;
core.slots.placeEnd.splice(core.slots.placeEnd.indexOf(ending), 1);
show('a session the team follows, and one in a member\'s folder: short rows, with what of the team they have',
     lines(rowHTML(dark, kindNow(dark), NOW)) + ' / ' + lines(rowHTML(visitor, kindNow(visitor), NOW)));
show('a session of no team: a short row too, nothing of the team on it', lines(rowHTML(plain, kindNow(plain), NOW)));
