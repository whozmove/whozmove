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
