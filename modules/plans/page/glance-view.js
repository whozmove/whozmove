// A plan at a glance, drawn: the card a plan opens on with the whole plan folded by section, or the plan as written,
// as you choose to read plans; and the few lines the plan card on a row shows. The places that show a plan (the
// reader, the request card) ask for these through core.plans, passing the text they have; they never call what's
// here, and nothing here reads what's theirs.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Your picks that differ from Claude's, by the request's id (only the plan Claude waits on takes picks); what's open,
// by session, then plan and part; and what each view was last drawn from, by session, then plan, so a press draws it
// again the same way. Each goes a minute after its session or request has gone from the list (forgetGone). And how
// you read a plan beside the list, Skimmed or Full version of the plan: one choice for every plan, kept across
// launches.
moduleState({ planPicks: {}, planOpen: {}, planDrawn: {}, planReadAs: store.get('planReadAs', 'skimmed') });
core.forgotten.keys.push('planPicks', 'planOpen', 'planDrawn');

const PLAN_SLOT_WORDS = { changes: 'What changes for you', decide: 'You decide', risks: 'Could go wrong',
                          tryIt: 'You\'ll try', keeps: 'What it keeps or sends', leftOut: 'Left out' };

const PLAN_LOOKS = [['skimmed', 'Skimmed'], ['full', 'Full version of the plan']];

const planLineHTML = (words, cls = '') => `<p class="gl-line${cls ? ` ${cls}` : ''}">${mdInline(words)}</p>`;
const planIsOpen = (sid, id, what) => !!state.planOpen[sid]?.[`${id}\n${what}`];
// Whether a section is open: a section that starts open (planSections' `opens`) is kept as folded by you, so the same
// press turns either way.
const planFoldOpen = (sid, id, s, i) => planIsOpen(sid, id, `fold ${i}`) !== !!s.opens;

// A choice as one line (its question and the option picked, Recommended or Your Pick), which opens to its options and
// why. Only on the plan Claude waits on now does an option take a pick, and only where Claude recommended one (a pick
// goes back "in place of" Claude's); anywhere else the line shows Claude's pick and the options can't be pressed.
// Held (while the notes your picks go back in are being read), it shows your picks, and they can't be changed.
// Options that can't be pressed say why, under why Claude picked as it did (planUnpressed).
function planChoiceHTML(d, i, { sid, id, waiting, held }) {
  if (!d.options.length) return planLineHTML(d.q);
  const mine = waiting ? state.planPicks[id]?.[i] : undefined;
  const p = mine ?? d.rec, open = planIsOpen(sid, id, `choice ${i}`);
  const answer = p >= 0 ? `<span class="gl-pick">${mdInline(d.options[p])}</span>`
    + (mine !== undefined ? '<span class="tag pick gl-tag">Your pick</span>'
      : '<span class="tag gl-tag">Recommended</span>')
    : `<span class="gl-pick gl-none">${d.options.length} choices</span>`;
  const options = open ? `<div class="gl-open"><div class="options gl-options" role="radiogroup" `
      + `aria-label="${esc(planPlain(d.q))}">`
      + d.options.map((o, k) => `<button type="button" class="option gl-option" role="radio" aria-checked="${k === p}" `
        + `data-choice="${i}" data-option="${k}"${planUnpressed(d, waiting, held) ? ' disabled' : ''}>`
        + `<span class="tickbox round"></span><span class="gl-otext">${mdInline(o)}</span>`
        + `${k === d.rec ? '<span class="tag gl-tag">Recommended</span>' : ''}</button>`).join('') + '</div>'
      + `<p class="gl-why">${d.why ? `Why: ${mdInline(d.why)}` : 'The plan gives no why.'}</p>`
      + (planUnpressed(d, waiting, held) ? `<p class="gl-why">${planUnpressed(d, waiting, held)}</p>` : '') + '</div>'
    : '';
  return `<div class="gl-choice"><button type="button" class="gl-dline" data-choice="${i}" aria-expanded="${open}">`
    + `<span class="gl-chev" aria-hidden="true">›</span><span class="gl-q">${mdInline(d.q)}`
    + `${/[?:.]$/.test(planPlain(d.q)) ? '' : ':'}</span>${answer}</button>`
    + `${options}</div>`;
}

