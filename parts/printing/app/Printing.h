// Printing: what the print runs the tests check have in common (main.m's and the modules' own).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core, Row;

// The object as JSON on the standard output, keys sorted and indented, so a test can compare it with a recorded copy;
// the exit status: 1 if it isn't JSON.
int PrintJSON(id object);
// The rows read once, the way the panel reads them, waited for on the main run loop (10 seconds at most).
NSArray<Row *> *ReadRows(Core *core);
// The rows for the home folder in $HOME, once what's worked out alongside them (transcripts, git, counts) has come
// back: each module says whether it's still working, and the main run loop runs until none is (10 seconds at most).
// Files the whole Mac shares are read from that home folder too, and nothing in a print run asks the network, so the
// rows depend on neither the network nor the Mac.
NSArray<Row *> *SettledRows(Core *core);
