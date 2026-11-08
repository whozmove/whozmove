// One Task on the page: a mode of the reader beside the list that hands you the one thing that needs you most, and
// what it does with your answer. What waits is the tasks sessions sent (setTasks, from the app): a session's own
// request, question or plan stays on its row in the list, answered there. The order and the kinds' answers are
// order.js's; drawing, one-task-view.js's. While it isn't in sight and something waits, the line under the header says
// so (a page sender's notice: core.noticeSenders), with Open.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

moduleState({
  tasks: [],        // what the app sent: each { sessionId, task, at, sent, back, pick, for, seenAt }, the task as
                    // it was checked, `pick` for the lead's pick, `for` the member's session it's for, and `seenAt`
                    // when you were last on it, once read
  tasksOn: true,    // Settings ▸ One Task
  tasksSent: {},    // what you've answered here, by taskStepKey, until the app's list no longer has it
  tasksBack: {},    // what you've put back here with Can't Now, by taskStepKey, until the app's list says so
  tasksNewest: 0,   // when the newest of what waits came, never going back (taskNewest), for the line's ×
  tasksCount: -1,   // how many wait, as the app was last told, for the pawn menu's One Task
  tasksWant: null,  // the task a reply's notice or a row's task line opened One Task at, in front until you move on
  tasksLetGo: {},   // tasks taken back that the app was told to let go, by key, at the send they were taken back on
  tasksGone: {},    // those tasks as they were taken back, by key, for what the foot says of one you'd set aside
  tasksSeen: {},    // the tasks you've read, by key: in front TASK_SEEN_MS with One Task open, or pressed; a task's,
                    // not a step's, so a reword or its next step leaves it read; and those the app keeps as read
  tasksLastOn: null, // the task you were last on in One Task ({key, step, ui, title, task, sid}), kept while it's
                     // closed
  tasksGoUrgent: false, // One Task opened from the urgent line under the header: straight to the first urgent one
  tasksRules: { next: 'picks', why: false, waitForGo: true, talk: true, held: 'self', turnedAway: [] },
                    // how One Task works, as its page on the back sets it (setTasks)
  talkDrafts: {},   // what you've written in the talk's box, by task, kept through its next steps
  talkLead: {},     // the lead's picks whose talk you chose to have with the lead, by task, before it begins
  talkSeen: {},     // when you last saw each task's talk in One Task, by task, for the reply's notice
  talkBack: {},     // why words that couldn't go in are back in the box, by task: { why, way, permission }
  talkTaken: {},    // those words, by task and when they were said, once put back, so they're put back only once
  talkBegan: {},    // the step (its `sent`) you began writing in the talk's box on, by task, for a next step coming in
  taskAskKeys: {},  // session id -> the task step its row's ask line last said, so a line saying another is seen first
  taskCopied: {},   // session id -> when its row's command was copied, for the tick on its button a moment after
});

// As wide as the task's column, with nothing down its side.
const ONE_TASK_WIDTH = 420;
// How long the foot says where your answer went, and a reply's Copy says Copied (and a row's Copy shows its tick).
const ONE_TASK_SAID_MS = 4000;
const ONE_TASK_COPIED_MS = 2000;

const oneTaskReading = () => state.reading?.mode === 'oneTask' && !state.reading.closing;
const oneTaskStepOf = (one) => taskStepKey({ key: `task:${one.sessionId}:${one.task.id}`, sent: one.sent || 0 });

// What waits, in order: but what you've just answered here, which the app takes away a moment later, and with what
// you've just put back already at the back. A task its session took back stays only while it's the one you're on
// (pointing at it or typing in it, as no press could land on it then); else it's let go at once, and if it was the one
// in front, the foot says what became of it.
function oneTaskItems() {
  if (!state.tasksOn) return [];
  const sent = state.tasks.filter((one) => !state.tasksSent[oneTaskStepOf(one)])
    .map((one) => (state.tasksBack[oneTaskStepOf(one)] && !one.back ? { ...one, back: true, at: Date.now() } : one));
  const ot = oneTaskReading() ? state.reading.ot : null;
  return taskLine(sent, state.last.sessions || [], state.tasksRules).filter((item) => {
    if (!item.takenBack || (ot && item.key === ot.key && oneTaskHolding())) return true;
    oneTaskLetGo(item, ot && item.key === ot.key ? ot : null);
    return false;
  });
}

// A task taken back, let go: the app is told once, and the foot says what became of it when it was in front.
function oneTaskLetGo(item, ot) {
  if (state.tasksLetGo[item.key] === item.sent) return;
  state.tasksLetGo[item.key] = item.sent;
  state.tasksGone[item.key] = item;
  delete state.tasksSeen[item.key];
  native({ type: 'taskLetGo', sessionId: item.sid, id: item.task.id });
  if (ot) {
    const now = Date.now();
    Object.assign(ot, { said: `${taskTakenBackWords(item)}.`, saidAt: now, quietAt: now });
  }
}

// How many wait, told to the app when it changes, for the pawn menu's One Task.
function oneTaskTell(items) {
  if (items.length === state.tasksCount) return;
  state.tasksCount = items.length;
  native({ type: 'oneTaskWaiting', count: items.length });
}

// Whether the one in front stays where it is: you type in the view, or point at it.
function oneTaskHolding() {
  const view = reader.querySelector('.r-body'), foot = reader.querySelector('.r-answer'), pointed = pointedAt();
  return !!view && (view.contains(document.activeElement) || !!foot?.contains(document.activeElement)
    || (!!pointed && view.contains(pointed)));
}

const oneTaskUi = () => ({ first: false, chosen: [], ticks: {}, note: '', open: {}, copied: {} });

// ---- Drawing ----

