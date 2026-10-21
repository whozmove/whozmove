// What the panel's modules plug into the page with. A module's scripts (tools/page.sh lists them, from its
// module.json) only register here as they load. The core then runs them: their start-up once every script has loaded,
// their part of each update, each fold, each row and each press (panel.js, rows.js, input.js, …). So a module never
// acts before the page is whole, and never needs to name another module. Each list holds the modules' entries; the
// core's own are in its scripts.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const core = {
  // Starting, the updates from the app, and folding to the header (panel.js).
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

  // A row (rows.js). `row` is { s, kind, now, owner, clock }, and what the modules' looks add to it: `kind` is what the
  // session is now (classify).
  rowLooks: [],        // (row) a module's first look at a row, which keeps what it found on `row` for its parts
  // The cards that can show under a row's chat, one at a time: { name, order, wants(row), html(row), away(row),
  // close(sid) }. The most pressing (lowest order) that wants to show does; the others are away.
  rowCards: [],
  rowNotes: [],        // (row) → { text, quiet } or null: the row's note, when the core has none
  // The places on a row's template, and on a project's header, each (row or project) → HTML: after the name; the work
  // line's start (the pull requests), its numbers and its steps at its end; the bottom line's start (how the agent is
  // set up) and its end, after where the session runs; and the project's header after its name.
  slots: { rowClass: [], name: [], workStart: [], numbers: [], steps: [], setup: [], placeEnd: [], project: [] },

  // Pressing and typing (input.js).
  presses: [],         // [selector, press(target, event)]: a press on the list, checked before the core's own
  typing: [],          // [selector, typed(box, event)]: what's typed in a box on the list
  returns: [],         // [selector, returned(box, event)]: Return in one (else it presses its card's main button)
  textBoxes: [],       // the boxes outside the cards that take the keyboard while they're typed in (wantKeyboard)
  // Cards on a row that take the keyboard once pressed, so keys work on them (heldCard): { card, id(card), open(card),
  // takes(card, target), key(card, event) }: the card's selector, its id (found again by it as the list is rebuilt),
  // whether it still waits for you, whether a press on `target` in it takes the keyboard (not one that answers it), and
  // what a key does there (true if it did something; Return presses its main button, Esc lets go).
  keyCards: [],

  // The pointer (hover.js).
  pointerTargets: [],  // more of what the pointer can point at
  pointerWatchers: [], // (el) each time what's under the pointer is looked at: what it's on, or null
  cards: [],           // the card shown while something is pointed at: { selector, key(anchor), html(anchor) }

  // The panel's height (reportHeight, listHeight).
  strips: [],          // the ids of what's above or under the list (its strips), which the panel makes room for
  overhangs: [],       // () → how far down something hanging below the list reaches, or 0

  // The reader (reader.js): what it can show, by name ({ draw, … }), and the presses in it.
  readerModes: {},
  readerPresses: [],

  // How the list moves (morph.js): how a row's lines move, by the line's selector, where a module's part needs more
  // than the core's ({ text, swap, shape, morph, grow, fold, still }: `still(el)` takes out of a copy of the line
  // what's only there while it moves, for the copy of the row you're on held at the list's edge, sticky.js), and the
  // bits of a row that cross-fade when their text changes.
  lines: {},
  swaps: [],

  // A step's note arriving for a session (stepNote): (session)
  noted: [],

  // What the page keeps per session or request, forgotten a minute after it has gone from the list (forgetGone): the
  // state's keys, each an object by session or request id, and the prefixes of the cards' first-shown times in
  // state.shownAt ('compact:<id>').
  forgotten: { keys: [], prefixes: [] },

  // What an agent's details mean, for the parts that show them: { modelName, modeName, contextWindow, compactLimit }.
  agent: {},

  // The apps sessions run in, as the page names them, each a module's (hostOf in rows.js): { holds(s), name, openNow,
  // inName, closedTip(s) (what a row that isn't running says a press does), project(s) }. A session none holds runs in
  // a terminal.
  hosts: [],
};

// A module's own state, kept on the page's one state object (state.js) under keys nothing else has.
function moduleState(fields) {
  for (const [key, value] of Object.entries(fields)) {
    if (key in state) throw new Error(`state.${key} is taken`);
    state[key] = value;
  }
}
