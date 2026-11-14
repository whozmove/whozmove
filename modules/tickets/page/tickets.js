// Tickets on the page: the Ticket chip on the new conversation card (core.startCardParts), which finds a ticket as you
// type, takes one pasted as a link in your words, offers Create a ticket, or signs you in first; and on each row with a
// ticket (row.ticket, from the app), its tag after the name, the card pointing at the tag shows, the card asking "Work
// on PAY-148 here?", the one asking "Move PAY-142 to In Review?" and the one asking "Create this ticket?". The app
// finds, reads, binds, moves and makes tickets (TicketsModule.m); this asks, and draws what it's told (ticket-words.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The trackers and how each one's sign-in stands, as the app last said; the card's ticket, picked or pasted; its list,
// while it's open; whether Copy What to Ask was just pressed; the asks waiting for an answer, by number; when each
// row's ticket was last asked to be read again, as its card opened; and, for the card's ticket in its project, whether
// Start would also let that project's conversations read your tickets, as asked and answered: { k, asked, said }.
moduleState({ ticketTrackers: [], ticketPick: null, ticketList: null, ticketCopied: false, ticketAsks: 0,
              ticketFinding: null, ticketLooked: {}, ticketReads: null });

let ticketApi = null, ticketTyping = null;
// How long the card's search waits for a pause in your typing, and how soon a row's card asks to read again.
const TICKET_PAUSE = 250, TICKET_LOOK_AGAIN = 30000;

const ticketField = () => document.querySelector('.tk-q');
// Drawn again, and the list's field given the caret only when `focusField` says so: only ever straight after your own
// press or key on the card, never as the app answers, which would take the keyboard back from the app you're in. As
// you type, the field stays where it is as the list comes in around it (the card's keepField), caret and all.
function ticketRedraw(api, focusField) {
  if (api) ticketApi = api;
  ticketApi?.refresh();
  const field = focusField && ticketField();
  if (field && document.activeElement !== field) {
    field.focus({ preventScroll: true });
    field.setSelectionRange(field.value.length, field.value.length);
  }
}

// The card's search, for the words in the list's line, once you pause; answered by ticketsFound, for its number.
function ticketSearch(now) {
  clearTimeout(ticketTyping);
  const list = state.ticketList;
  if (!list || !ticketsSignedIn(state.ticketTrackers).length) return;
  const ask = () => {
    list.asked = ++state.ticketAsks;
    list.answered = false;
    native({ type: 'ticketSearch', words: list.q, asked: list.asked });
    ticketRedraw(null, false);
  };
  if (now) ask();
  else ticketTyping = setTimeout(ask, TICKET_PAUSE);
}

function ticketOpenList(api) {
  state.ticketList = { q: '', items: [], sel: 0, asked: 0, answered: false };
  ticketRedraw(api, true);
  ticketSearch(true);
}
function ticketCloseList(api) {
  clearTimeout(ticketTyping);
  state.ticketList = null;
  ticketRedraw(api, false);
  api?.focusBox();
}
// One found, or Create a ticket, after them: a new ticket in the tracker you're signed in to, on its site when it has
// one.
function ticketPickFound(i, api) {
  const list = state.ticketList, tracker = ticketsSignedIn(state.ticketTrackers)[0];
  if (!list) return;
  if (i === list.items.length && tracker) {
    const sites = tracker.sites || [];
    state.ticketPick = { create: true, tracker: tracker.name, site: sites.length === 1 ? sites[0] : '' };
    return ticketCloseList(api);
  }
  const t = list.items[i];
  if (!t) return;
  state.ticketPick = t;
  ticketCloseList(api);
}
// How many the list offers to pick from: what was found, and Create a ticket, once you're signed in.
const ticketChoices = (list) => (ticketsSignedIn(state.ticketTrackers).length ? list.items.length + 1 : 0);

// The card's ticket, for the card's other parts (where a ticket starts): its tracker, site and key, never anything else
// it said; none for Create a ticket, which has no key yet.
core.cardTicket = () => {
  const p = state.ticketPick;
  return p && !p.create && p.key ? { tracker: p.tracker, site: p.site, key: p.key } : null;
};