function drawOneTask() {
  const r = state.reading, now = Date.now();
  if (!r.ot) r.ot = oneTaskOpening(oneTaskItems());
  const ot = r.ot, items = oneTaskItems();
  oneTaskTell(items);
  // While one slides out, what's there stays as it was, head and foot too, until the next has come in.
  if (ot.sliding) return;
  // A reply's notice or a row's task line opened it at a task: that one stays in front until you move on.
  if (state.tasksWant && !items.some((item) => item.key === state.tasksWant)) state.tasksWant = null;
  const wanted = state.tasksWant && (ot.key === undefined || ot.key === state.tasksWant) ? state.tasksWant : null;
  if (ot.left) oneTaskLeft(ot, items);
  const front = oneTaskChoose(items, ot, wanted);
  const body = reader.querySelector('.r-body'), key = front?.key ?? null, step = front ? taskStepKey(front) : null;
  if (key !== ot.key || step !== ot.step) {
    const how = ot.key === undefined ? 'now' : key === ot.key ? 'step' : 'task';
    // Back on the task you set aside or were last on: where it was scrolled, the keyboard, and what you'd done on it,
    // or, when it changed meanwhile, as much as order.js keeps of it (your words, never a pick made on the old ones).
    const back = ot.restore && ot.restore.key === key ? ot.restore : null;
    const changedAway = !!back && back.step !== step;
    // The one you were on gone from under you, neither answered here nor taken back (each of which says so itself):
    // kept, so it comes back if its session's row was only missing from a read, or the foot says it no longer waits
    // once the app no longer keeps it (oneTaskLeft), so it never just slides away.
    const last = state.tasksLastOn;
    if (how === 'task' && ot.key && last?.key === ot.key && !items.some((item) => item.key === ot.key)
        && !state.tasksSent[ot.step] && !state.tasksGone[ot.key]) ot.left = last;
    // A reword while you type in its box: the box is drawn again, the cursor put back in it.
    const on = how === 'step' && document.activeElement?.closest?.('#reader') ? document.activeElement : null;
    const typing = on?.matches('.ot-talk-field') ? 'talk' : on?.matches('.ot-note') ? 'note' : null;
    const before = ot.ui, ui = back ? taskKeptUi(back.ui, back.task, front.task)
      : how === 'step' ? taskKeptUi(before, ot.task, front.task) : oneTaskUi();
    Object.assign(ot, { key, step, task: front?.task, ui, shownAt: now, restore: null, touched: false,
                        restoring: back || (typing ? { focus: typing, scroll: body.scrollTop } : null) });
    // What the foot held for you stays only under the task it was said on: moving to another lets it go.
    if (ot.saidStays && ot.stayOn !== undefined && ot.stayOn !== key)
      Object.assign(ot, { said: '', saidStays: false, kept: '', stayOn: undefined });
    if (back) {
      state.tasksSeen[key] = true;
      Object.assign(ot, { said: changedAway ? taskUpdatedAwayWords(front, taskPickLetGo(back.ui, ui))
                            : taskBackWords(back.title, !back.fresh),
                          saidAt: now, quietAt: now, saidStays: true, stayOn: key });
    }
    // Changed in front of you under the same id: the foot says so, quietly.
    if (how === 'step') Object.assign(ot, { said: taskUpdatedWords(front, taskPickLetGo(before, ui)), saidAt: now,
                                            quietAt: now });
    return oneTaskSwap(body, how);
  }
  // Seen once it has been in front long enough with One Task open; and the app told, each time you're on it.
  if (front && now - ot.shownAt >= TASK_SEEN_MS) state.tasksSeen[key] = true;
  if (front && state.tasksSeen[key]) oneTaskSeenTold(front);
  if (front) state.tasksLastOn = { key, step, ui: ot.ui, title: front.task.title, task: front.task, sid: front.sid };
  const changed = oneTaskFrame(front, items, now);
  if (oneTaskPage(body.firstElementChild, front) || changed) {
    fitReader();
    syncHover();
  }
  oneTaskStuck();
}

// A fresh view of One Task, as it opens: from the urgent line under the header, straight to the first urgent one, the
// task you were last on set aside; else, opened at a task that still waits (state.tasksWant), that one, nothing put
// back; else back on the task order.js opens on (taskOpensOn): the one you were last on, as you left it, or as much as
// it keeps of it when it changed meanwhile; after Whozmove restarts, the one the app says you read last, as it is.
function oneTaskOpening(items) {
  const ot = { key: undefined, step: null, ui: oneTaskUi(), said: '', saidAt: 0, shownAt: 0, sliding: false };
  const last = state.tasksLastOn, still = taskOpensOn(items, last, (key) => !!state.tasksSeen[key]);
  const seenLast = !!still && !!last;
  const urgent = state.tasksGoUrgent && taskUrgentOthers(items, still?.key ?? last?.key)[0];
  state.tasksGoUrgent = false;
  if (!urgent && items.some((item) => item.key === state.tasksWant)) return ot;
  // After a restart, the task you read last is set aside all the same, with nothing of what you'd done on it.
  const aside = seenLast ? last : still && { key: still.key, step: taskStepKey(still), ui: oneTaskUi(),
                                            title: still.task.title, task: still.task, sid: still.sid, fresh: true };
  if (urgent) Object.assign(ot, { next: urgent.key, aside: aside && taskSetsAside(still) ? aside : null });
  else if (seenLast) Object.assign(ot, { next: last.key, restore: last });
  else if (still) ot.next = still.key;
  return ot;
}

// The task in front: one a press has just brought in (Go, ‹ Back, Open from the urgent line); else the one you're on,
// if you've seen it or are pointing at it or typing in it, as a task you've seen is yours until you leave it; else
// the one a reply's notice opened at; while you're on the urgent ones with a task set aside, the next urgent one, and
// then the one you set aside; else the line's first.
// Back on the task you set aside: as you left it, or with as much as taskKeptUi keeps when it changed meanwhile; or,
// when it no longer waits (taken back by its session, say), the foot says so, with what you'd typed in its Comment
// box and talk box to copy (taskKeptWords), until you move on.
function oneTaskChoose(items, ot, wanted) {
  const aside = ot.aside;
  // With urgent tasks not waiting for your Go (One Task's page), only pointing or typing holds the one you're on.
  const waitForGo = state.tasksRules.waitForGo !== false;
  const { front, gone } = taskChooseFront(items, { next: ot.next, key: ot.key, held: oneTaskHolding(),
    seen: (key) => waitForGo && !!state.tasksSeen[key], wanted, aside, gone: aside && state.tasksGone[aside.key] });
  ot.next = null;
  if (aside && front?.key === aside.key) {
    ot.aside = null;
    ot.restore = aside;
  } else if (aside && gone) {
    const now = Date.now();
    Object.assign(ot, { aside: null, said: taskAsideGone(aside.title, gone), saidAt: now, quietAt: now,
                        saidStays: true, kept: taskKeptWords(state.talkDrafts[aside.key], aside.ui),
                        stayOn: front?.key ?? null });
  }
  return front;
}

