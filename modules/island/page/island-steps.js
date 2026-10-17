// The card of the island's commits stage: the commits not on GitHub yet, and the steps to take with them.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The card while it's up ({sid, step, card}), and where its bottom edge is; and each row's card as the app last said it
// (showStageCard), by session.
moduleState({ stepsShown: null, stepsBottom: 0, stageCards: {} });

// The island's commits stage, pointed at: its menu as a card below it (the app's, stageCard), with the commits not on
// GitHub yet and the steps to take with them; pressing the stage itself opens what they changed (pressStage). The card
// stays while the pointer is on the stage or on the card, and goes as soon as it's on neither.
const stepsCard = document.getElementById('steps');
function syncSteps(el) {
  const seg = el?.closest('.seg[data-stage="commits"]'), onCard = !!el?.closest('#steps');
  if (onCard) return;
  const sid = seg?.closest('.island')?.dataset.sid;
  if (!sid || !(+seg.dataset.count > 0)) { hideSteps(); return; }
  if (state.stepsShown?.sid === sid) { placeSteps(seg); return; }
  state.stepsShown = { sid, step: seg.dataset.step || '', card: null };
  // Shown at once from the last answer, which is never older than the last change (keepStageCards), and drawn again
  // if the app's answer now differs.
  const kept = state.stageCards[sid];
  if (kept?.step === (seg.dataset.step || '')) showStageCard(sid, kept.card);
  native({ type: 'stageCard', sessionId: sid, stage: 'commits', step: seg.dataset.step || '', count: +seg.dataset.count });
}

// Each row's commits stage card as the app last said it, asked for again as the rows come in, the app answering only
// when it has changed, so pointing at the stage shows it at once.
function keepStageCards() {
  for (const seg of document.querySelectorAll('.island .seg[data-stage="commits"]')) {
    const sid = seg.closest('.island').dataset.sid;
    if (!(+seg.dataset.count > 0) || seg.closest('.closed')) continue;
    native({ type: 'stageCard', sessionId: sid, stage: 'commits', step: seg.dataset.step || '',
             count: +seg.dataset.count, quiet: true });
  }
}

window.showStageCard = (sid, card, step) => {
  state.stageCards[sid] = { card, step: step ?? state.stageCards[sid]?.step ?? '' };
  const shown = state.stepsShown;
  if (shown?.sid !== sid) return;
  // The card is the one for this step now (the stage's step can change while it's up), and a press says so.
  if (step != null) shown.step = step;
  if (shown.card && JSON.stringify(shown.card) === JSON.stringify(card)) return;
  // Each time its steps are drawn, as it comes up and whenever they change while it's up (a step that can now be
  // pressed, or one a longer list has moved under the pointer), they take no press for a moment: a press meant for
  // what was there before can't land on one.
  state.shownAt['steps:' + sid] = Date.now();
  shown.card = card;
  stepsCard.innerHTML = stepsHTML(card);
  stepsCard.hidden = false;
  const seg = segAt(sid, 'commits');
  if (seg) placeSteps(seg);
  reportHeight();
};

function stepsHTML(card) {
  const items = (card.items || []).map((subject) => `<div class="f-file">${esc(subject)}</div>`).join('');
  const more = card.more > 0 ? `<div class="f-more">and ${thousands(card.more)} more</div>` : '';
  const steps = (card.steps || []).map((st) => `<button class="st-step" data-step="${esc(st.step)}" title="${esc(st.tip)}"`
    + `${card.enabled ? '' : ' disabled'}>${esc(st.title)}</button>`).join('');
  return `<div class="f-head"><span>${esc(card.heading)}</span></div><div class="f-list">${items}${more}</div>`
    + (steps ? `<div class="st-steps">${steps}</div>` : '')
    + (card.wait ? `<div class="st-wait">${esc(card.wait)}</div>` : '')
    + '<div class="st-hint">Press the stage to see what they changed.</div>';
}

// A stage of a row's island, the one in view (a row pinned below its folded group is there twice).
function segAt(sid, stage) {
  return [...document.querySelectorAll(`.island[data-sid="${CSS.escape(sid)}"] .seg[data-stage="${stage}"]`)]
    .find((seg) => !seg.closest('.closed')) || null;
}

// Just below the stage, or above it when the panel can't grow to fit it below.
function placeSteps(seg) {
  if (stepsCard.hidden) return;
  const r = seg.getBoundingClientRect(), h = stepsCard.offsetHeight, w = stepsCard.offsetWidth;
  const column = document.getElementById('root').getBoundingClientRect();
  const below = r.bottom + 6 + h + 8 <= state.panelMax;
  stepsCard.style.left = Math.max(column.left + 10, Math.min(r.left - 4, column.right - w - 10)) + 'px';
  stepsCard.style.top = (below ? r.bottom + 6 : Math.max(6, r.top - h - 6)) + 'px';
  stepsCard.classList.toggle('above', !below);
  state.stepsBottom = Math.ceil((below ? r.bottom + 6 : r.top - h - 6) + h + 8);
}

function hideSteps() {
  if (!state.stepsShown) return;
  state.stepsShown = null;
  stepsCard.hidden = true;
  reportHeight();
}

// A step on the card: the app asks the agent, in the step's own words, if the card still offers it.
stepsCard.addEventListener('mousedown', (e) => {
  const button = e.target.closest('.st-step[data-step]');
  const shown = state.stepsShown;
  if (e.button !== 0 || !button || button.disabled || !shown) return;
  e.preventDefault();
  if (justShown('steps:' + shown.sid)) return;
  native({ type: 'stageStep', sessionId: shown.sid, from: shown.step, step: button.dataset.step });
  hideSteps();
});

core.pointerWatchers.push(syncSteps);
core.pointerTargets.push('.st-step');
core.afterDraw.push(keepStageCards);
core.overhangs.push(() => (state.stepsShown ? state.stepsBottom : 0));
core.forgotten.prefixes.push('steps');