// Why a choice's options can't be pressed, or '' when they can: a pick goes back only on the plan Claude waits on
// now and that can be answered here, "in place of" the option it recommended, and is held while the notes it goes
// back in are open. Each a short line, true whichever way the plan can't take picks (an older version, one sent back
// or stopped, one from a session the panel can't answer), and naming nothing outside the card.
function planUnpressed(d, waiting, held) {
  if (!waiting) return 'This plan can\'t take your picks here, so it shows Claude\'s.';
  if (d.rec < 0) return 'Claude recommended none of these, so there\'s no pick to change.';
  return held ? 'Your picks are held while your notes are open.' : '';
}

// Every choice as lines, for a view with nothing to press: its question and Claude's pick, marked Recommended, or its
// options when Claude picked none; then why, which a choice with no options keeps too.
function planChoiceLinesHTML(glance) {
  const why = (d) => (d.why ? `<p class="gl-why">Why: ${mdInline(d.why)}</p>` : '');
  return `<div class="gl-choices">${glance.decide.map((d) => {
    if (!d.options.length) return `<div class="gl-choice">${planLineHTML(d.q)}${why(d)}</div>`;
    const q = `<span class="gl-q">${mdInline(d.q)}${/[?:.]$/.test(planPlain(d.q)) ? '' : ':'}</span> `;
    const pick = d.rec >= 0 ? `<span class="gl-pick">${mdInline(d.options[d.rec])}</span>`
      + '<span class="tag gl-tag">Recommended</span>'
      : `<span class="gl-pick gl-none">${d.options.map((o) => mdInline(o)).join(', or ')}</span>`;
    return `<div class="gl-choice"><p class="gl-line">${q}${pick}</p>${why(d)}</div>`;
  }).join('')}</div>`;
}

function planChoicesHTML(glance, where) {
  const all = glance.decide, more = all.length - PLAN_CHOICES_SHOWN;
  const shown = more > 0 && !planIsOpen(where.sid, where.id, 'more') ? all.slice(0, PLAN_CHOICES_SHOWN) : all;
  return `<div class="gl-choices">${shown.map((d, i) => planChoiceHTML(d, i, where)).join('')}`
    + (shown.length < all.length ? `<button type="button" class="button quiet small gl-more">+${more} more `
      + `${more === 1 ? 'choice' : 'choices'}</button>` : '') + '</div>';
}

// What changes for you: its lines, then Before and After side by side; or, pulled from no heading, a line saying
// where to read instead, never another slot's words.
function planChangesHTML(glance, who) {
  const ba = (label, words) => (words ? `<div class="gl-ba"><span class="gl-ba-label">${label}</span>`
    + `${planLineHTML(words)}</div>` : '');
  const html = (glance.slots.changes || []).map((l) => planLineHTML(l)).join('')
    + (glance.before || glance.after
      ? `<div class="gl-bas">${ba('Before', glance.before)}${ba('After', glance.after)}</div>` : '');
  if (html || glance.from !== 'pulled') return html;
  const plan = who ? `${who}'s plan` : 'The plan';
  return glance.context ? planLineHTML(`${plan} doesn't say what changes for you: read Context below`, 'gl-none')
    : planLineHTML('The plan doesn\'t say what changes for you: read it below', 'gl-none');
}

// The card a plan opens on: each slot the plan has, in their one order, under its label; pulled from a heading, the
// label says which, and a slot whose heading has more under it says so.
// Bare (One Task's, where nothing in it presses), it sits in its view with no edge of its own, and each choice is
// lines (planChoiceLinesHTML).
function planCardHTML(glance, where, bare = false) {
  const inSlot = (key, html) => `<div class="gl-unit"><span class="caps">${PLAN_SLOT_WORDS[key]}`
    + (glance.sources[key] ? `<span class="gl-src">From “${esc(glance.sources[key])}”</span>` : '') + `</span>${html}`
    + (glance.more[key] ? planLineHTML(`More under “${glance.more[key]}”`, 'gl-none') : '') + '</div>';
  const lines = (key) => (glance.slots[key] || []).map((l) => planLineHTML(l)).join('');
  const changes = planChangesHTML(glance, where.who);
  return `<div class="gl-card${bare ? ' bare' : ''}"><div class="gl-head"><span class="gl-title">At a glance</span>`
    + `<span class="gl-from">${glance.from === 'pulled' ? 'Pulled from the plan\'s headings' : 'Written with the plan'}`
    + '</span></div>'
    + (changes ? inSlot('changes', changes) : '')
    + (glance.decide.length ? inSlot('decide', bare ? planChoiceLinesHTML(glance)
      : planChoicesHTML(glance, where)) : '')
    + ['risks', 'tryIt', 'keeps', 'leftOut'].filter((k) => glance.slots[k]).map((k) => inSlot(k, lines(k))).join('')
    + (where.flow ? planFlowHTML(where.flow) : '')
    + '</div>';
}