// The task you were on, gone from the line without your answer (`ot.left`), as order.js's taskLeft decides: back in
// front, as you left it, once its session's row is back; or the foot says it no longer waits, with what you'd written
// in its Comment box and talk box to copy, until you move on; or forgotten.
function oneTaskLeft(ot, items) {
  const left = ot.left, now = Date.now();
  const what = taskLeft(left, items, { on: state.tasksOn, turnedAway: state.tasksRules.turnedAway || [],
    waiting: new Set(state.tasks.map((one) => `task:${one.sessionId}:${one.task.id}`)), touched: !!ot.touched });
  if (!what) return;
  ot.left = null;
  if (what === 'back') Object.assign(ot, { next: left.key, restore: left });
  if (what === 'gone') Object.assign(ot, { said: taskAsideGone(left.title, null), saidAt: now, quietAt: now,
                                           saidStays: true, kept: taskKeptWords(state.talkDrafts[left.key], left.ui),
                                           stayOn: ot.key });
}

// The app told you're on a task you've read, once each time you come to it, so it keeps it read through its next
// steps and a restart (taskSeen).
function oneTaskSeenTold(item) {
  const ot = state.reading?.ot;
  if (!ot || ot.toldSeen === item.key) return;
  ot.toldSeen = item.key;
  native({ type: 'taskSeen', sessionId: item.sid, id: item.task.id, sent: item.sent });
}

// A press on the strip: Go sets the task you're on aside, with everything you'd done on it, and brings the first urgent
// one in, leaving the keyboard free; ‹ Back goes back to it, the urgent ones waiting first, their strip back on.
function oneTaskUrgent(act) {
  const ot = state.reading?.ot;
  if (!ot || ot.sliding) return;
  const items = oneTaskItems(), current = items.find((item) => item.key === ot.key);
  if (act === 'go') {
    const urgent = taskUrgentOthers(items, ot.key)[0];
    if (!urgent) return;
    if (!ot.aside && taskSetsAside(current)) {
      const on = document.activeElement?.closest?.('#reader') ? document.activeElement : null;
      ot.aside = { key: current.key, step: ot.step, ui: ot.ui, title: current.task.title, task: current.task,
                   scroll: reader.querySelector('.r-body')?.scrollTop || 0,
                   focus: on?.matches('.ot-talk-field') ? 'talk' : on?.matches('.ot-note') ? 'note' : null };
      on?.blur();
      wantKeyboard(false);
    }
    Object.assign(ot, { next: urgent.key, said: '', saidStays: false, kept: '' });
  } else if (act === 'back' && ot.aside) {
    Object.assign(ot, { next: ot.aside.key, restore: ot.aside, aside: null, said: '', saidStays: false, kept: '' });
  }
  drawReader();
}

// The head and the foot, for the one in front: who it's from, where your last answer went (fading in and out in place),
// how many more wait. Whether the head changed.
function oneTaskFrame(front, items, now) {
  const ot = state.reading.ot, foot = reader.querySelector('.r-answer');
  if (ot.said && !ot.saidStays && now - ot.saidAt > ONE_TASK_SAID_MS) ot.said = '';
  putHTML(foot, TASK_FOOT);
  if (front?.task) oneTaskTalkSeen(front);
  const sent = foot.querySelector('.ot-sent');
  if (ot.said) setText(sent, ot.said);
  sent.classList.toggle('shown', !!ot.said);
  // Your move's colour for where an answer went; a copy's line stays quiet, as nothing is asked of you by it.
  sent.classList.toggle('turn', ot.quietAt !== ot.saidAt);
  setText(foot.querySelector('.ot-more'), taskMoreWords(items.length - 1, !!front,
                                                       taskUrgentOthers(items, front?.key).length));
  const kept = foot.querySelector('.ot-kept-row');
  kept.hidden = !ot.kept;
  if (ot.kept) setText(kept.querySelector('.ot-kept'), ot.kept);
  oneTaskTalkBox(foot.querySelector('.ot-talkbox'), front);
  return putHTML(reader.querySelector('.r-head'), taskHeadHTML(front, now));
}

// Whom the talk about a task is with, as it's drawn and as your words are sent.
// None while the talk is off (One Task's page); `waits` while words written as it works wait for your Send Now.
const oneTaskTalkTo = (item) => (!state.tasksRules.talk ? null
  : { ...talkTo(item, state.last.sessions || [], !!state.talkLead[item.key]), waits: state.tasksRules.held === 'wait' });

// The talk's box at the foot, for the task in front: what you've written about it (kept by task), how much more fits
// with the words that open it, and under it exactly what will go in, or why nothing can, with the way forward: the way
// past the reason and Copy and Go, or Take Me There. A next step that came in as you wrote is said, and Send names it.
function oneTaskTalkBox(box, item) {
  if (!box) return;
  box.hidden = !item?.task || !!item.takenBack || !state.tasksRules.talk;
  if (box.hidden) return;
  const field = box.querySelector('.ot-talk-field'), send = box.querySelector('[data-talk="send"]');
  const to = oneTaskTalkTo(item), opening = talkOpening(item, to), back = state.talkBack[item.key];
  if (field.dataset.key !== item.key) {
    field.dataset.key = item.key;
    field.value = state.talkDrafts[item.key] || '';
  }
  field.maxLength = talkRoom(opening);
  field.placeholder = `Ask ${to.name} about this…`;
  field.setAttribute('aria-label', field.placeholder);
  field.disabled = to.gone;
  const words = field.value.trim(), step = words ? talkNewStep(item, state.talkBegan[item.key]) : null;
  send.disabled = to.gone || !words;
  setText(send, step?.send || 'Send');
  const goes = box.querySelector('.ot-talk-goes');
  const act = (talk, word) => ` <button type="button" class="ot-talk-act" data-talk="${talk}">${esc(word)}</button>`;
  goes.classList.toggle('why', to.gone || !!back || !!step);
  putHTML(goes, to.gone ? `${esc(to.name)} isn’t on this task now: answer it above, or${act('there', 'Take Me There')}`
    : back ? `${esc(back.why)} Your words are back in the box.${back.way ? act('way', back.way) : ''}`
      + `${words ? act('copy', 'Copy and Go') : ''}`
      : `${step ? `${esc(step.note)} ` : ''}Goes to ${esc(to.name)} as: `
        + `${words ? `${esc(opening)}${esc(words)}` : `${esc(opening.replace(/ $/, '\u00a0'))}…`}`);
}

// Whether the answer is stuck at the view's foot, with the task going on out of sight under it: only then does it take
// its fill, so a task that fits has no band behind its buttons. Asked as the view is drawn and as it scrolls.
function oneTaskStuck() {
  const view = reader.querySelector('.r-body'), act = view?.querySelector('.ot-act');
  if (!act) return;
  const bottom = view.getBoundingClientRect().bottom;
  act.classList.toggle('stuck', view.scrollHeight > view.clientHeight + 1
    && act.getBoundingClientRect().bottom >= bottom - 1);
}

