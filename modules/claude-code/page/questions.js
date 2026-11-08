// Claude's questions on its session's row (its question tool, through the permission hook), each kind in a look of its
// own, and your answers, which go back as Claude's own question box sends them (answerAsk with `answers`).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Each question card's picks, typing and skips by question, whether its "Type an answer" box is open, which of several
// questions is in view (`at`), and the words of the answer sent (for the line that then says so), by ask id, so a
// rebuild of the list keeps them.
moduleState({ quiz: {} });
function quizState(id) { return state.quiz[id] || (state.quiz[id] = { picks: {}, typed: {}, skipped: {} }); }

// A question card, by what's asked (askKind):
// - one pick (qOne): its options numbered, as the 1 to 9 keys pick them, each with what it means, and a last row to
//   type an answer; one press answers, with no Submit to find;
// - several picks (qMulti): "Pick any", boxes to tick, Skip and Submit;
// - several questions (qSteps): one at a time (pageHTML), ‹ › and Next moving between them, then Submit, the ones
//   left unanswered skipped;
// Every option has the one shape, its name with what it means under it, and what a question is about (its header,
// "Pick any") is a small label above it. A question's and its options' words are drawn from their markdown, as the
// reader draws a line (mdInline: escaped first), so no marks show.
// - a number (qNumber): − and + beside it, its unit, and Submit;
// Every card's answers sit in the one place, at its foot on the right, as a request's do.
// - a typed answer (qText): its box, Skip and Submit.
// × dismisses it without answering. Once sent, the first answer stands.
function quizHTML(ask, now = Date.now()) {
  state.shownAt[ask.id] ??= Date.now();
  const kind = askKind(ask), st = quizState(ask.id);
  const close = '<button class="icon-button small q-close" title="Dismiss without answering">×</button>';
  const goes = goesHTML(ask, now), qs = questionsOf(ask), q = qs[0] || {};
  const head = (label = '', words = mdInline(q.question)) => labelHTML(label) + `<div class="q-top"><span class="card-title">`
    + `${words}</span>${goes}${close}</div>` + (q.description && kind !== 'qSteps' ? `<div class="q-help">`
    + `${esc(q.description)}</div>` : '');
  const answers = (canSkip) => `<div class="perm-actions">${canSkip ? '<button class="q-skip">Skip</button>' : ''}`
    + `<button class="perm-allow q-submit"${quizAnswered(ask, st) ? '' : ' disabled'}>Submit</button></div>`;
  let body;
  if (kind === 'qOne') {
    const opts = q.options || [];
    const rows = opts.map((o, oi) => `<button class="opt ask-num" data-o="${oi}"><span class="tag mark">${oi + 1}`
      + `</span><span class="ask-num-label">${mdInline(o.label)}</span>${o.description ? `<span class="ask-num-desc">`
      + `${mdInline(o.description)}</span>` : ''}</button>`).join('')
      + typeRowHTML(st, 0, `<span class="tag mark">${opts.length + 1}</span>`, 'opt ask-num', 'ask-num-label');
    body = head(q.header) + `<div class="ask-nums">${rows}</div>`;
  } else if (kind === 'qMulti') {
    const picks = st.picks[0] || [];
    const opts = (q.options || []).map((o, oi) => `<button class="opt${picks.includes(oi) ? ' on' : ''}" data-q="0" `
      + `data-o="${oi}"><span class="opt-label">${mdInline(o.label)}</span>${o.description ? `<span class="opt-desc">`
      + `${mdInline(o.description)}</span>` : ''}</button>`).join('');
    const kept = !!String(st.typed[0] ?? '').trim();
    body = head([q.header, 'Pick any'].filter(Boolean).join(' · ')) + `<div class="q-opts multi">${opts}`
      + typeRowHTML(st, 0, '', `opt${kept ? ' on' : ''}`, 'opt-label', true) + '</div>' + answers(true);
  } else if (kind === 'qSteps') {
    body = pageHTML(ask, qs, st, goes, close);
  } else if (kind === 'qNumber') {
    // Its range beside it, in the colour of something to put right while what's typed is outside it.
    const value = st.typed[0] !== undefined ? st.typed[0] : (defaultOf(q) ?? q.min ?? '');
    const range = numberRange(q), outside = outOfRange(q, value);
    body = head() + '<div class="ask-foot"><span class="ask-stepper"><button class="ask-dec" title="Less">−</button>'
      + `<input class="field q-type" type="number" data-q="0" min="${esc(q.min ?? '')}" max="${esc(q.max ?? '')}" `
      + `step="${esc(q.step ?? 1)}" value="${esc(value)}"><button class="ask-inc" title="More">+</button></span>`
      + (q.unit ? `<span class="q-unit">${esc(q.unit)}</span>` : '')
      + `<span class="ask-foot-words ask-range${outside ? ' warn' : ''}" data-q="0">${esc(range)}</span></div>`
      + answers(false);
  } else {
    const value = st.typed[0] !== undefined ? st.typed[0] : defaultOf(q) ?? '';
    body = head() + `<input class="field q-type" data-q="0" placeholder="${esc(q.placeholder || 'Your answer')}" `
      + `value="${esc(value)}">` + answers(true);
  }
  const title = ask.input?.title ? `<div class="q-title">${esc(ask.input.title)}</div>` : '';
  return `<div class="perm quiz ask-${kind}" data-ask="${esc(ask.id)}">${title}${body}</div>`;
}

