// The icons the panel's core draws; a module keeps its own.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later

/* The branch icon is GitHub's Octicon git-branch, from https://github.com/primer/octicons, under this licence:

   MIT License

   Copyright (c) 2026 GitHub Inc.

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. */
// Octicon git-branch.
const BRANCH_ICON = '<svg width="10" height="10" viewBox="0 0 16 16"><path fill="currentColor" '
  + 'd="M9.5 3.25a2.25 2.25 0 1 1 3 2.122V6A2.5 2.5 0 0 1 10 8.5H6a1 1 0 0 0-1 1v1.128a2.251 2.251 0 1 1-1.5 0V5.372'
  + 'a2.25 2.25 0 1 1 1.5 0v1.836A2.493 2.493 0 0 1 6 7h4a1 1 0 0 0 1-1v-.628A2.25 2.25 0 0 1 9.5 3.25Z'
  + 'm-6 0a.75.75 0 1 0 1.5 0 .75.75 0 0 0-1.5 0Zm8.25-.75a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z'
  + 'M4.25 12a.75.75 0 1 0 0 1.5.75.75 0 0 0 0-1.5Z"/></svg>';

// A worktree: a folder with a branch in it, on the bottom line and the new conversation card.
const WORKTREE_ICON = '<svg width="11" height="11" viewBox="0 0 16 16"><path fill="none" stroke="currentColor" '
  + 'stroke-width="1.3" stroke-linejoin="round" d="M1.6 4.2c0-.6.4-1 1-1h3.3l1.4 1.5h6.1c.6 0 1 .4 1 1v6.9c0 .6-.4 1-1 '
  + '1H2.6c-.6 0-1-.4-1-1z"/><circle cx="6.2" cy="8.2" r="1.05" fill="currentColor"/><circle cx="6.2" cy="11.4" '
  + 'r="1.05" fill="currentColor"/><circle cx="10.2" cy="8.2" r="1.05" fill="currentColor"/><path fill="none" '
  + 'stroke="currentColor" stroke-width="1.1" stroke-linecap="round" d="M6.2 9.2v1.2M10.2 9.2c0 1.1-.9 1.5-2 '
  + '1.6l-1.1.2"/></svg>';

// The disk, as a ring with the part in use filled: the low-disk line above the list, and Storage's tile on the back.
const DISK_ICON = '<svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.1" fill="none" '
  + 'stroke="currentColor" stroke-width="1.6"/><path d="M8 8V1.9A6.1 6.1 0 0 1 13.9 9.6Z" fill="currentColor"/></svg>';

// A key, its bow a ring and its blade with two teeth: the line above the list when keys were found where they shouldn't
// be, and Storage's Keys tab.
const KEY_ICON = '<svg width="16" height="16" viewBox="0 0 16 16"><circle cx="5" cy="8" r="3" fill="none" '
  + 'stroke="currentColor" stroke-width="1.6"/><path d="M8 8h6.2M11.5 8v2.4M13.6 8v1.8" fill="none" '
  + 'stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';

// Desktop / Terminal, as an icon on the new conversation card.
// Two windows, one over the other: a conversation open more than once.
const TWICE_ICON = '<svg width="13" height="12" viewBox="0 0 13 12" aria-hidden="true"><rect x=".65" y="3.15" '
  + 'width="8" height="8" rx="2" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M4 3.15V2.65a2 2 '
  + '0 0 1 2-2h4.35a2 2 0 0 1 2 2V7a2 2 0 0 1-2 2H8.65" fill="none" stroke="currentColor" stroke-width="1.3"/></svg>';
const DESKTOP_ICON = '<svg class="kind" width="11" height="11" viewBox="0 0 16 16"><path fill="none" '
  + 'stroke="currentColor" stroke-width="1.4" d="M2 3h12v8H2zM6 14h4M8 11v3"/></svg>';
const TERMINAL_ICON = '<svg class="kind" width="11" height="11" viewBox="0 0 16 16"><path fill="none" '
  + 'stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" '
  + 'd="M3 4l4 4-4 4M8.5 12H13"/></svg>';
