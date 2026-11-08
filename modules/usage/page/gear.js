// The gear's seats: "Gear" and its number, then a seat for each gear from the lowest to the highest, those up to your
// gear in a box, drawn on the usage card, the one place the gear is changed; the panel's page gets the gear through
// core.gear, for what shows it beyond the card. The seats show the gear the app last said (setGear, on both pages at
// once), and a press only asks the app (gearSet), which keeps the new gear: so the card and the panel never disagree.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What the app last said of the gear (usage.js says what's in it), null until it's known and while the gear is off in
// Settings, and whether it's off there; and what runs each time it says it, with whether your press made the change.
const gearNow = { facts: null, off: false };
const gearWatchers = [];

// The seats, as usage.js lays them out (gearSeats): "Gear" and its number, the box round your gear's seats, the ring a
// press would make, the seats to press, and the notch under the recommended one. Drawn as the card is built, before
// the gear is known; gearSeatsDraw draws what the app says.
function gearSeatsHTML(facts = gearNow.facts) {
  const seats = Array.from({ length: GEAR_HIGHEST }, (_, i) => `<button type="button" class="u-seat"
    data-to="${i + 1}" aria-label="${GEAR_SEATS.seat(i + 1, false, false)}"><i></i></button>`).join('');
  return `<span class="u-seats" role="group" aria-label="${GEAR_SEATS.label}"><span class="u-seats-read"><span
    class="u-seats-label">${GEAR_SEATS.label}</span><span class="u-num" aria-live="polite"><span>${
    facts?.gear ?? '–'}</span></span></span><span class="u-seats-row" style="--seats: ${GEAR_HIGHEST}"><span
    class="u-box"></span><span class="u-ring"></span>${seats}<span class="u-rec"></span></span></span>`;
}

// Every set of seats drawn in `root` shows the gear: what VoiceOver says for them as a whole, how many are working, the
// box's end, each seat in it or past it, lit or not and what VoiceOver says for it, the notch. After your press, the
// old number fades and lifts out as the new one comes in (0 to 160 ms), the first beat of what the press changes, and
// the box eases to its new end (gear.css); otherwise they're there at once. With reduced motion, the number
// cross-fades.
function gearSeatsDraw(root, facts, pressed) {
  if (!facts) return;
  const laid = gearSeats(facts), calmNow = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  for (const box of root.querySelectorAll('.u-seats')) {
    const row = box.querySelector('.u-seats-row');
    if (!pressed) box.classList.add('is-still');
    box.classList.toggle('no-gear', facts.gear == null);
    row.style.setProperty('--end', laid.end);
    row.classList.toggle('has-rec', laid.rec != null);
    if (box.getAttribute('aria-label') !== laid.label) box.setAttribute('aria-label', laid.label);
    if (laid.rec != null) row.style.setProperty('--rec', laid.rec);
    box.querySelectorAll('.u-seat').forEach((seat, i) => {
      seat.classList.toggle('in', laid.seats[i].in);
      seat.classList.toggle('lit', laid.seats[i].lit);
      const label = laid.seats[i].label;
      if (seat.getAttribute('aria-label') !== label) seat.setAttribute('aria-label', label);
    });
    if (!pressed) {
      void box.offsetWidth;
      box.classList.remove('is-still');
    }
    const num = box.querySelector('.u-num'), old = num.lastElementChild, text = String(facts.gear ?? '–');
    if (old.textContent === text) continue;
    if (!pressed || !old.animate) {
      old.textContent = text;
      continue;
    }
    const next = document.createElement('span');
    next.textContent = text;
    num.appendChild(next);
    const lift = (y) => calmNow ? 'none' : `translateY(${y}px)`;
    const out = old.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: lift(-3) }],
                            { duration: 100, easing: 'ease', fill: 'forwards' });
    out.finished.then(() => old.remove(), () => old.remove());
    next.animate([{ opacity: 0, transform: lift(3) }, { opacity: 1, transform: 'none' }],
                 { duration: 160, easing: 'cubic-bezier(.2, .8, .2, 1)' });
  }
}

// The ring round the box a press on seat `to` would make, while it's pointed at; none for null.
function gearRing(root, to) {
  for (const box of root.querySelectorAll('.u-seats')) {
    box.classList.toggle('is-pointing', to != null);
    if (to != null) box.querySelector('.u-seats-row').style.setProperty('--to', to);
  }
}

// A press on a seat: the app keeps that gear and says it.
function gearPress(seat) {
  native({ type: 'gearSet', to: Number(seat.dataset.to) });
}

// What the app says each time the gear's facts change, and at once after your press (`pressed`): on both pages. Null,
// with `off`, while the gear is turned off in Settings, so what shows the gear beyond the card can tell that from a
// gear not known yet.
window.setGear = (facts, pressed, off) => {
  gearNow.facts = facts || null;
  gearNow.off = !!off;
  if (typeof document !== 'undefined') gearSeatsDraw(document, gearNow.facts, pressed);
  for (const watcher of gearWatchers) watcher(gearNow.facts, pressed);
};

// On the panel's page, the gear for the rest of it (parts/bridge/page/modules.js says what each is), without the
// seats, which only the card draws.
if (typeof core !== 'undefined') {
  core.gear = {
    facts: () => gearNow.facts,
    off: () => gearNow.off,
    changed: gearWatchers,
    line: (facts) => gearLine(facts),
    whyLine: (facts, now) => gearWhy(facts, now),
    words: { ...GEAR_WORDS, where: (facts) => gearWhere(facts, gearNow.off) },
  };
}
