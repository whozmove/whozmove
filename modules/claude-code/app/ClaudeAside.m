// ClaudeAside: questions asked on the side of Claude Code's sessions, one kept copy of each session's conversation.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeAside.h"
#import <signal.h>
#import "Files.h"
#import "Git.h"
#import "Log.h"
#import "Processes.h"
#import "Text.h"
#import "ClaudeCodeFacts.h"
#import "ClaudeCommand.h"
#import "ClaudeSessions.h"
#import "ClaudeUsage.h"

// How long a side question has to answer, the most of its answer that's kept, how long a copy waits to be asked
// again, and how much of the earlier side questions a fresh copy is told (in characters, about four thousand words).
static const NSTimeInterval kAsideDeadline = 300;
static const NSUInteger kAsideMost = 16384;
static const NSTimeInterval kAsideKept = 300;
static const NSUInteger kAsideCarriedMost = 24000;

static NSString *Cut(NSString *text) {
    if (text.length <= kAsideMost) return text;
    return [text substringToIndex:[text rangeOfComposedCharacterSequenceAtIndex:kAsideMost].location];
}

NSDictionary *ClaudeAsideAnswer(NSArray<NSData *> *lines, BOOL timedOut, BOOL stopped) {
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    NSDictionary *result = nil;
    BOOL reached = NO;
    double resetsAt = 0;
    for (NSData *line in lines) {
        NSDictionary *message = AsRecord([NSJSONSerialization JSONObjectWithData:line options:0 error:nil]);
        NSString *type = AsText(message[@"type"]);
        if ([type isEqual:@"assistant"]) {
            for (id each in AsList(AsRecord(message[@"message"])[@"content"])) {
                NSDictionary *block = AsRecord(each);
                if ([block[@"type"] isEqual:@"tool_use"]) reached = YES;
                else if ([block[@"type"] isEqual:@"text"] && AsText(block[@"text"]).length) [said addObject:block[@"text"]];
            }
        } else if ([type isEqual:@"rate_limit_event"]) {
            // Seconds since 1970, as Claude Code passes on Anthropic's own.
            double at = AsNumber(AsRecord(message[@"rate_limit_info"])[@"resetsAt"]).doubleValue;
            if (at > 0) resetsAt = at * 1000;
        } else if ([type isEqual:@"result"]) {
            result = message;
        }
    }
    NSMutableDictionary *answer = [NSMutableDictionary dictionary];
    NSDictionary *usage = AsRecord(result[@"usage"]);
    NSDictionary *counts = @{@"cacheRead": @"cache_read_input_tokens", @"fresh": @"input_tokens",
                             @"written": @"cache_creation_input_tokens", @"output": @"output_tokens"};
    [counts enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *field, BOOL *stop) {
        if (AsNumber(usage[field])) answer[key] = usage[field];
    }];
    if (AsNumber(result[@"api_error_status"])) answer[@"status"] = result[@"api_error_status"];
    NSString *subtype = AsText(result[@"subtype"]), *words = AsText(result[@"result"]);
    // An error Claude Code passes on, by the words it uses for each (checked with 2.1.304).
    NSString *error = [[NSString stringWithFormat:@"%@ %@", words ?: @"", AsText(result[@"api_error_status"]) ?: @""]
                       lowercaseString];
    if (stopped) answer[@"state"] = @"stopped";
    else if (!result) answer[@"state"] = timedOut ? @"tooSlow" : @"noAnswer";
    else if ([subtype isEqual:@"error_max_turns"]) answer[@"state"] = reached ? @"wantedTool" : @"noAnswer";
    else if (![result[@"is_error"] isEqual:@YES] && [subtype isEqual:@"success"]) {
        NSString *text = words.length ? words : [said componentsJoinedByString:@"\n\n"];
        answer[@"state"] = text.length ? @"answered" : @"noAnswer";
        if (text.length) answer[@"text"] = Cut(text);
    } else if ([error containsString:@"too long"] || [error containsString:@"context limit"]
               || [error containsString:@"context window"]) {
        // Before the plan's limit: a conversation too long for its model says "limit" too.
        answer[@"state"] = @"tooLong";
    } else if ([error containsString:@"401"] || [error containsString:@"/login"] || [error containsString:@"log in"]
               || [error containsString:@"authentication"]) {
        answer[@"state"] = @"signedOut";
    } else if ([error containsString:@"limit"] || [error containsString:@"429"]) {
        // "You've hit your limit", or Anthropic's own words passed on as they are.
        answer[@"state"] = @"limit";
        if (resetsAt > 0) answer[@"resetsAt"] = @(resetsAt);
    } else if (answer[@"status"] || [error hasPrefix:@"api error"]) {
        // Any other error the API sent back ("API Error: 400 …"): said as one, not as no answer.
        answer[@"state"] = @"apiError";
    } else {
        answer[@"state"] = @"noAnswer";
    }
    return answer;
}

