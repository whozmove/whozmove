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

// Desktop / Terminal, as an icon on the details line.
const DESKTOP_ICON = '<svg class="kind" width="11" height="11" viewBox="0 0 16 16"><path fill="none" '
  + 'stroke="currentColor" stroke-width="1.4" d="M2 3h12v8H2zM6 14h4M8 11v3"/></svg>';
const TERMINAL_ICON = '<svg class="kind" width="11" height="11" viewBox="0 0 16 16"><path fill="none" '
  + 'stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" '
  + 'd="M3 4l4 4-4 4M8.5 12H13"/></svg>';
const CHEVRON_ICON = '<svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 3.5 5 6.5 8 3.5" fill="none" '
  + 'stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const CLOSE_ICON = '<svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 2l6 6M8 2l-6 6" stroke="currentColor" '
  + 'stroke-width="1.5" stroke-linecap="round"/></svg>';
