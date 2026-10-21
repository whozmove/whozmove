// ClaudeCommand: Claude Code's command, `claude`, as the panel runs it itself (your plan's usage, Whozmove's plugin):
// where it may be, and what it runs with.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Where `claude` may be, best first: on `path` (your terminal's PATH), where its installers put it, then Claude
// Desktop's own copies, newest first.
NSArray<NSString *> *ClaudeCandidates(NSString *path);
// Whether Claude Code is on this Mac, found without running anything: `claude` where its installers put it, or Claude
// Desktop's own copy (ClaudeCandidates without your terminal's PATH, which only your shell could say), else its
// sessions' registry, once it has run here (as from a version manager's folder, which only that PATH has).
BOOL ClaudeCodeOnThisMac(void);
// What `claude` runs with: `path` and the bare essentials, and nothing of this app's, so the marks an agent's shell
// would have left (a Whozmove restarted from one inherits them) can't make it think it's an agent's.
NSDictionary<NSString *, NSString *> *ClaudeEnvironment(NSString *path);
