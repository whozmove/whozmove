// What a Claude Code session's request is, and what its card and Claude's line say about it: plain functions, with no
// page in them, so the module's page test checks every case (tests/page-cases.js). The cards that draw them are in
// requests.js, questions.js and answered.js.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// Claude Code's own tools the panel has plain words for, by the tool's name: the card's title, Claude's line, and what
// Allow once says. Any other tool shows its fields under its name.
const TOOL_WORDS = {
  KillShell: { title: 'Stop a command running in the background?', line: 'Wants to stop a background command',
               yes: 'Stop it' },
};
// A change made in this many edits or more shows one edit at a time.
const BIG_CHANGE = 3;
// How many questions a card asks, as Claude's own box does.
const MAX_QUESTIONS = 4;

// A request's questions, and each question's kind (choice, text or number) and default, by Claude Code's names for
// them (kind, defaultValue) or the older ones (type, default).
const questionsOf = (ask) => (ask?.input?.questions || []).slice(0, MAX_QUESTIONS);
const kindOf = (q) => q.kind || q.type || 'choice';
const defaultOf = (q) => q.defaultValue ?? q.default;

// The edits a request makes to a file, each { old_string, new_string }: one for Edit, each of MultiEdit's, and a
// notebook cell's new source (none for a cell taken out).
function editsOf(ask) {
  const i = ask?.input || {};
  if (ask?.tool === 'MultiEdit') return i.edits || [];
  if (ask?.tool === 'NotebookEdit') {
    return i.edit_mode === 'delete' ? [] : [{ old_string: '', new_string: i.new_source ?? '' }];
  }
  return [i];
}

// What a notebook edit does, and to which cell: "Replace cell 3 · code", "Insert a markdown cell after 3", "Delete cell
// 3" (Claude Code's edit_mode, cell_id and cell_type).
function notebookWhat(i) {
  const cell = i.cell_id ? `cell ${i.cell_id}` : 'the first cell', type = i.cell_type ? `${i.cell_type} ` : '';
  if (i.edit_mode === 'delete') return `Delete ${cell}`;
  if (i.edit_mode === 'insert') return `Insert a ${type}cell ${i.cell_id ? `after ${i.cell_id}` : 'at the top'}`;
  return `Replace ${cell}${i.cell_type ? ` · ${i.cell_type}` : ''}`;
}

// What a request is, which picks its card's look: a tool's (command, edit, bigEdit, write, read, fetch, search, mcp or
// other), a question's (qOne for one pick, qMulti for several, qSteps for several questions, qNumber, qText), or plan.
// A change cut short shows as an edit, with what's missing said, as there's nothing past the cut to step through.
function askKind(ask) {
  const tool = ask?.tool || '';
  if (tool === 'AskUserQuestion') {
    const qs = questionsOf(ask);
    if (qs.length > 1) return 'qSteps';
    const q = qs[0] || {}, kind = kindOf(q);
    return kind === 'number' ? 'qNumber' : kind === 'text' ? 'qText' : q.multiSelect ? 'qMulti' : 'qOne';
  }
  if (tool === 'ExitPlanMode') return 'plan';
  if (tool === 'Bash') return 'command';
  if (tool === 'Edit' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
    return editsOf(ask).length >= BIG_CHANGE && !ask.truncated ? 'bigEdit' : 'edit';
  }
  const kinds = { Write: 'write', Read: 'read', WebFetch: 'fetch', WebSearch: 'search' };
  if (kinds[tool]) return kinds[tool];
  return tool.startsWith('mcp__') ? 'mcp' : 'other';
}

// A path's file name, and the folder it's in: inside the project (`root`, its checkout or its folder) as a path from
// there, '' at the project's top, else in full.
const fileName = (path) => String(path || '').split('/').pop();
function folderIn(path, root) {
  const dir = String(path || '').split('/').slice(0, -1).join('/');
  if (root && (dir === root || dir.startsWith(root + '/'))) return dir.slice(root.length + 1);
  return dir;
}

// How many lines a text has (none for an empty one, and a last line ended by its line break counted once), and the
// lines a change puts in (+) and takes out (−), over all its edits.
const lineCount = (text) => (String(text ?? '') === '' ? 0 : String(text).replace(/\n$/, '').split('\n').length);
function changeCounts(edits) {
  return edits.reduce((n, e) => ({ add: n.add + lineCount(e.new_string), del: n.del + lineCount(e.old_string) }),
                      { add: 0, del: 0 });
}

