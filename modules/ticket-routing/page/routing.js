// Where a ticket starts, on the new conversation card (core.startCardParts): once the card has a ticket
// (core.cardTicket), the app is asked where its project's tickets open, and the card is told where to start it (where),
// the line under its box says where and why (under), and a warning shows where another ticket's conversation works
// (warn). The first time in a git project, the guide takes the line's place; Start keeps its lit choice for the
// project, Not Now starts this one in the project's folder, and Esc only puts the guide away. A ticket a conversation
// already works says so, with Go to It. The app keeps each project's way (TicketRoutingModule.m); this asks, and draws
// what it's told (routing-words.js).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The card's ticket and folder as last asked about, with the app's answer once it came: { k, asked, folder, ticket,
// answer }; the guide's lit choice and when it first showed (a press just after it shows doesn't count); and the
// card's ticket whose guide was put away, by Not Now or Esc.
moduleState({ routeAsk: null, routeLit: 'own', routeGuideAt: 0, routeNotNow: null });

let routeAsks = 0;
// The card's api, as it was last handed to this part, for drawing the card again once the app's answer comes.
let routeApi = null;
// How long the guide waits after it shows before it takes a press: a press meant for what was there can't land on it.
const ROUTE_GUIDE_SETTLES = 600;

// The ask for the card's ticket in its folder: made again only when either changes. Asking here, as the card draws
// what it has, is what lets the card ask nothing of this part until it has a ticket.
function routeAsk(card) {
  const ticket = core.cardTicket?.();
  if (!ticket || !card?.folder) {
    state.routeAsk = null;
    return null;
  }
  const k = [card.folder, ticket.tracker, ticket.site, ticket.key].join('\n');
  if (state.routeAsk?.k !== k) {
    state.routeAsk = { k, asked: ++routeAsks, folder: card.folder, ticket, answer: null };
    Object.assign(state, { routeLit: 'own', routeGuideAt: 0, routeNotNow: null });
    native({ type: 'ticketRoute', asked: state.routeAsk.asked, folder: card.folder, tracker: ticket.tracker,
             site: ticket.site, key: ticket.key });
  }
  return state.routeAsk;
}

// What the routing part has to go on now: the answer, and the conversation already working the ticket, if any.
function routeNow(card) {
  return routeSays(routeAsk(card));
}
function routeSays(ask) {
  const answer = ask?.answer;
  if (!answer) return null;
  return { ask, answer, worked: ticketWorkedBy(state.last.sessions, ask.ticket), notNow: state.routeNotNow === ask.k };
}
// Whether the guide shows: a git project with no way yet, until it's put away, while it's drawn (the card draws it only
// while you haven't picked where yourself, and no list of the card's is open).
const routeGuides = (now, card) => !!now && !!card && !card.chosen && !card.list && now.answer.git && !now.answer.way
  && !now.notNow && !now.worked;
// Whether a press on the guide counts: not just after it showed, or changed.
const routeSettled = () => Date.now() - state.routeGuideAt >= ROUTE_GUIDE_SETTLES;