// The one in front, drawn into its page; whether anything changed. It keeps what you've typed in its box.
function oneTaskPage(page, item) {
  if (!page) return false;
  if (!item) return putHTML(page, state.tasksOn ? TASK_NOTHING : TASK_OFF);
  const ot = state.reading.ot, ui = ot.ui, typing = document.activeElement?.closest?.('.ot-note');
  oneTaskTalkSeen(item);
  const items = oneTaskItems(), rules = state.tasksRules, now = Date.now();
  const strip = taskStripHTML(ot.aside ? [] : taskUrgentOthers(items, item.key), ot.aside);
  const why = rules.why ? taskWhyHTML(item, items, now) : '';
  const away = taskTurnedAwayWords(rules.turnedAway || [], state.last.sessions || []);
  const after = (rules.why ? taskAfterHTML(item, items, now) : '')
    + (away ? `<p class="ot-hint ot-away">${esc(away)}. Only a team’s chief may, as One Task’s page under Tools `
      + 'says.</p>' : '');
  const body = taskBodyHTML(item, ui, oneTaskTalkTo(item)).replace(/<\/div>$/, `${after}</div>`)
    .replace('<div class="ot-body">', `<div class="ot-body">${why}`);
  if (!putHTML(page, strip + body)) return false;
  const box = page.querySelector('.ot-note');
  if (box) {
    box.value = ui.note;
    oneTaskSendable();
    if (typing) box.focus({ preventScroll: true });
  }
  return true;
}

// The one in front changed: a new task slides in from the side as the one before slides out, and once it's in, the
// head and foot say whose it is, their words fading out and in again; a task's next step keeps its title and rewrites
// its step's words (oneTaskStep). Under reduced motion, it's simply there. VoiceOver says each as it comes.
function oneTaskSwap(body, how) {
  const r = state.reading, ot = r.ot, old = body.firstElementChild;
  const here = () => state.reading === r && oneTaskReading();
  // The one in front, put in its page; with `frame`, the head and foot too.
  const fill = (frame) => {
    const items = oneTaskItems(), front = taskFront(items, ot.key, false), now = Date.now();
    ot.shownAt = now;
    if (frame) oneTaskFrame(front, items, now);
    body.innerHTML = '<div class="ot-page"></div>';
    oneTaskPage(body.firstElementChild, front);
    setText(reader.querySelector('.ot-say'), taskSayWords(front));
    r.ready = true;
    fitReader();
    syncHover();
    oneTaskStuck();
    // Back on the one set aside: where it was scrolled, and the keyboard where it was.
    const back = ot.restoring;
    ot.restoring = null;
    if (back) {
      body.scrollTop = back.scroll || 0;
      const box = back.focus === 'talk' ? reader.querySelector('.ot-talk-field')
        : back.focus === 'note' ? reader.querySelector('.ot-note') : null;
      if (box) {
        wantKeyboard(true);
        box.focus({ preventScroll: true });
      }
    }
    // Seen once it has been in front this long with One Task open: looked at again then, so it holds its place.
    const shown = ot.step;
    setTimeout(() => { if (state.reading === r && oneTaskReading() && ot.step === shown) drawReader(); }, TASK_SEEN_MS + 50);
    return { front, items };
  };
  if (how === 'now' || !old || calm.matches) return fill(true);
  if (how === 'step') return oneTaskStep(body, fill);
  ot.sliding = true;
  const stop = () => { ot.sliding = false; };
  old.animate([{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateX(-28px)' }],
              { duration: 220, easing: 'ease-in', fill: 'forwards' }).finished.then(() => {
    if (!here()) return stop();
    const { front, items } = fill(false);
    body.firstElementChild?.animate([{ opacity: 0, transform: 'translateX(28px)' }, { opacity: 1, transform: 'none' }],
                                    { duration: 280, easing: MORPH_EASE }).finished.then(() => {
      stop();
      if (!here()) return;
      oneTaskFrameIn(front, items);
      drawOneTask();
    }, stop);
  }, stop);
}

// The head's and foot's words for the one that has just come in: those that change fade out, then the new fade in.
function oneTaskFrameIn(front, items) {
  const changing = () => [reader.querySelector('.r-head .r-sub'), reader.querySelector('.ot-more')].filter(Boolean);
  const head = reader.querySelector('.r-head');
  if (head.dataset.drawn === taskHeadHTML(front, Date.now())
      && reader.querySelector('.ot-more')?.textContent === taskMoreWords(items.length - 1, !!front)) return;
  Promise.all(changing().map((el) => el.animate([{ opacity: 1 }, { opacity: 0 }],
                                                { duration: 120, easing: 'ease', fill: 'forwards' }).finished))
    .then(() => {
      if (!oneTaskReading()) return;
      oneTaskFrame(front, items, Date.now());
      for (const el of changing()) {
        for (const a of el.getAnimations()) a.cancel();
        el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: MORPH_EASE });
      }
    }, () => {});
}

// A task's next step: its title stays. The rest under it (why, what to do, what's attached, its buttons) fades first;
// then the step's words past what they share are erased and the new written in, as a chat line's are (rewriteText),
// its dashes easing to their new fill as the new words start; and only then does the rest come in, lifting, the
// buttons with it, so nothing can be pressed under the step before's words. Until it's in, no press counts.
function oneTaskStep(body, fill) {
  const r = state.reading, ot = r.ot, page = body.firstElementChild;
  const word = page?.querySelector('.ot-word')?.textContent || '';
  const dashes = [...(page?.querySelectorAll('.ot-track i') || [])].map((i) => i.className);
  const rest = (el) => [...(el?.querySelectorAll('.ot-steps > :not(.ot-step), .ot-buttons') || [])];
  const here = () => state.reading === r && oneTaskReading();
  const stop = () => { ot.sliding = false; };
  ot.sliding = true;
  Promise.all(rest(page).map((el) => el.animate([{ opacity: 1 }, { opacity: 0 }],
                                                { duration: 150, easing: 'ease', fill: 'forwards' }).finished))
    .then(() => {
      if (!here()) return stop();
      fill(true);
      const next = body.firstElementChild, coming = rest(next);
      for (const el of coming) el.style.opacity = '0';
      const now = [...next.querySelectorAll('.ot-track i')], to = now.map((i) => i.className);
      const fillDashes = () => now.forEach((i, k) => { i.className = to[k]; });
      // The dashes show the step before's fill until the new words start: put back at once, with no easing, as the
      // new page has already been measured with its own.
      if (now.length === dashes.length) {
        now.forEach((i, k) => {
          i.style.transition = 'none';
          i.className = dashes[k];
        });
        void next.offsetWidth;
        for (const i of now) i.style.removeProperty('transition');
      }
      const line = next.querySelector('.ot-word');
      const written = line && word ? rewriteText(line, word, { writing: fillDashes })
        : (fillDashes(), Promise.resolve());
      return written.then(() => {
        if (!here()) return stop();
        for (const el of coming) {
          el.style.removeProperty('opacity');
          el.animate([{ opacity: 0, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }],
                     { duration: 300, easing: MORPH_EASE });
        }
        stop();
        ot.shownAt = Date.now();
      });
    })
    .catch(stop);
}

