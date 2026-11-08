// PluginInstall: Whozmove's hooks as Claude Code's plugin, put into Claude Code and kept up to date there with its own
// `claude plugin` commands (the agent's AgentInstall).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The folder in Whozmove's own that Claude Code's marketplace reads the plugin from.
NSString *PluginFolder(void);
// Puts the hooks in the folder `hooks` into Claude Code, or brings them up to date there, as AgentInstall's
// connect:before:from: says, with `claude` looked for on `path` first (your terminal's PATH). It blocks: on the
// caller's queue.
NSDictionary *ConnectPlugin(NSString *answer, BOOL before, NSString *hooks, NSString *path);
// AgentInstall's hooksStamp, from when Claude Code last wrote its records of its plugins, and your settings and the
// machine's, which say whether each is on. Nil while it keeps no record of them.
NSString *HooksStamp(void);

// A part of Whozmove's hooks that a session runs only if it started after the part went in.
typedef NS_ENUM(NSInteger, HookPart) {
    HookPartSwitches,  // "Switch model?" asked in the panel (the permission hook on PreModelSwitch, in hooks.json)
    HookPartDontWait,  // a request that goes by itself if no one answers, for a session with it on (DONT_WAIT)
    HookPartHookLine,  // requests asked, and answered, over a line to the panel rather than in files (HOOK_LINE)
    HookPartApprovePlan,  // a plan approved from the panel, by a session you allow (APPROVE_PLAN)
    HookPartBetweenSteps,  // words handed in between steps and as a turn ends (the words hook on PostToolBatch)
};
// Whether the session with that process has that part of the hooks: Claude Code gives a session the hooks it had as the
// session started, so the hooks put in place in Whozmove's folder have the part, and the session started after hooks
// with it first were (not after they were last put in place, which every later change of them moves). When the part
// was first seen is kept in the app's defaults, unless `remember` is NO (a print run, whose home isn't yours).
BOOL SessionHasHookPart(pid_t pid, HookPart part, BOOL remember);
// Whether the hooks put in place in Whozmove's folder have that part, whatever sessions run.
BOOL HookPartInPlace(HookPart part);
