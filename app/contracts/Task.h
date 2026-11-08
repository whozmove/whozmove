// Task: one thing a sender hands the user to do, in one shape whatever the project: its kind, its title (the same
// across its steps), the step it's at, why, what to do, what's attached. A session sends one with ask-panel.sh task.
// The One Task module keeps it, and the kind picks its buttons, so a sender never names them. A task is checked as it comes in
// (TaskFrom), and only a task that passes is kept: so whatever shows it can trust its words to be short, its ids plain,
// its links the web's and its command one line.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// What it asks, in the order the panel shows them: try a change, pick from a prototype, approve (a plan, a merge, a
// proposal), answer a question, run a command only the user can, do something by hand, and news with nothing to
// answer. A session's own request is never a task: the panel shows that from the session itself.
extern NSArray<NSString *> *const TaskKinds;
// Each kind's word, as what shows a kind names it ("Try"): the team board's marks and filters.
extern NSDictionary<NSString *, NSString *> *const TaskKindWords;

// The most each part may be, so one fits the view beside the list, and an ask (16 KB, base64) carries it whole.
extern const NSUInteger TaskMostTitle, TaskMostWhy, TaskMostLine, TaskMostItems;

// The task `json` as sent, checked: the task, or nil with why it can't be taken (`why`, in plain words a sender can act
// on). An id is letters, digits, '.', '_' or '-', 64 at most; text has no control or invisible characters, and each
// part is a line (why too, and all but a plan's glance); a command is one line; a link is the web's, over https only
// (only https:// leaves this Mac), and one that isn't is kept without it, so it shows without Open; a file is a full
// path, and an image a picture's file (.png, .jpg, .gif or .heic), which is shown only from inside the sending
// session's folder or its writings, its path resolved first; and nothing in it is shaped like a key, a token or a
// private key (LooksLikeSecret, shared/Text.h). A plan or proposal may be cut short to its points, a line each, or its
// phases, each a name and a line or three, or a plan to approve may carry its own short view as written (`glance`, its
// "At a glance" block, its lines kept); a try may say what changed and what to look for, a line each; and it may name
// the session it's about by its id (`about`). Unknown fields are left out, a priority among them: Whozmove orders tasks
// itself.
NSDictionary *TaskFrom(NSDictionary *json, NSString **why);

// Whether `value` is a task's id as TaskFrom takes one: letters, digits, '.', '_' or '-', 64 at most.
BOOL TaskIdPlain(id value);

// Whether `text` has a character that hides what it says: a control character (but a line break, where `lines`), or one
// that's invisible or turns the text round (Unicode's format characters, the tag characters among them, and the line
// and paragraph separators).
BOOL TaskTextHides(NSString *text, BOOL lines);
