// Git: a checkout's branch, worktree, status, its base branch (GitHub's and this Mac's), its new files, when its last
// commit was made, the branches GitHub's copy of its repo has, running git itself, and which git only reads.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSDictionary *RunGit(NSArray<NSString *> *arguments);
// Git run on someone else's behalf, only to read: what git does that a reader wouldn't expect, checked with git 2.50.1.
// `git diff --output=<file>` writes that file; an external diff, a text conversion, a signature check (log's
// --show-signature, a format's %G) or a pager runs another program; outside a checkout `git diff <a> <b>` compares any
// two files, as --no-index does; from a folder inside a checkout git reads the whole checkout above it; a partial
// clone fetches what it lacks from its remote unless protocol.allow is never; and a plain `git status` writes the
// index under its lock.
// The commands that only read: status, log, diff and show.
NSArray<NSString *> *GitReadOnlyCommands(void);
// The options one of them needs before any `--` to only read: --no-ext-diff --no-textconv for log, diff and show, and
// none for status.
NSArray<NSString *> *GitReadOnlyNeeds(NSString *command);
// Why `arguments` (a command, then its words, as given after `git`) isn't one that only reads, or nil when it is: one
// of GitReadOnlyCommands; each option before any `--` one that only reads, written in full, or one with a value (a
// count, a time, a name to look for, a diff's context, or a format that never asks for a signature); and log, diff and
// show with --no-ext-diff --no-textconv before any `--`. Which paths it names is the caller's to check.
NSString *GitReadOnlyWhyNot(NSArray<NSString *> *arguments);
// `base` with git's settings for those commands, carried in the environment so no command is rewritten: no hooks,
// pager, external diff, signature check, file system monitor or going online, no prompt, no index written, and each
// pathspec the file it names, never a pattern.
NSDictionary<NSString *, NSString *> *GitReadOnlyEnvironment(NSDictionary<NSString *, NSString *> *base);
// The same settings as git's own options, before the command, for git run to ask about one of those commands.
NSArray<NSString *> *GitReadOnlyArguments(void);
// The first word of `arguments` (as GitReadOnlyWhyNot takes them) before any `--` that names an object that isn't a
// commit (a file's contents or a folder, by its id, or a tag of one; a folder at a commit, HEAD: or HEAD:src), which
// git would print whole, asked of git in `folder`; a word or range end that names no object is a path, and a file at
// a commit (HEAD:src/app.js) is named in its word. Nil when there's none; the word too when git can't say.
NSString *GitReadOnlyNotCommit(NSArray<NSString *> *arguments, NSString *folder);
// The files whose contents `arguments` would print in a patch (diff and show unless only names, counts or ids are
// asked for, log only when a patch is), asked of git in `folder` for the same commits and paths, renames as the file
// removed and the one added: empty when it prints none, nil when git can't say. A file at a commit (HEAD:src/app.js)
// that show prints isn't among them: it's named in its word; diff and log are asked about the very words given.
NSArray<NSString *> *GitReadOnlyShownFiles(NSArray<NSString *> *arguments, NSString *folder);
// The start of a git command that only reads `root`: without optional locks, so it writes nothing there (a plain `git
// status` refreshes the index), and without the program a repo's settings may name to watch its files (core.fsmonitor),
// which would run at every read and write files of its own there, each read then counting as a change (CheckoutWatch).
NSArray<NSString *> *GitReading(NSString *root);
NSDictionary *GitInfo(NSString *cwd);
// The project a folder is in: its repo's main checkout, for a worktree too, as its .git says; nil outside a repo.
NSString *ProjectRoot(NSString *folder);
// The folders a repo's branches are checked out in, the main checkout and each linked worktree that's still there, as
// {real path: branch} (one on no branch, detached, left out), from `repo`'s git folder: its worktrees' records and each
// one's HEAD, read straight from the files, without running git. Empty outside a repo.
NSDictionary<NSString *, NSString *> *CheckoutsInFiles(NSString *repo);
NSDictionary *FetchCheckoutState(NSString *root, NSString *remoteNames);
NSDictionary *FetchChangeCounts(NSString *root, NSArray<NSString *> *baseBranch);
// The names of a checkout's remotes, a line each, as `git remote` prints them, or nil when git can't say. Blocking.
NSString *RemoteNames(NSString *root);
// A checkout's base branch: the one GitHub's copy points at (origin/HEAD), else main or master, as [name, ref], the ref
// GitHub's copy of it if there is one, else the local one; empty with none, and nil when git couldn't say. Blocking.
NSArray<NSString *> *BaseBranch(NSString *root);
NSArray<NSString *> *RemoteBranches(NSString *root);
// A checkout's own git folder (its .git, or the folder a linked worktree's .git file names) in `own`, and the one with
// its repo's refs, packed-refs and config in `common`, which a linked worktree shares with its main checkout; NO when
// `root` has no .git of its own. Read straight from the files, without running git.
BOOL GitFolders(NSString *root, NSString **own, NSString **common);
// The repo's base branch as BaseBranch finds it, read from its shared git folder (`common`, GitFolders') without
// running git: its name, with `local` YES when it's the local branch (no copy of it on origin) and NO when it's
// origin's copy; nil with none.
NSString *BaseBranchInFiles(NSString *common, BOOL *local);
// Whether a branch is on one of the repo's remotes, as this Mac last fetched them (refs/remotes/<remote>/<branch>,
// loose or packed), so it can have a pull request; YES when the repo can't be read. Without running git.
BOOL BranchOnRemote(NSString *root, NSString *branch);
NSString *LocalBaseBranch(NSString *root);