// ---- Presses ----

// The task in front, as it's drawn, if a press on it counts: not one that came as it had only just come in, which may
// have taken the place of the one meant.
function oneTaskPressed() {
  const r = state.reading, ot = r?.ot;
  if (!ot || ot.sliding || Date.now() - ot.shownAt < FRESH_MS) return null;
  const item = oneTaskItems().find((one) => one.key === ot.key);
  if (!item?.task) return null;
  // A press means you've seen it, and moves you on from what the foot was holding for you.
  state.tasksSeen[ot.key] = true;
  Object.assign(ot, { saidStays: false, kept: '', touched: true });
  return item;
}

function oneTaskAct(act) {
  const item = oneTaskPressed();
  if (!item) return;
  const ot = state.reading.ot, ui = ot.ui, task = item.task, to = { sessionId: item.sid, id: task.id,
                                                                    sent: item.sent };
  if (act === 'first') {
    ui.first = true;
    native(task.kind === 'run' ? { type: 'taskCopy', ...to } : { type: 'taskOpen', ...to, at: taskOpenAt(task) });
  } else if (act === 'there') {
    // To the session a lead's task is about (taskAboutOf), else to its sender, or the member it's for.
    if (item.about?.s && task.kind === 'do') ui.first = true;
    openSession(item.about?.s || taskThere(item));
  } else if (act === 'later') {
    // It goes to the back at once, and the next comes to the front, though you point at it still.
    native({ type: 'taskPutBack', ...to });
    state.tasksBack[ot.step] = true;
    Object.assign(ot, { key: null, step: null, said: 'At the back of your line.', saidAt: Date.now() });
  } else if (act === 'answer') {
    // The one action: the choice picked, and for Comment its words. Pressed while it waits, it brings what it waits
    // for into view, as on a long task that may be out of sight above it: the choices, or Comment's box, the cursor
    // in it.
    const answer = taskAnswer(task, ui.chosen), note = answer === 'Comment' ? ui.note.trim() : '';
    if (!taskCanAnswer(task, ui)) return oneTaskShowChoices(ui);
    native({ type: 'taskAnswer', ...to, answer, note });
    state.tasksSent[ot.step] = true;
    // Answered, it's done with: a next step sent after your answer is new to you.
    delete state.tasksSeen[ot.key];
    Object.assign(ui, { chosen: [], note: '' });
    // Words still waiting to go in go with the task, and the foot says so.
    const held = (item.talk?.says || []).some((said) => said.state === 'held');
    Object.assign(ot, { said: `${taskSaid(item, answer, note)}${held
      ? ' Your question in the talk wasn’t sent, as the task is answered.' : ''}`, saidAt: Date.now() });
    wantKeyboard(false);
  }
  drawReader();
}

// What's attached, as taskAttachOpens says: a link or a page in your browser (the app opens only the web's, from the
// task as it was checked); a writing, in the reader, under the session that wrote it (taskWriting); the changes, in
// the changes view, the member's for a pick about one.
function oneTaskOpen(i) {
  const item = oneTaskPressed(), a = item?.task.attach?.[i];
  const opens = a && taskAttachOpens(a, item);
  if (opens === 'changes') openReader(taskThere(item).sessionId, null, 'changes');
  else if (opens === 'writing') {
    const { s, w } = taskWriting(item, a.path);
    openReader(s.sessionId, w.id, 'writings');
  }
  else if (opens === 'web') native({ type: 'taskOpen', sessionId: item.sid, id: item.task.id, sent: item.sent, at: i });
}

// What's new in the talk about the task in front, as it's shown: a reply (said to VoiceOver, and no longer new for the
// line under the header), and words that couldn't go in or stopped part-way, put back in the box once with why, unless
// you've written there since. Before the box is drawn, so they're never shown twice.
function oneTaskTalkSeen(item) {
  const says = item.talk?.says || [], to = oneTaskTalkTo(item);
  if (!to) return;
  const replied = Math.max(0, ...says.map((said) => said.repliedAt || 0));
  if (replied > (state.talkSeen[item.key] || 0)) {
    state.talkSeen[item.key] = replied;
    const last = says.find((said) => said.repliedAt === replied);
    if (last?.reply) setText(reader.querySelector('.ot-say'), `${to.name}: ${talkReplyWords(talkReply(last.reply))}`);
  }
  for (const said of says) {
    const taken = `${item.key} ${said.at}`;
    if (!['refused', 'stopped'].includes(said.state) || state.talkTaken[taken]) continue;
    state.talkTaken[taken] = true;
    if (!state.talkDrafts[item.key]) {
      state.talkDrafts[item.key] = said.words;
      state.talkBegan[item.key] = item.sent;
    }
    state.talkBack[item.key] = talkBackWords(said);
    const field = reader.querySelector('.ot-talk-field');
    if (field?.dataset.key === item.key && !field.value) field.value = state.talkDrafts[item.key];
    native({ type: 'taskTakeBack', sessionId: item.sid, id: item.task.id, sent: item.sent, at: said.at });
  }
}

