// One Task's view, as HTML: the task in front in one shape whatever its kind and project (its kind and title, the step
// it's at, why, what to do, what's attached, the kind's own buttons), drawn with the kit's pieces; the head saying who
// it's from, and the foot where your answer went and how many more wait. A session's own request isn't here: it stays
// on its row in the list.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The head: what it is, who it's from as Whozmove found it asking, where it's for, and how long it has waited, counted
// as its place in the line is (`came`: a lead's pick from when its queue first named it).
function taskHeadHTML(item, now) {
  const from = item ? taskFrom(item) : '';
  const waited = item ? ago(now - (item.came || item.at)) : '';
  return `<span class="r-title">One Task</span>`
    + `<span class="r-sub">${item ? `${esc(from)} ${taskWhereHTML(item)} · ${esc(waited)}` : ''}</span>`
    + `<button class="icon-button r-close" title="Close">${CLOSE_ICON}</button>`;
}

// Where the task is for, as the list's rows say where a session runs: a worktree on its chip (worktreeChip), else
// its branch, or outside git its folder. For a lead's pick, the member's, as that's the work it's about (taskThere).
function taskWhereHTML(item) {
  const s = taskThere(item), g = s?.git;
  if (!s) return '';
  if (!g) return `<span class="ot-in">${esc(base(s.cwd || ''))}</span>`;
  const branch = g.branch || `detached @${g.detached}`;
  return g.worktree ? worktreeChip(branch, 'ot-in')
    : `<span class="ot-in ot-branch">${BRANCH_ICON}${esc(branch)}</span>`;
}

// The foot: where your last answer went (said to VoiceOver as it comes), how many more wait after this one, never
// which, and out of sight, what VoiceOver says of each task as it comes in. Put in once as the view opens; what it
// says changes in place (one-task.js), so its line can fade.
const TASK_FOOT = '<div class="ot-talkbox" hidden><div class="ot-talk-row">'
  + '<input class="field small q-type ot-talk-field" aria-label="Ask about this task">'
  + '<button type="button" class="button small main" data-talk="send" disabled>Send</button></div>'
  + '<span class="ot-talk-goes"></span></div>'
  + '<div class="ot-foot-line"><span class="notice inline turn ot-sent" role="status"></span>'
  + '<span class="ot-more"></span></div><div class="ot-kept-row" hidden><span class="ot-kept"></span>'
  + '<button type="button" class="button small" data-talk="copyKept">Copy Your Words</button></div>'
  + '<span class="ot-say" aria-live="polite"></span>';

// With Say Why (One Task's page): over the task, why it's first; under it, what's after it by name, each with why.
function taskWhyHTML(item, items, now) {
  return `<p class="ot-why-here"><b>Here first:</b> ${esc(taskWhyHere(item, items, now))}.</p>`;
}
function taskAfterHTML(item, items, now) {
  const after = items.filter((one) => one !== item);
  if (!after.length) return '';
  return '<div class="ot-part ot-after"><span class="caps">After this</span><ol>' + after.map((one) =>
    `<li>${esc(one.task.title)} <i>· ${esc(taskWhyHere(one, items, now))}</i></li>`).join('') + '</ol></div>';
}

// The strip under One Task's head: the tasks to do now ahead of the one you're on, as the kit's urgent notice, with
// Go; or, while you're on one of them, ‹ Back to the task you set aside. Nothing when neither.
function taskStripHTML(urgent, aside) {
  if (aside) return '<div class="ot-strip" data-stays>'
    + `<button type="button" class="ot-back" data-urgent="back">‹ Back to ${esc(aside.title)}</button></div>`;
  const parts = taskUrgentParts(urgent);
  if (!parts) return '';
  return '<div class="ot-strip" data-stays><div class="notice urgent" role="status"><span class="notice-text">'
    + `<b>${esc(parts.head)}:</b> ${esc(parts.title)}${esc(parts.more)}</span>`
    + '<button type="button" class="button small main" data-urgent="go">Go</button></div></div>';
}
const taskMoreWords = (more, any, doNow = 0) => (more > 0 ? `${more} more after this${doNow ? `, ${doNow} to do now`
  : ''}` : any ? 'Nothing after this' : '');
// What VoiceOver says as a task comes in: its kind and title, and whom it's from.
const taskSayWords = (item) => (!item ? 'Nothing needs you'
  : `${taskKindWords[item.task.kind] || ''}: ${item.task.title}, ${taskFrom(item).replace(/^From/, 'from')}`);