core.startCardParts.push({
  name: 'routing',
  where(card) {
    const now = routeNow(card);
    return now && routeWhere(now.answer, { lit: state.routeLit, notNow: now.notNow, worked: now.worked });
  },
  // A way by a field, its ticket still being read: Start waits until it's known where it goes.
  waits(card) {
    const now = routeNow(card);
    return !!now && !now.worked && !!now.answer.place?.reading;
  },
  under(card, api) {
    routeApi = api;
    const now = routeNow(card);
    if (!now) return '';
    const place = api.place();
    if (routeGuides(now, card)) {
      if (!state.routeGuideAt) state.routeGuideAt = Date.now();
      return routeGuideHTML(now.answer, state.routeLit, place?.terminal || null, place?.app);
    }
    return routeLineHTML(routeLine(now.answer, place, now.worked));
  },
  warn(card, api) {
    routeApi = api;
    // Wherever it starts, a conversation working it already among them: one situation, one set of words.
    const now = routeNow(card), place = now && api.place();
    if (!place) return null;
    const said = routeWarn(otherTicketIn(state.last.sessions, place.path, now.answer.key), now.answer.key);
    // With Go to It on the card, its own worktree is the one being worked: a new one by its name would be that one, so
    // the warning comes without a button, and Go to It is the way forward.
    return said && now.worked ? { text: said.text } : said;
  },
  press(t, card, api) {
    const now = routeNow(card);
    if (!now || !t.closest('.rt-guide, .rt-row')) return false;
    if (t.closest('.rt-guide') && !routeSettled()) return true;
    const way = t.closest('.rt-opt[data-way]');
    if (way) {
      state.routeLit = way.dataset.way;
      api.refresh();
      return true;
    }
    if (t.closest('.rt-notnow')) return routeNotNow(now, api);
    const act = t.closest('.rt-act')?.dataset.act;
    if (act === 'here') api.useHere();
    else if (act === 'reopen' && now.worked) openSession(now.worked, { carryOn: true });
    else if (act === 'setIt') {
      // The project's own page in Settings ▸ Tickets, where the option's folder is set, and the panel turned to it.
      native({ type: 'appsShow', app: 'ticket-routing', page: now.answer.project });
      turnToApps();
    } else if (act === 'signIn') native({ type: 'ticketRouteSignIn', tracker: now.ask.ticket.tracker });
    else if (act === 'again') {
      state.routeAsk = null;
      api.refresh();
    }
    return true;
  },
  // Esc on the guide, once it has settled, only puts it away: nothing starts, the card shows the project's folder, as
  // Not Now would start it, and Esc again closes the card, as it always does.
  boxKeys(card, e, api) {
    const now = routeNow(card);
    if (e.key !== 'Escape' || !routeGuides(now, card)) return false;
    if (routeSettled()) routeAway(now, api);
    return true;
  },
  // Start with the guide showing keeps its lit choice for the project. What was asked is read as it stands, not asked
  // again: the tickets module may have let the card's ticket go already, as the start went.
  sent(card) {
    const ask = state.routeAsk, answer = ask?.answer, now = routeSays(ask);
    if (routeGuides(now, card)) native({ type: 'ticketRouteSet', folder: ask.folder,
                                         way: { kind: state.routeLit, ...(answer.guide?.field && state.routeLit === 'field'
                                           ? { field: answer.guide.field.id } : {}) } });
    Object.assign(state, { routeAsk: null, routeLit: 'own', routeGuideAt: 0, routeNotNow: null });
  },
});

// Not Now: the guide goes, and this ticket starts in the project's folder, this once; the guide comes back next time.
// It starts only when Start would start it and nothing more: in a folder Claude hasn't worked in, Start would also
// trust it, which only your press of Trust and Start does, so the guide only goes.
function routeNotNow(now, api) {
  routeAway(now, api);
  if (!api.place()?.trust) api.start();
  return true;
}
// The guide put away for the card's ticket, until the card has another: it comes back next time.
function routeAway(now, api) {
  state.routeNotNow = now.ask.k;
  api.refresh();
}

// What the app said (ticketRoute): where the project's tickets open and where this one goes, or the guide's choices;
// told again once a ticket's fields are read. An answer for a ticket or folder the card has moved on from is let go.
// The guide changing shape (its field coming in) counts as showing anew, so a press meant for what was there can't
// land on what took its place.
window.ticketRouted = (answer) => {
  const ask = state.routeAsk;
  if (!ask || answer?.asked !== ask.asked) return;
  const had = ask.answer;
  ask.answer = answer;
  if (had && state.routeGuideAt && (!!had.guide?.field !== !!answer.guide?.field || !!had.guide?.reading
                                    !== !!answer.guide?.reading)) state.routeGuideAt = Date.now();
  // The guide's field, once it's offered, is lit only by your press: the recommendation stays lit until then.
  routeApi?.refresh();
};

// Signed in again (ticketRouteSignIn): the card's ticket is asked about afresh.
window.ticketRouteAgain = () => {
  state.routeAsk = null;
  routeApi?.refresh();
};

core.pointerTargets.push('.rt-opt', '.rt-notnow', '.rt-act');
