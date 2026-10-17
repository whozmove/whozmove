// Trust: whether Claude may work in a folder, as Claude Code and Claude Desktop both record it, and recording your yes.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Both apps ask once before working in a folder you've never opened Claude in, and keep the answer in Claude Code's
// state file (kClaudeCodeState). A start from the panel would otherwise stop on that question in the app, so the panel
// asks it in the card instead, and records your answer where both apps look. Blocking; call off the main thread.
#import <Foundation/Foundation.h>

// Whether a folder is trusted: it, its checkout or its repo, or any folder above it.
BOOL FolderTrusted(NSString *folder);
// Records that you trust a folder, as Claude Code and Claude Desktop record it. Nil once done (or if it already was),
// else why it couldn't be, as the panel says it.
NSString *TrustFolder(NSString *folder);
