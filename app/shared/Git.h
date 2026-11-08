// Git: a checkout's branch, worktree, status, its base branch (GitHub's and this Mac's), its new files, when its last
// commit was made, the branches GitHub's copy of its repo has, and running git itself.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSDictionary *RunGit(NSArray<NSString *> *arguments);
NSDictionary *GitInfo(NSString *cwd);
// The project a folder is in: its repo's main checkout, for a worktree too, as its .git says; nil outside a repo.
NSString *ProjectRoot(NSString *folder);
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
