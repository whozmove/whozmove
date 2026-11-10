// A session that has stopped (its grey row, status "closed": a terminal session whose Claude has ended, or a Claude
// Desktop conversation Claude isn't running) says so, and that pressing its row carries it on, quietly, at its work
// line's start, after its pull requests, as Reload's line is said, so what isn't committed in its checkout and the steps
// it has to take stay at the line's end. The line takes no press of its own: a press anywhere on the row carries the
// conversation on, as it always has. A running session's row says nothing new, and nor does one closed while it waits
// on someone else (its documented `wait` says `closed`), whose own line says it stopped and how to carry it on, so the
// row says it once. A row shown briefly has no work line, so there it's the row's note, quiet, given only when nothing
// else is said on the row, with nothing at its end (a context ring there would read as something still at work).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

function endedLineHTML(row) {
  if (row.s.status !== 'closed' || row.s.wait?.closed) return '';
  return '<div class="nopr ended"><span class="pt">Stopped · press to carry on</span></div>';
}

function endedNote(row) {
  return row.brief && !row.tools && row.s.status === 'closed' && !row.s.wait?.closed
    ? { text: 'Stopped · press to carry on', quiet: true, end: false } : null;
}

core.slots.workStart.push(endedLineHTML);
core.rowNotesLast.push(endedNote);