// A press in the talk: your words sent; Take Back, which puts held words back in the box; Send Now; Show It, the
// session's own request on its row; Take Me There; the way past why words couldn't go in (the terminal's, or
// Accessibility's in System Settings); Copy and Go, your words as they'd go in on the clipboard and their session in
// front; a code block in a reply shown whole or on one line again, and its Copy (by its place in the reply the app
// read, never its words from here); or, before the talk begins, the member or the lead for the lead's pick.
function oneTaskTalk(act, b) {
  // Your words about a task taken back while you were away: copied, whatever's in front now.
  if (act === 'copyKept') {
    const ot = state.reading?.ot;
    if (!ot?.kept) return;
    native({ type: 'taskWordsCopy', words: ot.kept });
    Object.assign(ot, { said: 'Your words are copied.', saidAt: Date.now(), quietAt: Date.now(), saidStays: true,
                        kept: '', stayOn: ot.key ?? null });
    return drawReader();
  }
  const item = act === 'send' || act === 'copy' ? oneTaskInFront() : oneTaskPressed();
  if (!item?.task) return;
  const to = oneTaskTalkTo(item), at = Number(b?.dataset.at), msg = { sessionId: item.sid, id: item.task.id,
                                                                      sent: item.sent };
  if (!to) return;
  if (act === 'send') {
    const field = reader.querySelector('.ot-talk-field'), words = field?.value.trim();
    if (!words || to.gone) return;
    native({ type: 'taskSay', ...msg, to: to.lead ? 'lead' : 'member', words });
    field.value = '';
    oneTaskTalkCleared(item.key);
  } else if (act === 'copy') {
    const field = reader.querySelector('.ot-talk-field'), words = field?.value.trim();
    if (!words || to.gone) return;
    native({ type: 'taskTalkCopy', ...msg, to: to.lead ? 'lead' : 'member', words });
    field.value = '';
    oneTaskTalkCleared(item.key);
    const now = Date.now();
    Object.assign(state.reading.ot, { said: `Copied: paste it in ${to.name}’s session.`, saidAt: now, quietAt: now });
    openSession(to.s);
  } else if (act === 'code') {
    const key = taskCodeKey(item, at, Number(b?.dataset.part)), open = state.reading.ot.ui.open;
    if (open[key]) delete open[key];
    else open[key] = true;
  } else if (act === 'copyCode') {
    native({ type: 'taskReplyCopy', ...msg, at, part: Number(b?.dataset.part) });
    // The Copy pressed says Copied a moment, where you're looking, and the foot says it whole, quietly.
    const ot = state.reading.ot, key = taskCodeKey(item, at, Number(b?.dataset.part)), now = Date.now();
    ot.ui.copied[key] = now;
    Object.assign(ot, { said: 'Copied. Nothing was run.', saidAt: now, quietAt: now });
    setTimeout(() => {
      if (ot.ui.copied[key] !== now) return;
      delete ot.ui.copied[key];
      if (state.reading?.ot === ot && oneTaskReading()) drawReader();
    }, ONE_TASK_COPIED_MS);
  } else if (act === 'show') {
    if (to.s?.ask) waitingBring({ id: to.s.ask.id, sid: to.s.sessionId });
  } else if (act === 'takeBack') {
    const said = (item.talk?.says || []).find((one) => one.at === at);
    if (!said) return;
    native({ type: 'taskTakeBack', ...msg, at });
    const draft = state.talkDrafts[item.key];
    state.talkDrafts[item.key] = draft ? `${draft} ${said.words}` : said.words;
    if (!draft) state.talkBegan[item.key] = item.sent;
    const field = reader.querySelector('.ot-talk-field');
    if (field?.dataset.key === item.key) field.value = state.talkDrafts[item.key];
  } else if (act === 'sayNow') {
    native({ type: 'taskSayNow', ...msg, at });
  } else if (act === 'there') {
    openSession(to.s || to.was || taskThere(item));
  } else if (act === 'way') {
    const back = state.talkBack[item.key];
    if (back?.permission) native({ type: 'taskTalkPermission' });
    else if (to.s) native({ type: 'wayPast', sessionId: to.s.sessionId });
    delete state.talkBack[item.key];
  } else if (act === 'member' || act === 'lead') {
    state.talkLead[item.key] = act === 'lead';
  }
  drawReader();
}

// The talk's box emptied, its words sent or copied: nothing back in it, and no step it began on.
function oneTaskTalkCleared(key) {
  delete state.talkDrafts[key];
  delete state.talkBack[key];
  delete state.talkBegan[key];
}

// The task in front as it's drawn, for the box at the foot: a press there sends words you've written and seen, so it
// counts whenever the task is still the one in front.
function oneTaskInFront() {
  const ot = state.reading?.ot;
  return ot ? oneTaskItems().find((one) => one.key === ot.key) || null : null;
}

// Send waits for a comment's words: there's nothing to send without them.
// Answer waits for a comment's words: lit once there are some, and what it waits for said beside it till then.
function oneTaskSendable() {
  const ot = state.reading?.ot, item = ot && oneTaskItems().find((one) => one.key === ot.key);
  const answer = reader.querySelector('.ot-body [data-act="answer"]');
  if (!answer || !item) return;
  const off = !taskCanAnswer(item.task, ot.ui);
  answer.classList.toggle('off', off);
  if (off) answer.setAttribute('aria-disabled', 'true');
  else answer.removeAttribute('aria-disabled');
  setText(reader.querySelector('.ot-body .ot-waits'), taskAnswerWaits(item.task, ot.ui));
}

// The choices brought into view, or with Comment picked, its box with the cursor in it: what Answer waits for. Into
// the part of the view nothing covers, between the strip held at its top and Answer's bar held at its foot, so none
// of it lands behind the bar (as scrolling it just into view would); its top first, if it's taller than that.
function oneTaskShowChoices(ui) {
  const view = reader.querySelector('.r-body'), box = ui.chosen.includes('Comment') && view?.querySelector('.ot-note');
  const choices = box || view?.querySelector('.ot-choices')?.closest('.ot-part');
  if (!choices) return;
  const shown = view.getBoundingClientRect(), it = choices.getBoundingClientRect(), gap = 8;
  const top = shown.top + (view.querySelector('.ot-strip')?.offsetHeight || 0) + gap;
  const bottom = shown.bottom - (view.querySelector('.ot-act')?.offsetHeight || 0) - gap;
  const by = it.bottom > bottom ? Math.min(it.bottom - bottom, it.top - top) : Math.min(0, it.top - top);
  if (by) view.scrollBy({ top: by, behavior: calm.matches ? 'auto' : 'smooth' });
  if (box) {
    wantKeyboard(true);
    box.focus({ preventScroll: true });
  }
}

