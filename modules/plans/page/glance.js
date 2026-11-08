// A plan at a glance, as plain functions (its page cases check them): the short view a plan opens on, read from its
// "## At a glance" block, or pulled from headings that are each slot and nothing else; its sections, to fold; and the
// words your picks go back to Claude in, and how many the plan card says you've changed.
// Nothing here draws (glance-view.js does), and nothing asks an AI: what a plan says is all there is.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// The slots, in the order the card shows them, each with what its label in the block reads and the headings it may be
// pulled from when there's no block. A heading that isn't one of these (Context, Steps, Pieces, Tests) never fills one:
// a slot only ever holds what it says it is.
const PLAN_SLOTS = [
  { key: 'changes', label: /^what changes for you$/i, from: /^what you('|’)?ll see$|^what you see$/i },
  { key: 'decide', label: /^you decide$/i, from: /^(open )?decisions?\b/i },
  { key: 'risks', label: /^could go wrong$/i, from: /^could go wrong$|^risks?$/i },
  { key: 'tryIt', label: /^you('|’)ll try$/i, from: /^you('|’)ll try$|^how to try it$|^try it$/i },
  { key: 'keeps', label: /^what it keeps or sends$/i, from: /^what it keeps or sends$|^privacy$/i },
  { key: 'leftOut', label: /^left out$/i, from: /^left out$|^not in it$|^out of scope$/i },
];
const PLAN_BLOCK = /^at a glance$/i;
// How many choices show before "+2 more choices": the card fits the reader without scrolling.
const PLAN_CHOICES_SHOWN = 4;

// The plan's lines, with code blocks marked, so a "#" or a list inside one is never read as the plan's own.
function planLines(text) {
  let fence = null;
  return String(text ?? '').replace(/\r\n?/g, '\n').split('\n').map((line) => {
    const mark = line.match(/^\s*(```+|~~~+)/);
    const code = !!fence || !!mark;
    if (mark) fence = fence ? (line.trim().startsWith(fence) ? null : fence) : mark[1];
    const heading = !code && line.match(/^\s*(#{1,6})\s+(.*?)\s*#*\s*$/);
    return { line, code, level: heading ? heading[1].length : 0, title: heading ? heading[2] : '' };
  });
}

// A heading's words, without the Markdown around them, to match.
const planHeadingWords = (title) => title.replace(/[*_`]/g, '').replace(/[:.]\s*$/, '').trim();

// The plan in parts: its title (its first top heading), what comes before the first section, and its sections at the
// shallowest level under the title, each with its heading's words, its level and its body as written. A later top
// heading (an earlier version kept under the new one, say) is a section of its own, holding everything under it, so
// the sections under the title are still the plan's own, its "## At a glance" block among them.
function planParts(text) {
  const lines = planLines(text);
  // Its title: its first top heading that isn't the "At a glance" block.
  const titleAt = lines.findIndex((l) => l.level === 1 && !PLAN_BLOCK.test(planHeadingWords(l.title)));
  const later = titleAt < 0 ? -1 : lines.findIndex((l, i) => i > titleAt && l.level === 1);
  const under = later < 0 ? [] : lines.slice(titleAt + 1, later).filter((l) => l.level > 1).map((l) => l.level);
  const levels = under.length ? under
    : lines.filter((l, i) => l.level > 1 || (l.level === 1 && i !== titleAt)).map((l) => l.level);
  const level = levels.length ? Math.min(...levels) : 0;
  const parts = { title: titleAt >= 0 ? lines[titleAt].title : '', intro: [], sections: [] };
  let current = null;
  lines.forEach((l, i) => {
    if (i === titleAt) return;
    if (under.length && i >= later ? l.level === 1 : level && l.level === level) {
      current = { title: l.title, words: planHeadingWords(l.title), level: l.level, lines: [] };
      parts.sections.push(current);
    } else (current ? current.lines : parts.intro).push(l);
  });
  const body = (ls) => ls.map((l) => l.line).join('\n').trim();
  parts.intro = body(parts.intro);
  parts.sections.forEach((s) => { s.body = body(s.lines); });
  return parts;
}

// A part of the plan as its blocks: each list item (with the lines that carry it on and what's nested in it), each
// paragraph, each code block, each table; and the depth of each item, so a decision's nested lines stay with it.
function planBlocks(body) {
  const lines = planLines(body), blocks = [];
  let i = 0;
  while (i < lines.length) {
    const l = lines[i];
    if (!l.line.trim()) { i++; continue; }
    if (l.code) {
      const code = [];
      while (i < lines.length && lines[i].code) code.push(lines[i++].line);
      blocks.push({ kind: 'code', text: code.join('\n') });
      continue;
    }
    if (l.level) { blocks.push({ kind: 'heading', text: l.title }); i++; continue; }
    const item = l.line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
    if (item) {
      const indent = item[1].length, text = [item[3]], nested = [];
      i++;
      while (i < lines.length && lines[i].line.trim() && !lines[i].level) {
        const next = lines[i].line.match(/^(\s*)([-*+]|\d+[.)])\s+/);
        if (next && next[1].length <= indent) break;
        if (next || nested.length) nested.push(lines[i].line);
        else text.push(lines[i].line.trim());
        i++;
      }
      blocks.push({ kind: 'item', text: text.join(' '), nested: nested.join('\n'), numbered: /\d/.test(item[2]) });
      continue;
    }
    const para = [];
    while (i < lines.length && lines[i].line.trim() && !lines[i].level && !lines[i].code
           && !/^\s*([-*+]|\d+[.)])\s+/.test(lines[i].line)) para.push(lines[i++].line.trim());
    blocks.push({ kind: /^\|/.test(para[0]) ? 'table' : 'para', text: para.join(' ') });
  }
  return blocks;
}

// One choice, from "Question: option A (recommended), or option B. Why: one line": the question (up to its first
// colon, or in bold), its options, the one recommended (-1 when none says so) and why. Options part at semicolons
// when there are any (so an option can have a comma, or an "or", in it: "on or off (recommended); or neither"); else
// at commas when the list ends ", or C"; else at "or". A choice that names no options is just its words.
function planChoice(text) {
  let rest = String(text).trim(), why = '';
  const whyAt = rest.search(/\bWhy:\s*/i);
  if (whyAt >= 0) {
    why = rest.slice(whyAt).replace(/^Why:\s*/i, '').trim();
    rest = rest.slice(0, whyAt).trim().replace(/[.;,]$/, '');
  }
  let q = '';
  const bold = rest.match(/^\*\*(.+?)\*\*:?\s*(.*)$/);
  if (bold) { q = bold[1].replace(/:$/, ''); rest = bold[2]; }
  else {
    const colon = rest.indexOf(':');
    if (colon > 0) { q = rest.slice(0, colon); rest = rest.slice(colon + 1).trim(); }
  }
  let options = rest.includes(';') ? rest.split(/;\s*(?:or\s+)?/i)
    : /,\s*or\s+/i.test(rest) ? rest.split(/,\s*(?:or\s+)?/i) : rest.split(/\s+or\s+/i);
  options = options.map((o) => o.trim()).filter(Boolean);
  if (!q || options.length < 2) return { q: q || rest, options: [], rec: -1, why };
  const rec = options.findIndex((o) => /\(recommended\)/i.test(o));
  return {
    q, why, rec,
    options: options.map((o) => o.replace(/\s*\(recommended\)/i, '').replace(/[.;,]+$/, '').trim()
      .replace(/^./, (c) => c.toUpperCase())),
  };
}

// A line as a slot shows it, starting with a capital: after a label, a plan often carries on in lower case.
const planCapital = (words) => String(words).replace(/^[a-z]/, (c) => c.toUpperCase());
// A slot's lines from a block's body: its items, or else its paragraphs.
const planSlotLines = (blocks) => blocks.filter((b) => b.kind === 'item' || b.kind === 'para').map((b) => planCapital(b.text));

// The short view of a plan, or null when it has none to show: { from: 'written' or 'pulled', slots: { key → lines },
// decide: [choice], sources: { key → where it came from, when pulled }, more: { key → the heading with more under it,
// when pulled }, before, after, context (it has a Context section, which a missing What Changes for You points to) }.
// Written is the plan's own "## At a glance" block, each "**Label:** words" item in the slot it names. Pulled is each
// slot from a heading that is that slot, and only those; What Changes for You from What You See's first line, said so.
// The label an item of the block starts with ("**You decide:**"), without its colon, or ''.
const planItemLabel = (b) => (b.kind === 'item' && b.text.match(/^\*\*(.+?):?\*\*/)?.[1].replace(/:$/, '').trim())
  || '';
// Whether a label is one the card places: a slot's, or Before or After.
const planPlacedLabel = (label) => [...PLAN_SLOTS.map((x) => x.label), /^before$/i, /^after$/i]
  .some((l) => l.test(label));

// The plan's own "## At a glance" section, or undefined. A block with none of the slots' labels in it is no block:
// its headings are read instead.
const planBlockOf = (parts) => parts.sections.find((s) => PLAN_BLOCK.test(s.words)
  && planBlocks(s.body).some((b) => planPlacedLabel(planItemLabel(b))));

// Whether every line of a plan's own block is on its card: each item has a label the card places, a slot's words
// are on its line or in plain lines under it, and each choice is one line, with nothing under it; no paragraph, code
// or table between them. Where something isn't, the card would leave it out without a word, so a view with Approve
// under it (One Task's) shows the block as it was written instead.
function planBlockWhole(text) {
  const block = planBlockOf(planParts(text));
  return !!block && planBlocks(block.body).every(planOnCard);
}
// Whether one part of the block is on the card whole.
function planOnCard(b) {
  const label = planItemLabel(b);
  if (!planPlacedLabel(label)) return false;
  const words = b.text.replace(/^\*\*(.+?):?\*\*:?\s*/, '').trim();
  if (!b.nested) return true;
  if (PLAN_SLOTS.find((x) => x.label.test(label))?.key === 'decide')
    return planBlocks(b.nested).every((x) => x.kind === 'item' && !x.nested);
  const flat = planBlocks(b.nested).every((x) => (x.kind === 'item' || x.kind === 'para') && !x.nested);
  return !!words && !/^(before|after)$/i.test(label) && flat;
}

function planGlance(text) {
  const parts = planParts(text);
  const block = planBlockOf(parts);
  const glance = { from: block ? 'written' : 'pulled', slots: {}, decide: [], sources: {}, more: {}, before: '', after: '',
                   context: parts.sections.some((s) => /^context$/i.test(s.words)) };
  if (block) {
    for (const b of planBlocks(block.body)) {
      if (b.kind !== 'item') continue;
      const labelled = b.text.match(/^\*\*(.+?):?\*\*:?\s*(.*)$/);
      if (!labelled) continue;
      const label = labelled[1].replace(/:$/, '').trim(), words = labelled[2].trim();
      if (/^before$/i.test(label)) {
        const after = words.match(/^(.*?)\s*\*\*After:?\*\*:?\s*(.*)$/i);
        glance.before = planCapital(after ? after[1] : words);
        if (after) glance.after = planCapital(after[2]);
        continue;
      }
      if (/^after$/i.test(label)) { glance.after = planCapital(words); continue; }
      const slot = PLAN_SLOTS.find((x) => x.label.test(label));
      if (!slot) continue;
      if (slot.key === 'decide') {
        glance.decide = planBlocks(b.nested).filter((x) => x.kind === 'item').map((x) => planChoice(x.text));
        if (!glance.decide.length && words) glance.decide = [planChoice(words)];
      } else if (words) glance.slots[slot.key] = [planCapital(words), ...planSlotLines(planBlocks(b.nested))];
    }
  } else {
    // Any level, so a plan's "### Risks" counts as well as its "## Risks"; the first heading that is the slot wins.
    const headings = planLines(text).map((l, i) => ({ ...l, i })).filter((l) => l.level > 1);
    const all = planLines(text);
    for (const slot of PLAN_SLOTS) {
      const h = headings.find((x) => slot.from.test(planHeadingWords(x.title)));
      if (!h) continue;
      // Its own lines only: up to the next heading of any level, so a "### Risks" under Decisions is never a choice.
      const end = all.findIndex((l, i) => i > h.i && l.level);
      const blocks = planBlocks(all.slice(h.i + 1, end < 0 ? undefined : end).map((l) => l.line).join('\n'));
      if (slot.key === 'decide') {
        glance.decide = blocks.filter((b) => b.kind === 'item').map((b) => planChoice(b.text));
        if (glance.decide.length) glance.sources.decide = planHeadingWords(h.title);
        continue;
      }
      // Its first item only, so the card stays one screen; the rest is under its heading, and the card says so.
      const lines = planSlotLines(blocks);
      if (!lines.length) continue;
      glance.slots[slot.key] = lines.slice(0, 1);
      glance.sources[slot.key] = planHeadingWords(h.title);
      if (lines.length > 1) glance.more[slot.key] = planHeadingWords(h.title);
    }
    if (!Object.keys(glance.slots).length && !glance.decide.length) return null;
  }
  return glance;
}

// The sections to fold, in order: each { title, body, first, opens }, `first` its first sentence as plain words. The
// "At a glance" block is left out only when every line of it is on the card above (planBlockWhole). A block the card
// reads in part, or not at all (labels of its own), stays, so none of it is hidden, and `opens`: it's the plan's own
// short view, what Skimmed is for. Read in part, it's named so it isn't taken for the card again, and its first line
// is the first one the card left out, so the fold says what's new in it.
function planSections(text) {
  const parts = planParts(text), read = planBlockOf(parts), whole = planBlockWhole(text);
  return parts.sections.filter((s) => !(whole && PLAN_BLOCK.test(s.words))).map((s) => {
    if (!PLAN_BLOCK.test(s.words)) return { title: s.title, body: s.body, first: planFoldWords(s.body) };
    if (s !== read) return { title: s.title, body: s.body, first: planFoldWords(s.body), opens: true };
    const left = planBlocks(s.body).find((b) => !planOnCard(b));
    return { title: 'At a glance, as written', body: s.body, first: planFirstWords(left ? left.text : s.body),
             opens: true };
  });
}

// What a folded section says: its first sentence, or, for a section that's only a diagram, what the diagram shows
// (core.diagrams), so it's never left with nothing under its title.
const planFoldWords = (body) => planFirstWords(body) || core.diagrams?.words(body) || '';

// The plan's first flow with something to show, for its card (core.diagrams), so the card never says only "A flow
// diagram.": the section it's in, by its place among the folds, its title
// and the flow's text; or null.
function planFlow(text) {
  if (!core.diagrams) return null;
  for (const [i, s] of planSections(text).entries()) {
    const flow = core.diagrams.firstFlow(s.body);
    if (flow) return { i, title: planHeadingWords(s.title), text: flow };
  }
  return null;
}

// Markdown as plain words: what a fold says before it's opened.
function planPlain(md) {
  return planLines(md).filter((l) => !l.code && !l.level).map((l) => l.line).join(' ')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/(^|\s)([-*+]|\d+[.)])\s+/g, '$1')
    .replace(/[*_`>|]/g, '').replace(/\s+/g, ' ').trim();
}
function planFirstWords(md) {
  const plain = planPlain(md), end = plain.search(/[.!?](\s|$)/);
  return end >= 0 ? plain.slice(0, end + 1) : plain;
}

// A choice's words as the notes quote them: only what the card showed (a link's words, not its address or title),
// without the characters a person can't see, and cut short. The notes go back in the user's name, so the plan's own
// text may only name the choice; the numbers carry the pick.
const PLAN_NOTE_WORDS = 120;
function planNoteWords(md) {
  const words = [...planPlain(md).replace(/[\p{Cc}\p{Cf}\u{E0000}-\u{E007F}]/gu, '').replace(/["“”]/g, '\'').trim()];
  return `"${words.length > PLAN_NOTE_WORDS ? `${words.slice(0, PLAN_NOTE_WORDS - 1).join('').trimEnd()}…`
    : words.join('')}"`;
}

// What goes back to Claude for the picks that differ from its own: one sentence each, as the notes of a send-back.
// `picks` is { choice's index → option's index }; a choice with no recommendation takes no pick.
function planPicksNote(glance, picks) {
  const changed = (glance?.decide || []).map((d, i) => ({ d, i, p: picks?.[i] }))
    .filter(({ d, p }) => d.rec >= 0 && p !== undefined && p !== d.rec && d.options[p] !== undefined);
  return {
    changed: changed.length,
    note: changed.map(({ d, i, p }) => `Decision ${i + 1} (${planNoteWords(d.q)}): option ${p + 1}, `
      + `${planNoteWords(d.options[p])}, in place of your recommended option ${d.rec + 1}, `
      + `${planNoteWords(d.options[d.rec])}.`).join(' '),
  };
}

// What the plan card on a row says of its choices: how many you've changed from Claude's picks, once you have (as the
// reader's bar counts them, planPicksNote); else how many come with Claude's pick.
function planDecideWords(glance, picks) {
  const n = glance.decide.length, recs = glance.decide.filter((d) => d.rec >= 0).length;
  const choices = `${n} ${n === 1 ? 'choice' : 'choices'}`, changed = planPicksNote(glance, picks).changed;
  if (changed) return `${choices}, ${changed} changed by you`;
  return recs === n ? `${choices}, Claude's ${n === 1 ? 'pick' : 'picks'} ready`
    : recs ? `${choices}, ${recs} with Claude's pick` : choices;
}