const CHEVRON_ICON = '<svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 3.5 5 6.5 8 3.5" fill="none" '
  + 'stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const CLOSE_ICON = '<svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 2l6 6M8 2l-6 6" stroke="currentColor" '
  + 'stroke-width="1.5" stroke-linecap="round"/></svg>';
// The time left, as a ring (controls.css's .time-ring): its track and the part left. Round a small round icon button's
// × (.timed), or standing by itself (.time-left).
const TIME_RING_ICON = '<svg class="time-ring" viewBox="0 0 20 20" aria-hidden="true"><circle class="track" cx="10" '
  + 'cy="10" r="7.25"/><circle class="left" cx="10" cy="10" r="7.25" pathLength="100"/></svg>';
// The × with the time left round it, for a small round icon button (.timed): the ring, then a smaller ×, 4pt across, so
// it sits clear inside the ring.
const TIMED_CLOSE_ICON = TIME_RING_ICON + '<svg width="10" height="10" viewBox="0 0 10 10"><path d="M3 3l4 4M7 3l-4 4" '
  + 'stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';
// A pin: a chat beside the folded cat kept out until you're done with it (chats.js), its head filled while it's kept.
const PIN_ICON = '<svg width="11" height="11" viewBox="0 0 12 12" aria-hidden="true"><path class="pin-head" '
  + 'd="M4 1.5h4l-.6 3.2L9.6 7H2.4l2.2-2.3z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/>'
  + '<path d="M6 7.2v3.4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>';
// A tick in a ring, in the colour of what's finished (controls.css's .done-tick): a code review with nothing left to
// fix, and Whozmove connected to its agent.
const DONE_ICON = '<svg class="done-tick" width="12" height="12" viewBox="0 0 16 16" aria-hidden="true"><circle '
  + 'cx="8" cy="8" r="6.4" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M5.3 8.2 7.2 10.1 10.8 6.2" '
  + 'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';

// What takes you out of the panel, to another app or a session's window (Take Me There): a box, its arrow from the
// middle out past its corner.
const OUT_ICON = '<svg class="out-icon" width="10" height="10" viewBox="0 0 12 12" aria-hidden="true" fill="none" '
  + 'stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"><path d="M6.2 1.5H2.5a1 1 '
  + '0 0 0-1 1v7a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V5.8"/><path d="M6 6l4.8-4.8M7.6 1.2h3.2v3.2"/></svg>';
// What an ask is for, on the button that does it (a row's ask line): a plan to read, a prototype to open, a command to
// copy, a question to answer, something to look at. Each 10px, in the button's colour.
const ACT_ICON = (paths) => '<svg width="10" height="10" viewBox="0 0 12 12" aria-hidden="true" fill="none" '
  + `stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
const PLAN_ICON = ACT_ICON('<rect x="2" y="1.3" width="8" height="9.4" rx="1.2"/>'
  + '<path d="M4.2 4h3.6M4.2 6h3.6M4.2 8h2.2"/>');
const PROTOTYPE_ICON = ACT_ICON('<rect x="1.3" y="2" width="9.4" height="7.4" rx="1.2"/><path d="M1.3 4.2h9.4"/>'
  + '<path d="M6 5.6l3 1.1-1.3.5-.5 1.3z" fill="currentColor"/>');
const COPY_ICON = ACT_ICON('<rect x="4" y="4" width="6.5" height="6.5" rx="1.2"/>'
  + '<path d="M8 2.5V2.3a1 1 0 0 0-1-1H2.5a1 1 0 0 0-1 1V7a1 1 0 0 0 1 1h.2"/>');
const ANSWER_ICON = ACT_ICON('<circle cx="6" cy="6" r="4.8"/><path d="M4.3 4.4a1.8 1.8 0 1 1 2.5 1.7c-.5.2-.8.6-.8 '
  + '1.1v.3"/><circle cx="6" cy="9.4" r=".35" fill="currentColor"/>');
const COPIED_ICON = ACT_ICON('<path d="M2.6 6.3 5 8.7 9.6 3.6"/>');  // what Copy shows a moment, once it's copied
const SEEN_ICON = ACT_ICON('<path d="M1 6s1.8-3.4 5-3.4S11 6 11 6 9.2 9.4 6 9.4 1 6 1 6z"/>'
  + '<circle cx="6" cy="6" r="1.5"/>');
