// Markdown, as plans and notes are written, turned into the reader's HTML.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

// What plans and notes use: headings, paragraphs, lists (nested by indent), quotes, code blocks, tables and rules,
// with bold, italic and code inside a line. Everything is escaped first, so no HTML in the text reaches the page.
// A link shows as its words, since the panel doesn't go anywhere; its address shows when pointed at.
function markdownHTML(text) {
  const lines = String(text ?? '').replace(/\r\n?/g, '\n').split('\n');
  return mdBlocks(lines, 0, lines.length);
}

function mdInline(text) {
  return String(text).split(/(`+[^`]*`+)/).map((part, i) => {
    if (i % 2) return `<code>${esc(part.replace(/^`+|`+$/g, ''))}</code>`;
    return esc(part)
      .replace(/!?\[([^\]]*)\]\(([^)\s]*)[^)]*\)/g, (m, words, url) => `<span class="md-link" title="${url}">${words}</span>`)
      .replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, (m, a, b) => `<strong>${a ?? b}</strong>`)
      .replace(/(^|[^*\w])\*([^*\s][^*]*)\*(?!\*)/g, '$1<em>$2</em>')
      .replace(/(^|[^_\w])_([^_\s][^_]*)_(?![_\w])/g, '$1<em>$2</em>')
      .replace(/~~([^~]+)~~/g, '<del>$1</del>');
  }).join('');
}

const MD_ITEM = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
const mdIndent = (line) => line.match(/^\s*/)[0].replace(/\t/g, '    ').length;
const mdCells = (line) => line.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());

function mdBlocks(lines, from, to) {
  let html = '', i = from;
  while (i < to) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    const fence = line.match(/^\s*(```+|~~~+)\s*([\w+-]*)/);
    if (fence) {
      const body = [];
      i++;
      while (i < to && !lines[i].trim().startsWith(fence[1])) body.push(lines[i++]);
      i++;
      html += `<pre><code>${esc(body.join('\n'))}</code></pre>`;
      continue;
    }
    const heading = line.match(/^\s*(#{1,6})\s+(.*?)\s*#*\s*$/);
    if (heading) {
      html += `<h${heading[1].length}>${mdInline(heading[2])}</h${heading[1].length}>`;
      i++;
      continue;
    }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) { html += '<hr>'; i++; continue; }
    if (line.includes('|') && i + 1 < to && /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$|^\s*\|\s*:?-+:?\s*\|\s*$/.test(lines[i + 1])) {
      const head = mdCells(line);
      html += '<div class="md-table"><table><thead><tr>' + head.map((c) => `<th>${mdInline(c)}</th>`).join('')
        + '</tr></thead><tbody>';
      i += 2;
      while (i < to && lines[i].includes('|') && lines[i].trim()) {
        html += '<tr>' + mdCells(lines[i]).map((c) => `<td>${mdInline(c)}</td>`).join('') + '</tr>';
        i++;
      }
      html += '</tbody></table></div>';
      continue;
    }
    if (/^\s*>/.test(line)) {
      const quoted = [];
      while (i < to && /^\s*>/.test(lines[i])) quoted.push(lines[i++].replace(/^\s*>\s?/, ''));
      html += `<blockquote>${mdBlocks(quoted, 0, quoted.length)}</blockquote>`;
      continue;
    }
    if (MD_ITEM.test(line)) {
      const [html_, next] = mdList(lines, i, to);
      html += html_;
      i = next;
      continue;
    }
    const para = [];
    while (i < to && lines[i].trim() && !MD_ITEM.test(lines[i]) && !/^\s*(#{1,6}\s|```|~~~|>)/.test(lines[i])) {
      para.push(lines[i++].trim());
    }
    html += `<p>${para.map(mdInline).join(' ')}</p>`;
  }
  return html;
}

// A list and what's nested in it: an item takes the lines after it that are indented further than its marker, or
// that carry on its text.
function mdList(lines, from, to) {
  const first = lines[from].match(MD_ITEM), indent = mdIndent(lines[from]);
  const ordered = /\d/.test(first[2]), tag = ordered ? 'ol' : 'ul';
  const start = ordered && parseInt(first[2], 10) !== 1 ? ` start="${parseInt(first[2], 10)}"` : '';
  let html = `<${tag}${start}>`, i = from;
  while (i < to) {
    const item = lines[i].match(MD_ITEM);
    if (!item || mdIndent(lines[i]) !== indent || /\d/.test(item[2]) !== ordered) break;
    const text = [item[3]];
    i++;
    while (i < to && lines[i].trim() && !MD_ITEM.test(lines[i]) && mdIndent(lines[i]) > indent) text.push(lines[i++].trim());
    let nested = '';
    while (i < to && (MD_ITEM.test(lines[i]) && mdIndent(lines[i]) > indent)) {
      const [inner, next] = mdList(lines, i, to);
      nested += inner;
      i = next;
    }
    const task = text[0].match(/^\[([ xX])\]\s+(.*)$/);
    const body = task ? `<span class="md-task${task[1] === ' ' ? '' : ' done'}"></span>${mdInline(task[2])}`
                      : mdInline(text[0]);
    html += `<li>${[body, ...text.slice(1).map(mdInline)].join(' ')}${nested}</li>`;
    // A blank line between items keeps the list going; anything else after one ends it.
    if (i < to && !lines[i].trim() && i + 1 < to && MD_ITEM.test(lines[i + 1]) && mdIndent(lines[i + 1]) === indent) i++;
  }
  return [html + `</${tag}>`, i];
}
