// ClaudeCodeFacts: what Whozmove relies on about Claude Code that it could change. When one changes, the fix belongs
// here.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The version these were last checked with is in the README ("Tested with").
//
// What isn't here, and why: the layout of a file is known only to the code that reads it (transcripts, the settings
// files), so it is still in one place each. The hooks know Claude Code's tool names and events. build.sh knows the mark
// Claude Code puts on the commands an agent runs (CLAUDECODE; the app's own copy is kClaudeCodeAgentMarks), plugin.sh
// and app/swap-in.sh how it keeps an installed plugin (a copy per version, refreshed by `claude plugin update`),
// Prompt.m how its prompt keeps a draft through Ctrl+S, and Results.m how it words a command's result. The module's
// page part keeps the few facts it needs itself: each model's context window, in page/agent.js.
#import <Foundation/Foundation.h>

// Claude Code's own folder in the home folder, a path in it, and what Whozmove reads there.
extern NSString *const kClaudeCodeFolder;
NSString *ClaudeDir(NSString *sub);
extern NSString *const kClaudeCodeRegistry;      // one file per running session
extern NSString *const kClaudeCodeTranscripts;   // one folder per project, one transcript per session
extern NSString *const kClaudeCodeSettings;
// A project's own settings that stay on this Mac, in its kClaudeCodeFolder beside the shared kClaudeCodeSettings.
extern NSString *const kClaudeCodeLocalSettings;
// Settings an organisation sets for the whole machine.
extern NSString *const kClaudeCodeManagedSettings;
// Whether Claude Code records the lines a shell command changed in its checkout (a result's bashEditDiff) for a
// command run in `mode`: in auto and bypassPermissions modes unless the setting (kClaudeCodeShellDiffSetting, from the
// machine's settings, the project's or yours, `setting` being its value or nil) turns it off, and in any mode it turns
// on.
BOOL ClaudeRecordsShellChanges(NSString *mode, id setting);
extern NSString *const kClaudeCodeShellDiffSetting;
// How the result of a shell command that failed starts, which then records nothing of what the command changed.
extern NSString *const kClaudeCodeShellFailure;
// The folder beside a session's transcript where Claude Code keeps its sub-agents' records, one file each.
extern NSString *const kClaudeCodeSubagents;
// The marks Claude Code puts on the commands an agent runs, as environment variables, separated by spaces. A command
// you set off from the panel (Deploy, an extra stage's) is yours, so they're taken off it.
extern NSString *const kClaudeCodeAgentMarks;
// Claude Code's command. A new session takes the id it's given (--session-id <uuid>, checked with 2.1.300), which is
// how the panel knows its row before it's listed, and its first message as its last argument.
extern NSString *const kClaudeCodeCommand;
// Claude Code's state file in the home folder. Among much else, it records each folder you've trusted Claude to work
// in, as projects[<folder>].<kClaudeCodeTrustKey>: Claude Code and Claude Desktop both read and write it there, and
// both ask once before working in a folder that neither it, its repo nor any folder above it has. While either writes
// the file, it holds a lock: a folder beside it (kClaudeCodeStateLock), which only one can make, waited for up to 15s
// and taken as abandoned once it's 10s old. A project they add starts from ClaudeCodeProjectDefaults().
extern NSString *const kClaudeCodeState;
extern NSString *const kClaudeCodeStateLock;
extern NSString *const kClaudeCodeTrustKey;
NSDictionary *ClaudeCodeProjectDefaults(void);

// Claude Code's command, `claude`: where its installers put it (folders in the home folder, then elsewhere), and where
// Claude Desktop keeps copies of its own, one folder per version, then one per build, each with the command at
// kClaudeDesktopCommandInBuild. A Mac with only Claude Desktop has only those.
NSArray<NSString *> *ClaudeCommandFolders(void);
extern NSString *const kClaudeDesktopCommands;
extern NSString *const kClaudeDesktopCommandInBuild;
// Asking it for your plan's usage: run with ClaudeUsageArguments it answers requests sent to its input, a JSON line
// each, and nothing else starts (no hooks, plugins or MCP servers) or is saved. kClaudeUsageRequest is the request.
NSArray<NSString *> *ClaudeUsageArguments(void);
extern NSString *const kClaudeUsageRequest;
// Whether it's signed in (it prints JSON with loggedIn), and signing it in.
NSArray<NSString *> *ClaudeAuthStatusArguments(void);
NSArray<NSString *> *ClaudeSignInArguments(void);
// The environment variables that point it at an API key or another provider instead of a Claude plan.
NSArray<NSString *> *ClaudeOtherAuthVariables(void);


// The choices the details line offers, as [the value Claude Code takes, the name shown]. Models are the current
// family, by the id /model takes; efforts are Claude Code's levels; modes are in Claude's own order.
NSArray<NSArray<NSString *> *> *ModelChoices(void);
NSArray<NSArray<NSString *> *> *EffortChoices(void);
NSArray<NSArray<NSString *> *> *ModeChoices(void);
