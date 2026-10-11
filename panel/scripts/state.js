// Everything the page keeps from one rebuild of the list to the next, in one object.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const state = {
  // The newest update from the app: the rows, and the time it sent them.
  last: { sessions: [], now: Date.now() },

  // How the list is grouped (status, activity or project): the app keeps the choice from its menu bar item and
  // sets it (setGroupBy) before the first update. Whether the Idle group is open, which project groups are
  // folded, and how many groups are sliding open or shut right now (slideGroup). Kept across launches: showIdle
  // and closedProjects.
  groupBy: 'status',
  showIdle: store.get('showIdle', false),
  closedProjects: store.get('closedProjects', {}),  // project folder -> true while folded
  sliding: 0,

  // The session you're on (goTo) and the conversation Claude last showed; where each row was last shown (needs,
  // busy, turn or idle); when each session was last clicked here (kept across launches); a Claude Desktop
  // conversation just clicked, { sessionId, at } (openedNow); and the conversation open in Claude at the last
  // render.
  current: null,
  claudeShowed: null,
  shownKind: {},
  seen: store.get('seen', {}),
  opening: null,
  lastOpenId: null,

  // The Compact card, per session: open, its note, and the focus typed in it. The session whose context ring is
  // pointed at.
  compactOpen: {}, compactNotes: {}, compactFocus: {},
  hoverCtx: null,
  // Requests and questions, by ask id: 'allow' or 'deny' once answered (until the request goes away), when that
  // was, when each first showed (justShown), and each question card's step, picks, typing and skips.
  answering: {}, answeredAt: {}, shownAt: {}, quiz: {},
  // When each session and request was last listed, and when the page loaded: what's kept for one of them goes a
  // minute after it has gone from the list (forgetGone).
  listedAt: {}, loadedAt: Date.now(),
  // "Switch model?" while it's up: { sessionId, never }, and where its card ends.
  asking: null, askBottom: 0,

  // Whether the list has been drawn before, and until when the next rebuild waits for an animation to finish.
  morphed: false, settleUntil: 0, settleTimer: null,

  // The pointer, as the app reports it; the PR card it opened, where that ends, and its timer. How tall the panel
  // can grow where it is (kMaxHeight in app/PanelWindow.m, or less where the screen ends; setRoom).
  pointer: null, cardUrl: null, cardBottom: 0, cardTimer: null,
  panelMax: 640,

  // Whether the panel has the keyboard (wantKeyboard), and whether an input method is mid-word.
  keyboardWanted: false, keyboardTimer: null,
  composing: false,
};