const TASK_NOTHING = '<div class="ot-body ot-none"><div class="card-title">Nothing needs you</div>'
  + '<div class="card-lead">The next thing that does comes here first.</div></div>';
const TASK_OFF = '<div class="ot-body ot-none"><div class="card-title">One Task is off</div>'
  + '<div class="card-lead">Turn it on in Settings ▸ One Task.</div></div>';

// The step's track, the kit's (stepTrackHTML): one bar, what's done, the one now in the task's look (taskLook: to do
// now in the colour of something to put right, the lowest priority as low). One Task only places it, at the end of the
// step's line, and draws none where the kit draws none (a task of one step).
function taskTrackHTML(step, look) {
  const track = step ? stepTrackHTML(step.of, step.n - 1, look) : '';
  return track ? `<span class="ot-track" aria-hidden="true">${track}</span>` : '';
}

// What it attached, each on a line, with what a press there does (taskAttachOpens): a file from another session than
// the one that sent it says whose, by the name the list knows it by, and one that doesn't open says why.
function taskAttachHTML(a, i, item) {
  const opens = taskAttachOpens(a, item);
  if (a.kind === 'diff') return `<button type="button" class="ot-att" data-att="${i}"><span class="diff">`
    + `<span class="add">+${Number(a.added) || 0}</span> <span class="del">−${Number(a.removed) || 0}</span></span>`
    + `<span>${esc(a.label)}</span><span class="ot-att-do">See the Changes</span></button>`;
  const mark = { link: '↗', page: '↗', file: '▤', commit: '●' }[a.kind] || '·';
  const tag = opens ? `button type="button" data-att="${i}"` : 'span';
  const from = opens === 'writing' && taskWriting(item, a.path).s, theirs = from && from !== item.s;
  const end = opens ? '<span class="ot-att-do">Open</span>'
    : a.kind === 'file' ? `<span class="ot-att-do">${esc(taskAttachWhy(item))}</span>` : '';
  return `<${tag} class="ot-att"><b class="ot-att-mark">${mark}</b><span>${esc(a.label)}`
    + `${theirs ? `<em class="ot-att-from"> · from ${esc(taskWho(from))}</em>` : ''}</span>${end}`
    + `</${tag.split(' ')[0]}>`;
}

// Its answers to pick from (taskChoices), the kit's short list: each with its box to tick (round where only one is
// picked), a pick's letter, what it means under it, Recommended; and once Comment is picked, the box for its words
// right under it (`asks`, its hint).
function taskChoicesHTML(task, chosen, asks) {
  const several = (c) => !taskAlone(c.id) && (task.kind === 'pick' || task.several);
  return '<div class="options ot-choices">' + taskChoices(task).map((c) => {
    const on = chosen.includes(c.id), letter = task.kind === 'pick' && !taskAlone(c.id);
    const row = `<button type="button" class="option${on ? ' on' : ''}" data-pick="${esc(c.id)}" `
      + `role="${several(c) ? 'checkbox' : 'radio'}" aria-checked="${on}"><span class="tickbox${several(c) ? ''
        : ' round'}"></span>${letter ? `<b class="ot-letter">${esc(c.id)}</b>` : ''}<span class="ot-ch">${esc(c.label)}`
      + `${c.detail ? `<em>${esc(c.detail)}</em>` : ''}</span>`
      + `${c.recommended ? '<span class="tag new">Recommended</span>' : ''}</button>`;
    return row + (c.comment && on && asks ? '<input class="field small q-type ot-note" maxlength="1000" '
      + `placeholder="${esc(asks)}" aria-label="${esc(asks)}">` : '');
  }).join('') + '</div>';
}