core.readerPresses.push(
  ['.ot-body [data-act]', (b) => { if (!b.disabled) oneTaskAct(b.dataset.act); }],
  ['.ot-body [data-tick]', (b) => {
    const ui = oneTaskPressed() && state.reading.ot.ui;
    if (!ui) return;
    ui.ticks[b.dataset.tick] = !ui.ticks[b.dataset.tick];
    drawReader();
  }],
  ['.ot-body [data-pick]', (b) => {
    const item = oneTaskPressed();
    if (!item) return;
    const ui = state.reading.ot.ui;
    ui.chosen = taskChoose(item.task, ui.chosen, b.dataset.pick);
    drawReader();
    // Comment picked: the cursor goes to its box. It asks for the keyboard before the box is focused, as a window
    // without it gets no focus events to ask with.
    if (ui.chosen.includes('Comment')) {
      wantKeyboard(true);
      reader.querySelector('.ot-note')?.focus({ preventScroll: true });
    }
  }],
  ['.ot-body [data-att]', (b) => oneTaskOpen(Number(b.dataset.att))],
  ['.k-one-task [data-talk]', (b) => { if (!b.disabled) oneTaskTalk(b.dataset.talk, b); }],
  ['.k-one-task [data-urgent]', (b) => oneTaskUrgent(b.dataset.urgent)],
  ['.ot-body [data-talk-to]', (b) => oneTaskTalk(b.dataset.talkTo, b)],
);
core.pointerTargets.push('#reader .ot-strip .button', '#reader .ot-back', '#reader .ot-kept-row .button',
                         '#reader .ot-talkbox .button:not(:disabled)', '#reader .ot-body .ot-talk-act',
                         '#reader .ot-body .ot-code button',
                         '#reader .ot-body .ot-to button', '#reader .ot-talkbox .ot-talk-act',
                         '#reader .ot-body .button:not(:disabled)', '#reader .ot-body .icon-button',
                         '#reader .ot-body .option', '#reader .ot-body .ot-check', '#reader .ot-body button.ot-att');
// The view scrolled: the answer takes its fill only while it's stuck at the foot.
reader.addEventListener('scroll', (e) => {
  if (oneTaskReading() && e.target.matches?.('.r-body')) oneTaskStuck();
}, { capture: true, passive: true });
// What you type in a task's box is kept as you type, so drawing it again keeps it; Return sends it.
reader.addEventListener('input', (e) => {
  // Typing in a task means you've seen it.
  if (state.reading?.ot?.key) {
    state.tasksSeen[state.reading.ot.key] = true;
    state.reading.ot.touched = true;
  }
  if (e.target.matches?.('.ot-talk-field') && state.reading?.ot) {
    const key = e.target.dataset.key, item = oneTaskInFront();
    state.talkDrafts[key] = e.target.value;
    delete state.talkBack[key];
    if (!e.target.value.trim()) delete state.talkBegan[key];
    else if (!state.talkBegan[key] && item?.key === key) state.talkBegan[key] = item.sent;
    if (item?.key === key) oneTaskTalkBox(e.target.closest('.ot-talkbox'), item);
    return;
  }
  if (!e.target.matches?.('.ot-note') || !state.reading?.ot) return;
  state.reading.ot.ui.note = e.target.value;
  oneTaskSendable();
});
reader.addEventListener('keydown', (e) => {
  if (e.target.matches?.('.ot-talk-field') && !e.isComposing && e.keyCode !== 229) {
    if (e.key === 'Enter') {
      e.preventDefault();
      oneTaskTalk('send');
    } else if (e.key === 'Escape') {
      e.preventDefault();
      e.target.blur();
      wantKeyboard(false);
    }
    return;
  }
  // In Comment's box, Return answers with your words and Esc leaves the box, keeping them.
  if (e.isComposing || e.keyCode === 229 || !e.target.matches?.('.ot-note')) return;
  if (e.key === 'Enter') {
    e.preventDefault();
    oneTaskAct('answer');
  } else if (e.key === 'Escape') {
    e.preventDefault();
    e.target.blur();
    wantKeyboard(false);
  }
});

// ---- What it plugs into ----

// Opening, leaving or closing it changes what the line under the header says: told once the reader has changed.
const oneTaskSaid = () => queueMicrotask(() => core.notices.said?.());
core.readerModes.oneTask = {
  sessionless: true,
  width: () => ONE_TASK_WIDTH,
  draw: drawOneTask,
  // Opened at a task (a reply's notice, a row's task line), named as the reader's scope: it's set here, once any other
  // mode's reset has gone, so it stays in front until you move on.
  shown(r) {
    r.ot = null;
    if (r.scope) state.tasksWant = r.scope;
    oneTaskSaid();
  },
  reset(r) {
    r.ot = null;
    state.tasksWant = null;
    oneTaskSaid();
  },
  closed() {
    state.tasksWant = null;
    oneTaskSaid();
  },
  cls: 'k-one-task',
};

// The line under the header, while One Task isn't in sight: the one in front, with Open; put away by its ×, how many
// wait, until another comes.
core.noticeSenders.push({
  from: 'one-task',
  notices() {
    const items = oneTaskItems();
    state.tasksNewest = taskNewest(items, state.tasksNewest);
    if (oneTaskReading()) return [];
    const notice = taskNotice(items, state.tasksNewest);
    // Something urgent has its own line, first: Open goes straight to it, the task you were on set aside.
    const urgent = taskUrgentNotice(items);
    // A session's reply to your words about a task, until you've seen it there: Open opens One Task at that task.
    const reply = talkNotice(items, state.last.sessions || [], state.talkSeen);
    return [...(urgent ? [{ ...urgent, press: () => {
      state.tasksGoUrgent = true;
      openReader(null, null, 'oneTask');
    } }] : []),
      ...(notice ? [{ ...notice, press: () => openReader(null, null, 'oneTask') }] : []),
      ...(reply ? [{ ...reply, item: undefined, press: () => {
        openReader(null, null, 'oneTask', reply.item.key);
      } }] : [])];
  },
});
// The pawn menu's count follows what waits, the panel open or not.
core.updates.push(() => oneTaskTell(oneTaskItems()));

// ---- On the session's row ----

// A session's task also shows on its row, in any way of showing the list: a line in your move's colour, its kind's word
// and its title, and "+N" when more of its own wait (taskAsks); pressed, One Task opens at that task. It's the row's
// note, on a line of its own, so the work line stays; it gives way to any other note (a team's own line, a deploy, a
// warning), and stands in for where a team member's job stands. Worked out once each time the list is drawn.
let oneTaskAsks = new Map();
// The step a row's line says: the task, and which time it was sent.
const oneTaskRowStep = (item) => `${item.key}:${item.sent}`;
core.beforeDraw.push(() => {
  oneTaskAsks = taskAsks(oneTaskItems());
  for (const sid of Object.keys(state.taskAskKeys)) if (!oneTaskAsks.has(sid)) delete state.taskAskKeys[sid];
  // A line that has only just come, or now says another task, or the next step of the same one (sent again under its
  // id, perhaps of another kind), waits to be seen before it takes a press.
  for (const [sid, ask] of oneTaskAsks) {
    const step = oneTaskRowStep(ask.item);
    if (state.taskAskKeys[sid] === step) continue;
    state.taskAskKeys[sid] = step;
    state.shownAt['ot-row:' + sid] = Date.now();
  }
});
// Back after giving way to another note (a step's note and its button, say), it's there in that note's place: it waits
// to be seen again before it takes a press, as a press meant for what was there may land on it.
let oneTaskLinesDrawn = new Set();
function oneTaskLinesBack(list) {
  const now = new Set([...list.querySelectorAll('.row[data-id] [data-one-task]')]
    .map((el) => el.closest('.row[data-id]').dataset.id));
  for (const sid of now) if (!oneTaskLinesDrawn.has(sid)) state.shownAt['ot-row:' + sid] = Date.now();
  oneTaskLinesDrawn = now;
}
core.drawn.push(oneTaskLinesBack);
core.forgotten.keys.push('taskAskKeys', 'taskCopied');
core.forgotten.prefixes.push('ot-row');
// It's a bubble in your move's colour, with no priority of its own (a lead's picks, which have one, are said on the
// lead's row by the team), ending in its one action (taskRowAct), the kit's icon for what it does. A command copied
// shows a tick for a moment (state.taskCopied), so the press is seen to have done something.
const TASK_ROW_ICONS = { out: OUT_ICON, plan: PLAN_ICON, prototype: PROTOTYPE_ICON, answer: ANSWER_ICON,
                         copy: COPY_ICON, seen: SEEN_ICON };