static NSString *const kThinking = @"Thinking";

// Words for the step's line: on one line, with nothing hidden in them, and past `most` characters cut there with "…"
// after, as the session's own hook cuts its steps (`shorten` in whozmove-claude.py; its test holds them alike).
static NSString *Shortened(NSString *text, NSUInteger most) {
    NSString *plain = PlainOneLine(text, 4096);
    NSString *one = [plain stringByReplacingOccurrencesOfString:@"\\s+" withString:@" "
                                                        options:NSRegularExpressionSearch
                                                          range:NSMakeRange(0, plain.length)];
    if (one.length <= most) return one;
    NSString *kept = [one substringToIndex:[one rangeOfComposedCharacterSequenceAtIndex:most].location];
    return [[kept stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] stringByAppendingString:@"…"];
}

// Whether a file a tool was given is in the session's folder, by where it really is: so the line names only a file
// the session's own folder holds.
static BOOL InFolder(NSString *path, NSString *folder) {
    if (!path.length || !folder.length || [path hasPrefix:@"~"]) return NO;
    NSString *full = path.isAbsolutePath ? path : [folder stringByAppendingPathComponent:path];
    // A file that isn't there is where its folder really is.
    NSString *real = [NSFileManager.defaultManager fileExistsAtPath:full] ? RealPath(full)
        : [RealPath(full.stringByDeletingLastPathComponent) stringByAppendingPathComponent:full.lastPathComponent]
              .stringByStandardizingPath;
    return [real hasPrefix:[RealPath(folder) stringByAppendingString:@"/"]];
}