// The plan's flow on its card, small (core.diagrams), or in words where it isn't drawn here; pressed, its section
// opens. VoiceOver reads what it shows, then what the press does.
const planFlowHTML = (flow) => `<div class="gl-unit"><span class="caps">Flow<span class="gl-src">From `
  + `“${esc(flow.title)}”</span></span><button type="button" class="gl-flow" data-fold="${flow.i}" `
  + `aria-label="${esc(`${core.diagrams.says(flow.text)} Open ${flow.title}.`)}">`
  + `${core.diagrams.smallHTML(flow.text)}</button></div>`;

// The whole plan under the card: each section folded to its heading and first sentence, opened one by one or all at
// once. A plan with no sections is shown whole.
function planFoldsHTML(text, { sid, id }) {
  const sections = planSections(text);
  const intro = planParts(text).intro;
  if (!sections.length) return intro ? `<article class="md gl-whole">${markdownHTML(intro)}</article>` : '';
  const shut = sections.some((s, i) => !planFoldOpen(sid, id, s, i));
  return `<div class="gl-folds"><div class="gl-folds-head"><span class="caps">The whole plan · ${sections.length} `
    + `${sections.length === 1 ? 'section' : 'sections'}</span><button type="button" class="button quiet small gl-all" `
    + `data-all="${shut ? 'open' : 'fold'}">${shut ? 'Open All' : 'Fold All'}</button></div>`
    + sections.map((s, i) => {
      const open = planFoldOpen(sid, id, s, i);
      return `<div class="gl-fold"><button type="button" class="gl-fbtn${s.first ? '' : ' alone'}" data-fold="${i}" `
        + `aria-expanded="${open}">`
        + `<span class="gl-chev" aria-hidden="true">›</span><span class="gl-ft">${mdInline(s.title)}</span>`
        + (open || !s.first ? '' : `<span class="gl-fl">${esc(s.first)}</span>`) + '</button>'
        + (open ? `<div class="gl-open"><div class="md gl-fbody">${markdownHTML(s.body)}</div></div>` : '') + '</div>';
    }).join('') + '</div>';
}

// How to read the plan, on its title's line (Skimmed) or above the plan (Full): the panel's tabs, the one you read
// by pressed.
const planLooksHTML = () => '<div class="tabs gl-looks" role="group" aria-label="How to read the plan">'
  + PLAN_LOOKS.map(([look, words]) => `<button type="button" data-look="${look}" `
    + `aria-pressed="${look === state.planReadAs}">${words}</button>`).join('') + '</div>';

// The reader's view of a plan: its title with the toggle, the card, and the whole plan folded (Skimmed); or the plan
// exactly as Claude wrote it, title and all, drawn as the reader draws any writing, with only the toggle above it
// (Full version of the plan), so you can see the plan itself, nothing taken out or added; or null for a plan with no
// glance and no sections, which the reader shows as it always has.
// `sessionId` and `id` say whose plan it is (the request's id while Claude waits on it, which is what picks are kept
// by); `who` the session's name; `waiting` that Claude waits on it now and it can be answered here; `held` that your
// picks are being sent back, so they show but can't be changed.
function planReaderHTML(text, opts = {}) {
  const sid = String(opts.sessionId ?? ''), id = String(opts.id ?? '');
  const glance = planGlance(text), parts = planParts(text);
  if (!glance && !parts.sections.length) return null;
  (state.planDrawn[sid] ??= {})[id] = { text, opts, glance };
  const where = { sid, id, who: opts.who, waiting: !!opts.waiting, held: !!opts.held, flow: planFlow(text) };
  const open = (cls) => `<div class="${cls}" data-session="${esc(sid)}" data-plan="${esc(id)}">`;
  if (state.planReadAs === 'full') {
    return `${open('gl-view gl-asis')}<div class="gl-lookline">${planLooksHTML()}</div>`
      + `<article class="md">${markdownHTML(text)}</article></div>`;
  }
  const title = `<div class="md gl-top">${parts.title ? `<h1>${mdInline(parts.title)}</h1>` : ''}</div>`;
  return `${open('gl-view')}<div class="gl-titleline">${title}${planLooksHTML()}</div>`
    + (parts.intro && parts.sections.length ? `<div class="md gl-top">${markdownHTML(parts.intro)}</div>` : '')
    + (glance ? planCardHTML(glance, where) : '')
    + planFoldsHTML(text, where) + '</div>';
}

