// Claude's "Switch model?" (switching re-reads a cached conversation), asked in the panel instead of in Claude: the app
// asks it before sending /model to a Claude Desktop conversation, or when Claude asks anyway, and answers Claude's own
// box with what's picked here.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The question while it's up, { sessionId, never }, and where its card ends.
moduleState({ asking: null, askBottom: 0 });

const switchCard = document.getElementById('ask');

function showSwitchQuestion({ sessionId, from, to }) {
  state.asking = { sessionId, never: false };
  const was = esc(core.agent.modelName(from) || 'its model'), now = esc(core.agent.modelName(to) || to);
  switchCard.innerHTML = `<h3>Switch model?</h3>
      <p>This session is cached for ${was}. Switching to ${now} means
        Claude re-reads the whole session on your next message, which uses more of your limit.</p>
      <div class="never"><span class="box"></span>Don't ask again</div>
      <div class="buttons"><button class="cancel">Cancel</button><button class="go">Switch model</button></div>`;
  switchCard.hidden = false;
  placeAsk();
  reportHeight();
}

// Just below its row, or above it when there's no room below.
function placeAsk() {
  const row = [...document.querySelectorAll('.row')].find((r) => r.dataset.id === state.asking.sessionId);
  const r = row?.getBoundingClientRect(), h = switchCard.offsetHeight;
  let top = r ? r.bottom + 4 : 56;
  if (top + h + 8 > state.panelMax) top = Math.max(6, (r ? r.top : 56) - h - 4);
  switchCard.style.top = top + 'px';
  state.askBottom = Math.ceil(top + h + 8);
}

// Don't ask again ticks on and off; Switch model or Cancel answers, and the card goes.
switchCard.addEventListener('mousedown', (e) => {
  if (!state.asking) return;
  if (e.target.closest('.never')) {
    state.asking.never = !state.asking.never;
    switchCard.querySelector('.never').classList.toggle('on', state.asking.never);
    return;
  }
  const go = !!e.target.closest('.go');
  if (!go && !e.target.closest('.cancel')) return;
  native({ type: 'switchAnswer', sessionId: state.asking.sessionId, ok: go, never: go && state.asking.never });
  state.asking = null;
  switchCard.hidden = true;
  reportHeight();
});

window.askSwitch = (question) => showSwitchQuestion(question);

// It follows its row as the rows come in, and the panel grows to fit it while it's up.
core.updating.push(() => { if (state.asking) placeAsk(); });
core.overhangs.push(() => (state.asking ? state.askBottom : 0));
core.pointerTargets.push('#ask button');
