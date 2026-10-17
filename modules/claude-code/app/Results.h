// Results: a slash command's result, as Claude Code writes it into a session's transcript, and what it says.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// A slash command's result in a transcript, among what was written after `from`, or nil while there's none.
NSString *CommandResult(NSString *path, unsigned long long from, NSString *command);
// What a command's result says: the value that now applies for the field the command changed (nil: it changed nothing,
// declined or failed); whether it saved the pick as the default for new sessions; and after /compact, nil once it
// compacted, else what its card says, in plain text ("" when there's no result to say).
NSString *ResultApplies(NSString *field, NSString *value, NSString *result);
BOOL ResultSavedDefault(NSString *result);
NSString *CompactNote(NSString *result);
