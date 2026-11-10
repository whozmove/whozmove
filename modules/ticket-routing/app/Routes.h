// Routes: where a project's tickets open, as plain functions, so the tests check every case without the app. A
// project's way is kept by its main folder (ProjectRoot), and is one of: its own worktree for each ticket ({kind:
// own}), the project's own folder ({kind: folder}), or by one of its tickets' fields ({kind: field, tracker, site,
// field: {id, name}, folders: {option id: {name, folder}}}), each option's folder one of the project's own (its main
// folder or one of its worktrees), or none yet. Nothing here names a tracker or a field: they come from the tracker.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// What's kept, read back and checked: {project: {runs, at}}, each project only while it's still a repo's main
// checkout, its way only in one of the shapes above, and each of a field's folders only while it's still one of the
// project's own, or isn't there any more (kept, to be said as gone). What was let go is said in `dropped`, a line each, naming only the project, never a ticket or a folder.
NSDictionary *RoutesChecked(id json, NSMutableArray<NSString *> *dropped);
NSDictionary *RoutesRead(NSString *path, NSMutableArray<NSString *> *dropped);
// Kept where only you can read it (0600, in a folder only you can open). NO when it couldn't be written.
BOOL RoutesWrite(NSString *path, NSDictionary *routes);

// Whether a folder is one of the project's own: its main folder, or one of its worktrees, as their .git files say.
BOOL RouteFolderOfProject(NSString *project, NSString *folder);

// Where a ticket opens by its project's way, given the ticket's own values (Ticket's `values`, by field id), nil when
// they couldn't be read: {kind: own} (its own worktree), {kind: here} (the project's folder), or {kind: folder, folder}
// (one of its worktrees). By a field it's the option's folder, or, with `why`, its own worktree for now: `noValue`
// (the ticket has no option there), `noFolder` (the option has none yet), `gone` (its folder isn't one of the project's
// any more) or `unread`; with `value`, the option {id, name}, where it has one. No way yet is its own worktree.
NSDictionary *RoutePlace(NSString *project, NSDictionary *way, NSDictionary<NSString *, NSDictionary *> *values);

// Each of a field's options matched to one of the project's folders by name ({path: branch}, as CheckoutsInFiles has
// them): the option's name, ignoring case, spaces, dashes and underscores, the same as a folder's branch or its folder's
// name, or that name with the project's name and a dash before it (acme-shop-checkout). {option id: {name, folder}},
// the folder NSNull for one without.
NSDictionary *RouteMatch(NSString *project, NSArray<NSDictionary *> *options, NSDictionary<NSString *, NSString *> *checkouts);

// A way in a few words, as Settings and the guide name it ("Its own worktree", "In acme-shop itself", "By its Team
// field"), and where a new ticket goes by it, for before and after ("its own worktree", "acme-shop").
NSString *RouteWayName(NSString *project, NSDictionary *way);
NSString *RouteGoesTo(NSString *project, NSDictionary *way);
// What changing a project's way from `was` to `now` does, before you press Change: {before, after, warn, keep}: where
// a new ticket goes, then and after; a warning when after puts it where another ticket's conversation works (`busy`, the
// keys of the tickets the project's own conversations work in its own folder), or nil; and that the tickets started
// already keep their folders.
NSDictionary *RouteBeforeAfter(NSString *project, NSDictionary *was, NSDictionary *now, NSArray<NSString *> *busy);
