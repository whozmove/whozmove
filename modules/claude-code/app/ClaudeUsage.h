// ClaudeUsage: your Claude plan's usage, in the five-hour session and the week, asked of Claude Code itself.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The folder the check runs in, kept for it alone (RunningSessions leaves the session it runs out of the rows).
NSString *UsageFolder(void);

@interface ClaudeUsage : NSObject
// On a queue of the caller's, as it can take a few seconds: Claude Code's answer, as AgentUsage's askUsage gives it.
- (NSDictionary *)ask;
@end

// The parts the module's --print-usage prints, for tests/rows.sh (where `claude` may be: ClaudeCommand.h).
// What the strip needs from Claude Code's answer to the usage request, from one line of its output: nil if the line
// isn't that answer, @{@"error": why} when the answer is an error.
NSDictionary *UsageFromReply(NSData *line);
// From `claude auth status`: @"signedIn", @"signedOut", or nil when it can't be read.
NSString *AuthStateFrom(NSData *output);
// Why an answer has no plan's numbers, from what `claude auth status` said (AuthStateFrom's) and whether your
// terminal's shell sets an API key or another provider for it: nil when it's signed out with no such key (the card
// offers Sign in), else @"signedIn", @"shell" (signed out, but the shell's key is what Claude Code uses there) or
// @"unknown" (its sign-in couldn't be read). Only what was read, never a guess at why.
NSString *UsageNoPlanReason(NSString *auth, BOOL shellUsesOther);
// The command that signs in the `claude` at this path, as typed in a terminal.
NSString *ClaudeSignInCommand(NSString *claude);