core.startCardParts.push({
  name: 'tickets',
  chip: () => ticketChipHTML(state.ticketPick),
  list: () => ticketListHTML(state.ticketList, state.ticketTrackers, state.ticketCopied),
  placeholder: () => (state.ticketPick ? ticketPlaceholder(state.ticketPick) : ''),
  words: () => (state.ticketPick ? ticketStartLine(state.ticketPick) : ''),
  // What the app binds the new session to: the ticket's tracker, site and key, never anything else it said; or, for
  // Create a ticket, the tracker and site its new ticket goes to.
  with: () => {
    const p = state.ticketPick;
    if (!p) return null;
    return p.create ? { tracker: p.tracker, site: p.site, create: true } : { tracker: p.tracker, site: p.site, key: p.key };
  },
  // With a ticket on the card, what Start would also do: let the project's conversations read your tickets, while
  // it reads none yet. None for Create a ticket: Start gives it no ticket yet, and the row's Create Ticket card says it
  // then. Asked of the app again when the card's folder or ticket changes, or the app says reading changed.
  note(card, api) {
    const t = core.cardTicket();
    if (!t || !card?.folder) {
      state.ticketReads = null;
      return '';
    }
    ticketApi = api;
    const k = [card.folder, t.tracker, t.site, t.key].join('\n');
    if (state.ticketReads?.k !== k) {
      state.ticketReads = { k, asked: ++state.ticketAsks, said: null };
      native({ type: 'ticketReadsAsk', folder: card.folder, asked: state.ticketReads.asked });
    }
    return ticketReadsLine(state.ticketReads.said);
  },
  sent: () => {
    state.ticketPick = null;
    state.ticketList = null;
    state.ticketFinding = null;
    state.ticketReads = null;
  },
  press(t, card, api) {
    if (t.closest('.tk-x')) {
      state.ticketPick = null;
      ticketRedraw(api, false);
      return true;
    }
    if (t.closest('.tk-chip')) {
      if (state.ticketList) ticketCloseList(api);
      else ticketOpenList(api);
      return true;
    }
    const found = t.closest('.tk-res[data-i]');
    if (found) {
      ticketPickFound(+found.dataset.i, api);
      return true;
    }
    const button = t.closest('[data-tk-act]');
    if (!button) return !!t.closest('.tk-list');
    const tracker = button.dataset.tracker, act = button.dataset.tkAct;
    if (act === 'signIn') native({ type: 'ticketSignIn', tracker });
    else if (act === 'cancel') native({ type: 'ticketCancelSignIn', tracker });
    else if (act === 'copyAsk') {
      native({ type: 'ticketCopyAsk', tracker });
      state.ticketCopied = true;
      ticketRedraw(api, false);
    } else if (act === 'search') ticketSearch(true);
    else if (act === 'find' && state.ticketList) {
      // The link again, as it was pasted.
      state.ticketFinding = { text: state.ticketList.q, asked: ++state.ticketAsks };
      native({ type: 'ticketFind', text: state.ticketList.q, asked: state.ticketFinding.asked });
    }
    return true;
  },
  typed(card, el, api) {
    ticketApi = api;
    if (el.matches('.tk-q')) {
      if (!state.ticketList) return;
      state.ticketList.q = el.value;
      state.ticketList.picked = null;
      return ticketSearch(false);
    }
    // A link pasted into your words: the app says whether it's a ticket, and reads it for the chip.
    const link = !state.ticketPick && ticketLinkIn(el.value);
    if (!link || link === state.ticketFinding?.text) return;
    state.ticketFinding = { text: link, asked: ++state.ticketAsks };
    native({ type: 'ticketFind', text: link, asked: state.ticketFinding.asked });
  },
  keys(card, e, api) {
    const list = state.ticketList, n = list ? ticketChoices(list) : 0;
    if (!list) return false;
    if (e.key === 'Escape') {
      ticketCloseList(api);
      return true;
    }
    if (n && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) {
      list.sel = (list.sel + (e.key === 'ArrowDown' ? 1 : n - 1)) % n;
      ticketRedraw(api, true);
      return true;
    }
    if (e.key === 'Enter' && !e.metaKey && !e.ctrlKey) {
      // While a search is out, Return waits for what it finds, so it never picks Create a ticket in its place.
      if (n && !(list.asked && !list.answered)) ticketPickFound(list.sel, api);
      return true;
    }
    return false;
  },
});

// A project's reading changed (turned on or off, or a ticket given there): the card's line is asked for again.
window.ticketReadsChanged = () => {
  if (!state.ticketReads) return;
  state.ticketReads.k = null;
  ticketRedraw(null, false);
};