// The plan card's few lines on a row, in place of its first steps: at most 4, from the plan's own block; or null (the
// card shows its steps as before) when it has none, or none of the slots these lines come from. A glance pulled from
// headings can be a single line, which tells less than the steps it would stand in for; the reader shows it, with the
// plan under it. `id` is the request's, so You decide says how many of Claude's picks you've changed in the reader.
function planCardLinesHTML(text, id) {
  const glance = planGlance(text);
  if (glance?.from !== 'written') return null;
  const line = (label, html) => `<div class="gl-mini"><span class="gl-ml">${label}</span>`
    + `<span class="gl-mt">${html}</span></div>`;
  const lines = [];
  const first = glance.slots.changes?.[0] || glance.after;
  if (first) lines.push(line('For you', mdInline(first)));
  if (glance.decide.length) lines.push(line('You decide', planDecideWords(glance, state.planPicks[id])));
  if (glance.slots.risks?.[0]) lines.push(line('Could go wrong', mdInline(glance.slots.risks[0])));
  return lines.length ? `<div class="gl-minis">${lines.slice(0, 4).join('')}</div>` : null;
}

// A task's view of the plan it asks you to approve (One Task's): the plan's own short view, its card alone and bare,
// with no title and no folds, and nothing to press; or null when the block isn't one, or holds a line the card would
// leave out (planBlockWhole), as Approve is right under it. `text` is the block as the task carries it, with or
// without its "## At a glance" heading.
function planTaskHTML(text) {
  const given = String(text ?? '');
  const md = /^\s*#{1,6}\s*at a glance\s*[:#]*\s*$/im.test(given) ? given : `## At a glance\n\n${given}`;
  const glance = planBlockWhole(md) && planGlance(md);
  return glance?.from === 'written' ? planCardHTML(glance, {}, true) : null;
}

// ---- Presses, in the reader ----

// The view a press was in, drawn again from what it was last drawn from; then the reader, whose answer bar asks
// core.plans.picks (drawReader, the pane part's).
function planRedraw(view) {
  const drawn = state.planDrawn[view.dataset.session]?.[view.dataset.plan];
  if (!drawn) return;
  const html = planReaderHTML(drawn.text, drawn.opts), around = view.parentElement;
  if (html) view.outerHTML = html;
  // What's drawn at the width it has (a diagram) is drawn as the view goes in, never a moment after.
  core.diagrams?.draw(around);
  drawReader();
}

// A choice or a section opened or folded in place, so it moves as the panel's lines do: what opens grows in
// (growIn), what folds eases away (foldAway), and the chevron turns as aria-expanded changes. A section's first line
// is part of the move: opening, it fades as its own height eases away, so the line closes up as its body grows;
// folding, its room grows back as the body folds, and its words come in once the body has gone. With reduced motion,
// each only fades, and the first line comes back only once the body has gone. The view is drawn afresh off the page
// and only what changed is carried over, so nothing else is put in again.
function planTurn(view) {
  const drawn = state.planDrawn[view.dataset.session]?.[view.dataset.plan];
  const box = document.createElement('div');
  box.innerHTML = drawn ? planReaderHTML(drawn.text, drawn.opts) || '' : '';
  const fresh = box.firstElementChild;
  if (!fresh) return;
  for (const now of fresh.querySelectorAll('.gl-dline, .gl-fbtn')) {
    const key = now.matches('.gl-dline') ? `.gl-dline[data-choice="${now.dataset.choice}"]`
      : `.gl-fbtn[data-fold="${now.dataset.fold}"]`;
    const was = view.querySelector(key);
    if (!was || was.getAttribute('aria-expanded') === now.getAttribute('aria-expanded')) continue;
    was.setAttribute('aria-expanded', now.getAttribute('aria-expanded'));
    const part = now.parentElement.querySelector(':scope > .gl-open');
    if (part) {
      planLineOut(was.querySelector('.gl-fl:not(.gl-going)'));
      planOpenPart(was, part);
    } else {
      const line = now.querySelector('.gl-fl');
      const going = was.parentElement.querySelector(':scope > .gl-open:not(.gl-going)');
      if (calm.matches) planShut(going, () => planLineIn(was, line));
      else {
        planShut(going);
        planLineIn(was, line);
      }
    }
  }
  view.querySelector('.gl-folds-head')?.replaceWith(fresh.querySelector('.gl-folds-head'));
}
const PLAN_FADE_MS = 300;  // as long as foldAway takes
const PLAN_GROW_MS = 340;  // as long as growIn takes