// What it is and what to do: every part the task has (taskParts), each a label in capitals over a few short lines. A
// plan's own short view on its card, as the plans module draws it, or as the plan wrote it without the module; its
// points numbered, what it leaves out greyed; its phases each a name over its lines; a try's line on what changed and
// on what to look for.
function taskDoHTML(task, ui, asks) {
  const part = (label, html) => `<div class="ot-part"><span class="caps">${esc(label)}</span>${html}</div>`;
  const line = (words) => `<p class="ot-line">${esc(words)}</p>`;
  const hint = taskPickHint(task, ui.chosen);
  const parts = {
    glance: () => core.plans?.taskHTML(task.glance)
      ?? part('The plan at a glance', `<div class="ot-glance">${markdownHTML(task.glance
        .replace(/^\s*#{1,6}\s*at a glance\s*[:#]*\s*\n+/i, ''))}</div>`),
    changed: () => part('What changed', line(task.changed)),
    points: () => part(taskPointsWords(task), '<ol class="ot-points">' + task.points.map((p) => `<li${
      taskPointOut(p) ? ' class="out"' : ''}>${esc(p)}</li>`).join('') + '</ol>'),
    phases: () => part(`${task.phases.length} phases`, '<ol class="ot-phases">' + task.phases.map((p, i) =>
      `<li class="ot-phase"><span class="ot-num">${i + 1}</span><span class="ot-pn">${esc(p.name)}</span>`
      + `<span class="ot-pl">${p.lines.map((l) => `<span>${esc(l)}</span>`).join('')}</span></li>`).join('') + '</ol>'),
    lookFor: () => part('Look for', line(task.lookFor)),
    todo: () => part(task.kind === 'do' ? 'By hand' : task.kind === 'try' ? 'Do this' : 'What to do', '<div class="ot-todo">'
      + task.todo.map((w, i) => `<button type="button" class="ot-check" data-tick="${i}" role="checkbox" `
        + `aria-checked="${!!ui.ticks[i]}"><span class="tickbox"></span><span>${esc(w)}</span></button>`).join('')
      + '</div>'),
    command: () => part('Only you can run this', '<div class="ot-command">'
      + `<span class="card-help">In your own terminal${task.command.where ? `, in ${esc(task.command.where)}` : ''}`
      + `</span><code class="perm-detail">$ ${esc(task.command.run)}</code></div>`),
    choices: () => part(task.kind === 'pick' ? 'Pick one, or mix two' : task.several ? 'Pick any'
                          : task.kind === 'answer' ? 'Pick one' : 'Your answer',
                        taskChoicesHTML(task, ui.chosen, asks) + (hint ? `<p class="ot-hint">${esc(hint)}</p>` : '')),
  };
  return taskParts(task).map((name) => parts[name]()).join('');
}

// The task in front, whole: `ui` is what you've done on it so far (ticks, choices, the first thing pressed, the box
// open, and whether there's anything in it); `to`, whom the talk under it is with (talkTo), if it has one.
function taskBodyHTML(item, ui, to) {
  const task = item.task, step = taskStepWords(task);
  // Taken back by its session while you're on it: no answer to give, only what became of it.
  const buttons = item.takenBack ? `<p class="ot-hint">${esc(taskTakenBackWords(item))}.</p>`
    : taskButtons(task, ui, item.about).map((b) => `<button type="button" class="button${b.quiet ? ' quiet' : ''}`
      + `${b.main ? ' main' : ''}${b.off ? ' off' : ''}" data-act="${b.act}"${b.off ? ' aria-disabled="true"' : ''}>`
      + `${esc(b.word)}${b.act === 'there' ? OUT_ICON : ''}</button>`).join('')
      + `<span class="ot-waits">${esc(taskAnswerWaits(task, ui))}</span>`
      + (item.about?.why ? `<span class="ot-there-why">${esc(item.about.why)}</span>` : '');
  const asks = !item.takenBack && taskBoxWords(taskTo(item));
  return '<div class="ot-body">'
    + `<div class="ot-title"><span class="tag count">${taskKindWords[task.kind] || ''}</span>`
    + `<span class="card-title big">${esc(task.title)}</span></div>`
    + '<div class="ot-steps">'
    + (step ? `<div class="ot-step"><span class="ot-word">${esc(step)}</span>${taskTrackHTML(task.step, taskLook(item))}</div>` : '')
    + `<p class="ot-why">${esc(task.why)}</p>`
    + taskDoHTML(task, ui, asks)
    + (task.attach?.length ? '<div class="ot-part"><span class="caps">Attached</span><div class="ot-atts">'
      + task.attach.map((a, i) => taskAttachHTML(a, i, item)).join('') + '</div></div>' : '')
    + '</div>'
    + `<div class="ot-act"><div class="ot-buttons">${buttons}</div></div>`
    + (to ? taskTalkHTML(item, to, ui.open, ui.copied) : '')
    + '</div>';
}

