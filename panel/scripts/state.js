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

  // The session you're on (goTo) and the one the app last marked as shown, in Claude Desktop or Ghostty
  // (followClaude); the rows you've pressed, until you've moved on from the panel (keepInPlace); what each session was
  // at the last render (needs, busy, turn, seen or idle: classify), and where its row was shown, { section, key, tie,
  // latest } (placeRows); when you last read each session's reply (markRead), and the time before which every reply
  // counts as read (isRead), both kept across launches; a Claude Desktop conversation just clicked, { sessionId, at }
  // (openedNow); and the session marked as shown at the last render (revealOpenConversation).
  current: null,
  claudeShowed: null,
  pressedRows: new Set(),
  kinds: {},
  placed: {},
  seen: store.get('seen', {}),
  readBefore: store.get('readBefore', 0),
  opening: null,
  lastOpenId: null,

  // Requests answered from the page, by ask id: 'allow' or 'deny' (until the request goes away), and when that was
  // (fresh.js). When each card, island or button on the list first showed (justShown).
  answering: {}, answeredAt: {}, shownAt: {},
  // When each session and request was last listed, and when the page loaded: what's kept for one of them goes a
  // minute after it has gone from the list (forgetGone).
  listedAt: {}, loadedAt: Date.now(),

  // The pawn menu's switches (setSwitches): Show Next Steps, Show Deploy, and Show Build in Header; and the build of
  // Whozmove running now (setRunningBuild), which the header names while that's on.
  switches: { nextSteps: true, deploy: true, build: false }, running: null,
  // The sessions that speak for their checkouts, from the last render (checkoutOwners), whose rows show their
  // checkout's island and Deploy; and how a step from a row's menus went, or why it couldn't, { text, quiet, at }, said
  // under the details for a few seconds (stepNote).
  owners: new Set(), stepNotes: {},

  // Whether the list has been drawn before, and until when the next rebuild waits for an animation to finish.
  morphed: false, settleUntil: 0, settleTimer: null,

  // The pointer, as the app reports it, and whether it's off the panel without having moved there yet (hoverEnd); the
  // card it opened, where that ends, and its timer. How tall the panel can grow where it is (kMaxHeight in
  // app/core/PanelWindow.m, or less where the screen ends; setRoom). The card's HTML as last drawn, and the room it
  // took below the list, kept a moment after it goes (hideCard).
  pointer: null, pointerStill: false, cardKey: null, cardBottom: 0, cardHTML: '', cardHeld: null,
  panelMax: 640,

  // Whether the panel has the keyboard (wantKeyboard), and whether an input method is mid-word.
  keyboardWanted: false, keyboardTimer: null,
  composing: false,
};