// What's still moving from an earlier press, swapped for a copy held where it is now, so that move's end can't land
// on what moves next; it then goes on from there. Anything else is given back as it is.
function planHeld(el) {
  if (!el?.classList.contains('gl-moving')) return el;
  const { height } = el.getBoundingClientRect(), { opacity } = getComputedStyle(el);
  const copy = el.cloneNode(true);
  copy.removeAttribute('style');
  copy.classList.remove('gl-moving', 'gl-going');
  Object.assign(copy.style, { height: `${height}px`, opacity, overflow: 'hidden' });
  el.replaceWith(copy);
  return copy;
}

// `el` eased from where it's held to its height and full strength (or only to its height, as faint as it is, with
// `faint`), then left as it is.
function planEaseIn(el, ms, done, faint) {
  const from = { height: el.style.height, opacity: el.style.opacity, overflow: 'hidden' };
  el.style.height = el.style.opacity = '';
  const to = { height: `${el.offsetHeight}px`, opacity: faint ? from.opacity : '1' };
  el.classList.add('gl-moving');
  tween(el, from, to, () => {
    el.classList.remove('gl-moving');
    done?.();
  }, ms);
}

// What a choice or a section opens to: grown in under its line, or, if it was still folding away, turned round from
// where it is, so the two are never there at once.
function planOpenPart(line, part) {
  const going = planHeld(line.parentElement.querySelector(':scope > .gl-open.gl-going'));
  if (going) {
    if (calm.matches) going.style.height = '';
    planEaseIn(going, calm.matches ? PLAN_FADE_MS : PLAN_GROW_MS);
    if (!calm.matches) followHeight(PLAN_GROW_MS + 40);
    return;
  }
  line.after(part);
  // What's drawn at the width it has (a diagram) is drawn before it's measured to grow in.
  core.diagrams?.draw(part);
  part.classList.add('gl-moving');
  const done = () => part.classList.remove('gl-moving');
  if (calm.matches) tween(part, { opacity: '0' }, { opacity: '1' }, done, PLAN_FADE_MS);
  else growIn(part, 0, done);
}

// What a choice or a section folds away from: eased away from where it is, then taken out.
function planShut(el, done) {
  const moving = el?.classList.contains('gl-moving');
  el = planHeld(el);
  if (!el) return done?.();
  el.classList.add('gl-going', 'gl-moving');
  const gone = () => {
    if (!el.isConnected || !el.classList.contains('gl-going')) return;
    el.remove();
    done?.();
  };
  if (calm.matches) tween(el, { opacity: getComputedStyle(el).opacity }, { opacity: '0' }, gone, PLAN_FADE_MS);
  else if (!moving) foldAway(el, gone);
  else {
    // Caught as it grew: foldAway's way, from the height and strength it had got to.
    tween(el, { height: el.style.height, opacity: el.style.opacity, overflow: 'hidden' },
          { height: '0px', opacity: '0' }, gone, PLAN_FADE_MS);
    followHeight(PLAN_FADE_MS + 40);
  }
}

// A section's first line, going as its body comes: it fades as its own height eases away, so the line closes up
// rather than dropping once it's gone. With reduced motion it fades, then goes.
function planLineOut(first) {
  first = planHeld(first);
  if (!first) return;
  first.classList.add('gl-going', 'gl-moving');
  const gone = () => first.isConnected && first.classList.contains('gl-going') && first.remove();
  if (calm.matches) return tween(first, { opacity: getComputedStyle(first).opacity }, { opacity: '0' }, gone,
                                 PLAN_FADE_MS);
  tween(first, { height: `${first.getBoundingClientRect().height}px`, opacity: getComputedStyle(first).opacity,
                 overflow: 'hidden' }, { height: '0px', opacity: '0' }, gone, PLAN_FADE_MS);
}