// The site a page is on ("example.com"), or ''.
const urlHost = (url) => (/\/\/([^/?#]+)/.exec(url || '') || [])[1] || '';

// A tool's field that holds words to read, not code (an issue's description, a message's body): one of these names,
// holding text. It shows as prose, wrapped, its markdown drawn; any other long field shows as code.
const PROSE_FIELDS = ['description', 'body', 'text', 'content', 'message', 'comment', 'summary', 'notes', 'details'];
const isProse = (key, value) => typeof value === 'string' && PROSE_FIELDS.includes(String(key).toLowerCase());

// A connected app's tool (mcp__<app>__<action>): the app's name in words, its first letter a capital, and the action
// in words ("create_issue" as "Create issue"). Claude Code names a connector from claude.ai's account
// `claude_ai_<app>`, and a plugin's server `plugin_<plugin>_<app>`; those prefixes aren't the app's name.
const capital = (words) => words.charAt(0).toUpperCase() + words.slice(1);
function mcpName(tool) {
  const [, server = '', action = ''] = String(tool).split('__');
  const app = server.replace(/^claude_ai_/, '').replace(/^plugin_[^_]+_/, '').replace(/_/g, ' ').trim();
  return { app: capital(app), action: capital(action.replace(/_/g, ' ').trim()) };
}

// A plan's title (its first heading, without its markdown's marks), its numbered steps (the top-level ones only, each
// with its own number and the lines that carry on its words, as the reader shows them), and, for a plan with none, its
// first lines of words (`lead`, those not a heading, up to PLAN_LEAD of them). A step's words are the plan's markdown.
const PLAN_LEAD = 3;
function planOf(ask) {
  const lines = String(ask?.input?.plan || '').split('\n');
  const title = (lines.join('\n').match(/^\s*#+\s*(.+)$/m) || [])[1] || 'Its plan';
  const steps = [];
  let open = false;  // whether the next line can carry on the last step's words: until a blank line, or one not indented
  for (const line of lines) {
    const step = line.match(/^(\d+)[.)]\s+(\S.*)$/);
    const carries = open && /^\s+\S/.test(line) && !/^\s*([-*+]|\d+[.)])\s/.test(line);  // a nested list isn't
    if (step) steps.push({ n: Number(step[1]), text: step[2].trim() });
    else if (carries) steps.at(-1).text += ` ${line.trim()}`;
    open = !!step || carries;
  }
  const lead = steps.length ? [] : lines.map((l) => l.trim()).filter((l) => l && !/^#/.test(l)).slice(0, PLAN_LEAD);
  return { title: title.replace(/\*\*|__|`/g, '').trim(), steps, lead };
}

// Whether what a request would do needs Show all to be read whole: more than `cap` lines, or a line longer than a card
// shows on one (WIDE_LINE characters of code), which the card cuts at its edge.
const WIDE_LINE = 44;
function showAllNeeded(text, cap) {
  const lines = String(text ?? '').replace(/\n$/, '').split('\n');
  return lines.length > cap || lines.some((l) => l.length > WIDE_LINE);
}

// What a number question says of its range ("12 to 96", "at least 1"), and whether `value` is outside it.
function numberRange(q) {
  if (q.min != null && q.max != null) return `${q.min} to ${q.max}`;
  if (q.min != null) return `at least ${q.min}`;
  return q.max != null ? `at most ${q.max}` : '';
}
function outOfRange(q, value) {
  const n = Number(value);
  return String(value ?? '').trim() !== '' && (!Number.isFinite(n) || (q.min != null && n < q.min)
    || (q.max != null && n > q.max));
}

// What Claude's line says while a request waits: what it wants, in a few words.
function askLine(ask) {
  const i = ask?.input || {}, kind = askKind(ask);
  const qs = questionsOf(ask), header = String(qs[0]?.header || '').trim();
  switch (kind) {
    case 'command': return 'Wants to run a command';
    case 'edit': case 'bigEdit': return `Wants to edit ${fileName(i.file_path || i.notebook_path)}`;
    case 'write': return `Wants to write ${fileName(i.file_path)}`;
    case 'read': return `Wants to read ${fileName(i.file_path)}`;
    case 'fetch': return urlHost(i.url) ? `Wants to read a page on ${urlHost(i.url)}` : 'Wants to read a page';
    case 'search': return 'Wants to search the web';
    case 'mcp': return `Wants to use ${mcpName(ask.tool).app}`;
    case 'plan': return 'Wants your OK on its plan';
    case 'qSteps': return `Has ${qs.length} questions for you`;
    case 'qOne': case 'qMulti': case 'qNumber': case 'qText':
      return header ? `Asks about ${header}` : 'Has a question for you';
    default: return TOOL_WORDS[ask?.tool]?.line || `Wants to use ${ask?.tool || 'a tool'}`;
  }
}

// What a request is about, in a few words, for the line that says it was answered: the command's first line, the
// file's name, the page's site, the words searched, the question, the plan's title.
function askSubject(ask) {
  const i = ask?.input || {};
  switch (askKind(ask)) {
    case 'command': return String(i.command || '').split('\n')[0];
    case 'edit': case 'bigEdit': case 'write': case 'read': return fileName(i.file_path || i.notebook_path);
    case 'fetch': return urlHost(i.url) || i.url || '';
    case 'search': return i.query || '';
    case 'mcp': return mcpName(ask.tool).action;
    case 'plan': return planOf(ask).title;
    case 'other': return '';
    default: return questionsOf(ask)[0]?.question || '';
  }
}

// The words of the line that takes a card's place once you've answered it, by how (answered's): allowed once or denied,
// a question answered, skipped or dismissed, a plan approved, sent back or stopped.
const RECEIPT_WORDS = { allow: 'Allowed once', deny: 'Denied', answered: 'Answered', skipped: 'Skipped',
                        dismissed: 'Dismissed', approved: 'Approved', sentBack: 'Sent back', stopped: 'Stopped' };
const receiptWords = (how) => RECEIPT_WORDS[how] || 'Answered';

// When a request goes by itself if no one answers it (Don't Wait on Me, turned on for its session: the hook says when,
// as expiresAt), in whole minutes, or null for one that waits; it waits on a while longer as you answer it, here or in
// its session's tab. Never on a plan, which the hook never lets go.
function goesWords(ask, now) {
  if (!ask?.expiresAt || ask.tool === 'ExitPlanMode') return null;
  const left = ask.expiresAt - now;
  if (left < 60000) return 'Goes by itself in under a minute if no one answers';
  return `Goes by itself in ${Math.floor(left / 60000)} min if no one answers`;
}
// The same on its ring: how much of its session's whole wait is left (the app's `waits`, else from when it asked till
// it goes), from 1 to 0, more than all of it counting as full (answering here holds it a while longer); and the time
// left in minutes (minutesLeft). null where goesWords is.
const goesSpan = (ask) => ask.waits || Math.max(0, ask.expiresAt - (ask.at || ask.expiresAt));
function goesRing(ask, now) {
  if (!goesWords(ask, now)) return null;
  const left = Math.max(0, ask.expiresAt - now), span = goesSpan(ask);
  return { left: span > 0 ? Math.min(1, left / span) : 0, words: minutesLeft(left) };
}

// What a session you allow answered for this one (row.answeredFor), as its card says it: who (the session that
// answered, by its name), what it did and how it went, an approval taken in your move's colour (`turn`) and one not
// taken in the colour of something to put right (`warn`). null while an approval hasn't been taken yet, which the card
// waits for.
function answeredForWords(a) {
  if (!a || (a.what === 'approved' && a.state === 'pending')) return null;
  // Your own Approve beside the list (`yours`): nothing once it's taken, as the request's own line said Approved;
  // where it wasn't, said the same way, with the way to its tab. Your notes typed into a session for a plan that
  // stopped asking here: nothing while they go in or once they're in, as the reader says so; where they weren't, why.
  if (a.yours) {
    if (a.what === 'sentBack') {
      return a.state === 'notTyped' ? { head: 'Your notes', what: `Your notes on the plan weren't typed in: ${a.why}`,
                                        warn: true, plan: true } : null;
    }
    return a.what === 'approved' && a.state === 'notTaken' ? { head: 'Your approval', what: 'Your approval wasn\'t '
      + 'taken: approve the plan in its tab', warn: true, plan: true } : null;
  }
  const head = `${a.by} answered for you`;
  if (a.what === 'sentBack') return { head, what: `Sent the plan back: “${a.note}”` };
  if (a.what === 'answered') return { head, what: `Answered: ${a.note}` };
  if (a.what !== 'approved') return null;
  return a.state === 'approved' ? { head, what: `Approved the plan: “${a.title}”`, plan: true, turn: true }
    : { head, what: "Its approval wasn't taken: approve the plan in its tab", warn: true, plan: true };
}
