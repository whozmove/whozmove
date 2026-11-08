// Task: one thing a sender hands the user to do, checked as it comes in.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Task.h"
#import "Text.h"

NSArray<NSString *> *const TaskKinds = @[@"try", @"pick", @"approve", @"answer", @"run", @"do", @"seen"];
NSDictionary<NSString *, NSString *> *const TaskKindWords = @{@"try": @"Try", @"pick": @"Pick", @"approve": @"Approve",
                                                             @"answer": @"Answer", @"run": @"Run", @"do": @"Do",
                                                             @"seen": @"Seen"};
const NSUInteger TaskMostTitle = 80, TaskMostWhy = 160, TaskMostLine = 200, TaskMostItems = 6;
// A plan or proposal cut short: its points (a line each), or its phases (a name, and a line or few on what it does);
// and a try's one line on what changed and one on what to look for. Slim by rule, so a task never becomes a page.
static const NSUInteger kMostPoints = 12, kMostPoint = 90, kMostPhases = 8, kMostPhaseName = 40, kMostPhaseLines = 3,
                        kMostPhaseLine = 60;
static const NSUInteger kMostTryLine = 120, kMostImages = 4;
// A plan's own short view, as written: its "At a glance" block, in place of points or phases. About 120 words as the
// plan's skill asks, with room to spare; at most this, so the largest task, with it in place of phases, still fits
// one ask once its line breaks are written out.
static const NSUInteger kMostGlance = 2000;
// The longest command, file path and link. With the rest, a task of plain text stays inside what one ask may carry
// (16 KB, about 12 KB once base64-encoded).
static const NSUInteger kMostCommand = 400, kMostPath = 400, kMostLink = 400;

BOOL TaskTextHides(NSString *text, BOOL lines) {
    // Unicode's control and format characters (Cc and Cf: the zero-width ones, the marks that turn text round, the tag
    // characters), and the line and paragraph separators; a line break only where lines are wanted.
    static NSCharacterSet *hiding, *hidingButBreaks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSCharacterSet.controlCharacterSet mutableCopy];
        [set addCharactersInString:@"\u2028\u2029"];
        hiding = [set copy];
        [set removeCharactersInString:@"\n"];
        hidingButBreaks = [set copy];
    });
    return [text rangeOfCharacterFromSet:lines ? hidingButBreaks : hiding].location != NSNotFound;
}

// A plain id: letters, digits, '.', '_' or '-', from 1 to `most`.
static BOOL PlainId(id value, NSUInteger most) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *text = value;
    if (!text.length || text.length > most) return NO;
    NSCharacterSet *plain = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    return [text rangeOfCharacterFromSet:plain.invertedSet].location == NSNotFound;
}

BOOL TaskIdPlain(id value) {
    return PlainId(value, 64);
}

// Text that may be in a task: a string, not empty, at most `most`, hiding nothing. Sets `why` when it isn't, naming
// the field, and returns nil.
static NSString *Text(id value, NSString *field, NSUInteger most, BOOL lines, NSString **why) {
    NSString *text = [value isKindOfClass:NSString.class] ? [value stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] : nil;
    if (!text.length) *why = [NSString stringWithFormat:@"give it %@, as words", field];
    else if (text.length > most) *why = [NSString stringWithFormat:@"%@ may be %lu characters at most",
                                                                   field, (unsigned long)most];
    else if (TaskTextHides(text, lines))
        *why = [NSString stringWithFormat:@"%@ has a control or invisible character in it: send plain text", field];
    else return text;
    return nil;
}

// Text that may be left out: nil when it is, else as Text.
static NSString *MaybeText(id value, NSString *field, NSUInteger most, NSString **why) {
    if (!value || value == NSNull.null) return nil;
    return Text(value, field, most, NO, why);
}

// A whole number from `least` to `most`, or nil.
static NSNumber *Count(id value, NSInteger least, NSInteger most) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        return nil;
    double n = [value doubleValue];
    if (n != floor(n) || n < least || n > most) return nil;
    return @((NSInteger)n);
}

