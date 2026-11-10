// ProcessNotes: the plain functions of a project's note: the project a session's folder is in, its short name, its own
// pages, a draft checked, what changed against the note as kept, whether a draft after Not Now holds anything new,
// the row's card, the way handed to a session, and the record kept and read back. ProcessNotesModule.m is its face for
// the core; nothing here asks anything of the app.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The most a draft may be: characters in all, lines, and characters in a line.
extern const NSUInteger kProcessMostCharacters, kProcessMostLines, kProcessMostInLine;

// A session's draft waiting on its row: its project (the folder) and that project's short name, its lines, when it
// was asked (ms since 1970, which the card's press names), whether Keep It is writing it now, and why it couldn't be
// kept, if it couldn't.
@interface ProcessDraft : NSObject
@property (copy) NSString *project, *name, *problem;
@property (copy) NSArray<NSString *> *lines;
@property (assign) double at;
@property (assign) BOOL keeping;
@end

// The project a session's folder is in: its repo's main checkout, for a worktree too, as its row's `git` says (read
// from its .git without running git); its folder itself outside git. Nil for none.
NSString *ProcessProject(NSDictionary *git, NSString *cwd);
// Its short name: the folder's own name.
NSString *ProcessProjectName(NSString *project);
// The session's own checkout, where its pages are looked for: its row's `git` root, else its folder.
NSString *ProcessCheckout(NSDictionary *git, NSString *cwd);
// The project's own pages on how work is done there, found by name in the checkout: CONTRIBUTING.md, the files that
// hold the session's agent's instructions (`instructions`, as the agent names them: Agent's instructionPages),
// .github/pull_request_template.md, and docs/ pages on contributing, reviewing or releasing (in docs/ or a folder
// inside it), as paths inside the checkout. Only a plain file whose real path is inside the checkout is listed, so a
// link to a file elsewhere on the Mac never is.
NSArray<NSString *> *ProcessPages(NSString *checkout, NSArray<NSString *> *instructions);

// A draft as the session sent it, checked: its lines, each trimmed, blank ones left out, a list's own mark at a line's
// start ("- ", "1. ") taken off, as the card numbers them; or nil, with why in `why`: nothing in it, too long in all,
// too many lines, a line too long, a character that isn't plain text, or a line holding something shaped like a key
// or a token: a provider's own shapes (LooksLikeSecret), a password or key's name set to what looks like one, a
// password in a link, a signed token (a JWT), Atlassian's API tokens, or AWS's secret.
NSArray<NSString *> *ProcessDraftLines(NSString *text, NSString **why);
// What changed between the note as kept and a draft, in the draft's order, with each line taken out where it was:
// [{text, mark}], `mark` `added` or `removed`, none for a line in both.
NSArray<NSDictionary *> *ProcessChanges(NSArray<NSString *> *kept, NSArray<NSString *> *draft);
// Whether a draft changes the note as kept (`kept`, nil for none) in a way the one you said Not Now to didn't, so it
// may ask you again: a line neither of them has, or a kept line taken out that the declined one kept.
BOOL ProcessHoldsNew(NSArray<NSString *> *draft, NSArray<NSString *> *declined, NSArray<NSString *> *kept);

// The row's `processDraft` for a draft waiting: {at, project, lines, keptAt, declinedAt, keeping, problem}, its lines
// marked against the note as kept (`kept`, nil for none) as ProcessChanges marks them, so Keep It changes exactly what
// the card shows; `keptAt` (ms) when there is a note, `declinedAt` (ms) when you said Not Now to the project's last
// and this one holds something new (ProcessHoldsNew).
NSDictionary *ProcessDraftShown(ProcessDraft *draft, NSArray<NSString *> *kept, double keptAt, double declinedAt);
// What a session is handed of its project's way (ProjectWay's wayFor:): {project, pages, note, keptAt, draft}.
NSDictionary *ProcessWay(NSString *name, NSArray<NSString *> *pages, NSArray<NSString *> *kept, double keptAt,
                         NSString *draft);

// The file a project's note is kept in, in Whozmove's folder: a hash of its folder, as one name that holds nothing of
// the path.
NSString *ProcessRecordName(NSString *project);
// The record kept by Keep It, {project, note, keptAt}, and the note's lines read back, for that project only (nil for
// a record that isn't one, or is another project's), with when it was kept. Each line read back is checked again, as
// a draft is: one that holds a key or isn't plain text is left out.
NSDictionary *ProcessRecord(NSString *project, NSArray<NSString *> *lines, double keptAt);
NSArray<NSString *> *ProcessKeptLines(NSDictionary *record, NSString *project, double *keptAt);