// A single question's last row, "Type an answer": pressed (or its number keyed), the row itself becomes the box, in
// place, at the same height, with the keyboard in it; Return sends what's typed (with the ticks, where it takes
// several), and Esc gives the row back. Words typed and kept show in the row, faint, in place of "Type an answer", so
// an answer typed is never hidden. `qi` is which question it's for (st.typing says which one's box is open), `mark`
// what leads the row (its number), `cls` its classes, `label` its words' class. In a list of options with marks
// (`inLabel`: several picks, or any question of several), the box sits in the row's words, after its mark, which is on
// once there are words, as they're then the answer, or go with the ticks.
function typeRowHTML(st, qi, mark, cls, label, inLabel = false) {
  const typed = String(st.typed[qi] ?? '');
  if (st.typing === qi) {
    const box = `<input class="field q-type ask-row-box" data-q="${qi}" placeholder="Type an answer" `
      + `aria-label="Type an answer" value="${esc(typed)}">`;
    return `<div class="${cls} ask-type-opt is-typing">${mark}`
      + `${inLabel ? `<span class="${label}">${box}</span>` : box}</div>`;
  }
  return `<button class="${cls} ask-type-opt" data-q="${qi}">${mark}<span class="${label}`
    + `${typed.trim() ? ' ask-kept' : ''}">${typed.trim() ? esc(typed.trim()) : 'Type an answer'}</span></button>`;
}

// Several questions, one at a time: the one in view, with what it's about and ‹ › and where you are at the top, its
// options numbered as a single pick's are (1 to 9 pick them, and the number after the last types an answer), only
// picked, never sent, or its box; then Skip, which leaves it out and moves on, and Next, which moves on whether it's
// answered or not, as one left unanswered is left out too. The last has Submit in Next's place, with the other answers
// in a line above it so the whole of what's sent is in view, or, while none is answered, what to do instead.
function pageHTML(ask, qs, st, goes, close) {
  const at = pageAt(ask, st), q = qs[at] || {}, last = at === qs.length - 1;
  const about = [q.header, q.multiSelect ? 'Pick any' : ''].filter(Boolean).join(' · ');
  const step = stepperHTML(at, qs.length, 'The question before', 'The next question',
                           st.skipped[at] ? ' · skipped' : '');
  const top = `<div class="q-head">${labelHTML(about) || '<span></span>'}${step}</div><div class="q-top">`
    + `<span class="card-title">${mdInline(q.question)}</span>${goes}${close}</div>`;
  let help = '';
  if (last) {
    const others = qs.slice(0, -1).map((qq, qi) => (st.skipped[qi] ? '' : answerTo(qq, st, qi))).filter(Boolean);
    help = others.length ? `<div class="card-help ask-with">With: ${esc(others.join(' · '))}</div>`
      : `<div class="card-help ask-none"${quizAnswered(ask, st) ? ' hidden' : ''}>Answer one, or × to leave them all `
        + 'to Claude</div>';
  }
  const forward = last
    ? `<button class="perm-allow q-submit"${quizAnswered(ask, st) ? '' : ' disabled'}>Submit</button>`
    : '<button class="perm-allow q-next">Next</button>';
  return top + `<div class="ask-page">${pageAnswerHTML(q, at, st)}</div>${help}`
    + `<div class="perm-actions"><button class="q-pass">Skip</button>${forward}</div>`;
}

// The question in view of several, kept within them as they change.
function pageAt(ask, st) {
  return Math.max(0, Math.min(st.at || 0, questionsOf(ask).length - 1));
}