// A line of its thinking's summary for the step's line: the first, without its markdown, unless it names a path or
// holds something shaped like a key, when it's just "Thinking".
static NSString *Thought(NSString *summary) {
    for (NSString *line in [summary ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *plain = [line stringByTrimmingCharactersInSet:
                               [NSCharacterSet characterSetWithCharactersInString:@"*_`#> \t"]];
        plain = [plain stringByReplacingOccurrencesOfString:@"[*_`]" withString:@""
                                                    options:NSRegularExpressionSearch range:NSMakeRange(0, plain.length)];
        if (!plain.length) continue;
        if ([plain rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/~"]].location
                != NSNotFound || LooksLikeSecret(plain))
            return kThinking;
        return Shortened(plain, 80);
    }
    return kThinking;
}

// A tool it calls, in words, as the session's own hook says its steps: only a file's name, only for a file in the
// session's folder; a search's words, or a pattern, only when it names no path; git's own command, never what Claude
// wrote of it. Anything shaped like a key gives the step's words without it.
static NSString *ToolStep(NSString *tool, NSDictionary *input, NSString *folder) {
    NSCharacterSet *path = [NSCharacterSet characterSetWithCharactersInString:@"/~"];
    NSString *(^clean)(NSString *, NSString *) = ^NSString *(NSString *words, NSString *plain) {
        return words.length && !LooksLikeSecret(words) ? words : plain;
    };
    if ([tool isEqual:kClaudeToolRead]) {
        NSString *file = AsText(input[kClaudeToolFilePath]);
        return InFolder(file, folder) ? clean([@"Reading " stringByAppendingString:PlainOneLine(file.lastPathComponent,
                                                                                                 4096)],
                                              @"Reading a file")
                                      : @"Reading a file";
    }
    if ([tool isEqual:kClaudeToolGrep]) {
        NSString *pattern = AsText(input[kClaudeToolPattern]);
        if (!pattern.length || [pattern rangeOfCharacterFromSet:path].location != NSNotFound) return @"Searching";
        return clean([NSString stringWithFormat:@"Searching for “%@”", Shortened(pattern, 30)], @"Searching");
    }
    if ([tool isEqual:kClaudeToolGlob]) {
        NSString *pattern = AsText(input[kClaudeToolPattern]);
        if (!pattern.length || [pattern hasPrefix:@"/"] || [pattern hasPrefix:@"~"] || [pattern containsString:@".."])
            return @"Finding files";
        return clean([@"Finding files " stringByAppendingString:Shortened(pattern, 30)], @"Finding files");
    }
    if ([tool isEqual:kClaudeToolBash]) {
        NSArray *words = [[AsText(input[kClaudeToolCommand]) ?: @"" componentsSeparatedByCharactersInSet:
                               NSCharacterSet.whitespaceAndNewlineCharacterSet]
                          filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (![words.firstObject isEqual:@"git"]) return @"Running a command";
        return words.count > 1 && [GitReadOnlyCommands() containsObject:words[1]]
            ? [@"Running git " stringByAppendingString:words[1]] : @"Running git";
    }
    return @"Working";
}

NSString *ClaudeAsideStep(NSDictionary *line, NSString *folder) {
    if (![AsText(line[@"type"]) isEqual:@"assistant"]) return nil;
    NSString *step = nil;
    for (id each in AsList(AsRecord(line[@"message"])[@"content"])) {
        NSDictionary *block = AsRecord(each);
        NSString *type = AsText(block[@"type"]);
        if ([type isEqual:@"thinking"]) step = Thought(AsText(block[@"thinking"]));
        else if ([type isEqual:@"redacted_thinking"]) step = kThinking;
        else if ([type isEqual:@"tool_use"]) step = ToolStep(AsText(block[@"name"]), AsRecord(block[@"input"]), folder);
    }
    return step;
}

BOOL ClaudeAsideThinks(NSString *version, NSSet<NSString *> *refused) {
    return version.length && [ClaudeAsideThinkingVersions() containsObject:version] && ![refused containsObject:version];
}

BOOL ClaudeAsideFlagRefused(NSDictionary *ran, BOOL heard, BOOL stopped) {
    return ran && !heard && !stopped && ![ran[@"timedOut"] boolValue] && [ran[@"status"] integerValue] != 0;
}

NSString *ClaudeAsideModel(NSString *model, NSString *flagModel, NSInteger tokens) {
    if (!model.length) return flagModel.length ? flagModel : nil;
    if ([model containsString:@"["]) return model;
    NSString *flagCanonical = [flagModel componentsSeparatedByString:@"["].firstObject;
    // Over 200k, the long context, but never for a model whose own window is already the long one (ClaudeContextWindow):
    // a "[1m]" on its name makes Claude Code send a beta flag the session's own requests never do.
    BOOL longOne = ([flagModel containsString:@"[1m]"] && [flagCanonical isEqual:model])
        || (tokens > 200000 && ClaudeContextWindow(model, 0) < 1000000);
    return longOne ? [model stringByAppendingString:@"[1m]"] : model;
}

NSString *ClaudeAsideProgram(NSString *running, NSArray<NSString *> *candidates) {
    NSString *real = running.length ? RealPath(running) : nil;
    for (NSString *candidate in candidates)
        if (real && [RealPath(candidate) isEqual:real]) return candidate;
    return candidates.firstObject;
}
BOOL ClaudeAsideMoved(NSDictionary *opened, NSDictionary *now) {
    NSNumber *size = AsNumber(opened[@"size"]), *at = AsNumber(opened[@"at"]);
    if (!size || !at) return YES;
    return ![size isEqual:AsNumber(now[@"size"])] || ![at isEqual:AsNumber(now[@"at"])];
}

NSArray<NSDictionary *> *ClaudeAsideCarried(NSArray<NSDictionary *> *earlier, double compactedAt) {
    NSMutableArray<NSDictionary *> *carried = [NSMutableArray array];
    NSUInteger total = 0;
    for (NSDictionary *each in earlier.reverseObjectEnumerator) {
        NSString *question = AsText(each[@"question"]), *text = AsText(each[@"text"]);
        if (!question.length || !text.length || AsNumber(each[@"at"]).doubleValue <= compactedAt) break;
        total += question.length + text.length;
        if (total > kAsideCarriedMost) break;
        [carried insertObject:each atIndex:0];
    }
    return carried;
}

NSString *ClaudeAsideWords(NSString *question, NSArray<NSDictionary *> *carried, BOOL fresh) {
    NSMutableString *words = [NSMutableString stringWithString:ClaudeAsideLine()];
    if (fresh && carried.count) {
        [words appendString:@"\n\nEarlier, on the side, the user asked you these, and you answered:"];
        for (NSDictionary *each in carried)
            [words appendFormat:@"\n\nQuestion: %@\n\nYour answer: %@", each[@"question"], each[@"text"]];
        [words appendString:@"\n\nNow they ask:"];
    }
    [words appendFormat:@"\n\n%@", question];
    return words;
}

NSDictionary<NSString *, NSString *> *ClaudeAsideEnvironment(NSDictionary<NSString *, NSString *> *base,
                                                             NSString *checker, NSString *folder) {
    NSMutableDictionary *environment = [GitReadOnlyEnvironment(base) mutableCopy];
    environment[kClaudeAsideCheckVariable] = checker ?: @"";
    environment[kClaudeAsideFolderVariable] = folder ?: @"";
    return environment;
}

BOOL ClaudeAsideReuses(NSDictionary *opened, NSDictionary *now) {
    long long started = [opened[@"started"] longLongValue];
    return ![opened[@"busy"] boolValue] && started > 0 && [now[@"started"] longLongValue] == started
        && [opened[@"model"] ?: @"" isEqual:now[@"model"] ?: @""]
        && [opened[@"effort"] ?: @"" isEqual:now[@"effort"] ?: @""]
        && !ClaudeAsideMoved(opened[@"mark"], now[@"mark"]);
}

// A session's copy: its process once started (told apart from a later one given the same pid by its start), the
// model and effort it was started with, the session's transcript as it opened, and the ask it's answering now (nil
// while it waits to be asked again), with what it has said so far for it, the step it last told, and whether its
// process has written anything at all. All but `wake` under the copies' lock.
@interface AsideCopy : NSObject
@property (copy) NSString *sessionId, *model, *effort, *program;
@property (strong) NSDictionary *opened;
@property (assign) double openedAt;
@property (assign) pid_t pid;
@property (assign) long long started;
@property (assign) BOOL ending, stopped, heard;
@property (assign) NSUInteger known;  // the earlier side questions it knows: told as it opened, and answered in it
@property (copy) NSString *askId;
@property (copy) void (^done)(NSDictionary *answer);
@property (copy) void (^step)(NSString *step);
@property (copy) NSString *told;
@property (strong) NSData *pending;
@property (strong) NSMutableArray<NSData *> *lines;
@property (assign) NSUInteger kept;
@property (strong) dispatch_semaphore_t wake;
@end

@implementation AsideCopy
@end

@interface ClaudeAside ()
@property (copy) NSString *checker, *program;
@property (strong) NSMutableDictionary<NSString *, AsideCopy *> *copies;  // by session id; under its own lock
// The versions of Claude Code that turned the thinking summaries' flag down while Whozmove runs; under its own lock.
@property (strong) NSMutableSet<NSString *> *refused;
@end

@implementation ClaudeAside

- (instancetype)initWithChecker:(NSString *)checker program:(NSString *)program {
    if (!(self = [super init])) return nil;
    self.checker = checker;
    self.program = program;
    self.copies = [NSMutableDictionary dictionary];
    self.refused = [NSMutableSet set];
    return self;
}

// Its process and everything it started, ended, only while it's still the one this copy started.
static void EndCopy(AsideCopy *copy) {
    if (copy.pid > 0 && copy.started && ProcessStartedAt(copy.pid) == copy.started) killpg(copy.pid, SIGTERM);
}

static NSData *LineOf(NSString *words) {
    NSDictionary *line = @{@"type": @"user", @"message": @{@"role": @"user", @"content": words}};
    NSMutableData *send = [[NSJSONSerialization dataWithJSONObject:line options:0 error:nil] mutableCopy];
    [send appendBytes:"\n" length:1];
    return send;
}

// The answer to the ask a copy is giving, told once, on the main thread, with how many earlier questions it knew;
// and the copy ready for the next. Under the copies' lock.
static void Tell(AsideCopy *copy, NSDictionary *given) {
    void (^done)(NSDictionary *) = copy.done;
    NSMutableDictionary *answer = [given mutableCopy];
    answer[@"remembered"] = @(copy.known);
    if ([answer[@"state"] isEqual:@"signedOut"] && copy.program) answer[@"signIn"] = ClaudeSignInCommand(copy.program);
    if ([answer[@"state"] isEqual:@"answered"]) copy.known += 1;
    copy.askId = nil;
    copy.done = nil;
    copy.step = nil;
    copy.told = nil;
    copy.lines = [NSMutableArray array];
    copy.kept = 0;
    if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(answer); });
}

- (NSString *)ask:(NSString *)question earlier:(NSArray<NSDictionary *> *)earlier running:(NSString *)running
        sessionId:(NSString *)sessionId model:(NSString *)model effort:(NSString *)effort folder:(NSString *)folder
             mark:(NSDictionary *)mark step:(void (^)(NSString *step))step
             done:(void (^)(NSDictionary *answer))done {
    NSArray *arguments = ClaudeAsideArguments(sessionId, model, effort, DeveloperToolsReady());
    if (!arguments) return nil;
    NSString *askId = NSUUID.UUID.UUIDString;
    AsideCopy *fresh = nil;
    @synchronized (self.copies) {
        AsideCopy *open = self.copies[sessionId];
        if (open && ClaudeAsideReuses(@{@"busy": @(open.ending || open.askId), @"started": @(open.started),
                                        @"model": open.model ?: @"", @"effort": open.effort ?: @"",
                                        @"mark": open.opened ?: @{}},
                                      @{@"started": @(open.pid > 0 ? ProcessStartedAt(open.pid) : 0),
                                        @"model": model ?: @"", @"effort": effort ?: @"", @"mark": mark ?: @{}})) {
            open.askId = askId;
            open.done = done;
            open.step = step;
            open.pending = LineOf(ClaudeAsideWords(question, nil, NO));
            dispatch_semaphore_signal(open.wake);
            return askId;
        }
        if (open) [self endLocked:open];
        fresh = [AsideCopy new];
        fresh.sessionId = sessionId;
        fresh.model = model;
        fresh.effort = effort;
        fresh.opened = mark;
        fresh.openedAt = NSDate.date.timeIntervalSince1970 * 1000;
        fresh.askId = askId;
        fresh.done = done;
        fresh.step = step;
        fresh.known = earlier.count;
        fresh.lines = [NSMutableArray array];
        fresh.wake = dispatch_semaphore_create(0);
        self.copies[sessionId] = fresh;
    }
    NSData *first = LineOf(ClaudeAsideWords(question, earlier, YES));
    NSMutableDictionary *copies = self.copies;
    NSString *checker = self.checker, *given = self.program;
    NSMutableSet *refused = self.refused;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Where Claude Code is comes from your login shell's PATH, which can take a moment the first time; a print
        // run gives its own stand-in.
        NSString *path = given ? @"/usr/bin:/bin" : LoginPath();
        NSString *claude = given ?: ClaudeAsideProgram(running, ClaudeCandidates(path));
        if (!claude) {
            @synchronized (copies) {
                fresh.ending = YES;
                if (copies[sessionId] == fresh) [copies removeObjectForKey:sessionId];
                Tell(fresh, @{@"state": @"noCommand"});
            }
            return;
        }
        @synchronized (copies) {
            fresh.program = claude;
        }
        NSDictionary *environment = ClaudeAsideEnvironment(ClaudeEnvironment(path), checker, folder);
        NSDictionary *(^run)(NSArray *) = ^NSDictionary *(NSArray *with) {
            return RunConversationOn(claude, with, environment, folder, first, ^BOOL(NSData *each) {
                NSDictionary *message = AsRecord([NSJSONSerialization JSONObjectWithData:each options:0 error:nil]);
                @synchronized (copies) {
                    fresh.heard = YES;
                    // Every line is kept until the result's, but no more than an answer needs.
                    if (fresh.kept < 4 * 1024 * 1024) {
                        [fresh.lines addObject:each];
                        fresh.kept += each.length;
                    }
                    if (![message[@"type"] isEqual:@"result"]) {
                        // Each new step of the ask it's answering told on the main thread, before its answer.
                        NSString *now = fresh.askId ? ClaudeAsideStep(message, folder) : nil;
                        void (^told)(NSString *) = fresh.step;
                        if (now && told && ![now isEqual:fresh.told]) {
                            fresh.told = now;
                            dispatch_async(dispatch_get_main_queue(), ^{ told(now); });
                        }
                        return NO;
                    }
                    Tell(fresh, ClaudeAsideAnswer(fresh.lines, NO, fresh.stopped));
                }
                return YES;
            }, kAsideDeadline, ^(pid_t pid) {
                // Kept out of the rows before it can register, and ended at once if Stop came first.
                NoteAsideProcess(pid, YES);
                @synchronized (copies) {
                    fresh.pid = pid;
                    fresh.started = ProcessStartedAt(pid);
                    if (fresh.stopped) EndCopy(fresh);
                }
            }, ^NSData * {
                // The next question, once it's asked: five minutes at most, and none once it's ending.
                @synchronized (copies) {
                    if (fresh.ending) return nil;
                }
                dispatch_semaphore_wait(fresh.wake,
                                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAsideKept * NSEC_PER_SEC)));
                @synchronized (copies) {
                    NSData *more = fresh.ending ? nil : fresh.pending;
                    fresh.pending = nil;
                    if (!more) fresh.ending = YES;
                    return more;
                }
            });
        };
        // Its thinking's summaries are asked for only from a version they were checked with. One that ends at once,
        // having said nothing, is asked again without them; and if it then answers, the flag was what it turned down,
        // so that version isn't asked for them again while Whozmove runs.
        NSString *version = ClaudeCodeVersionAt(claude);
        BOOL thinks;
        @synchronized (refused) {
            thinks = ClaudeAsideThinks(version, refused);
        }
        NSDictionary *ran = run(thinks ? [arguments arrayByAddingObjectsFromArray:ClaudeAsideThinkingArguments()]
                                       : arguments);
        BOOL again;
        @synchronized (copies) {
            again = thinks && ClaudeAsideFlagRefused(ran, fresh.heard, fresh.stopped);
        }
        if (again) {
            if (fresh.pid > 0) NoteAsideProcess(fresh.pid, NO);
            @synchronized (copies) {
                fresh.pid = 0;
                fresh.started = 0;
            }
            ran = run(arguments);
            BOOL heard;
            @synchronized (copies) {
                heard = fresh.heard;
            }
            if (heard) {
                @synchronized (refused) {
                    [refused addObject:version];
                }
                LogProblem([NSString stringWithFormat:@"side question: Claude Code %@ turned down %@, so it's asked "
                            "without it from now on", version, ClaudeAsideThinkingArguments().firstObject]);
            }
        }
        @synchronized (copies) {
            fresh.ending = YES;
            if (copies[sessionId] == fresh) [copies removeObjectForKey:sessionId];
            // An ask it hadn't answered when it ended: said as how it ended.
            if (fresh.askId)
                Tell(fresh, ran ? ClaudeAsideAnswer(fresh.lines, [ran[@"timedOut"] boolValue], fresh.stopped)
                                : @{@"state": fresh.stopped ? @"stopped" : @"noAnswer"});
        }
        if (fresh.pid > 0) NoteAsideProcess(fresh.pid, NO);
        if (!ran) LogProblem([NSString stringWithFormat:@"side question: %@ didn't start", claude]);
    });
    return askId;
}

