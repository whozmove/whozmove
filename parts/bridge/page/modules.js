// What the panel's modules plug into the page with. A module's scripts (tools/page.sh lists them, from its module.json)
// only register here as they load. The core then runs them: their start-up once every script has loaded, their part of
// each update, each fold, each row and each press (app-calls.js, panel.js, rows.js, input.js, …). So a module never
// acts before the page is whole, and never needs to name another module. Each list holds the modules' entries; the
// core's own are in its scripts.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const core = {
  // Starting, the updates from the app, and folding to the header (app-calls.js, panel.js).
  starts: [],          // run once every script has loaded, in the order they were added
  updating: [],        // (sessions) with each update from the app, before the list is drawn again
  updates: [],         // (now) with each update from the app, once the list is drawn
  collapses: [],       // (collapsed) when the panel folds into the cat, or opens again

  // The list (panel.js, morph.js).
  moreRows: [],        // (listed) → sessions to draw with the app's: ones it hasn't listed yet
  beforeDraw: [],      // (listed) once what each session is (state.kinds) and where it's shown are known, before the
                       // list is drawn
  drawn: [],           // (list) as soon as the list's new HTML is in, before anything measures it
  afterDraw: [],       // () once the list is drawn and what's under the pointer looked at again
  // Groups of a module's own above the projects (the list is always its projects, A to Z): each (placed) → { groups,
  // rest } or null. `groups` in order, each { key, name, rows } with a key of its own among every group's
  // (what keeps it folded), its name (null for rows on top with no header) and its rows in the order they were placed;
  // `rest`, the placed rows it leaves for the projects. A row in neither isn't shown (one the module hides). A row
  // marked `waits` waits on you in the module's own way, and stays in view while its group is folded. Null while the
  // module has nothing to group, when the next one is asked, and in the end every row goes under its project.
  topGroups: [],
  // (s) → whether the session's last reply went to another session rather than to you (whose-move.js): it then counts
  // as read, so it never waits on you.
  repliesElsewhere: [],
  // (s) → whether nothing in the session is yours to read, as a module says (whose-move.js): none of its replies waits
  // on you, not even one kept to read from before. Only a module's word makes a conversation so, never a default.
  notYoursToRead: [],

  // A row (rows.js). `row` is { s, kind, now, owner, clock, chat }, and what the modules' looks add to it: `kind` is
  // what the session is now (classify), and `chat` says it's drawn as a chat beside the folded panel (chats.js), not in
  // the list.
  rowLooks: [],        // (row) a module's first look at a row, which keeps what it found on `row` for its parts. The
                       // row part has already said whether the row is shown briefly (`row.brief`: every row in the
                       // list but one still starting from the panel; a chat beside the folded panel is drawn whole,
                       // and takes that look as it lands there: landing.js): its title line (its brief slot's parts
                       // after the name, and `row.name` in place of the session's, if set), Claude's line only where
                       // nothing else says it, its card and its note, the row marked `brief`; and whether that row
                       // keeps its work line and bottom line all the same (`row.tools`: the row you're on)
  // The cards that can show under a row's chat, one at a time: { name, order, wants(row), html(row), away(row),
  // close(sid) }. The most pressing (lowest order) that wants to show does; the others are away.
  rowCards: [],
  rowNotes: [],        // (row) → { text, quiet, tone, cls, html, end, line } or null: the row's note, when the core has
                       // none (`tone` 'turn' for your move's colour rather than something to put right, giving way to
                       // any other, `cls` a class of the module's own for its layout, `html` said in place of `text`,
                       // made safe by it, `line` for a line of its own rather than the work line's place); on a row
                       // shown briefly, the bottom line's end (placeEnd) goes at its end, unless `end` is false; an
                       // ask line (`cls` 'ask-note', on a line of its own) is a bubble coloured by `look` (urgent,
                       // normal or low), ending in its one action, `act` { want, html } (askAct)
  rowNotesLast: [],    // (row) → the same, asked only when no other note answers: one that says where things stand,
                       // quietly, giving way to any other
  // What a module adds to the new conversation card (the starts module's), each { name, chip(card), list(card),
  // placeholder(card), press(target, card, api), typed(card, el, api), keys(card, event, api), words(card), with(card),
  // sent(card) }, each optional: a chip after where it starts; a list under the box (`.st-plist`, shown while the
  // card's own list isn't), whose field (`.st-field`, a child of it, `data-part` its name) stays put as the list comes
  // in afresh around it; the box's words while it says something; a press on the card it takes (true); what's typed in
  // its field or the box; a key in its field it takes (true); a line it adds to your words; what the start carries for
  // its module, by its name, handed to it once the start becomes a session (Module's started:with:); and that it was
  // sent. Then where it starts: `where(card)`, where the part would have it start, { name } (a worktree by its
  // branch's name: one that's there, the branch with no folder yet, or a new one), { path } (one of the repo's
  // folders) or { here } (its own), followed while you haven't picked where yourself, and let go of once the part has
  // none; `under(card, api)`, the line under the box in the card's own line's place (one element of class `c-under`),
  // while you haven't picked where yourself; `warn(card, api)`, { text, name }, a warning in the busy notice's place,
  // its Use a New Worktree giving the worktree named; and `boxKeys(card, event, api)`, a key in the box it takes
  // (true); and `waits(card, api)`, true while it's still finding out where it starts, which holds Start. Each of a
  // part's drawn pieces (chip, list, placeholder, words, under, warn) is handed `api` too. `api` is { refresh(),
  // focusBox(), place(), useHere(), start() }: place() is where the card would start now, { kind (here, open, branch,
  // new), name, where, path (for one that's there), trust (Start would also trust the folder), app (desktop or
  // terminal: the one it would start in in the project's own folder), followed, chosen, git, terminal (its name, or null) }; useHere() starts it in the
  // project's own folder, as your pick; start() is Start.
  startCardParts: [],
  // The places on a row's template, and on a project's header, each (row or project) → HTML: after the name; after the
  // title line's words (the name and the parts after it), and what lines up at its end, before the time; at the end of
  // Claude's line, after its words (and its time while it works), moving with them as they change, only while the row
  // has that line; the work line's start (the pull requests), its numbers and its steps at its end; the bottom line's
  // start (how the agent is set up) and its end, after where the session runs, which on a row shown briefly goes at its
  // note's end instead, and is drawn nowhere while the row asks something of you; an ask's one action, at its line's
  // end, for what the ask wants (`askAct`: row.askWant, as 'try' for Deploy, 'plan' and 'look' for the reader), the
  // first given standing in for the note's own; the project's header after its name; and after the name on a row shown
  // briefly (row.brief), in place of `name`. Before the title line's are asked, the row says whether it has Claude's
  // line (row.claudeLine), whether it asks something of you (row.asking) and for what (row.askWant), whether the
  // bottom line's end is drawn (row.placeEnd), and whether that end is drawn at its note's end (row.endAtNote: a row
  // shown briefly), so a module with one thing to show puts it in one place. Just before that end, what stays on the
  // bottom line whatever its end does (`placeStays`: Deploy's address, which must stay pressable there), asked only on
  // a full row's bottom line.
  // And the strip at the row's far edge (`edge`), the side the reader opens on, past the end of its lines: what's given
  // fills it, its look the row's bar, which swells while the pointer is on it (state.edgePointed); marked `.keep` it
  // keeps the bar lit (its chat open), and marked `.lit` it lights it in your move's colour (rows.js, rows.css).
  slots: { rowClass: [], name: [], titleEnd: [], titleTrail: [], chatEnd: [], workStart: [], numbers: [], steps: [],
           setup: [], placeStays: [], placeEnd: [], askAct: [], project: [], brief: [], edge: [] },

  // Pressing and typing (input.js).
  presses: [],         // [selector, press(target, event)]: a press on the list, checked before the core's own
  typing: [],          // [selector, typed(box, event)]: what's typed in a box on the list
  returns: [],         // [selector, returned(box, event)]: Return in one (else it presses its card's main button)
  escapes: [],         // [selector, escaped(box, event)]: Esc in one (else Esc does what it did before)
  textBoxes: [],       // the boxes outside the cards that take the keyboard while they're typed in (wantKeyboard)
  // Cards on a row that take the keyboard once pressed, so keys work on them (heldCard): { card, id(card), open(card),
  // takes(card, target), key(card, event) }: the card's selector, its id (found again by it as the list is rebuilt),
  // whether it still waits for you, whether a press on `target` in it takes the keyboard (not one that answers it), and
  // what a key does there (true if it did something; Return presses its main button, Esc lets go).
  keyCards: [],
  // The places beside the list where a module draws rows whose cards take keys that way (keyPlaces): elements, each
  // there while the rows in it can be answered, or { el, open(card, pressing) } where that's up to each card (whether
  // it can have the keys now, and with `pressing`, whether a press on it counts). A press holds the copy of a card in
  // the place it was in; a place drawn after the list shows that copy's edge with showHeldCard.
  keyPlaces: [],

  // The pointer (hover.js), and a row's details (parts/details).
  pointerTargets: [],  // more of what the pointer can point at
  pointerWatchers: [], // (el) each time what's under the pointer is looked at: what it's on, or null
  // A team's job, as the team module draws it, for what draws its jobs elsewhere (the team board): { track(job, kind) →
  // {count, at, look}, for stepTrackHTML; stageWord(stage) → where a job at that stage is, in the list's words (work,
  // queued, parked); priorityWord(priority) → Critical, P0, P1 or P2; priorityPlace(priority) → {at, of, look}, its
  // place in that ladder, 0 the most pressing, one it doesn't know as P1's, and its look (urgent, normal or low);
  // doNow(priority) → whether it's Critical or P0, drawn in the colour of something to put right }.
  teamJob: null,
  // The ticket on the new conversation card, as the module that gives sessions tickets has it, for the card's other
  // parts: () → { tracker, site, key }, or null while there's none, or one not made yet (Create a ticket).
  cardTicket: null,
  // Each kind of task as One Task does it, for what shows an ask of that kind elsewhere (a team's step): { act(kind) →
  // { icon, verb, does } (the kit's icon, its verb, and what a press does with the task in hand: 'copy', 'open',
  // 'read' or 'there'), or null for a kind it doesn't know }.
  taskKinds: null,
  // Your gear, as the usage module keeps it (modules/usage/page/gear.js), for what shows it beyond the card: facts() → what the app last said (app/contracts/Module.h's GearFacts says what's in it), null while unknown
  // or turned off; off() → whether Usage Gear is off in Settings, when nothing limits what starts; changed, a list of
  // (facts, pressed) each run after the app says it, `pressed` when your press on a seat made it; line(facts) →
  // { says, over }, the gear's line with its count, for what shows it without seats ("6 working", " · 2 over the
  // gear"); whyLine(facts, now) → one line in every state (the session at its limit, why it can't be measured yet, or
  // where the week ends at the gear); words, for what lists the sessions and what waits beside the gear: { overMark
  // ("Over the gear"), overSays (with what happens: it carries on, as the gear holds back only queued jobs waiting to
  // start), lineSays(gear) (the gear's line in words, for VoiceOver), where(facts) (where the gear is changed, said
  // where it shows without its seats, which are only on the usage card; with no gear, why nothing is let in, or that
  // nothing limits what starts) }. Every word is the usage module's. Null without the module.
  gear: null,
  // A plan at a glance, as the plans module draws it, for the places that show a plan (the reader, the plan card on a
  // row, One Task), each passing the plan's text as it has it:
  // - readerHTML(text, { sessionId, id, who, waiting, held }) → the reader's view (Skimmed: the card, then the plan
  //   folded by section; Full: the plan exactly as written, the toggle above it; held, your picks shown but not
  //   changed), or null to show it as before;
  // - cardLines(text, id) → the plan card's few lines from the plan's own block, saying how many picks you've changed
  //   on the request `id`, or null for its steps;
  // - taskHTML(text) → a task's view of the plan it asks you to approve, from its own block (with or without its
  //   heading): the card alone, bare, every choice as lines, nothing to press; or null;
  // - picks(id) → { changed, note }, how many of your picks on the plan the request `id` waits on differ from
  //   Claude's, and the notes that send them back; clearPicks(id);
  // - folded(sessionId, id) → whether that plan is shown folded beside the list (drawn by readerHTML, read Skimmed).
  // Null without the module: each place shows as before.
  plans: null,
  // Each agent's page module (Claude Code's): the plan a session's agent waits for your OK on, and how to answer it, so
  // the module that shows it beside the list (the reader) reads no agent's request and sends no agent's message. Each
  // pushes { of(s) → { id (what an answer goes to), at, text (as asked), path, whole (false: it came cut short, its
  // text not all of it), answerable (false: only its tab answers it), digest (of `text`, which Approve carries), whyNot
  // (why Approve beside the list can't be offered, in words, or ''), approval (how your last press of Approve went:
  // { why, at, again }, or null) }, or null while that agent's session waits on no plan; yours(s, id) → your Approve
  // of request `id` as its row says it went: 'pending', 'approved', 'notTaken' or null; approve(s, id, digest),
  // sendBack(s, id, message), stop(s, id) and hold(s, id) (being answered beside the list, so no session you allow
  // answers it meanwhile); and for a plan its session still waits on with no request for it up any more: left(s) →
  // { id (its writing's), held (only its session's own prompt can answer it) } or null, typeBack(s, id, words) (your
  // notes typed into the session as a message), and typed(s, id) → how that went: { state ('typing', 'typed' or
  // 'notTyped'), why, way } or null }. The first whose `of` (or `left`) answers for a session is the one that answers it.
  planAsks: [],
  cards: [],           // a row's details, opened as something is rested on: { selector, key(anchor), html(anchor) }

  // The header (parts/header) and the row you're on, held at the list's edge (sticky.js): what's measured from the
  // header's edge, placed again each time it moves; and how far the held row's copy has gone past where it folded all
  // it can at the list's top, once it's placed for the list's scroll, which pushes the header away.
  headerMoves: [],     // () each time the header moves
  heldPast: () => 0,

  // The panel's height (reportHeight, listHeight).
  strips: [],          // the ids of what's above or under the list (its strips), which the panel makes room for
  overhangs: [],       // () → how far down something hanging below the list reaches, or 0

  // The reader (reader.js): what it can show, by name ({ draw, … }), and the presses in it; and (body) each time it's
  // fitted, once its width is set and before what it shows is measured (fitReader), for what's drawn at the width it
  // has (a diagram).
  readerModes: {},
  readerPresses: [],
  readerDrawn: [],
  // Fenced blocks a module draws, by their language (markdown.js): (text, place) → HTML, made safe by it, or null to
  // show the block as code; `place` is 'reader' (beside the list) or 'list' (a card on a row). One module for each
  // language.
  fences: {},
  // Diagrams, as the diagrams module draws them, for the places that show Markdown: smallHTML(text) → a block's small
  // drawing, for a card; words(markdown) → what Markdown that's one diagram and nothing else says in words, or null;
  // says(text) → what a diagram's text says in words; firstFlow(markdown) → the text of its first flow with something
  // to show on a card (drawn, or its steps named), or null; draw(el) draws what's in `el` at the width it has, for a
  // place that measures it before the reader is fitted (a section growing open, a view put in again). Null without
  // the module.
  diagrams: null,

  // How the list moves (morph.js): how a row's lines move, by the line's selector, where a module's part needs more
  // than the morph part's ({ text, swap, shape, morph, grow, fold, still }: `still(el)` takes out of a copy of the line
  // what's only there while it moves, for the copy of the row you're on held at the list's edge, sticky.js), and the
  // bits of a row that cross-fade when their text changes.
  lines: {},
  swaps: [],

  // A step's note arriving for a session (stepNote): (session)
  noted: [],
  // What a note's button does on the page, by the name the app gives it (stepNote's `go`): (session). 'open' is the
  // core's own, opening the session.
  noteWays: {},

  // What the page keeps per session or request, forgotten a minute after it has gone from the list (forgetGone): the
  // state's keys, each an object by session or request id, and the prefixes of the cards' first-shown times in
  // state.shownAt ('compact:<id>').
  forgotten: { keys: [], prefixes: [] },

  // What an agent's details mean, for the parts that show them: { modelName, modeName, contextWindow, compactLimit,
  // askLine(ask), answeredLine(ask) }: what Claude's line on a row says while a request waits ("Wants to run a
  // command"), and on a chat beside the folded panel once you've answered it there, till it goes or the answer is
  // late ({ text, no }, or null).
  agent: {},

  // The apps sessions run in, as the page names them, each a module's (hostOf in rows.js): { holds(s), name, openNow,
  // inName, closedTip(s) (what a row that isn't running says a press does), project(s) }. A session none holds runs in
  // a terminal.
  hosts: [],

  // Notifications (the notifications module decides what shows, when and where). A notice's level is one of
  // `noticeLevels`, most first: 'urgent' (something stops or waits without you), 'soon' (something to do when you can)
  // or 'know' (nothing to do); its id is its sender and key ('storage/disk'). The places that show what it picks, by name, each filled by the part that
  // draws it, and each saying whether it would be seen now (`inSight()`), the app saying whether the panel is:
  // - `line`, the line under the header: { inSight(), show(line, more) }, the notice to show ({ id, level, text,
  //   button, pressedWord, busy, closes, done, tag }, or null) and how many more wait;
  // - `besideEdge`, Whozmove beside the panel at its edge (parts/beside): { inSight(), show(count) }, how many need
  //   you, which it shows by flicking an ear when there are more;
  // - `besideFold`, the chats beside the folded panel, each a session's row, for the notices naming a session: {
  //   inSight(), state() → { placed, now, sessions, out, queue, most, quiet, pointed }, show({ out, queue, came, went,
  //   inTab, holding, open }) }: the rows as placed and their time (its own, for drawing them), the ids of the sessions
  //   it can show, each once, in its order (`sessions`, which notifications keeps to when it's given, and orders by its
  //   senders until then), what's out now (each { sid, news, left, outFor, kept }) and what waits, in order, how many
  //   fit beside the cat, whether nothing may come out now, and the sessions whose chats you point at or type in; then
  //   what should be out and what waits, in order, which sessions came out and which went, the chat you hold by going
  //   where it's about (one you pressed, or whose row you pressed, while it was out), whether you hold one out, and
  //   whether the panel is open.
  // What a place tells it, by id, each running the decider again: `back(id, why)`, one gone from it ('closed' by its ×,
  // or 'expired' as its time ran out: what it said counts as seen); `pin(id, on)`, one pinned or let go; `holding(on)`,
  // you point at what it shows or type in it, or have let go; `again()`, anything else that changes what may come out
  // (the rows drawn again, the peek going); `said()`, what a page sender says has changed, so the line decides again at
  // once. The notifications module fills those in. And what parts of the page add to what the app sends:
  // `noticeSenders`, each { from, notices(now) → [{ key, level, text, after, button, press, since, awayFor, closes,
  // done, busy, pressedWord, tag, seenNow, answersYou, session, outFor, at, evenWhenSeen, openedAt, chip, chipTitle }]
  // }, the fields the app's notices have (app/contracts/Notice.h): `from` its module's name (its notices' ids are
  // `from/key`), `after` a few quiet words after its own ("3 waiting"), `press` what its button does, run on the page,
  // `since` what makes it new (put away by its ×, it stays away while that's the same, or until `awayFor` seconds have
  // passed), `closes: false` for one with no ×, `done` all went well (it goes once seen), `busy` its button waits,
  // `pressedWord` said on the button after a press ("Copied"), `tag` a word before its words ("New"), `seenNow` you're
  // looking at what it's about (it isn't said meanwhile), `answersYou` it answers something you just did (said at night
  // too), `session` the id of the session it's about, `outFor` how long it's out at most where it comes out by itself
  // (in seconds; beside the folded panel takes only one that says), and `chip` what it folds to meanwhile ("3 waiting", with `chipTitle` saying what a press does), if it
  // does. One naming a session goes only beside the folded panel, as that session's chat, out once for each word of its
  // since (one word, its source before its ':'), held out while seenNow, and with `at` its time, `evenWhenSeen` that it
  // comes out even while seenNow (going once its since changes there to one that isn't), and `openedAt` when you went
  // to it from the panel (ms since 1970), which holds its chat out while you're there. And what a module knows is new
  // in a session beyond its row's own state (a reply in its side chat), which the needs-you module reads
  // (modules/needs-you): `sessionNews`, each (s) → { news, level, line, at } | null, `news` a key that changes with
  // each new thing (its module's word first, 'side:…', under 80 characters) and `level` as above, kept as given. It
  // comes out beside the folded panel and counts at the panel's edge as the row's own news does, when the row has no
  // news of its own. Whether it's read is the module's to say: its word goes null, and stays null, once it's read, in
  // the module's own place or by your being in the session's tab since it came, kept after you leave. Until then the
  // edge counts it, and it comes out once for each new word. `line`, if it has one, is what a chat out for it says in
  // Claude's place (plain text, 160 characters at most), and `at` its time (ms since 1970).
  noticeLevels: ['urgent', 'soon', 'know'],
  places: {},
  notices: {},
  noticeSenders: [],
  sessionNews: [],
};

// A module's own state, kept on the page's one state object (state.js) under keys nothing else has.
function moduleState(fields) {
  for (const [key, value] of Object.entries(fields)) {
    if (key in state) throw new Error(`state.${key} is taken`);
    state[key] = value;
  }
}