// The answer to the question in view of several: its options numbered, picked (each with what it means under it), then
// Type an answer as the number after them, on where its words are the answer or go with the ticks; else its box.
function pageAnswerHTML(q, qi, st) {
  if (kindOf(q) === 'number' || kindOf(q) === 'text') return answerBoxHTML(q, qi, st);
  const opts = q.options || [], picks = st.picks[qi] || [], kept = !!String(st.typed[qi] ?? '').trim();
  const rows = opts.map((o, oi) => `<button class="opt ask-num${picks.includes(oi) ? ' on' : ''}" data-q="${qi}" `
    + `data-o="${oi}"><span class="tag mark">${oi + 1}</span><span class="ask-num-label">${mdInline(o.label)}</span>`
    + `${o.description ? `<span class="ask-num-desc">${mdInline(o.description)}</span>` : ''}</button>`).join('');
  const on = kept && (q.multiSelect || !picks.length) ? ' on' : '';
  return `<div class="ask-nums">${rows}`
    + typeRowHTML(st, qi, `<span class="tag mark">${opts.length + 1}</span>`, `opt ask-num${on}`, 'ask-num-label')
    + '</div>';
}

// Another of several questions into view, `to` its place: the box to type an answer goes, and for its first moment
// (justShown) it takes no press on its options, Skip, Next or Submit, which stay where they were as the question under
// them changes, so a quick second press meant for the one before would otherwise land on it unseen; and keys only
// for a blink (keyOnPage), so typing through the questions loses nothing.
function turnTo(ask, to) {
  const st = quizState(ask.id), at = Math.max(0, Math.min(to, questionsOf(ask).length - 1));
  if (at === pageAt(ask, st)) return;
  st.at = at;
  st.typing = false;
  state.shownAt[`qpage:${ask.id}`] = Date.now();
  render();
}

// What a question is about, as a small label above it (its header, "Pick any"), or nothing.
const labelHTML = (label) => (label ? `<div class="ask-label">${esc(label)}</div>` : '');

// One of several questions' answer: its options, each with what it means under it, to pick one of (or several, where it
// takes them), then Type an answer, as a single question has; else a box to type in.
function answerBoxHTML(q, qi, st) {
  const kind = kindOf(q);
  if (kind === 'number') {
    const value = st.typed[qi] !== undefined ? st.typed[qi] : defaultOf(q) ?? '', range = numberRange(q);
    return `<div class="ask-foot"><input class="field small q-type ask-sq-number" type="number" data-q="${qi}" `
      + `min="${esc(q.min ?? '')}" max="${esc(q.max ?? '')}" step="${esc(q.step ?? 1)}" value="${esc(value)}">`
      + (q.unit ? `<span class="q-unit">${esc(q.unit)}</span>` : '')
      + `<span class="ask-foot-words ask-range${outOfRange(q, value) ? ' warn' : ''}" data-q="${qi}">${esc(range)}`
      + '</span></div>';
  }
  if (kind === 'text') {
    const value = st.typed[qi] !== undefined ? st.typed[qi] : defaultOf(q) ?? '';
    return `<input class="field small q-type" data-q="${qi}" placeholder="${esc(q.placeholder || 'Your answer')}" `
      + `value="${esc(value)}">`;
  }
  const picks = st.picks[qi] || [], kept = !!String(st.typed[qi] ?? '').trim();
  return `<div class="q-opts${q.multiSelect ? ' multi' : ''}">` + (q.options || []).map((o, oi) => `<button class="opt`
    + `${picks.includes(oi) ? ' on' : ''}" data-q="${qi}" data-o="${oi}"><span class="opt-label">${mdInline(o.label)}</span>`
    + `${o.description ? `<span class="opt-desc">${mdInline(o.description)}</span>` : ''}</button>`).join('')
    + typeRowHTML(st, qi, '', `opt${kept ? ' on' : ''}`, 'opt-label', true) + '</div>';
}

// A question's answer as Claude's question box sends it, or '' if there isn't one yet. Words typed in win over a
// pick, and several picks are joined with commas; a number is a plain number within its range, and a number or
// text question left as it was answers with its default.
function answerTo(q, st, qi) {
  const typed = String(st.typed[qi] ?? '').trim(), kind = kindOf(q);
  if (kind === 'number') {
    const value = st.typed[qi] !== undefined ? typed : String(defaultOf(q) ?? q.min ?? '').trim(), n = Number(value);
    const inRange = Number.isFinite(n) && !(q.min != null && n < q.min) && !(q.max != null && n > q.max);
    return value !== '' && inRange ? String(n) : '';
  }
  if (kind === 'text') return st.typed[qi] !== undefined ? typed : String(defaultOf(q) ?? '').trim();
  const picked = (st.picks[qi] || []).map((oi) => q.options?.[oi]?.label).filter(Boolean);
  // Where it takes several, what's typed goes with the ticks; on a single pick, it's the answer in place of one.
  return q.multiSelect ? [...picked, typed].filter(Boolean).join(', ') : typed || picked.join(', ');
}