// No more asks go into it, and one waiting to be asked is told to finish now. Under the copies' lock.
- (void)endLocked:(AsideCopy *)copy {
    copy.ending = YES;
    if (!copy.askId) dispatch_semaphore_signal(copy.wake);
}

- (void)stop:(NSString *)askId {
    if (!askId) return;
    @synchronized (self.copies) {
        for (AsideCopy *copy in self.copies.allValues) {
            if (![copy.askId isEqual:askId] || copy.stopped) continue;
            copy.stopped = YES;
            copy.ending = YES;
            EndCopy(copy);
        }
    }
}

- (NSDictionary<NSString *, NSNumber *> *)openSince {
    NSMutableDictionary *open = [NSMutableDictionary dictionary];
    @synchronized (self.copies) {
        for (AsideCopy *copy in self.copies.allValues) open[copy.sessionId] = @(copy.openedAt);
    }
    return open;
}

- (void)end:(NSString *)sessionId {
    @synchronized (self.copies) {
        AsideCopy *copy = sessionId ? self.copies[sessionId] : nil;
        if (copy) [self endLocked:copy];
    }
}

- (void)stopAll {
    @synchronized (self.copies) {
        for (AsideCopy *copy in self.copies.allValues) {
            copy.stopped = YES;
            copy.ending = YES;
            EndCopy(copy);
            dispatch_semaphore_signal(copy.wake);
        }
    }
}

@end