// The talk under the task: whom your words go to and where it runs, with the member and the lead to choose between for
// the lead's pick until the talk begins; then what you said, each with how far it's got and its presses, and each
// reply, all of it in place, its prose's Markdown drawn (everything escaped), and each code block
// on a line of its own (taskCodeHTML); and while the session works on your words, its live line. Before anything is
// said, what it's for. Words back in your box aren't drawn. `open`: the code blocks shown whole, and `copied`, those
// whose Copy was just pressed, each by taskCodeKey.
function taskTalkHTML(item, to, open = {}, copied = {}) {
  const says = (item.talk?.says || []).filter((said) => !['refused', 'stopped'].includes(said.state));
  const name = to.name, asks = to.s?.ask ? core.agent.askLine?.(to.s.ask) || '' : '';
  const member = taskMember(item);
  const choose = member && !item.talk?.to
    ? '<span class="ot-to" role="group" aria-label="Who your words go to">' + [[member, 'member'], [item.s, 'lead']]
      .map(([s, who]) => `<button type="button" data-talk-to="${who}" aria-pressed="${to.s === s}">`
        + `${esc(taskWho(s))}</button>`).join('') + '</span>' : '';
  const head = `<div class="ot-talk-head"><span class="caps">Talk with ${esc(name)}</span>`
    + `<span class="ot-where">${esc(to.gone ? 'not on this task now' : talkWhere(to.s, item.talk?.terminals))}</span>`
    + `${choose}</div>`;
  const lines = says.map((said) => {
    const front = item.talk?.inFront?.includes(to.s?.sessionId) ? item.talk.terminals?.[to.s.sessionId] : '';
    const st = talkState(said, to.s, name, asks, front, !!to.waits);
    const press = st.acts.map((a) => ` <button type="button" class="ot-talk-act" data-talk="${a.act}" `
      + `data-at="${said.at}">${esc(a.word)}</button>`).join('');
    const you = `<div class="ot-you${st.held ? ' held' : ''}"><p>${esc(said.words)}</p>`
      + (st.words || press ? `<span class="ot-said${st.held ? ' held' : ''}">${esc(st.words)}${press}</span>` : '')
      + '</div>';
    if (said.state !== 'replied') return you;
    const reply = said.reply ? talkReply(said.reply) : null;
    return you + `<div class="ot-reply"><b>${esc(name)}</b>`
      + (reply ? `<div class="ot-reply-text">${reply.parts.map((p) => (p.code !== undefined
        ? taskCodeHTML(p, said.at, !!open[taskCodeKey(item, said.at, p.n)], !!copied[taskCodeKey(item, said.at, p.n)])
        : markdownHTML(p.prose))).join('')}</div>`
        : '')
      + (!reply || reply.cut ? `<span class="ot-said">${reply ? `The rest is in ${esc(name)}’s session`
        : `${esc(name)} answered in its session`} <button type="button" class="ot-talk-act" data-talk="there">`
        + 'Take Me There</button></span>' : '')
      + '</div>';
  }).join('');
  const live = talkLive(says, to.s, name);
  const empty = says.length ? '' : `<p class="ot-talk-empty">Ask ${esc(name)} what this is about, or what to press. `
    + 'It answers here.</p>';
  return `<div class="ot-talk">${head}${empty}<div class="ot-talk-lines">${lines}`
    + `${live ? `<p class="ot-live">${esc(live)}</p>` : ''}</div></div>`;
}

// A code block in a reply: one line, cut where it runs out of room, as a card shows a command (the kit's .perm-detail),
// with a press on it showing it whole; and Copy, which copies exactly what's between its fences, from the reply as the
// app read it, saying Copied a moment once pressed (`copied`). Nothing in it is ever run.
const taskCodeKey = (item, at, n) => `${item.key} ${at} ${n}`;
function taskCodeHTML(part, at, open, copied = false) {
  const lines = part.code.split('\n'), more = lines.length > 1;
  return `<div class="ot-code${open ? ' open' : ''}"><button type="button" class="ot-code-line" data-talk="code" `
    + `data-at="${at}" data-part="${part.n}" aria-expanded="${open}" title="${open ? 'Show one line' : 'Show it whole'}">`
    + `<pre class="perm-detail${open ? '' : ' cut capped'}" style="--lines:1">${open ? taskCodeWords(part.code)
      : esc(`${lines[0]}${more ? ' …' : ''}`)}</pre></button>`
    + `<button type="button" class="button small" data-talk="copyCode" data-at="${at}" data-part="${part.n}">`
    + `${copied ? 'Copied' : 'Copy'}</button></div>`;
}

// A command shown whole, escaped, wrapping only between its words: each word kept on one line ("--env=staging" never
// split after its "--"), but one longer than a line (TASK_CODE_WORD characters) left to break where it must.
const TASK_CODE_WORD = 48;
const taskCodeWords = (code) => code.split(/(\s+)/).map((w) => (!w || /^\s+$/.test(w) || w.length > TASK_CODE_WORD
  ? esc(w) : `<span class="ot-word-whole">${esc(w)}</span>`)).join('');