// Whether Submit has something to send: an answer to the question, or to any of several; and none of them a number
// typed outside its range, which its range beside it says, rather than its being left out unseen.
function quizAnswered(ask, st) {
  const qs = questionsOf(ask);
  if (qs.some((q, qi) => kindOf(q) === 'number' && st.typed[qi] !== undefined && outOfRange(q, st.typed[qi])))
    return false;
  return qs.some((q, qi) => !st.skipped[qi] && answerTo(q, st, qi) !== '');
}

// The answers as Claude's question box sends them: question text -> answer. Skipped and unanswered ones are left out.
function quizAnswers(ask) {
  const st = quizState(ask.id), answers = {};
  questionsOf(ask).forEach((q, qi) => {
    const value = st.skipped[qi] ? '' : answerTo(q, st, qi);
    if (value) answers[q.question] = value;
  });
  return answers;
}

// ---- Presses and keys ----

// A press on a question card (pressRequest has already let one through only once the card has been seen): true once
// it's been taken care of. One of a single pick's options answers at once; any other pick, chip, − or + only picks;
// Submit and Skip send; × dismisses.
function pressQuestion(card, e) {
  if (!card.matches('.quiz')) return false;
  const id = card.dataset.ask, ask = state.last.sessions.find((x) => x.ask?.id === id)?.ask;
  const button = e.target.closest('button');
  if (!button || !ask) return !!button;
  e.preventDefault();
  if (state.answering[id] || button.disabled) return true;
  const st = quizState(id), paged = askKind(ask) === 'qSteps';
  if (paged && button.matches('.ask-prev, .ask-next')) {
    turnTo(ask, pageAt(ask, st) + (button.matches('.ask-next') ? 1 : -1));
    return true;
  }
  if (paged && justShown(`qpage:${id}`)) return true;
  if (paged && button.matches('.q-next')) return turnTo(ask, pageAt(ask, st) + 1), true;
  if (paged && button.matches('.q-pass')) {
    const at = pageAt(ask, st);
    st.skipped[at] = true;
    st.picks[at] = [];
    st.typed[at] = '';
    st.typing = false;
    if (at < questionsOf(ask).length - 1) turnTo(ask, at + 1);
    else render();
    return true;
  }
  if (button.matches('.ask-type-opt')) return openTyping(id, +(button.dataset.q || 0)), true;
  if (!paged && button.matches('.ask-num[data-o]')) return answerOne(ask, +button.dataset.o), true;
  if (button.matches('.opt[data-o]')) {
    const qi = +button.dataset.q, oi = +button.dataset.o, picks = st.picks[qi] || [];
    const multi = !!questionsOf(ask)[qi]?.multiSelect;
    setPicks(id, qi, multi ? (picks.includes(oi) ? picks.filter((x) => x !== oi) : [...picks, oi])
      : picks.includes(oi) ? [] : [oi], multi);
    return true;
  }
  if (button.matches('.ask-dec, .ask-inc')) return stepNumber(ask, button.matches('.ask-inc') ? 1 : -1), true;
  if (button.matches('.q-close')) {
    answered(id, 'dismissed');
    native({ type: 'answerAsk', id, allow: false });
  } else if (button.matches('.q-skip')) {
    questionsOf(ask).forEach((q, qi) => { st.skipped[qi] = true; });
    answered(id, 'skipped');
    native({ type: 'answerAsk', id, allow: true, answers: {} });
  } else if (button.matches('.q-submit')) {
    const answers = quizAnswers(ask);
    answered(id, 'answered');
    st.sent = Object.values(answers).join(' · ');
    native({ type: 'answerAsk', id, allow: true, answers });
  }
  render();
  return true;
}

// A single pick's option, by a press or its key: the answer, sent at once.
function answerOne(ask, oi) {
  const q = questionsOf(ask)[0], label = q?.options?.[oi]?.label;
  if (!label || state.answering[ask.id]) return;
  answered(ask.id, 'answered');
  quizState(ask.id).sent = label;
  native({ type: 'answerAsk', id: ask.id, allow: true, answers: { [q.question]: label } });
  render();
}

