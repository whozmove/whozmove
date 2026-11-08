// EditKeys: ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z and ⇧⌘Z for a web view that's being typed in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

// The edit a key does (copy:, cut:, paste:, selectAll:, undo: or redo:), or NULL: a key that's pressed, not let go,
// only while what it's in has the keyboard, and only with ⌘ (and ⇧ for redo) and neither ⌥ nor ⌃ held. The key is
// the letter it makes with ⌘ held, as a menu's shortcuts are matched: a Russian or Greek layout makes its own letter
// without ⌘ and a Latin one with it. A plain function, so the print mode can show every case (--print-edit-keys).
SEL EditFor(NSEvent *event, BOOL typing);
// The edit done in a view, for its performKeyEquivalent:, while its window has the keyboard and what has it is in the
// view: YES if it was done. Whozmove has no Edit menu, where an app's edit keys come from, so without this a page's
// boxes would take none of them, a paste from a dictation app among them.
BOOL DoEditKey(NSView *view, NSEvent *event);