// Whether Start would also let the card's project read your tickets: for the last ask only.
window.ticketReadsSaid = (asked, said) => {
  if (!state.ticketReads || asked !== state.ticketReads.asked) return;
  state.ticketReads.said = said || {};
  ticketRedraw(null, false);
};

// What the app found for the list's words: for the last search asked only.
window.ticketsFound = (asked, said) => {
  const list = state.ticketList;
  if (!list || asked !== list.asked) return;
  Object.assign(list, { items: said.tickets || [], end: said.end || null, why: said.why || '', answered: true, sel: 0 });
  ticketRedraw(null, false);
};
// The ticket a key or link names, read: the card's ticket; or why it can't be, said in the list.
window.ticketPicked = (asked, said) => {
  const finding = state.ticketFinding, list = state.ticketList;
  if (said.ticket && (asked === finding?.asked || list)) {
    state.ticketPick = said.ticket;
    state.ticketList = null;
    return ticketRedraw(null, false);
  }
  if (said.none || asked !== finding?.asked) return;
  state.ticketList = { q: finding.text, items: [], sel: 0, asked: 0, answered: true, picked: said };
  ticketRedraw(null, false);
};
// How each tracker's sign-in stands: once signed in, the open list searches.
window.setTicketTrackers = (trackers) => {
  const was = ticketsSignedIn(state.ticketTrackers).length;
  state.ticketTrackers = trackers || [];
  if (ticketsSignedIn(state.ticketTrackers).length) state.ticketCopied = false;
  if (!state.ticketList) return;
  if (!was && ticketsSignedIn(state.ticketTrackers).length) ticketSearch(true);
  else ticketRedraw(null, false);
};

// ---- The row ----

const rowTicket = (sid) => state.last.sessions.find((s) => s.sessionId === sid)?.ticket;

// After the row's name, while Claude works too: its ticket, or "New ticket", on a row shown briefly as on a whole one
// (a chat beside the folded panel), with its card and what it says when the ticket can't be read.
const rowTicketTag = (row) => ticketTagHTML(row.s.sessionId, row.s.ticket?.bound, row.s.ticket?.creating);
core.slots.name.push(rowTicketTag);
core.slots.brief.push(rowTicketTag);
core.presses.push(['.tk-row[data-tk]', (tag) => native({ type: 'openTicket', sessionId: tag.dataset.tk })]);
core.pointerTargets.push('.tk-row[data-tk]', '.tk-row[data-tknew]', '.tk-chip', '.tk-res', '.tk-act', '.tk-use button',
  '.tk-move button', '.tk-draft button');
const ticketWho = (name) => state.ticketTrackers.find((x) => x.name === name)?.signInName;

// Pointed at: the ticket as last read, and read again as it opens (unless that was just now), so it's fresh next time.
core.cards.push({
  selector: '.tk-row[data-tk]',
  key: (tag) => {
    const t = rowTicket(tag.dataset.tk)?.bound;
    return `tk:${tag.dataset.tk}:${t?.state?.name || ''}:${t?.problem?.kind || ''}:${t?.readAt || ''}:`
      + `${t?.moved?.at || ''}:${Object.keys(t?.stopped || {}).join(',')}`;
  },
  html(tag) {
    const sid = tag.dataset.tk, t = rowTicket(sid)?.bound;
    if (t && Date.now() - (state.ticketLooked[sid] || 0) > TICKET_LOOK_AGAIN) {
      state.ticketLooked[sid] = Date.now();
      native({ type: 'ticketRead', sessionId: sid });
    }
    return ticketCardHTML(t, ticketWho(t?.tracker), Date.now());
  },
  press(key, act) {
    const sid = key.split(':')[1], t = rowTicket(sid)?.bound;
    if (!t) return false;
    if (act === 'signIn') native({ type: 'ticketSignIn', tracker: t.tracker });
    else native({ type: 'ticketRead', sessionId: sid, now: act === 'now' });
    return true;
  },
});

// Pointed at, "New ticket": what happens before anything is made in its tracker.
core.cards.push({
  selector: '.tk-row[data-tknew]',
  key: (tag) => `tknew:${tag.dataset.tknew}`,
  html: (tag) => ticketNewCardHTML(rowTicket(tag.dataset.tknew)?.creating),
});