static BOOL Yes(id value) {
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

// A full path (from / or ~/), one line, at most kMostPath: as given, or nil.
static NSString *FullPath(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *path = value;
    if (!path.length || path.length > kMostPath || TaskTextHides(path, NO)) return nil;
    return [path hasPrefix:@"/"] || [path hasPrefix:@"~/"] ? path : nil;
}

// A link on the web, over https only (only https:// leaves this Mac), whole, or nil.
static NSString *WebLink(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *text = value;
    if (!text.length || text.length > kMostLink || TaskTextHides(text, NO)) return nil;
    NSURL *url = [NSURL URLWithString:text];
    NSString *scheme = url.scheme.lowercaseString;
    return url.host.length && [scheme isEqual:@"https"] ? text : nil;
}

// Whether anything in the task as sent is shaped like a key, a token or a private key (LooksLikeSecret): a task is shown
// on the panel and kept, so it never holds one.
static BOOL HoldsKey(id json) {
    NSData *data = [NSJSONSerialization isValidJSONObject:json]
        ? [NSJSONSerialization dataWithJSONObject:json options:0 error:nil] : nil;
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    return LooksLikeSecret(text);
}

static NSArray *Items(id value) {
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSDictionary *Record(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

// What to do, by tick: steps, each a line.
static NSArray *Todo(id value, NSString **why) {
    NSArray *items = Items(value);
    if (!items.count || items.count > TaskMostItems) {
        *why = [NSString stringWithFormat:@"todo is a list of 1 to %lu steps", (unsigned long)TaskMostItems];
        return nil;
    }
    NSMutableArray *todo = [NSMutableArray array];
    for (id item in items) {
        NSString *line = Text(item, @"each step in todo", TaskMostLine, NO, why);
        if (!line) return nil;
        [todo addObject:line];
    }
    return todo;
}

// A command only the user can run: one line, and where (a folder), if said.
static NSDictionary *Command(id value, NSString **why) {
    NSDictionary *given = Record(value);
    NSString *run = Text(given[@"run"], @"command.run", kMostCommand, NO, why);
    if (!run) return nil;
    NSMutableDictionary *command = [@{@"run": run} mutableCopy];
    if (given[@"where"]) {
        NSString *where = FullPath(given[@"where"]);
        if (!where) {
            *why = @"command.where is the folder to run it in, as a full path";
            return nil;
        }
        command[@"where"] = where;
    }
    return command;
}

// The choices to pick from: each an id, its words, a line more, and whether it's the one recommended.
static NSArray *Choices(id value, NSString **why) {
    NSArray *items = Items(value);
    if (items.count < 2 || items.count > TaskMostItems) {
        *why = [NSString stringWithFormat:@"choices is a list of 2 to %lu", (unsigned long)TaskMostItems];
        return nil;
    }
    NSMutableArray *choices = [NSMutableArray array];
    NSMutableSet *ids = [NSMutableSet set];
    for (id item in items) {
        NSDictionary *given = Record(item);
        if (!PlainId(given[@"id"], 16) || [ids containsObject:given[@"id"]]) {
            *why = @"each choice needs an id of its own: letters, digits, '.', '_' or '-', 16 at most";
            return nil;
        }
        [ids addObject:given[@"id"]];
        NSString *label = Text(given[@"label"], @"each choice's label", TaskMostLine, NO, why);
        if (!label) return nil;
        NSMutableDictionary *choice = [@{@"id": given[@"id"], @"label": label} mutableCopy];
        NSString *detail = MaybeText(given[@"detail"], @"a choice's detail", TaskMostLine, why);
        if (*why) return nil;
        if (detail) choice[@"detail"] = detail;
        if (Yes(given[@"recommended"])) choice[@"recommended"] = @YES;
        [choices addObject:choice];
    }
    return choices;
}

// A plan or proposal's points: 2 to 12, a line each.
static NSArray *Points(id value, NSString **why) {
    NSArray *items = Items(value);
    if (items.count < 2 || items.count > kMostPoints) {
        *why = [NSString stringWithFormat:@"points is a list of 2 to %lu lines", (unsigned long)kMostPoints];
        return nil;
    }
    NSMutableArray *points = [NSMutableArray array];
    for (id item in items) {
        NSString *line = Text(item, @"each point", kMostPoint, NO, why);
        if (!line) return nil;
        [points addObject:line];
    }
    return points;
}

// Its phases: 2 to 8, each {name, lines}, its name and 1 to 3 lines on what it does.
static NSArray *Phases(id value, NSString **why) {
    NSArray *items = Items(value);
    if (items.count < 2 || items.count > kMostPhases) {
        *why = [NSString stringWithFormat:@"phases is a list of 2 to %lu, each {name, lines}", (unsigned long)kMostPhases];
        return nil;
    }
    NSMutableArray *phases = [NSMutableArray array];
    for (id item in items) {
        NSDictionary *given = Record(item);
        NSString *name = Text(given[@"name"], @"each phase's name", kMostPhaseName, NO, why);
        if (!name) return nil;
        NSArray *lines = Items(given[@"lines"]);
        if (!lines.count || lines.count > kMostPhaseLines) {
            *why = [NSString stringWithFormat:@"each phase's lines are 1 to %lu", (unsigned long)kMostPhaseLines];
            return nil;
        }
        NSMutableArray *said = [NSMutableArray array];
        for (id line in lines) {
            NSString *text = Text(line, @"each line of a phase", kMostPhaseLine, NO, why);
            if (!text) return nil;
            [said addObject:text];
        }
        [phases addObject:@{@"name": name, @"lines": said}];
    }
    return phases;
}

// A picture a session took, by its file: a full path to a PNG, JPEG, GIF or HEIC. Only the app reads it, to show it,
// and only once its path is resolved (realpath, so a link or ".." can't lead out) and lies inside the sending session's
// folder or its writings, as a file attachment must: else a session could show any picture on this Mac, your own
// photos among them. The check here is only its shape.
static BOOL PicturePath(NSString *path) {
    return [@[@"png", @"jpg", @"jpeg", @"gif", @"heic"] containsObject:path.pathExtension.lowercaseString];
}

// What's attached: a prototype's page or a link (the web's only: one that isn't keeps its words, without the link), a
// file, the changes (lines added and removed), a commit.
static NSArray *Attached(id value, NSString **why) {
    NSArray *items = Items(value);
    if (!items || items.count > TaskMostItems) {
        *why = [NSString stringWithFormat:@"attach is a list of %lu at most", (unsigned long)TaskMostItems];
        return nil;
    }
    NSMutableArray *attached = [NSMutableArray array];
    NSUInteger images = 0;
    for (id item in items) {
        NSDictionary *given = Record(item);
        NSString *kind = given[@"kind"];
        if (![@[@"page", @"link", @"file", @"image", @"diff", @"commit"] containsObject:kind ?: @""]) {
            *why = @"each attachment's kind is page, link, file, image, diff or commit";
            return nil;
        }
        NSString *label = Text(given[@"label"], @"each attachment's label", TaskMostLine, NO, why);
        if (!label) return nil;
        NSMutableDictionary *one = [@{@"kind": kind, @"label": label} mutableCopy];
        if ([kind isEqual:@"page"] || [kind isEqual:@"link"]) {
            NSString *url = WebLink(given[@"url"]);
            if (url) one[@"url"] = url;
        } else if ([kind isEqual:@"file"]) {
            NSString *path = FullPath(given[@"path"]);
            if (path) one[@"path"] = path;
        } else if ([kind isEqual:@"image"]) {
            NSString *path = FullPath(given[@"path"]);
            if (!path || !PicturePath(path)) {
                *why = @"an image is a picture's file, as a full path: .png, .jpg, .gif or .heic";
                return nil;
            }
            if (++images > kMostImages) {
                *why = [NSString stringWithFormat:@"%lu images at most", (unsigned long)kMostImages];
                return nil;
            }
            one[@"path"] = path;
            // The choice it's the picture of, for designs side by side: one of the task's choices, checked once both
            // are in.
            if (given[@"choice"]) {
                if (!PlainId(given[@"choice"], 16)) {
                    *why = @"an image's choice is the id of one of the task's choices";
                    return nil;
                }
                one[@"choice"] = given[@"choice"];
            }
        } else if ([kind isEqual:@"diff"]) {
            NSNumber *added = Count(given[@"added"], 0, 10000000), *removed = Count(given[@"removed"], 0, 10000000);
            if (added) one[@"added"] = added;
            if (removed) one[@"removed"] = removed;
        }
        [attached addObject:one];
    }
    return attached;
}

NSDictionary *TaskFrom(NSDictionary *json, NSString **why) {
    __autoreleasing NSString *ignored = nil;
    if (!why) why = &ignored;
    *why = nil;
    if (![json isKindOfClass:NSDictionary.class]) {
        *why = @"send the task as one JSON object";
        return nil;
    }
    if (HoldsKey(json)) {
        *why = @"it holds something shaped like a key, token or password: never put one in a task, as the panel shows it";
        return nil;
    }
    if (!PlainId(json[@"id"], 64)) {
        *why = @"give it an id: letters, digits, '.', '_' or '-', 64 at most, the same for each of its steps";
        return nil;
    }
    NSString *kind = [json[@"kind"] isKindOfClass:NSString.class] ? json[@"kind"] : nil;
    if (![TaskKinds containsObject:kind ?: @""]) {
        *why = [@"its kind is one of " stringByAppendingString:[TaskKinds componentsJoinedByString:@", "]];
        return nil;
    }
    NSString *title = Text(json[@"title"], @"a title", TaskMostTitle, NO, why);
    if (!title) return nil;
    NSString *because = Text(json[@"why"], @"why", TaskMostWhy, NO, why);
    if (!because) return nil;
    NSMutableDictionary *task = [@{@"id": json[@"id"], @"kind": kind, @"title": title, @"why": because} mutableCopy];

    if (json[@"step"]) {
        NSDictionary *given = Record(json[@"step"]);
        NSNumber *n = Count(given[@"n"], 1, 20), *of = Count(given[@"of"], 1, 20);
        if (!n || !of || n.integerValue > of.integerValue) {
            *why = @"step is {n, of}: step n of `of`, from 1 to 20";
            return nil;
        }
        NSMutableDictionary *step = [@{@"n": n, @"of": of} mutableCopy];
        NSString *name = MaybeText(given[@"name"], @"step.name", TaskMostTitle, why);
        if (*why) return nil;
        if (name) step[@"name"] = name;
        task[@"step"] = step;
    }

    // What to do: a run, a pick and an answer each need their own.
    NSDictionary *needs = @{@"run": @"command", @"pick": @"choices", @"answer": @"choices"};
    if (needs[kind] && !json[needs[kind]]) {
        *why = [NSString stringWithFormat:@"a %@ needs its %@", kind, needs[kind]];
        return nil;
    }
    if (json[@"todo"] && (task[@"todo"] = Todo(json[@"todo"], why)) == nil) return nil;
    if (json[@"command"] && (task[@"command"] = Command(json[@"command"], why)) == nil) return nil;
    if (json[@"choices"] && (task[@"choices"] = Choices(json[@"choices"], why)) == nil) return nil;
    // A pick's choices are its looks, each named by a letter, as two are mixed ("A+C"): words for a choice (yes, no)
    // make it a question.
    if ([kind isEqual:@"pick"])
        for (NSDictionary *choice in task[@"choices"] ?: @[])
            if (![choice[@"id"] rangeOfString:@"^[A-Z]$" options:NSRegularExpressionSearch].length) {
                *why = [NSString stringWithFormat:@"a pick's choices are named by a letter, A to Z, as its looks are: "
                                                  "%@ isn't one. For a question with words for its choices, such as "
                                                  "yes or no, send it as an answer", choice[@"id"]];
                return nil;
            }
    if (json[@"attach"] && (task[@"attach"] = Attached(json[@"attach"], why)) == nil) return nil;
    // A plan cut short: its points, or its phases, never both; and a try's line on what changed, and what to look for.
    NSMutableSet *choiceIds = [NSMutableSet set];
    for (NSDictionary *choice in task[@"choices"] ?: @[]) [choiceIds addObject:choice[@"id"]];
    for (NSDictionary *one in task[@"attach"] ?: @[])
        if (one[@"choice"] && ![choiceIds containsObject:one[@"choice"]]) {
            *why = [NSString stringWithFormat:@"an image's choice, %@, isn't one of the task's choices", one[@"choice"]];
            return nil;
        }
    if (json[@"points"] && json[@"phases"]) {
        *why = @"give it points or phases, not both";
        return nil;
    }
    if (json[@"points"] && (task[@"points"] = Points(json[@"points"], why)) == nil) return nil;
    if (json[@"phases"] && (task[@"phases"] = Phases(json[@"phases"], why)) == nil) return nil;
    // Or, for a plan to approve, its own short view, which says what its points or phases would, so never with them.
    if (json[@"glance"]) {
        if (![kind isEqual:@"approve"]) {
            *why = @"only an approve takes a glance: the At a glance block of the plan it asks you to approve";
            return nil;
        }
        if (json[@"points"] || json[@"phases"]) {
            *why = @"give it a glance, or points or phases, not both";
            return nil;
        }
        // As a block is often read from a file: its Windows line endings as line breaks, and its tabs as the four
        // spaces a Markdown list reads them as, so neither is refused as a hidden character.
        id given = json[@"glance"];
        if ([given isKindOfClass:NSString.class])
            given = [[given stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                     stringByReplacingOccurrencesOfString:@"\t" withString:@"    "];
        if ((task[@"glance"] = Text(given, @"glance", kMostGlance, YES, why)) == nil) return nil;
    }
    for (NSString *field in @[@"changed", @"lookFor"]) {
        NSString *line = MaybeText(json[field], field, kMostTryLine, why);
        if (*why) return nil;
        if (line) task[field] = line;
    }
    if ([kind isEqual:@"answer"] && Yes(json[@"several"])) task[@"several"] = @YES;
    if (Yes(json[@"inTab"])) task[@"inTab"] = @YES;
    // The session it's about, by its id alone: One Task takes you there only from a team's lead, to one of its team.
    if (json[@"about"]) {
        if (!PlainId(json[@"about"], 64)) {
            *why = @"name the session it's about by its id: letters, digits, '.', '_' or '-', 64 at most";
            return nil;
        }
        task[@"about"] = json[@"about"];
    }
    return task;
}