// A single pick's box to type an answer in, opened and given the keys: what's typed goes into it, not to the card's own
// keys (whose 1 to 9 would answer). The same request may be drawn in more than one place, so the box is the one in the
// card that has the keys (pressed or keyed, wherever it is: heldCard), else the list's, never the copy of the row held
// at the list's edge. Opened past the list's foot, the list moves the least that shows it, its card's top kept in view
// (showLeast); otherwise nothing moves.
function openTyping(id, qi = 0) {
  quizState(id).typing = qi;
  render();
  const held = heldCard(), card = held?.dataset.ask === id ? held
    : [...list.querySelectorAll('.row[data-id] .perm[data-ask]')].find((c) => c.dataset.ask === id);
  const box = card?.querySelector(`.ask-row-box[data-q="${qi}"]`);
  if (!box) return;
  box.focus({ preventScroll: true });
  if (list.contains(box)) showLeast(box, card);
}

// Return in the row that became its box: on a single pick, the typed answer goes; where it takes several, the ticks
// and the typed words go together, as Submit sends them; on one of several questions, Next moves on (Submit, on the
// last), the words kept.
function returnedInRow(box) {
  const card = box.closest('.perm'), ask = state.last.sessions.find((x) => x.ask?.id === card.dataset.ask)?.ask;
  if (askKind(ask) === 'qOne') return answerOneTyped(box);
  card.querySelector('.perm-allow:not([disabled])')?.dispatchEvent(new MouseEvent('mousedown', { bubbles: true,
                                                                                               button: 0 }));
}

// A typed answer to a single pick, sent with Return.
function answerOneTyped(box) {
  const id = box.closest('.perm').dataset.ask, ask = state.last.sessions.find((x) => x.ask?.id === id)?.ask;
  const q = questionsOf(ask)[0], text = box.value.trim();
  if (!q || !text || state.answering[id]) return;
  answered(id, 'answered');
  quizState(id).sent = text;
  native({ type: 'answerAsk', id, allow: true, answers: { [q.question]: text } });
  render();
}

// − or + on a number: a step down or up from what's there (its default, else its least), within its range.
function stepNumber(ask, way) {
  const q = questionsOf(ask)[0] || {}, st = quizState(ask.id), step = Number(q.step) || 1;
  const now = Number(st.typed[0] !== undefined ? st.typed[0] : (defaultOf(q) ?? q.min ?? 0)) || 0;
  let next = now + way * step;
  if (q.min != null) next = Math.max(Number(q.min), next);
  if (q.max != null) next = Math.min(Number(q.max), next);
  st.typed[0] = String(next);
  delete st.skipped[0];
  render();
}

// A question's picks, from a press or a key, which un-skip it. On a single pick, the last thing pressed wins, so a pick
// replaces words typed for it, as typing replaces the pick; where it takes several (`multi`), the words go with the
// ticks.
function setPicks(id, qi, picks, multi = false) {
  const st = quizState(id);
  st.picks[qi] = picks;
  if (!multi) st.typed[qi] = '';
  delete st.skipped[qi];
  render();
}

// The picks a key makes among a question's `count` options, given the ones made: 1 to 9 picks that option, or where
// the question takes several, adds it or takes it out. null for any other key, or a number past the options.
function keyPick(count, multi, picks, key) {
  if (!/^[1-9]$/.test(key)) return null;
  const oi = +key - 1;
  if (oi >= count) return null;
  return multi ? (picks.includes(oi) ? picks.filter((x) => x !== oi) : [...picks, oi]) : [oi];
}

// Keys on a question card once it's been pressed (core.keyCards): on a single pick, 1 to 9 answers with that option,
// and the number after the last opens the box to type an answer; on several picks, 1 to 9 tick and untick. On several
// questions, 1 to 9 pick on the one in view as its kind does, the number after its options opens its box, and ← and →
// move between them, as Claude Code's own box does. Return presses Submit (Next, before the last), and Esc lets the
// keyboard go, as the core does for any such card.
function keyOnRequest(card, e) {
  holdAsk(card.dataset.ask);
  const id = card.dataset.ask, ask = state.last.sessions.find((x) => x.ask?.id === id)?.ask;
  if (ask && askKind(ask) === 'qSteps') return keyOnPage(ask, e);
  if (!ask || !/^[1-9]$/.test(e.key)) return false;
  const kind = askKind(ask), q = questionsOf(ask)[0] || {}, count = (q.options || []).length;
  if (kind === 'qOne') {
    if (+e.key === count + 1) { openTyping(id); return true; }
    if (+e.key <= count) answerOne(ask, +e.key - 1);
    return true;
  }
  if (kind !== 'qMulti') return false;
  const picks = keyPick(count, true, quizState(id).picks[0] || [], e.key);
  if (picks) setPicks(id, 0, picks, true);
  return true;
}

