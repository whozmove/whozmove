// Records: where Claude Code keeps what its sessions were told and read, and what each part of it is about, for Keys
// (the agent's AgentRecords); and the command of its own that clears a project's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Its records, as AgentRecords' `records` describes them: the transcripts (its sub-agents' among them) and its tools'
// long outputs beside them, the prompts you typed, long pastes, the copies of files its sessions edited, and what it
// reads into its sessions as their instructions (kind `instructions`): yours, your organisation's, each project's
// memory, your plugins', and those of the folders its sessions ran in and up from them, with what they import.
NSArray<NSDictionary *> *ClaudeRecords(void);

// What part of one is about, as AgentRecords' about:line: says: a transcript's line has its session and folder, and
// says who it's from, a compaction's summary marked (`summary`); a typed prompt's, its project's folder; and a file,
// the session whose folder it's in.
NSDictionary *ClaudeRecordAbout(NSString *path, NSDictionary *line);

// `claude purge <folder>`, the folder quoted for the shell.
NSString *ClaudeClearCommand(NSString *folder);
