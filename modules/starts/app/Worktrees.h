// Worktrees: a new conversation's folder in a repo: the repo's own, one of its worktrees, or a new worktree, for a
// branch that's there or a new branch made from one (by default the repo's base branch as this Mac has it), which it
// then follows. What a repo has, whether a worktree can be made, where a repo's worktrees go (a folder you chose, else
// where the agent puts its own), and making one, with git run as you run it. A branch is only ever checked out in a
// new folder: a folder that's in use never switches.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core;

@interface Worktrees : NSObject
// The core says which marks agents leave on commands, which git runs without.
- (instancetype)initWithCore:(Core *)core;
// A name as the card sends it, if a worktree can take it: letters, digits, dots, dashes and underscores, starting with
// a letter or a digit, at most 60 of them, and never ending in ".lock"; else nil.
+ (NSString *)nameFrom:(id)value;
// What the repo `folder` is in has, for the card's # list: {here: {path, where, branch}, the folder itself and the
// branch it's on; worktrees: [{branch, path, where}], the repo's other folders; branches: the ones checked out in no
// folder; base: the branch a new worktree starts from unless you say; folderPath and folder: where new worktrees go,
// and as the card shows it}, or {none, where} outside git. Blocking: call it off the main thread.
- (NSDictionary *)listIn:(NSString *)folder;
// One of the repo's folders (as listIn: has them), by its path, or nil: a session starts only in one of its worktrees.
- (NSString *)openPath:(id)path in:(NSString *)folder;
// Whether a worktree can be made for a target: {kind: new, name, base} (a new branch, from `base`, else the repo's
// base branch) or {kind: branch, name} (a branch that's there, with no folder yet). {path, where, name, base}, the
// folder it would go in (and as the card shows it, with ~ for the home folder), or {why}, as the card says it.
// Blocking, as above.
- (NSDictionary *)check:(NSDictionary *)target in:(NSString *)folder;
// The worktree made: {path, where, name, base}, or {why} if git refused or something's in the way. Blocking.
- (NSDictionary *)make:(NSDictionary *)target in:(NSString *)folder;
// Where a repo's worktrees go (the repo by its main checkout): the folder you chose for them, or nil for the one beside
// the repo, named after it (besideFolderFor:, ~/code/shop-worktrees for ~/code/shop); and choosing one, nil to go back
// to that. Kept in worktrees.json in Whozmove's folder, never in the repo. Beside it, not inside it: a worktree inside
// the repo's folder would show among its new files, where `git add -A` takes it in as a repository of its own, and
// tools that look through the folder would find every file twice.
- (NSString *)chosenFor:(NSString *)repo;
+ (NSString *)besideFolderFor:(NSString *)repo;
- (void)choose:(NSString *)folder for:(NSString *)repo;
// A path as the card and its menu show it, with ~ for the home folder.
+ (NSString *)shown:(NSString *)path;
@end
