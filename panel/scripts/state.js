// Everything the page keeps from one rebuild of the list to the next, in one object. A module keeps its own here too,
// under keys of its own (moduleState in modules.js), each described where it's declared.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

const state = {
  // The newest update from the app: the rows, and the time it sent them.
  last: { sessions: [], now: Date.now() },

  // The reader, while it's open (openReader): its mode, the session it's on (none for a mode about none of them) and
  // what it shows, with what its mode keeps there; null while the list is on its own.
  reading: null,

  // How the list is grouped: newest first (`status`, its old name kept) or by project. The app keeps the choice from
  // its menu bar item and sets it (setGroupBy) before the first update. Which project groups are folded, and how many
  // groups are sliding open or shut right now (slideGroup). Kept across launches: closedProjects.
  groupBy: 'status',
  closedProjects: store.get('closedProjects', {}),  // project folder -> true while folded
  sliding: 0,

  // The session you're on (goTo) and the one the app last marked as shown, in Claude Desktop or a terminal
  // (followClaude); the rows you've pressed, until you've moved on from the panel (keepInPlace); what each session was
  // at the last render (needs, busy, turn, seen or idle: classify), and where its row was shown, { latest, quiet }
  // (placeRows); when you were last on each session while it was yours, which reads its replies (noteOnIt), and when
  // that was last written down, and the time before which every reply counts as read (isRead), the first and
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
  // (fresh.js). When each card, step or button on the list first showed (justShown).
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
  // checkout's numbers, next steps and Deploy; and how a step went, or why it couldn't, { text, quiet, at }, said in
  // the work line's place for a few seconds (stepNote).
  owners: new Set(), stepNotes: {},

  // Until when the next rebuild waits for an animation to finish.
  settleUntil: 0, settleTimer: null,

  // The row you're on, held at the list's edge as it would leave the list's visible part (sticky.js): the row in the
  // list and its session; the edge it holds on at (top, bottom or null); whether its place was in view, and where it
  // and the list's bottom edge were, when last looked at; the copy that holds on while it does, with its chat line's
  // text, its lines' kinds, each line as measured and its height; what it was last laid out for, and how many copies
  // have been made; where the copy has got to on its way to the row's place, how fast it's going, when that was worked
  // out, and the frame it's laid out again in until it's there; the part of the list it covers, the list's border above
  // that, and how far it's attached there at the list's top; how far it has faded in, the timer of its fade or of its
  // tint going to another row, and whether it's going; as it slides off, the part it covered as it began to, and how
  // far what it has uncovered there has come back; and the scroll back to the row after a press.
  sticky: { row: null, sid: null, edge: null, inView: false, lastT: null, lastV: 0, copy: null, chat: null, shape: '',
            lines: [], full: 0, drawn: '', copies: 0, at: null, speed: 0, easedAt: 0, follow: 0, band: [0, 0],
            clientTop: 0, attached: 0, fade: 1, ramp: 0, leaving: false, covered: null, back: 1, mover: 0 },

  // The header pushed away by the held row's copy (header.js): how far it has gone, where the list was last scrolled
  // to, the timer of its glide back, whether it counts as gone, and what the app was last told of it, once a frame at
  // most.
  header: { off: 0, last: 0, glide: 0, gone: false, told: null, telling: false },

  // The pointer, as the app reports it, and whether it's off the panel without having moved there yet (hoverEnd); the
  // card it opened (and what a press on one of its buttons does, for one that has them), where that ends, and its
  // timer. How tall the panel can grow where it is (down to where the screen ends; setRoom). The card's HTML as last
  // drawn, and the room it took below the list, kept a moment after it goes (hideCard).
  pointer: null, pointerStill: false, cardKey: null, cardPress: null, cardBottom: 0, cardHTML: '', cardHeld: null,
  panelMax: 640,

  // Whether the panel has the keyboard (wantKeyboard), the card that has it once pressed ({ kind, id }: heldCard), and
  // whether an input method is mid-word.
  keyboardWanted: false, keyboardTimer: null, keyCard: null,
  composing: false,

  // The folded cat (cat.js): the pose it holds, whether it's looking up at the pointer on it, where the pointer is from
  // its glass while it's near ({ x, y } in points, or null), whether it has just folded with the pointer still on it,
  // whether the panel is opening out of it, where its glass's middle is, just above the name's o, from #root's top-left
  // corner, as last measured (the app starts from the same, kCatAt in app/core/PanelWindow.m), what waits for the app
  // to say the glass is about to move as the panel opens (catGlass), while its eyes follow the pointer, where they are,
  // how fast they're moving, when they were last moved and whether they're still on their way (catEyes: { x, y, vx, vy,
  // at, moving }, or null), and how many sessions the app was last told are working, for its glass's breath
  // (catBreathe; null until it's first told, so it always is once), and its pose as the app was last told it, for
  // Whozmove beside the panel (likewise); and while the panel folds round Whozmove beside it (foldFromSide), that it
  // does, and the timer that hands over if the app doesn't say the cat beside the panel has grown into the folded cat
  // (catLanded). Which way what comes out of it goes, as the app last said ({ right, up, across, tall }: catWay); the
  // room beside it last asked for, its chats' parts (askCatRoom), the number of the last ask, what waits for the window
  // to have its room ({ ask, then }), and the timer that runs that if the app doesn't say.
  cat: { pose: null, hovering: false, near: null, waitForLeave: false, arriving: false, at: { x: 45, y: 23.15 },
         onGlass: null, eyes: null, working: null, toldPose: null, fromSide: false, landing: 0,
         way: { right: false, up: false, across: 1000, tall: 800 },
         room: { chats: [] }, roomAsk: 0, roomWaits: [], roomTimer: 0 },

  // The folded cat's list while it's pointed at (peek.js): whether it's out; the timers of its coming out once the
  // pointer has rested on the cat, and of its going once the pointer has left the panel; the one that ends its coming
  // in, and the one that puts the header back once it has folded away; whether the cat is pressed; and whether the
  // pointer, off the page, was last on what the panel holds over or under itself.
  peek: { open: false, rest: 0, leave: 0, coming: 0, folding: 0, pressed: false, kept: false },

  // The chats beside the folded cat (chats.js): those out, each { sid, news, left, kept } (what brought it out, the
  // time it has left in ms, whether it's pinned), the newest nearest the cat; those waiting, newest first, { sid, news };
  // what of each session has been seen, { sid: news }, so it doesn't come out again, and whether what was there as the
  // page loaded has been counted so; how many come out at once now, and the chat that was first when fewer fit;
  // whether the cat is being moved; the session last opened from here, { sid, at }, the sessions whose tab you're in,
  // and whether you held one of those out as they were last drawn; the room last asked for them, its key, and the
  // timer that asks for only what they need once they've moved; their clock's timer, and when it last ran; and as the
  // panel opens round the cat or its list goes back in, each one's way into its row or back out, by session
  // (chatFlight), the frame that moves them, and the timer that brings the rest of the panel in round them.
  chats: { out: [], queue: [], done: {}, seeded: false, fits: 3, fitsFor: null, moving: false, opened: null, inTab: [],
           holding: false, roomParts: [], roomKey: '[]', roomTimer: 0, clock: 0, tickAt: 0, flights: new Map(),
           flyFrame: 0, landTimer: 0 },
};
