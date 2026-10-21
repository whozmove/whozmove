// Everything the page keeps from one rebuild of the list to the next, in one object. A module keeps its own here too,
// under keys of its own (moduleState in modules.js), each described where it's declared.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const state = {
  // The newest update from the app: the rows, and the time it sent them.
  last: { sessions: [], now: Date.now() },

  // The reader, while it's open (openReader): its mode, the session it's on (none for a mode about none of them) and
  // what it shows, with what its mode keeps there; null while the list is on its own.
  reading: null,

  // How the list is grouped (status or project): the app keeps the choice from its menu bar item and
  // sets it (setGroupBy) before the first update. Whether the Idle group is open, which project groups are
  // folded, and how many groups are sliding open or shut right now (slideGroup). Kept across launches: showIdle
  // and closedProjects.
  groupBy: 'status',
  showIdle: store.get('showIdle', false),
  closedProjects: store.get('closedProjects', {}),  // project folder -> true while folded
  sliding: 0,

  // The session you're on (goTo) and the one the app last marked as shown, in Claude Desktop or a terminal
  // (followClaude); the rows you've pressed, until you've moved on from the panel (keepInPlace); what each session was
  // at the last render (needs, busy, turn, seen or idle: classify), and where its row was shown, { section, key, tie,
  // latest } (placeRows); when you were last on each session while it was yours, which reads its replies (noteOnIt),
  // and when that was last written down, and the time before which every reply counts as read (isRead), the first and
  // the last kept across launches; a session just clicked, { sessionId, at } (openedNow); and the
  // session marked as shown at the last render (revealOpenConversation).
  current: null,
  claudeShowed: null,
  pressedRows: new Set(),
  kinds: {},
  placed: {},
  seen: store.get('seen', {}),
  seenKeptAt: 0,
  readBefore: store.get('readBefore', 0),
  opening: null,
  lastOpenId: null,

  // Requests answered from the page, by ask id: 'allow' or 'deny' (until the request goes away), and when that was
  // (fresh.js). When each card, island or button on the list first showed (justShown).
  answering: {}, answeredAt: {}, shownAt: {},
  // When each session and request was last listed, and when the page loaded: what's kept for one of them goes a
  // minute after it has gone from the list (forgetGone).
  listedAt: {}, loadedAt: Date.now(),

  // Whether the panel is turned over to the apps on its back, or on its way (turned), and whether it turns over once
  // the reader beside the list has folded back (the header's four squares, input.js).
  turned: false, turnAfterReader: false,

  // The panel's switches (setSwitches): Show Next Steps, Show Deploy, and Show Build in Header; and the build of
  // Whozmove running now (setRunningBuild), which the header names while that's on.
  switches: { nextSteps: true, deploy: true, build: false }, running: null,
  // The sessions that speak for their checkouts, from the last render (checkoutOwners), whose rows show their
  // checkout's island and Deploy; and how a step from a row's menus went, or why it couldn't, { text, quiet, at }, said
  // under the details for a few seconds (stepNote).
  owners: new Set(), stepNotes: {},

  // Whether the list has been drawn before, and until when the next rebuild waits for an animation to finish.
  morphed: false, settleUntil: 0, settleTimer: null,

  // The row you're on, held at the list's edge as it would leave the list's visible part (sticky.js): the row in the
  // list and its session; the edge it holds on at (top, bottom or null); whether its place was in view, and where it
  // and the list's bottom edge were, when last looked at; the copy that holds on while it does, with its chat line's
  // text, its lines' kinds, each line as measured and its height; what it was last laid out for, and how many copies
  // have been made; the part of the list it covers and the list's border above that; how far it has faded in, the timer
  // of its fade or of its tint going to another row, and whether it's going; and the scroll back to the row after a
  // press.
  sticky: { row: null, sid: null, edge: null, inView: false, lastT: null, lastV: 0, copy: null, chat: null, shape: '',
            lines: [], full: 0, drawn: '', copies: 0, band: [0, 0], clientTop: 0, fade: 1, ramp: 0, leaving: false,
            mover: 0 },

  // The pointer, as the app reports it, and whether it's off the panel without having moved there yet (hoverEnd);
  // the card it opened (and what a press on one of its buttons does, for one that has them), where that ends, and
  // its timer. How tall the panel can grow where it is (down to where the screen ends; setRoom). The card's HTML as
  // last drawn, and the room it took below the list, kept a moment after it goes (hideCard).
  pointer: null, pointerStill: false, cardKey: null, cardPress: null, cardBottom: 0, cardHTML: '', cardHeld: null,
  panelMax: 640,

  // Whether the panel has the keyboard (wantKeyboard), and whether an input method is mid-word.
  keyboardWanted: false, keyboardTimer: null,
  composing: false,

  // The folded cat (cat.js): the pose it holds, its marks as last drawn, whether the pointer is on it and the timer of
  // its marks going back once it has left, where the pointer is from its glass while it's near ({ x, y } in points, or
  // null), whether it has just folded with the pointer still on it, whether the panel is opening out of it, which side
  // its labels come out on (right, on the screen's left half), what it was last drawn for, where its glass's middle is,
  // just above the name's o, from #root's top-left corner, as last measured (the app starts from the same, kCatAt in
  // app/core/PanelWindow.m), what waits for the app to say the glass is about to move as the panel opens (catGlass),
  // while its eyes follow the pointer, where they are, how fast they're moving, when they were last moved and whether
  // they're still on their way (catEyes: { x, y, vx, vy, at, moving }, or null), and how many sessions the app was last
  // told are working, for its glass's breath (catBreathe; null until it's first told, so it always is once).
  cat: { pose: null, marks: null, hovering: false, leaving: null, near: null, waitForLeave: false, arriving: false,
         right: false, drawn: null, at: { x: 45, y: 23.15 }, onGlass: null, eyes: null, working: null },
};