// Another module (the team, for a member's step of a kind) shows the same button for a kind of ask through the core,
// never by reading this file: its icon, its verb and what a press does with the task in hand (TASK_KIND_ACTS), or
// null for a kind it doesn't know.
core.taskKinds = { act: (kind) => (TASK_KIND_ACTS[kind]
  ? { ...TASK_KIND_ACTS[kind], icon: TASK_ROW_ICONS[TASK_KIND_ACTS[kind].icon] } : null) };
core.rowNotes.push((row) => {
  const ask = oneTaskAsks.get(row.s.sessionId);
  if (!ask) return null;
  const task = ask.item.task, words = `${taskKindWords[task.kind]}: ${task.title}`, label = `Open in One Task: ${words}`;
  const name = row.name || row.s.name || base(row.s.cwd);
  const moreTip = `${ask.more} more from ${name} ${ask.more === 1 ? 'waits' : 'wait'}`;
  const attrs = ` data-one-task="${esc(ask.item.key)}" role="button" title="${esc(label)}"`;
  const how = taskRowAct(ask.item);
  const copied = how.act === 'copy' && Date.now() - (state.taskCopied[row.s.sessionId] || 0) < ONE_TASK_COPIED_MS;
  const html = how.act === 'there' && !how.to?.sessionId ? ''
    : askActHTML(copied ? COPIED_ICON : TASK_ROW_ICONS[how.icon], copied ? 'Copied' : how.tip,
                 ` data-ot-act="${esc(oneTaskRowStep(ask.item))}"`);
  return { text: words, html: askLineHTML(words, ask.more, moreTip, attrs, label), tone: 'turn', quiet: false,
           cls: 'ask-note', line: true, look: 'normal', act: { want: how.want, html } };
});
core.presses.push(['[data-one-task]', (el, e) => {
  e.preventDefault();
  const sid = el.closest('.row[data-id]')?.dataset.id;
  if (!sid || justShown('ot-row:' + sid)) return;
  openReader(null, null, 'oneTask', el.dataset.oneTask);
}]);
// Its action, pressed once the line has been seen: only for the step the line still says, which the app is told too
// (`sent`), so it copies or opens nothing of a later one.
core.presses.push(['[data-ot-act]', (el, e) => {
  e.preventDefault();
  const sid = el.closest('.row[data-id]')?.dataset.id, item = sid && oneTaskAsks.get(sid)?.item;
  if (!item || oneTaskRowStep(item) !== el.dataset.otAct || justShown('ot-row:' + sid)) return;
  const how = taskRowAct(item), to = { sessionId: item.sid, id: item.task.id, sent: item.sent };
  if (how.act === 'copy') {
    native({ type: 'taskCopy', ...to });
    state.taskCopied[sid] = Date.now();
    render();
    setTimeout(render, ONE_TASK_COPIED_MS);
  } else if (how.act === 'open') native({ type: 'taskOpen', ...to, at: taskOpenAt(item.task) });
  else if (how.act === 'there') openSession(how.to);
  else openReader(null, null, 'oneTask', item.key);
}]);
core.pointerTargets.push('[data-one-task]', '[data-ot-act]');
// The pawn menu's One Task: the app has brought the panel up, back on its list side.
window.openOneTask = () => openReader(null, null, 'oneTask');

// What waits, as the app keeps it (each time it changes, and as the page loads), whether One Task is on, and the
// kinds' words from the task's contract.
window.setTasks = (list, on, kinds, rules) => {
  const takenOf = (tasks) => new Set(tasks.filter((one) => one.takenBack)
    .map((one) => `task:${one.sessionId}:${one.task.id}`));
  const takenBefore = takenOf(state.tasks);
  if (kinds && typeof kinds === 'object') taskKindWords = kinds;
  if (rules && typeof rules === 'object') state.tasksRules = { ...state.tasksRules, ...rules };
  state.tasks = (Array.isArray(list) ? list : []).filter((one) => one && typeof one.sessionId === 'string'
    && one.task && typeof one.task.id === 'string' && taskKindWords[one.task.kind]);
  state.tasksOn = on !== false;
  // What was answered or put back here goes once the app no longer has it waiting, or has it at the back.
  const waiting = new Set(state.tasks.map(oneTaskStepOf));
  const back = new Set(state.tasks.filter((one) => one.back).map(oneTaskStepOf));
  for (const step of Object.keys(state.tasksSent)) if (!waiting.has(step)) delete state.tasksSent[step];
  const keys = new Set(state.tasks.map((one) => `task:${one.sessionId}:${one.task.id}`));
  const takenNow = takenOf(state.tasks);
  for (const key of Object.keys(state.tasksLetGo)) if (!keys.has(key)) delete state.tasksLetGo[key];
  for (const step of Object.keys(state.tasksBack)) if (!waiting.has(step) || back.has(step)) delete state.tasksBack[step];
  // What you've read is kept by the app (`seenAt`), and stays read here, as after Whozmove restarts; a task the app no
  // longer has is forgotten, so one sent again after it's answered is new to you, as is one taken back and sent again.
  for (const key of Object.keys(state.tasksSeen)) if (!keys.has(key) || takenBefore.has(key) && !takenNow.has(key))
    delete state.tasksSeen[key];
  for (const one of state.tasks)
    if (one.seenAt && !one.takenBack) state.tasksSeen[`task:${one.sessionId}:${one.task.id}`] = true;
  oneTaskTell(oneTaskItems());
  core.notices.said?.();
  if (oneTaskReading()) drawReader();
};