// A ticket the session asked to work on, or had before Whozmove started again, waits on its row for Use It.
core.rowCards.push({
  name: 'ticketUse', order: 25,
  wants: (row) => !!row.s.ticket?.offer,
  html: (row) => {
    // Kept by the ticket it offers too, so a press can't land on a card that has just changed to another ticket.
    state.shownAt[`tkuse:${row.s.sessionId}:${row.s.ticket.offer.key}`] ??= Date.now();
    return ticketUseHTML(row.s.sessionId, row.s.ticket.offer, ticketWho(row.s.ticket.offer.tracker));
  },
  away: (row) => {
    for (const key of Object.keys(state.shownAt))
      if (key.startsWith(`tkuse:${row.s.sessionId}:`)) delete state.shownAt[key];
  },
});
core.presses.push(['.perm[data-tkuse]', (card, e) => {
  const button = e.target.closest('button[data-act]'), sid = card.dataset.tkuse;
  if (!button) return;
  e.preventDefault();
  if (justShown(`tkuse:${sid}:${card.dataset.key}`)) return;
  native({ type: 'ticketAnswer', sessionId: sid, key: card.dataset.key, act: button.dataset.act });
}]);
core.forgotten.prefixes.push('tkuse');

// A move the session asked for waits on its row for Move It, after the Use It card, as a ticket it works on comes first.
core.rowCards.push({
  name: 'ticketMove', order: 26,
  wants: (row) => !!row.s.ticket?.move,
  html: (row) => {
    // Kept by when it was asked and what it shows, so a press can't land on a card that has just changed to another
    // move, or from Move It to what its tracker said, with its own page where Move It was.
    const m = row.s.ticket.move;
    state.shownAt[`tkmove:${row.s.sessionId}:${m.at}:${ticketMoveState(m)}`] ??= Date.now();
    const tracker = row.s.ticket.bound?.tracker;
    return ticketMoveHTML(row.s.sessionId, m, tracker, ticketWho(tracker));
  },
  away: (row) => {
    for (const key of Object.keys(state.shownAt))
      if (key.startsWith(`tkmove:${row.s.sessionId}:`)) delete state.shownAt[key];
  },
});
core.presses.push(['.perm[data-tkmove]', (card, e) => {
  const button = e.target.closest('button[data-act]'), sid = card.dataset.tkmove;
  if (!button) return;
  e.preventDefault();
  if (justShown(`tkmove:${sid}:${card.dataset.at}:${card.dataset.state}`)) return;
  if (button.dataset.act === 'signIn') return native({ type: 'ticketSignIn', tracker: card.dataset.tracker });
  if (button.dataset.act === 'open') return native({ type: 'openTicket', sessionId: sid });
  native({ type: 'ticketMove', sessionId: sid, key: card.dataset.key, stepId: card.dataset.step,
           at: Number(card.dataset.at), act: button.dataset.act });
}]);
core.forgotten.prefixes.push('tkmove');

// A new ticket the session drafted waits on its row for Create Ticket, after a move it asked for.
core.rowCards.push({
  name: 'ticketDraft', order: 27,
  wants: (row) => !!row.s.ticket?.draft,
  html: (row) => {
    // Kept by when it was drafted and what it shows, so a press can't land on a card that has just changed to another
    // draft, or from Try Again to Create Ticket.
    const d = row.s.ticket.draft;
    state.shownAt[`tkdraft:${row.s.sessionId}:${d.at}:${ticketDraftState(d)}`] ??= Date.now();
    return ticketDraftHTML(row.s.sessionId, d, ticketWho(d.tracker), ticketSites(state.ticketTrackers).length);
  },
  away: (row) => {
    for (const key of Object.keys(state.shownAt))
      if (key.startsWith(`tkdraft:${row.s.sessionId}:`)) delete state.shownAt[key];
  },
});
core.presses.push(['.perm[data-tkdraft]', (card, e) => {
  const button = e.target.closest('button[data-act]'), sid = card.dataset.tkdraft;
  if (!button) return;
  e.preventDefault();
  if (justShown(`tkdraft:${sid}:${card.dataset.at}:${card.dataset.state}`)) return;
  if (button.dataset.act === 'signIn') return native({ type: 'ticketSignIn', tracker: card.dataset.tracker });
  native({ type: 'ticketDraft', sessionId: sid, at: Number(card.dataset.at), act: button.dataset.act });
}]);
core.forgotten.prefixes.push('tkdraft');