// A section's first line, coming back as its body folds: its room grows back alongside the fold, then its words come
// in; a line still going is turned round from where it is. With reduced motion (called once the body has gone) it
// only fades in.
function planLineIn(line, words) {
  if (!words || line.getAttribute('aria-expanded') !== 'false') return;
  const going = planHeld(line.querySelector('.gl-fl.gl-going'));
  if (going) {
    // Still going: it comes back the way it went, room and words together.
    going.classList.remove('gl-going');
    return planEaseIn(going, PLAN_FADE_MS);
  }
  if (line.querySelector('.gl-fl')) return;
  const first = line.appendChild(words);
  Object.assign(first.style, { height: calm.matches ? '' : '0px', opacity: '0', overflow: 'hidden' });
  if (calm.matches) return planEaseIn(first, PLAN_FADE_MS);
  planEaseIn(first, PLAN_FADE_MS, () => {
    if (!first.isConnected || first.classList.contains('gl-going')) return;
    first.classList.add('gl-moving');
    tween(first, { opacity: '0' }, { opacity: '1' }, () => first.classList.remove('gl-moving'), PLAN_FADE_MS);
  }, true);
}

const planToggle = (sid, id, what) => {
  const open = (state.planOpen[sid] ??= {}), key = `${id}\n${what}`;
  if (open[key]) delete open[key];
  else open[key] = true;
};
const planPress = (act, draw = planRedraw) => (el) => {
  const view = el.closest('.gl-view');
  if (!view || el.disabled) return;
  act(view.dataset.session, view.dataset.plan, el);
  draw(view);
};

core.readerPresses.push(
  ['.gl-dline', planPress((sid, id, el) => planToggle(sid, id, `choice ${el.dataset.choice}`), planTurn)],
  ['.gl-option', planPress((sid, id, el) => {
    const drawn = state.planDrawn[sid]?.[id], i = Number(el.dataset.choice), k = Number(el.dataset.option);
    const d = drawn?.glance?.decide[i];
    if (!d || !drawn.opts.waiting || drawn.opts.held) return;
    const picks = (state.planPicks[id] ??= {});
    if (k === d.rec) delete picks[i];
    else picks[i] = k;
  })],
  ['.gl-more', planPress((sid, id) => planToggle(sid, id, 'more'))],
  ['.gl-fbtn', planPress((sid, id, el) => planToggle(sid, id, `fold ${el.dataset.fold}`), planTurn)],
  ['.gl-looks button', planPress((sid, id, el) => {
    state.planReadAs = el.dataset.look === 'full' ? 'full' : 'skimmed';
    store.set('planReadAs', state.planReadAs);
  })],
  // The card's flow: its section opens, if it isn't, and comes into view.
  ['.gl-flow', planPress((sid, id, el) => {
    const i = Number(el.dataset.fold), s = planSections(state.planDrawn[sid]?.[id]?.text || '')[i];
    if (s && !planFoldOpen(sid, id, s, i)) planToggle(sid, id, `fold ${i}`);
  }, (view) => {
    planTurn(view);
    // Brought into view once it has grown, so it lands where the layout ends up, even near the plan's end.
    const i = view.querySelector('.gl-flow')?.dataset.fold;
    const bring = () => view.querySelector(`.gl-fbtn[data-fold="${i}"]`)?.scrollIntoView({ block: 'start',
      behavior: calm.matches ? 'auto' : 'smooth' });
    if (calm.matches) bring();
    else setTimeout(bring, PLAN_GROW_MS + 40);
  })],
  ['.gl-all', planPress((sid, id, el) => {
    const open = (state.planOpen[sid] ??= {});
    planSections(state.planDrawn[sid]?.[id]?.text || '').forEach((s, i) => {
      if ((el.dataset.all === 'open') !== !!s.opens) open[`${id}\nfold ${i}`] = true;
      else delete open[`${id}\nfold ${i}`];
    });
  }, planTurn)],
);

// ---- What it plugs into ----

// The glance of the plan Claude waits on under the request `id`, as last drawn, in whichever session's view.
function planWaitingGlance(id) {
  for (const plans of Object.values(state.planDrawn)) if (plans[id]?.opts.waiting) return plans[id].glance;
  return null;
}

// The places that show a plan draw it through these (parts/bridge/page/modules.js says what each gives).
core.plans = {
  readerHTML: planReaderHTML,
  cardLines: planCardLinesHTML,
  taskHTML: planTaskHTML,
  picks: (id) => planPicksNote(planWaitingGlance(id), state.planPicks[id]),
  clearPicks(id) {
    delete state.planPicks[id];
    for (const view of document.querySelectorAll('.gl-view')) if (view.dataset.plan === String(id)) planRedraw(view);
  },
};
