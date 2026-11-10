// What the app calls on the page: the frame's own functions, each one the app names (Page.m). The folded panel's, the
// reader's and turnToApps are beside what they draw (cat.js, peek.js, reader.js, input.js), as each module's are (as
// window.setDeploys in deploy-row.js). It's the page's last script, so the modules start once the page is whole.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// ---- What the app calls ----

// The newest rows, about once a second; while something moves, the newest data waits (renderWhenSettled), but for the
// session you're on changing in its app (another tab in a terminal, another conversation in Claude), which shows at once,
// as a press here does, cutting short what's moving. The strips under the list aren't in it, so they keep time on their
// own, each module's through core.updates (Spotify's song line).
window.update = (sessions, now) => {
  state.last = { sessions, now };
  if (!state.readBefore) store.set('readBefore', (state.readBefore = now - IDLE_AFTER_MS));
  forgetGone(sessions);
  for (const updating of core.updating) updating(sessions);
  const on = sessions.map(openedNow).find((s) => s.focused)?.sessionId || null;
  if (on !== state.claudeShowed && !state.sliding && !state.composing) {
    clearTimeout(state.settleTimer);
    render();
  } else renderWhenSettled();
  for (const updated of core.updates) updated(now);
};

// Whether anything of the panel can be seen (parts/glass): hidden from the menu bar, or with the screen asleep or
// locked, it can't, and the list isn't drawn meanwhile (listDrawing). Seen again, it's drawn at once as it is by then.
window.panelSeen = (on) => {
  state.shown = !!on;
  if (state.shown && state.listStale) renderWhenSettled();
};

// How tall the panel can grow where it is (`h`): down to where the screen ends below it, less the room kept there for
// what hangs under the panel (parts/glass). Within that, the header and the list keep to `most` (the glass's
// ListLimitFor: --most, glass.css), with what opens under them on top; where the room ends first, the list gives way
// and scrolls.
window.setRoom = (h, most = 640) => {
  state.panelMax = h;
  state.listMost = most;
  const root = document.getElementById('root');
  root.style.maxHeight = h + 'px';
  root.style.setProperty('--most', most + 'px');
  reportHeight();
};

// Settings' Show Conversation Text, told as the page loads and each time it's switched: off, rows show no one's words
// (the row part's rowHTML and conversationLine).
window.setConversationShown = (on) => {
  state.conversationShown = !!on;
  render();
};

// A click on the header folds the panel into the cat (cat.js), and a click on the cat opens it again (the chevron folds
// it too). With the folded cat's list out, the panel is open already, and a click on the cat only finishes opening it
// (peek.js).
window.toggleCollapsed = () => {
  if (state.peek.open) return peekStays();
  const collapsed = !document.body.classList.contains('collapsed');
  // Not while the reader is open: the panel folds from the list alone (PanelWindow+Fold.m).
  if (collapsed && state.reading) return;
  if (!collapsed) peekHeaderBack();
  foldPanel(collapsed);
};

// Where the pointer is over the panel, as the app polls it (see hover.js); folded, whether it's on the cat or its list.
// Once it has left, the rows you pressed go to their places (heldNow), so the list is drawn again for them: here, as
// what watches the pointer runs as the list is drawn (syncHover), and drawing it from there would never end. Off the
// panel `still`, the panel's edge having moved past it (a card folding away, a menu of its own closing where you
// picked from it), it's taken to be still with the panel until the app says it has moved; `held`, on what the panel
// holds over or under itself (Spotify's token, the usage card), it's still with the folded cat's list out beside it.
window.hoverAt = (x, y) => {
  state.pointerStill = false;
  pointerAt(x, y);
  peekPointer(x, y);
};
window.hoverEnd = (still, held) => {
  pointerGone();
  peekPointer(null, null, !!still || !!held);
  state.pointerStill = !!still;
  if (state.pressedRows.size && !still) renderWhenSettled();
};

// The panel no longer has the keyboard: another app took it (you clicked into it), or the panel gave it back. The box
// it was typed into, the card pressed, or the view beside the list pressed in, lets go of it too, so the list being
// drawn again doesn't put the keyboard back there, and the rows you pressed go once your pointer is off the panel.
window.keyboardGone = () => {
  if (document.activeElement?.closest?.(textBoxes())) document.activeElement.blur();
  state.keyboardWanted = false;
  state.keyCard = null;
  state.viewKeys = null;
  if (state.pressedRows.size) renderWhenSettled();
};

// The panel turning over to its back, or back on its list side (PanelWindow+Turn.m): meanwhile the
// pointer isn't on the list, and no box here has the keyboard.
window.turned = (on) => {
  state.turned = !!on;
  if (!on) return;
  pointerGone();
  if (document.activeElement?.closest?.(textBoxes())) document.activeElement.blur();
};

// The build of Whozmove running now, as build.sh recorded it (parts/builds), or null: the header's name for it.
window.setRunningBuild = (running) => {
  state.running = running;
  render();
};

// The panel's switches: Show Next Steps (each row's next steps, and Deploy's button), Show Deploy (Deploy's round
// button), and Show Build in Header; and the panel's look from Settings' Appearance, grey, black or glass, for the
// colours that match the panel's own (tokens.css).
window.setSwitches = (switches) => {
  state.switches = { nextSteps: !!switches.nextSteps, deploy: !!switches.deploy, build: !!switches.build };
  document.documentElement.dataset.look = switches.look || 'grey';
  render();
};

// How a step from a row's menus went (`quiet`: it worked), or why it couldn't go in, or why a deploy couldn't start or
// its command wasn't saved: the row's note for a few seconds, in its work line's place. What it settles for a module goes first
// (core.noted: a Deploy pressed there stops standing in for a run). Its button (`way`) is the terminal's way past the
// reason, unless `go` says what it does on the page instead: 'open' opens the session, else a module's (core.noteWays).
window.stepNote = (sid, text, quiet, way, go) => {
  const s = state.last.sessions.find((x) => x.sessionId === sid);
  if (s) for (const noted of core.noted) noted(s);
  state.stepNotes[sid] = { text, quiet: !!quiet, way: way || null, go: go || null, at: Date.now() };
  renderWhenSettled();
};

// Every script has loaded: the modules start (modules.js), now that the page is whole.
for (const start of core.starts) start();
