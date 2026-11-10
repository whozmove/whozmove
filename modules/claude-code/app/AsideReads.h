// AsideReads: what a side question's copy may do, decided before each tool it reaches for by Whozmove's own checker
// (a helper run, --helper-aside-check, which the copy's hook runs): read only, in the session's own folder, and never a
// file where keys are kept; and git's status, log, diff and show, with only the options that read.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"

// `keys` is where keys are kept, as Keys knows it (KeyPlaces, the storage module's, which the core finds), so a file
// Keys knows holds keys is never read here; without it, nothing is.

// Why the copy may not use `tool` with `input` in the session's `folder`, in a line it reads and answers from, or nil
// when it may. `home` is the home folder, for the files where keys are kept. Only Read, Grep and Glob, for what's
// really inside the folder (links followed) but outside git's own folder, Read and Grep never a file git ignores in a
// checkout (`git check-ignore`), Grep with no file-name filter, and its matching lines only from one file (names and
// counts from a folder); and Bash for AsideGitWhyNot's git, only where the folder is the top of a checkout. A session
// started in the home folder, or above it, has a copy that reads nothing.
NSString *AsideToolWhyNot(NSString *tool, NSDictionary *input, NSString *folder, NSString *home, id<KeyPlaces> keys);
// Why a Bash command isn't one of the git commands the copy may run, or nil when it is: `git` with status, log, diff or
// show as its second word and no option before it; one command, each word plain (letters, digits and -_./:=@^~,+%{})
// or one whole single-quoted word; no word that names a path from the top of the disk, the home folder or above the
// folder, nor a file that holds keys by what it's called; options git only reads with (GitReadOnlyWhyNot: each one
// written in full, and log, diff and show with --no-ext-diff --no-textconv before any `--`); and, asked of git in the
// checkout at `folder`, no object named by its id that isn't a commit, and no patch of a file that holds keys.
NSString *AsideGitWhyNot(NSString *command, NSString *folder, id<KeyPlaces> keys);
// Whether a path, as given or as it really is, is one where keys are kept: Claude Code's own settings, state and
// sign-in files; every place in the home folder Keys knows (the credential files, ssh's and the cloud tools' folders,
// the shell's histories and settings, other AI tools' records); and, wherever it is and in any case, a file that holds
// keys by what it's called (any .env, the package tools' and git's credentials, ssh's private keys, certificates and
// key stores, MCP settings such as .mcp.json and .cursor/mcp.json, and the like).
BOOL AsideKeyFile(NSString *path, NSString *home, id<KeyPlaces> keys);
// The checker's answer to the hook's call, `input` (Claude Code's JSON: the tool and what it was given): nil when it may
// go ahead, else the line that refuses it, for the copy to read. Anything it can't read is refused.
NSString *AsideCheck(NSString *folder, NSData *input, NSString *home, id<KeyPlaces> keys);
// The checker's whole run (--helper-aside-check): the call read from its input, and AsideCheck's answer, 0 with nothing
// printed, so the copy's allow rules still apply after it, or 2 with the line on stderr; refused too when it can't read
// and decide within a few seconds, as the hook's own timeout would let the tool run.
int AsideCheckRun(NSString *folder, NSString *home, id<KeyPlaces> keys);