// How long a question just turned to takes no key (ms): a key lands by what's in view, not where the pointer is, so it
// need wait only long enough that one pressed with the key that turned it isn't taken for it; a press waits FRESH_MS.
const PAGE_KEY_MS = 150;
const keyTooSoon = (ask) => Date.now() - (state.shownAt[`qpage:${ask.id}`] || 0) < PAGE_KEY_MS;

// Keys on several questions (keyOnRequest's), the one in view taking 1 to 9 and Return only a moment after it turned.
function keyOnPage(ask, e) {
  const st = quizState(ask.id), at = pageAt(ask, st);
  if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
    turnTo(ask, at + (e.key === 'ArrowRight' ? 1 : -1));
    return true;
  }
  if (e.key === 'Enter' && keyTooSoon(ask)) return true;
  const q = questionsOf(ask)[at] || {}, count = (q.options || []).length;
  if (!/^[1-9]$/.test(e.key) || kindOf(q) === 'number' || kindOf(q) === 'text') return false;
  if (keyTooSoon(ask)) return true;
  // The number after its options opens its box: 1, on a question with none, where Type an answer is all there is.
  if (+e.key === count + 1) return openTyping(ask.id, at), true;
  const picks = keyPick(count, !!q.multiSelect, st.picks[at] || [], e.key);
  if (picks) setPicks(ask.id, at, picks, !!q.multiSelect);
  return true;
}

// Whether a press on a request or question card answers it, rather than only picking: Allow once or Deny, ×, Submit
// or Skip, or a single pick's option. Such a press doesn't take the keyboard, and gives it back if the card had it.
function pressAnswers(card, target) {
  const button = target.closest('button');
  if (!button || button.disabled) return false;
  if (button.matches('.ask-type-opt, .ask-more, .ask-prev, .ask-next, .ask-dec, .ask-inc, .q-next, .q-pass'))
    return false;
  return !button.matches('.opt') || button.matches('.ask-num') && !card.matches?.('.ask-qSteps');
}

// An answer typed in: kept in the question's state (so rebuilds keep it), and it replaces that question's picks.
function typeAnswer(box) {
  const card = box.closest('.perm'), id = card.dataset.ask, st = quizState(id), qi = +box.dataset.q;
  const ask = state.last.sessions.find((x) => x.ask?.id === id)?.ask, q = questionsOf(ask)[qi];
  holdAsk(id);
  st.typed[qi] = box.value;
  delete st.skipped[qi];
  // Typed words replace a single pick; where it takes several, they go with the ticks. In a list of options with marks,
  // the row's own mark is on while there are words.
  box.closest('.q-opts .ask-type-opt, .ask-page .ask-type-opt')?.classList.toggle('on', !!box.value.trim());
  if (box.value && box.type !== 'number' && !q?.multiSelect && (st.picks[qi] || []).length) {
    st.picks[qi] = [];
    card.querySelectorAll(`[data-q="${qi}"].on`).forEach((o) => o.classList.remove('on'));
  }
  const submit = card.querySelector('.q-submit');
  if (submit && ask) submit.disabled = !quizAnswered(ask, st);
  // On the last of several questions, what to do while none is answered goes once one is.
  card.querySelector('.ask-none')?.toggleAttribute('hidden', !!ask && quizAnswered(ask, st));
  // A number's range turns to the colour of something to put right while what's typed is outside it.
  if (q && box.type === 'number')
    card.querySelector(`.ask-range[data-q="${qi}"]`)?.classList.toggle('warn', outOfRange(q, box.value));
}

core.typing.push(['.perm.quiz .q-type', typeAnswer]);
// The row that became its box: Return sends (with the ticks, where it takes several), Esc gives the row back, keeping
// what was typed, which the row then shows.
core.returns.push(['.perm.quiz .ask-row-box', returnedInRow]);
core.escapes.push(['.perm.quiz .ask-row-box', (box) => {
  const id = box.closest('.perm').dataset.ask;
  quizState(id).typing = false;
  render();
}]);
core.forgotten.keys.push('quiz');
core.forgotten.prefixes.push('qpage');
