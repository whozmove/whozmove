// ClaudeCodePrints: the Claude Code module's print modes, which the tests check: --print-mode-moves, --print-typing,
// --print-results, --print-usage, --print-spent, --print-reply, --print-writing-wait, --print-record-how,
// --print-reads, --print-trust, --print-kept, --print-plugin-install, --print-held, --print-hook-line,
// --print-askers, --print-program, --print-switch-holder and --print-dont-wait-files.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ClaudeCode.h"
#import "Core.h"
#import "Modules.h"
#import "Row.h"
#import "Files.h"
#import "Printing.h"
#import "Background.h"
#import "ClaudeCodeFacts.h"
#import "AgentDetails.h"
#import "ClaudeUsage.h"
#import "ClaudeCommand.h"
#import "PluginInstall.h"
#import "Prompt.h"
#import "Results.h"
#import "Trust.h"
#import "Transcripts.h"
#import "Writings.h"
#import "Edits.h"
#import "Records.h"
#import "KeptSessions.h"
#import "DontWait.h"
#import "HookLine.h"
#import "ClaudeSessions.h"
#import "AnswerFor.h"
#import "SwitchHolder.h"
#import "BetweenSteps.h"
#import "ClaudeAside.h"
#import "Asks.h"
#import "Allowed.h"
#import "Notice.h"
#import "Rows.h"
#import "SessionAsks.h"
#import "Text.h"
#import "Processes.h"
#import "Signature.h"
#import "ClaudeProgram.h"
#import "WhereSeenWorking.h"
#import "AsideReads.h"
#import "Git.h"
#import <fcntl.h>

// The module in a print run's core.
static ClaudeCode *AgentIn(Core *core) {
    for (id module in core.modules.all)
        if ([module isKindOfClass:ClaudeCode.class]) return module;
    return nil;
}

// `Whozmove --print-mode-moves`: for each terminal session in $HOME, why keys can't go into it now (null when they
// can), why the one Backspace a request may press while Claude works can't go in now (WhyNotEditDraft), and the
// Shift+Tabs its mode menu would type to reach each mode (null where it offers none), as JSON, then quit.
// tests/rows.sh checks them: a wrong answer types into a session that isn't safe to type into, and a wrong count
// lands a session in another mode.
static int PrintModeMoves(Core *core) {
    ClaudeCode *agent = AgentIn(core);
    NSMutableDictionary *sessions = [NSMutableDictionary dictionary];
    for (Row *row in SettledRows(core)) {
        if ([core hostHolding:row] || !row.sessionId)  // a conversation an app keeps (Claude Desktop's) has no tab
            continue;
        NSArray *cycles = [agent.details modeCyclesFor:row];
        NSMutableDictionary *moves = [NSMutableDictionary dictionary];
        for (NSArray<NSString *> *choice in ModeChoices()) {
            NSInteger presses = [agent.details shiftTabsFrom:row.agent[@"mode"] to:choice[0] cycles:cycles];
            moves[choice[0]] = presses > 0 ? @(presses) : NSNull.null;
        }
        Reason *why = WhyNotTypeInto(row.sessionId, row.pid), *edit = WhyNotEditDraft(row.sessionId, row.pid);
        sessions[row.sessionId] = @{@"mode": row.agent[@"mode"] ?: @"", @"possibleCycles": cycles,
                                        @"presses": moves,
                                        @"whyNotType": why ? @{@"log": why.description, @"card": why.onCard}
                                                           : NSNull.null,
                                        @"whyNotEditDraft": edit ? edit.description : NSNull.null};
    }
    return PrintJSON(sessions);
}

// A terminal that writes down every key it's asked to put in, for --print-typing, and refuses keys once it has been
// asked for `refuseAt` of them (0: never), as a terminal says when it didn't take one.
@interface RecordingTerminal : NSObject <TypingHost>
@property (strong) NSMutableArray<NSString *> *keys;
@property NSUInteger refuseAt;
@end

@implementation RecordingTerminal
- (NSString *)appId { return @"test"; }
- (NSString *)name { return @"Test"; }
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique { *unique = YES; return @"tab"; }
- (BOOL)open:(Row *)row { return YES; }
- (void)type:(NSString *)text inTab:(NSString *)tab { [self.keys addObject:[@"text " stringByAppendingString:text]]; }
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {
    NSString *name = @[@"Return", @"Backspace", @"Shift+Tab", @"Ctrl+S"][key];
    [self.keys addObject:[NSString stringWithFormat:@"%@ ×%ld", name, (long)times]];
}
- (NSString *)whyNotTypeIn:(NSString *)tab {
    return self.refuseAt && self.keys.count >= self.refuseAt ? @"It didn't take the last key" : nil;
}
@end

// `Whozmove --print-typing`: the keys a slash command is typed with, once into a session that stays at its prompt,
// once into one that turns busy after two keys, and once through a terminal that refuses the last key, the Return, as
// JSON, then quit. tests/rows.sh checks them: a key out of place, or one more after the session has moved on, could
// answer a prompt, and a refused Return taken for a command gone in would leave it waiting in the prompt.
static int PrintTyping(void) {
    NSMutableDictionary *runs = [NSMutableDictionary dictionary];
    NSArray *names = @[@"stays at its prompt", @"turns busy after two keys", @"its terminal refuses the Return"];
    for (NSString *run in names) {
        RecordingTerminal *terminal = [RecordingTerminal new];
        terminal.keys = [NSMutableArray array];
        if ([run hasPrefix:@"its terminal"]) terminal.refuseAt = 4;
        __block NSUInteger checked = 0;
        NSUInteger safe = [run hasPrefix:@"turns busy"] ? 2 : NSUIntegerMax;
        TypeCommand(terminal, @"tab", @"/model claude-opus-5-5",
                    ^{ return checked++ < safe ? nil : [Reason status:@"busy"]; },
                    ^(Reason *why, NSUInteger typed, NSUInteger steps) {
            if (!why) DeleteFiller(terminal, @"tab");
            runs[run] = @{@"keys": terminal.keys, @"stopped": why ? why.description : NSNull.null};
        });
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (deadline.timeIntervalSinceNow > 0 && runs.count < names.count)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return PrintJSON(runs);
}

// `Whozmove --print-results <command> <transcript>…`: for each pair, by the transcript's name, what's read from it as
// the command's result, all of it being new (CommandResult), and what the panel takes that result to say: the value
// now in effect for the field the command changes (null: it changed nothing), whether the pick was saved as the default
// for new sessions, for /compact, what its card says (null: it compacted), and for /reload-plugins, whether it reloaded. As JSON, then quit. tests/rows.sh
// checks them against results written the way Claude Code writes them.
static int PrintResults(NSArray<NSString *> *arguments) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i + 1 < arguments.count; i += 2) {
        NSString *command = arguments[i], *file = arguments[i + 1];
        NSString *name = [[command componentsSeparatedByString:@" "].firstObject substringFromIndex:1];
        NSString *rest = [command substringFromIndex:MIN(command.length, name.length + 2)];
        NSString *field = [name isEqual:@"plan"] ? @"mode" : name, *value = [name isEqual:@"plan"] ? @"plan" : rest;
        NSString *result = CommandResult(file, 0, command);
        NSMutableDictionary *read = [@{@"command": command, @"result": result ?: NSNull.null,
                                       @"applies": ResultApplies(field, value, result) ?: NSNull.null,
                                       @"savedDefault": @(ResultSavedDefault(result))} mutableCopy];
        if ([field isEqual:@"compact"]) read[@"compactNote"] = CompactNote(result) ?: NSNull.null;
        if ([command isEqual:kReloadPluginsCommand]) read[@"reloaded"] = @(ReloadedResult(result));
        out[file.lastPathComponent] = read;
    }
    return PrintJSON(out);
}

// `Whozmove --print-usage <file>…`: for each file, by its name, what the usage strip would take from it as Claude
// Code's output (the usage request's answer, read line by line, or null) and as `claude auth status`'s (signedIn,
// signedOut or null), and what an answer with no plan's numbers becomes beside that auth status (`noPlan`, null for
// signed out, as the card then offers Sign in), without and with a key in your shell; then where `claude` is looked
// for, for the PATH in $USAGE_PATH and the home folder in $HOME; as JSON, then quit. tests/rows.sh checks them against
// recorded answers and sample installs.
static int PrintUsage(NSArray<NSString *> *files) {
    MachineFilesInHome = YES;
    NSMutableDictionary *read = [NSMutableDictionary dictionary];
    for (NSString *file in files) {
        NSData *data = [NSData dataWithContentsOfFile:file] ?: NSData.data;
        id usage = NSNull.null;
        for (NSString *line in [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                                componentsSeparatedByString:@"\n"]) {
            NSDictionary *answer = line.length ? UsageFromReply([line dataUsingEncoding:NSUTF8StringEncoding]) : nil;
            if (answer) {
                usage = answer;
                break;
            }
        }
        NSString *auth = AuthStateFrom(data);
        read[file.lastPathComponent] = @{@"usage": usage, @"auth": auth ?: NSNull.null,
                                         @"noPlan": UsageNoPlanReason(auth, NO) ?: NSNull.null,
                                         @"noPlanShellKey": UsageNoPlanReason(auth, YES) ?: NSNull.null};
    }
    NSString *path = NSProcessInfo.processInfo.environment[@"USAGE_PATH"] ?: @"";
    NSMutableArray *candidates = [NSMutableArray array];  // from the home folder, so they read the same everywhere
    for (NSString *claude in ClaudeCandidates(path))
        [candidates addObject:[claude hasPrefix:Home()]
                                  ? [@"~" stringByAppendingString:[claude substringFromIndex:Home().length]]
                                  : claude];
    return PrintJSON(@{@"files": read, @"candidates": candidates});
}

// `Whozmove --print-reply <transcript> [<since> <prompt>]…`: Claude's reply to each prompt sent after `since` (ms),
// as ReplyAfter finds it in the transcript, read whole and with its first line cut off (so a turn that starts there
// is missed, as a read of a file's end may), a line each, its length in place of a reply longer than 200, then quit.
static int PrintReply(NSArray<NSString *> *arguments) {
    if (arguments.count < 3 || arguments.count % 2 == 0) {
        fprintf(stderr, "usage: --print-reply <transcript> [<since> <prompt>]…\n");
        return 2;
    }
    NSData *data = [NSData dataWithContentsOfFile:arguments[0]] ?: NSData.data;
    NSString *(^shown)(NSString *) = ^NSString *(NSString *reply) {
        if (!reply) return @"none yet";
        if (reply.length > 200)
            return [NSString stringWithFormat:@"%lu characters, ending \"%@\"", (unsigned long)reply.length,
                                              [reply substringFromIndex:reply.length - 3]];
        return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@[reply] options:0 error:nil]
                                     encoding:NSUTF8StringEncoding];
    };
    for (NSUInteger i = 1; i + 1 < arguments.count; i += 2) {
        double since = arguments[i].doubleValue;
        NSString *prompt = arguments[i + 1];
        printf("%s since %.0f: %s; read from its second line: %s\n", prompt.UTF8String, since,
               shown(ReplyAfter(data, YES, prompt, since)).UTF8String,
               shown(ReplyAfter(data, NO, prompt, since)).UTF8String);
    }
    return 0;
}

// `Whozmove --print-between-steps`: words handed to a session's own hook between its steps: what the hook is handed
// (BetweenStepsHandOut), whose hook may take them (BetweenStepsHookOf), and how a sample transcript records them taken
// in, and what Claude wrote after them (AfterHandedWords), as Claude Code 2.1.304 writes them.
// `Whozmove --print-aside`: a question asked on a session's side, in the home folder the run is given, running
// nothing of Claude Code's: the command it runs (ClaudeAsideArguments) and the words that open the question, the
// sessions it may be asked of (ClaudeAsideResumable), the model and the program it's asked with, how each ending of
// its output is read (ClaudeAsideAnswer), what its checker lets it read and run (AsideReads), when a follow-up goes
// into the open copy and what a fresh one is told, a kept conversation with a stand-in that answers each line, and its
// process kept out of everything read from Claude Code's registry while it runs. It writes sample programs, files and
// a registry file in the home folder, and takes them away after, so it refuses to run in your own. With `--arguments
// <session> <model> <effort>` it prints only the arguments a side question of that session runs with, as JSON, writing
// nothing (or refuses a session id it may not resume): the real Claude Code run asks a real Claude Code with them.
// With `--environment <folder>`, only what a side question in that folder adds to its environment
// (ClaudeAsideEnvironment, this program the checker), as JSON. With `--steps <file> <folder>`, only the step each
// sample tool call in the file (a JSON list of {tool, input}) says in a side question of that folder
// (ClaudeAsideStep), one a line: the test holds them beside the words the session's own hook gives the same calls.
static int PrintAside(Core *core, NSArray<NSString *> *given) {
    if (given.count == 4 && [given[0] isEqual:@"--arguments"]) {
        NSArray *arguments = ClaudeAsideArguments(given[1], given[2], given[3], YES);
        if (!arguments) {
            fprintf(stderr, "--print-aside --arguments: %s isn't a session id it may resume\n", given[1].UTF8String);
            return 2;
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:nil];
        printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return 0;
    }
    if (given.count == 2 && [given[0] isEqual:@"--environment"]) {
        NSDictionary *environment = ClaudeAsideEnvironment(@{}, NSBundle.mainBundle.executablePath, given[1]);
        NSData *json = [NSJSONSerialization dataWithJSONObject:environment options:NSJSONWritingSortedKeys error:nil];
        printf("%s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return 0;
    }
    if (given.count == 3 && [given[0] isEqual:@"--steps"]) {
        NSData *data = [NSData dataWithContentsOfFile:given[1]];
        NSArray *samples = data ? AsList([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]) : nil;
        if (!samples) {
            fprintf(stderr, "--print-aside --steps: %s isn't a JSON list of tool calls\n", given[1].UTF8String);
            return 2;
        }
        for (id each in samples) {
            NSDictionary *sample = AsRecord(each);
            NSDictionary *line = @{@"type": @"assistant", @"message": @{@"content": @[
                @{@"type": @"tool_use", @"name": AsText(sample[@"tool"]) ?: @"", @"input": AsRecord(sample[@"input"]) ?: @{}}]}};
            printf("%s\n", (ClaudeAsideStep(line, given[2]) ?: @"").UTF8String);
        }
        return 0;
    }
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-aside writes in $HOME: run it with a throwaway HOME, as "
                        "modules/claude-code/tests/test.sh does\n");
        return 2;
    }
    NSString *home = Home();
    void (^say)(NSString *, id) = ^(NSString *what, id value) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:value ?: NSNull.null
                                                       options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                         error:nil];
        NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        line = [line stringByReplacingOccurrencesOfString:[home stringByReplacingOccurrencesOfString:@"/"
                                                                                           withString:@"\\/"]
                                               withString:@"HOME"];
        printf("%s: %s\n", what.UTF8String, line.UTF8String);
    };
    printf("== What it runs\n");
    NSString *session = @"0b6c1d2e-3f40-4a51-8b62-7c83d94ea5f6";
    say(@"Its arguments", ClaudeAsideArguments(session, @"claude-opus-5-5[1m]", @"high", YES));
    say(@"No model or effort known: neither passed, so Claude Code's own",
        @([ClaudeAsideArguments(session, nil, @"", YES) containsObject:@"--model"]
          || [ClaudeAsideArguments(session, nil, @"", YES) containsObject:@"--effort"]));
    say(@"The words that open the question", ClaudeAsideLine());
    say(@"A session whose id is a UUID: asked", @(ClaudeAsideResumable(session)));
    say(@"…one whose id looks like a flag: never asked, as Claude Code would read it as one",
        @(ClaudeAsideResumable(@"--mcp-config=planted.json")));
    say(@"…one whose id is any other word: never asked", @(ClaudeAsideResumable(@"s-1")));
    say(@"…and no arguments for one, however it's asked", @(ClaudeAsideArguments(@"--mcp-config=planted.json",
                                                                                 @"claude-opus-5-5", @"high", YES)
                                                                            == nil));

    printf("\n== The model it's asked with\n");
    say(@"The session's, as its replies say", ClaudeAsideModel(@"claude-sonnet-5-5", nil, 40000));
    say(@"The long context its own --model asked for", ClaudeAsideModel(@"claude-opus-5-5", @"claude-opus-5-5[1m]",
                                                                         40000));
    say(@"Another model's long context: not this one's", ClaudeAsideModel(@"claude-sonnet-5-5", @"claude-opus-5-5[1m]",
                                                                           40000));
    say(@"A conversation over 200k: the long context", ClaudeAsideModel(@"claude-sonnet-5-5", nil, 250000));
    say(@"…but Opus 5.x over 200k: its own name, its window the long one already",
        ClaudeAsideModel(@"claude-opus-5-5", @"opus", 550000));
    say(@"Said with it already", ClaudeAsideModel(@"claude-opus-5-5[1m]", nil, 0));
    say(@"None known: its --model's", ClaudeAsideModel(@"", @"opus", 0));

    printf("\n== The program it runs\n");
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *installed = [home stringByAppendingPathComponent:@".local/bin/claude"];
    NSString *other = [home stringByAppendingPathComponent:@"versions/claude"];
    NSString *linked = [home stringByAppendingPathComponent:@"bin/claude"];
    for (NSString *path in @[installed, other]) {
        [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                          attributes:nil error:nil];
        [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [files createDirectoryAtPath:linked.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil
                           error:nil];
    [files createSymbolicLinkAtPath:linked withDestinationPath:other error:nil];
    say(@"The session's own, where Claude Code is installed", ClaudeAsideProgram(other, @[installed, linked]));
    say(@"The session's own isn't where Claude Code is installed: the first that is", ClaudeAsideProgram(
        [home stringByAppendingPathComponent:@"elsewhere/claude"], @[installed, linked]));
    say(@"Its own not known", ClaudeAsideProgram(nil, @[installed]));
    say(@"None installed", ClaudeAsideProgram(other, @[]));

    printf("\n== How its output is read\n");
    NSArray<NSData *> *(^lines)(NSArray *) = ^NSArray<NSData *> *(NSArray *messages) {
        NSMutableArray *out = [NSMutableArray array];
        for (id m in messages) [out addObject:[NSJSONSerialization dataWithJSONObject:m options:0 error:nil]];
        return out;
    };
    NSDictionary *init = @{@"type": @"system", @"subtype": @"init"};
    NSDictionary *usage = @{@"input_tokens": @4, @"cache_read_input_tokens": @301611, @"cache_creation_input_tokens":
                            @2400, @"output_tokens": @180};
    NSDictionary *(^said)(NSArray *) = ^NSDictionary *(NSArray *content) {
        return @{@"type": @"assistant", @"message": @{@"role": @"assistant", @"content": content}};
    };
    say(@"Answered", ClaudeAsideAnswer(lines(@[init, said(@[@{@"type": @"text", @"text": @"Because it holds the cart."}]),
        @{@"type": @"result", @"subtype": @"success", @"is_error": @NO, @"result": @"Because it holds the cart.",
          @"usage": usage}]), NO, NO));
    say(@"Answered, the result's words empty: its reply's", ClaudeAsideAnswer(lines(@[init,
        said(@[@{@"type": @"text", @"text": @"Because it holds the cart."}]),
        @{@"type": @"result", @"subtype": @"success", @"is_error": @NO, @"result": @""}]), NO, NO));
    say(@"It reached for a tool, and the run ended", ClaudeAsideAnswer(lines(@[init,
        said(@[@{@"type": @"text", @"text": @"Let me look."}, @{@"type": @"tool_use", @"name": @"Read"}]),
        @{@"type": @"result", @"subtype": @"error_max_turns", @"is_error": @YES, @"usage": usage}]), NO, NO));
    say(@"It ran out of turns without a tool: no answer", ClaudeAsideAnswer(lines(@[init,
        @{@"type": @"result", @"subtype": @"error_max_turns", @"is_error": @YES}]), NO, NO));
    say(@"Your plan's limit, with when it resets", ClaudeAsideAnswer(lines(@[init,
        @{@"type": @"rate_limit_event", @"rate_limit_info": @{@"status": @"rejected", @"resetsAt": @1798000000}},
        @{@"type": @"result", @"subtype": @"success", @"is_error": @YES,
          @"result": @"You've hit your usage limit · resets 11pm"}]), NO, NO));
    say(@"Signed out", ClaudeAsideAnswer(lines(@[init, @{@"type": @"result", @"subtype": @"success", @"is_error": @YES,
        @"result": @"Invalid API key · Please run /login"}]), NO, NO));
    say(@"Too long to read again", ClaudeAsideAnswer(lines(@[init, @{@"type": @"result", @"subtype": @"success",
        @"is_error": @YES, @"result": @"Prompt is too long"}]), NO, NO));
    say(@"…or past its model's context limit: too long, not your plan's limit", ClaudeAsideAnswer(lines(@[init,
        @{@"type": @"result", @"subtype": @"success", @"is_error": @YES,
          @"result": @"input length and max_tokens exceed context limit"}]), NO, NO));
    say(@"Your plan's limit, in Claude Code's own words", ClaudeAsideAnswer(lines(@[init, @{@"type": @"result",
        @"subtype": @"success", @"is_error": @YES, @"result": @"You've hit your limit \u00b7 resets 3pm"}]), NO, NO));
    say(@"Another error: no answer", ClaudeAsideAnswer(lines(@[init, @{@"type": @"result", @"subtype": @"success",
        @"is_error": @YES, @"result": @"Overloaded"}]), NO, NO));
    say(@"An error the API sent back: said as one, with its status", ClaudeAsideAnswer(lines(@[init, @{@"type": @"result",
        @"subtype": @"success", @"is_error": @YES, @"result": @"API Error: 400 a request it refused",
        @"api_error_status": @400, @"usage": @{@"input_tokens": @0, @"output_tokens": @0}}]), NO, NO));
    say(@"…one with no status, in Claude Code's words", ClaudeAsideAnswer(lines(@[init, @{@"type": @"result",
        @"subtype": @"success", @"is_error": @YES, @"result": @"API Error: Connection error."}]), NO, NO));
    say(@"Nothing in time: too slow", ClaudeAsideAnswer(lines(@[init]), YES, NO));
    say(@"Nothing, and it ended: no answer", ClaudeAsideAnswer(lines(@[init]), NO, NO));
    say(@"Stopped, whatever it said", ClaudeAsideAnswer(lines(@[init, @{@"type": @"result", @"subtype": @"success",
        @"is_error": @NO, @"result": @"Half"}]), NO, YES));
    say(@"A line that isn't JSON is passed over", ClaudeAsideAnswer(@[[@"not json" dataUsingEncoding:NSUTF8StringEncoding],
        lines(@[@{@"type": @"result", @"subtype": @"success", @"is_error": @NO, @"result": @"Yes."}]).firstObject], NO,
        NO)[@"state"]);
    NSString *longWords = [@"" stringByPaddingToLength:20000 withString:@"word " startingAtIndex:0];
    say(@"A long answer: 16,384 characters kept", @([ClaudeAsideAnswer(lines(@[@{@"type": @"result",
        @"subtype": @"success", @"is_error": @NO, @"result": longWords}]), NO, NO)[@"text"] length]));

    printf("\n== The steps it says as it answers\n");
    NSString *shop = [home stringByAppendingPathComponent:@"shop"];
    [files createDirectoryAtPath:shop withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *(^step)(NSArray *) = ^NSString *(NSArray *content) { return ClaudeAsideStep(said(content), shop); };
    NSDictionary *(^thought)(NSString *) = ^NSDictionary *(NSString *words) {
        return @{@"type": @"thinking", @"thinking": words, @"signature": @"c2lnbg=="};
    };
    NSDictionary *(^tool)(NSString *, NSDictionary *) = ^NSDictionary *(NSString *name, NSDictionary *input) {
        return @{@"type": @"tool_use", @"id": @"toolu_1", @"name": name, @"input": input};
    };
    // Made up as the run goes, in a key's shape.
    NSString *keyShaped = [@"sk-" stringByAppendingString:[@"" stringByPaddingToLength:28 withString:@"q7Z"
                                                                       startingAtIndex:0]];
    say(@"Thinking, its words not passed on", step(@[thought(@"")]));
    say(@"…its summary's first line, without its markdown", step(@[thought(@"**Looking at how the cart totals**\n\nThe "
                                                                           "cart adds each line.")]));
    say(@"…a long one, cut", step(@[thought([@"Weighing " stringByPaddingToLength:140 withString:@"the totals "
                                                                    startingAtIndex:0])]));
    say(@"…one that names a path, or holds a key's shape: just Thinking",
        @[step(@[thought(@"Checking /etc/hosts first")]), step(@[thought(@"Reading ~/notes")]),
          step(@[thought([@"The key " stringByAppendingString:keyShaped])])]);
    say(@"…hidden from it", step(@[@{@"type": @"redacted_thinking", @"data": @"ZGF0YQ=="}]));
    say(@"Reading a file in the session's folder: its name",
        @[step(@[tool(kClaudeToolRead, @{kClaudeToolFilePath: [shop stringByAppendingPathComponent:@"src/cart.ts"]})]),
          step(@[tool(kClaudeToolRead, @{kClaudeToolFilePath: @"src/cart.ts"})])]);
    say(@"…one outside it, by any way: no name",
        @[step(@[tool(kClaudeToolRead, @{kClaudeToolFilePath: @"/etc/hosts"})]),
          step(@[tool(kClaudeToolRead, @{kClaudeToolFilePath: @"~/.ssh/config"})]),
          step(@[tool(kClaudeToolRead, @{kClaudeToolFilePath: @"../outside/notes.txt"})]),
          step(@[tool(kClaudeToolRead, @{})])]);
    say(@"Searching: its words, cut", @[step(@[tool(kClaudeToolGrep, @{kClaudeToolPattern: @"total"})]),
                                        step(@[tool(kClaudeToolGrep, @{kClaudeToolPattern:
                                            @"function (add|remove)LineFromTheCart\\("})])]);
    say(@"…words that name a path, or hold a key's shape: no words",
        @[step(@[tool(kClaudeToolGrep, @{kClaudeToolPattern: @"/Users/you/"})]),
          step(@[tool(kClaudeToolGrep, @{kClaudeToolPattern: keyShaped})])]);
    say(@"Finding files: a pattern in the folder", step(@[tool(kClaudeToolGlob, @{kClaudeToolPattern: @"src/**/*.ts"})]));
    say(@"…one that reaches outside it: no pattern", @[step(@[tool(kClaudeToolGlob, @{kClaudeToolPattern: @"/etc/*"})]),
        step(@[tool(kClaudeToolGlob, @{kClaudeToolPattern: @"../*"})]),
        step(@[tool(kClaudeToolGlob, @{kClaudeToolPattern: @"~/*"})])]);
    say(@"git: its own command, never Claude's words for it",
        @[step(@[tool(kClaudeToolBash, @{kClaudeToolCommand: @"git log --oneline -5",
                                         @"description": @"Show the last commits in /Users/you/shop"})]),
          step(@[tool(kClaudeToolBash, @{kClaudeToolCommand: @"git -C /tmp log"})]),
          step(@[tool(kClaudeToolBash, @{kClaudeToolCommand: @"cat notes.txt"})])]);
    say(@"Any other tool", step(@[tool(@"Edit", @{kClaudeToolFilePath: @"src/cart.ts"})]));
    say(@"Several blocks in one line: the last's", step(@[thought(@""), tool(kClaudeToolGrep, @{kClaudeToolPattern:
                                                                                                 @"total"})]));
    say(@"Its words, a tool's result, the result, a line of anything else: no step",
        @[step(@[@{@"type": @"text", @"text": @"It holds the cart."}]) ?: NSNull.null,
          ClaudeAsideStep(@{@"type": @"user", @"message": @{@"content": @[@{@"type": @"tool_result",
                                                                             @"content": @"1 match"}]}}, shop)
              ?: NSNull.null,
          ClaudeAsideStep(@{@"type": @"result", @"subtype": @"success"}, shop) ?: NSNull.null,
          ClaudeAsideStep(@{@"type": @"system", @"subtype": @"init"}, shop) ?: NSNull.null]);

    printf("\n== Its thinking's summaries, by the version of Claude Code\n");
    say(@"Asked for with", ClaudeAsideThinkingArguments());
    NSString *versions = [home stringByAppendingPathComponent:@"versions-sample"];
    NSString *byInstaller = [versions stringByAppendingPathComponent:@"versions/2.1.319"];
    NSString *byCask = [versions stringByAppendingPathComponent:@"Caskroom/claude-code/2.1.319/claude"];
    NSString *byLink = [versions stringByAppendingPathComponent:@"bin/claude"];
    for (NSString *path in @[byInstaller, byCask, byLink])
        [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                          attributes:nil error:nil];
    [@"" writeToFile:byInstaller atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"" writeToFile:byCask atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [files createSymbolicLinkAtPath:byLink withDestinationPath:byInstaller error:nil];
    say(@"Its version: its installer's file, Homebrew's folder, a link to one, npm's",
        @[ClaudeCodeVersionAt(byInstaller) ?: NSNull.null, ClaudeCodeVersionAt(byCask) ?: NSNull.null,
          ClaudeCodeVersionAt(byLink) ?: NSNull.null,
          ClaudeCodeVersionAt([versions stringByAppendingPathComponent:@"node_modules/.bin/claude"]) ?: NSNull.null]);
    [files removeItemAtPath:versions error:nil];
    say(@"Asked for: a version they were checked with; not a later one, one that turned them down, or none known",
        @[@(ClaudeAsideThinks(@"2.1.319", [NSSet set])), @(ClaudeAsideThinks(@"2.1.999", [NSSet set])),
          @(ClaudeAsideThinks(@"2.1.319", [NSSet setWithObject:@"2.1.319"])), @(ClaudeAsideThinks(nil, [NSSet set]))]);
    say(@"Asked again without them: it ended with an error, having said nothing",
        @(ClaudeAsideFlagRefused(@{@"status": @1, @"answered": @NO, @"timedOut": @NO}, NO, NO)));
    say(@"…not once it said something, was stopped, ran out of time, ended well or didn't start",
        @[@(ClaudeAsideFlagRefused(@{@"status": @1, @"timedOut": @NO}, YES, NO)),
          @(ClaudeAsideFlagRefused(@{@"status": @1, @"timedOut": @NO}, NO, YES)),
          @(ClaudeAsideFlagRefused(@{@"status": @1, @"timedOut": @YES}, NO, NO)),
          @(ClaudeAsideFlagRefused(@{@"status": @0, @"timedOut": @NO}, NO, NO)),
          @(ClaudeAsideFlagRefused(nil, NO, NO))]);

    printf("\n== What it may read, as its checker decides (nothing: it may)\n");
    NSString *project = [home stringByAppendingPathComponent:@"shop"];
    NSString *outside = [home stringByAppendingPathComponent:@"outside"];
    for (NSString *folder in @[[project stringByAppendingPathComponent:@"src"], outside,
                               [project stringByAppendingPathComponent:@".cursor"],
                               [project stringByAppendingPathComponent:@".vscode"],
                               [home stringByAppendingPathComponent:@".ssh"],
                               [project stringByAppendingPathComponent:@"docs"],
                               [project stringByAppendingPathComponent:@"config"],
                               [project stringByAppendingPathComponent:@"vendor/lib/sub"],
                               [project stringByAppendingPathComponent:@"site"],
                               [project stringByAppendingPathComponent:@"api"],
                               [home stringByAppendingPathComponent:@"plain/a"],
                               [home stringByAppendingPathComponent:@"plain/b/.hg"],
                               [home stringByAppendingPathComponent:@"plain/c"]])
        [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    // A checkout, which keeps a token and a key out of git, and a line in capitals that git, told to match names in
    // either case, takes for site's .env, though ripgrep doesn't.
    RunGit(@[@"init", @"-q", project]);
    RunGit(@[@"-C", project, @"config", @"core.ignorecase", @"true"]);
    // And an ignore file named in the checkout's own config, which ripgrep never reads, leaving out api's .env.
    NSString *hiding = [home stringByAppendingPathComponent:@"hiding"];
    [@"api/.env\n" writeToFile:hiding atomically:YES encoding:NSUTF8StringEncoding error:nil];
    RunGit(@[@"-C", project, @"config", @"core.excludesFile", hiding]);
    [@"deploy_token\n.npmrc\nsite/.ENV\n" writeToFile:[project stringByAppendingPathComponent:@".gitignore"]
                                            atomically:YES encoding:NSUTF8StringEncoding error:nil];
    for (NSString *name in @[@"shop/one.txt", @"shop/src/two.txt", @"shop/.env", @"shop/.env.local", @"shop/site.pem",
                             @"shop/deploy.key", @"shop/prod.env", @"shop/.envrc", @"shop/SITE.PEM",
                             @"shop/deploy_token", @"shop/.npmrc", @"shop/src/id_rsa", @"shop/src/deploy_token",
                             @"shop/.mcp.json", @"shop/.cursor/mcp.json", @"shop/.vscode/mcp.json",
                             @"shop/src/.mcp.json", @"shop/.aider.chat.history.md", @"shop/package.json",
                             @"outside/notes.txt", @"shop/docs/guide.md", @"shop/config/app.txt",
                             @"shop/config/.npmrc", @"shop/vendor/lib/readme.txt", @"shop/vendor/lib/.env",
                             @"shop/vendor/lib/sub/.env", @"shop/site/index.html", @"shop/site/.env",
                             @"shop/api/server.js", @"shop/api/.env",
                             @"plain/a/notes.txt", @"plain/b/notes.txt", @"plain/b/.hg/.env", @"plain/c/.env",
                             @".ssh/id_ed25519", kClaudeCodeState, @".netrc"])
        [@"sample\n" writeToFile:[home stringByAppendingPathComponent:name] atomically:YES
                        encoding:NSUTF8StringEncoding error:nil];
    NSString *claude = [home stringByAppendingPathComponent:kClaudeCodeFolder];
    [files createDirectoryAtPath:claude withIntermediateDirectories:YES attributes:nil error:nil];
    [@"{}" writeToFile:[claude stringByAppendingPathComponent:kClaudeCodeLocalSettings] atomically:YES
              encoding:NSUTF8StringEncoding error:nil];
    [files createSymbolicLinkAtPath:[project stringByAppendingPathComponent:@"out"] withDestinationPath:outside
                              error:nil];
    [files createSymbolicLinkAtPath:[project stringByAppendingPathComponent:@"notes.txt"]
                withDestinationPath:[outside stringByAppendingPathComponent:@"notes.txt"] error:nil];
    // Another checkout inside it, which it doesn't track.
    RunGit(@[@"init", @"-q", [project stringByAppendingPathComponent:@"vendor/lib"]]);
    // Its history: a first commit with the MCP settings the project keeps, as many do, and a second that changes only
    // src/two.txt.
    NSArray<NSString *> *saving = @[@"-C", project, @"-c", @"user.name=Sample", @"-c", @"user.email=sample@example.com",
                                    @"-c", @"commit.gpgsign=false", @"-c", @"core.hooksPath=/dev/null"];
    RunGit([saving arrayByAddingObjectsFromArray:@[@"add", @"one.txt", @"src/two.txt", @".mcp.json", @".gitignore"]]);
    RunGit([saving arrayByAddingObjectsFromArray:@[@"commit", @"-q", @"-m", @"First"]]);
    [@"sample, changed\n" writeToFile:[project stringByAppendingPathComponent:@"src/two.txt"] atomically:YES
                             encoding:NSUTF8StringEncoding error:nil];
    RunGit([saving arrayByAddingObjectsFromArray:@[@"commit", @"-q", @"-a", @"-m", @"Second"]]);
    // Where keys are kept is Keys' (the storage module's), found as the checker's helper run finds it.
    id<KeyPlaces> keys = [core moduleThat:@protocol(KeyPlaces)];
    NSString *(^may)(NSString *, NSDictionary *) = ^NSString *(NSString *tool, NSDictionary *input) {
        return AsideToolWhyNot(tool, input, project, home, keys);
    };
    NSString *(^bash)(NSString *) = ^NSString *(NSString *command) {
        return may(kClaudeToolBash, @{kClaudeToolCommand: command});
    };
    NSString *(^read)(NSString *) = ^NSString *(NSString *file) {
        return may(kClaudeToolRead, @{kClaudeToolFilePath: file});
    };
    say(@"Read, a file in the folder", read([project stringByAppendingPathComponent:@"src/two.txt"]));
    say(@"…the same, from the folder", read(@"src/two.txt"));
    say(@"…a file outside it", read([outside stringByAppendingPathComponent:@"notes.txt"]));
    say(@"…a link in the folder that leads out", read([project stringByAppendingPathComponent:@"notes.txt"]));
    say(@"…through a linked folder", read([project stringByAppendingPathComponent:@"out/notes.txt"]));
    say(@"…a path that climbs out", read([project stringByAppendingPathComponent:@"src/../../outside/notes.txt"]));
    say(@"…one that isn't there", read([project stringByAppendingPathComponent:@"gone.txt"]));
    say(@"…from the home folder by ~", read(@"~/.netrc"));
    say(@"…a .env in the folder", read([project stringByAppendingPathComponent:@".env"]));
    say(@"…a .env.local", read([project stringByAppendingPathComponent:@".env.local"]));
    say(@"…a .pem", read([project stringByAppendingPathComponent:@"site.pem"]));
    say(@"…a .key", read([project stringByAppendingPathComponent:@"deploy.key"]));
    say(@"…one ending .env, direnv's .envrc, one in capitals",
        @[read(@"prod.env"), read(@".envrc"), read(@"SITE.PEM")]);
    say(@"…git's own config", read(@".git/config"));
    say(@"…the project's own .npmrc, an ssh key in it", @[read(@".npmrc"), read(@"src/id_rsa")]);
    say(@"…MCP settings, which often hold a server's key: the project's, Cursor's, VS Code's, one in a folder of it",
        @[read(@".mcp.json"), read(@".cursor/mcp.json"), read(@".vscode/mcp.json"), read(@"src/.mcp.json")]);
    say(@"…an AI tool's history in the project", read(@".aider.chat.history.md"));
    say(@"…a JSON file, as most aren't a key's", read(@"package.json"));
    say(@"…one git ignores, whatever its name", read(@"deploy_token"));
    say(@"…a file git doesn't ignore, beside it", read(@"one.txt"));
    say(@"…no file given", may(kClaudeToolRead, @{}));
    // Even a Grep that prints only which files match says whether a key file holds what it looked for.
    say(@"Grep, over the folder, which holds key files the project keeps",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO"}));
    say(@"…in a folder of it with key files in it",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolPath: @"src"}));
    say(@"…in a folder with no key file in it", may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO",
                                                                       kClaudeToolPath: @"docs"}));
    say(@"…in a folder whose only key file git ignores, which Grep leaves out too",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolPath: @"config"}));
    say(@"…in a folder holding another checkout, untracked, with a key file in it",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolPath: @"vendor"}));
    say(@"…in a folder of that other checkout, with a key file in it, which this one's git lists nothing of",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolPath: @"vendor/lib/sub"}));
    say(@"…in a folder whose .env a line in capitals hides from git told to match either case, not from ripgrep",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolPath: @"site"}));
    say(@"…in a folder whose .env only an ignore file the checkout's config names hides, which ripgrep never reads",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolPath: @"api"}));
    NSString *plain = [home stringByAppendingPathComponent:@"plain"];
    NSString *(^plainGrep)(NSString *) = ^NSString *(NSString *path) {
        return AsideToolWhyNot(kClaudeToolGrep, path ? @{kClaudeToolPattern: @"TODO", kClaudeToolPath: path}
                                                     : @{kClaudeToolPattern: @"TODO"}, plain, home, keys);
    };
    say(@"…in no checkout: over a folder with a key file further down, in a folder of it with one, and one without",
        @[plainGrep(nil) ?: NSNull.null, plainGrep(@"c") ?: NSNull.null, plainGrep(@"a") ?: NSNull.null]);
    say(@"…in no checkout, a folder whose only key file is in version control's own folder, which Grep leaves out",
        plainGrep(@"b"));
    say(@"…in a linked folder that leads out", may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO",
                                                                         kClaudeToolPath: @"out"}));
    say(@"…in the home folder", may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolPath: home}));
    say(@"…in a file git ignores", may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO",
                                                          kClaudeToolPath: @"deploy_token"}));
    say(@"…with a file-name filter, which searches what git ignores",
        may(kClaudeToolGrep, @{kClaudeToolPattern: @"TODO", kClaudeToolGrepFilter: @"*.env"}));
    NSString *(^matching)(NSString *) = ^NSString *(NSString *path) {
        NSMutableDictionary *input = [@{kClaudeToolPattern: @"KEY", kClaudeToolGrepMode: kClaudeGrepContent}
                                      mutableCopy];
        if (path) input[kClaudeToolPath] = path;
        return may(kClaudeToolGrep, input);
    };
    say(@"…its matching lines over the folder, or a folder of it, which can hold a key file the project keeps",
        @[matching(nil), matching(@"src")]);
    say(@"…its matching lines from one file, and the files that match, or how many lines, over a folder without a key",
        @[matching(@"src/two.txt") ?: NSNull.null,
          may(kClaudeToolGrep, @{kClaudeToolPattern: @"KEY", kClaudeToolGrepMode: kClaudeGrepFiles,
                                 kClaudeToolPath: @"docs"}) ?: NSNull.null,
          may(kClaudeToolGrep, @{kClaudeToolPattern: @"KEY", kClaudeToolGrepMode: kClaudeGrepCount,
                                 kClaudeToolPath: @"docs"}) ?: NSNull.null]);
    say(@"…the files that match, or how many lines, over the folder, which holds a key file",
        @[may(kClaudeToolGrep, @{kClaudeToolPattern: @"KEY", kClaudeToolGrepMode: kClaudeGrepFiles}) ?: NSNull.null,
          may(kClaudeToolGrep, @{kClaudeToolPattern: @"KEY", kClaudeToolGrepMode: kClaudeGrepCount}) ?: NSNull.null]);
    say(@"…its matching lines from MCP settings, and a way of printing it has no name for",
        @[matching(@".mcp.json"), may(kClaudeToolGrep, @{kClaudeToolPattern: @"KEY", kClaudeToolGrepMode: @"json"})]);
    say(@"Glob, a pattern from the folder down", may(kClaudeToolGlob, @{kClaudeToolPattern: @"**/*.txt"}));
    say(@"…a whole path, searched whatever its path says", may(kClaudeToolGlob, @{
        kClaudeToolPattern: [outside stringByAppendingPathComponent:@"*.txt"], kClaudeToolPath: project}));
    say(@"…from the home folder", may(kClaudeToolGlob, @{kClaudeToolPattern: @"~/.ssh/*"}));
    say(@"…climbing out", may(kClaudeToolGlob, @{kClaudeToolPattern: @"../outside/*"}));
    say(@"Write: never", may(@"Write", @{kClaudeToolFilePath: [project stringByAppendingPathComponent:@"new.txt"]}));
    say(@"Edit, WebFetch, an MCP tool: never",
        @[may(@"Edit", @{}), may(@"WebFetch", @{}), may(@"mcp__kit__ping", @{})]);
    say(@"git status", bash(@"git status"));
    say(@"git status --short --branch", bash(@"git status --short --branch"));
    say(@"git log, with --no-ext-diff --no-textconv", bash(@"git log --no-ext-diff --no-textconv --oneline -n20"));
    say(@"git diff, with them, of a file", bash(@"git diff --no-ext-diff --no-textconv HEAD~1 -- src/two.txt"));
    say(@"git show, with them, a format and a quoted search",
        bash(@"git show --no-ext-diff --no-textconv --stat --format=%h%x20%s HEAD"));
    say(@"git log, a single-quoted word", bash(@"git log --no-ext-diff --no-textconv '--grep=fix the cart'"));
    say(@"git diff without --no-ext-diff --no-textconv", bash(@"git diff"));
    say(@"…with them only after --", bash(@"git log -- --no-ext-diff --no-textconv"));
    say(@"git diff --output", bash(@"git diff --no-ext-diff --no-textconv --output=../written.txt"));
    say(@"…--output in single quotes", bash(@"git diff --no-ext-diff --no-textconv '--output=written.txt'"));
    say(@"…--ext-diff", bash(@"git diff --ext-diff --no-ext-diff --no-textconv"));
    say(@"…--textconv", bash(@"git log -p --textconv --no-ext-diff --no-textconv"));
    say(@"…--show-signature", bash(@"git log --show-signature --no-ext-diff --no-textconv"));
    say(@"…a format asking for the signature", bash(@"git log --no-ext-diff --no-textconv --format=%GS"));
    say(@"…--no-index", bash(@"git diff --no-ext-diff --no-textconv --no-index one.txt src/two.txt"));
    say(@"…a file from the top of the disk", bash(@"git diff --no-ext-diff --no-textconv /dev/null one.txt"));
    say(@"…from the home folder", bash(@"git diff --no-ext-diff --no-textconv ~/.netrc one.txt"));
    say(@"…above the folder", bash(@"git diff --no-ext-diff --no-textconv ../outside/notes.txt"));
    say(@"…a file above it at a commit", bash(@"git show --no-ext-diff --no-textconv HEAD:../outside/notes.txt"));
    say(@"…a file named as keys are, at a commit or as a path",
        @[bash(@"git show --no-ext-diff --no-textconv HEAD:.env"),
          bash(@"git diff --no-ext-diff --no-textconv prod.env one.txt")]);
    say(@"…MCP settings, at a commit or as a path",
        @[bash(@"git show --no-ext-diff --no-textconv HEAD:.mcp.json"),
          bash(@"git log --no-ext-diff --no-textconv -p -- .cursor/mcp.json")]);
    say(@"…a commit whose patch holds the MCP settings the project keeps, and the history that holds it",
        @[bash(@"git show --no-ext-diff --no-textconv HEAD~1"), bash(@"git log -p --no-ext-diff --no-textconv")]);
    say(@"…the commit after it, that history for one file, the history's names, and the first commit's",
        @[bash(@"git show --no-ext-diff --no-textconv HEAD") ?: NSNull.null,
          bash(@"git log -p --no-ext-diff --no-textconv -- src/two.txt") ?: NSNull.null,
          bash(@"git log --no-ext-diff --no-textconv --stat") ?: NSNull.null,
          bash(@"git show --no-ext-diff --no-textconv --name-only HEAD~1") ?: NSNull.null]);
    say(@"…a pattern, which git takes as the one file it names",
        bash(@"git log -p --no-ext-diff --no-textconv -- '*.json'") ?: NSNull.null);
    NSData *blobId = RunGit(@[@"-C", project, @"rev-parse", @"HEAD:.mcp.json"])[@"out"];
    NSString *blob = [[[NSString alloc] initWithData:blobId ?: NSData.data encoding:NSUTF8StringEncoding]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    say(@"…a file's contents by its id, as a patch's index line gives it, and a folder by its",
        @[bash([@"git show --no-ext-diff --no-textconv " stringByAppendingString:blob]),
          bash(@"git show --no-ext-diff --no-textconv HEAD^{tree}")]);
    say(@"…a folder at a commit, which git diff prints whole: between two commits, beside the working files, and shown",
        @[bash(@"git diff --no-ext-diff --no-textconv HEAD~1: HEAD:") ?: NSNull.null,
          bash(@"git diff --no-ext-diff --no-textconv HEAD:") ?: NSNull.null,
          bash(@"git show --no-ext-diff --no-textconv HEAD:src") ?: NSNull.null]);
    say(@"…a file at a commit: MCP settings, shown or compared; and one that isn't a key's, shown and compared",
        @[bash(@"git show --no-ext-diff --no-textconv HEAD:.mcp.json") ?: NSNull.null,
          bash(@"git diff --no-ext-diff --no-textconv HEAD~1:.mcp.json HEAD:one.txt") ?: NSNull.null,
          bash(@"git show --no-ext-diff --no-textconv HEAD:one.txt") ?: NSNull.null,
          bash(@"git diff --no-ext-diff --no-textconv HEAD~1:src/two.txt HEAD:src/two.txt") ?: NSNull.null]);
    say(@"…braces the shell would turn into options",
        bash(@"git log --no-ext-diff --no-textconv {--output=x,--stat}"));
    say(@"…a ~ the shell would turn into the home folder", bash(@"git log --no-ext-diff --no-textconv --author=~"));
    say(@"git -C, an option before the command", bash(@"git -C .. status"));
    say(@"git -c", bash(@"git -c core.pager=less log --no-ext-diff --no-textconv"));
    say(@"another git command", bash(@"git checkout one.txt"));
    say(@"a second command after it", bash(@"git status; rm one.txt"));
    say(@"…on a line of its own", bash(@"git status\nrm one.txt"));
    say(@"…piped", bash(@"git log --no-ext-diff --no-textconv | sh"));
    say(@"a variable", bash(@"git log --no-ext-diff --no-textconv $HOME"));
    say(@"a setting before git", bash(@"GIT_DIR=../outside git status"));
    say(@"another program", bash(@"cat one.txt"));
    say(@"git status, in the background", may(kClaudeToolBash, @{kClaudeToolCommand: @"git status",
                                                                kClaudeToolInBackground: @YES}));
    say(@"A session started in the home folder: reads nothing", AsideToolWhyNot(kClaudeToolRead, @{
        kClaudeToolFilePath: [project stringByAppendingPathComponent:@"one.txt"]}, home, home, keys));
    say(@"…nor git there", AsideToolWhyNot(kClaudeToolBash, @{kClaudeToolCommand: @"git status"}, home, home, keys));
    say(@"A session in a folder inside a checkout, or in none: no git, as it would read the whole checkout or any file",
        AsideToolWhyNot(kClaudeToolBash, @{kClaudeToolCommand: @"git status"},
                        [project stringByAppendingPathComponent:@"src"], home, keys));
    NSString *src = [project stringByAppendingPathComponent:@"src"];
    say(@"…but the checkout's .gitignore holds there: a file it ignores, and one beside it", @[
        AsideToolWhyNot(kClaudeToolRead, @{kClaudeToolFilePath: @"deploy_token"}, src, home, keys) ?: NSNull.null,
        AsideToolWhyNot(kClaudeToolRead, @{kClaudeToolFilePath: @"two.txt"}, src, home, keys) ?: NSNull.null]);
    say(@"…a folder in no checkout, where nothing is ignored", AsideToolWhyNot(kClaudeToolRead, @{
        kClaudeToolFilePath: @"notes.txt"}, [home stringByAppendingPathComponent:@"outside"], home, keys));
    say(@"A folder that isn't there", AsideToolWhyNot(kClaudeToolRead, @{
        kClaudeToolFilePath: @"one.txt"}, [home stringByAppendingPathComponent:@"gone"], home, keys));
    say(@"Where keys are kept, wherever the folder is", @[@(AsideKeyFile([home stringByAppendingPathComponent:
        @".ssh/id_ed25519"], home, keys)), @(AsideKeyFile([home stringByAppendingPathComponent:kClaudeCodeState], home,
        keys)), @(AsideKeyFile([claude stringByAppendingPathComponent:kClaudeCodeLocalSettings], home, keys)),
        @(AsideKeyFile([claude stringByAppendingPathComponent:@"notes.json"], home, keys)),
        @(AsideKeyFile([project stringByAppendingPathComponent:@"one.txt"], home, keys))]);
    say(@"…and every other place in the home folder Keys knows: Docker's sign-ins, Kubernetes', Codex's, GnuPG's, a "
        "shell's settings", @[@(AsideKeyFile([home stringByAppendingPathComponent:@".docker/config.json"], home, keys)),
        @(AsideKeyFile([home stringByAppendingPathComponent:@".kube/config"], home, keys)),
        @(AsideKeyFile([home stringByAppendingPathComponent:@".codex/auth.json"], home, keys)),
        @(AsideKeyFile([home stringByAppendingPathComponent:@".gnupg/private-keys-v1.d"], home, keys)),
        @(AsideKeyFile([home stringByAppendingPathComponent:@".zshrc"], home, keys))]);
    say(@"Without Keys' list: every file counts, and nothing is read or run",
        @[@(AsideKeyFile([project stringByAppendingPathComponent:@"one.txt"], home, nil)),
          AsideToolWhyNot(kClaudeToolRead, @{kClaudeToolFilePath: @"one.txt"}, project, home, nil),
          AsideToolWhyNot(kClaudeToolBash, @{kClaudeToolCommand: @"git status"}, project, home, nil)]);
    NSData *(^call)(NSString *, NSDictionary *) = ^NSData *(NSString *tool, NSDictionary *input) {
        return [NSJSONSerialization dataWithJSONObject:@{kClaudeHookToolName: tool, kClaudeHookToolInput: input,
                                                        @"session_id": session} options:0 error:nil];
    };
    say(@"The checker's answer to the hook: a read it may make", AsideCheck(project, call(kClaudeToolRead,
        @{kClaudeToolFilePath: [project stringByAppendingPathComponent:@"one.txt"]}), home, keys));
    say(@"…one it may not", AsideCheck(project, call(kClaudeToolRead,
        @{kClaudeToolFilePath: [outside stringByAppendingPathComponent:@"notes.txt"]}), home, keys));
    say(@"…a call it can't read", AsideCheck(project, [@"not json" dataUsingEncoding:NSUTF8StringEncoding], home,
        keys));
    say(@"…none", AsideCheck(project, nil, home, keys));

    printf("\n== Kept for follow-ups\n");
    NSDictionary *opened = @{@"size": @48213, @"at": @2000000000000};
    say(@"The session as it was when the copy opened: asked in it", @(ClaudeAsideMoved(opened,
        @{@"size": @48213, @"at": @2000000000000})));
    say(@"…a step since (its transcript grew): a fresh copy", @(ClaudeAsideMoved(opened,
        @{@"size": @51840, @"at": @2000000000000})));
    say(@"…a newer message: a fresh copy", @(ClaudeAsideMoved(opened, @{@"size": @48213, @"at": @2000000060000})));
    say(@"…not known as it opened, or now: a fresh copy", @[@(ClaudeAsideMoved(nil, opened)),
                                                           @(ClaudeAsideMoved(opened, nil))]);
    NSDictionary *open = @{@"busy": @NO, @"started": @2000000000123, @"model": @"claude-opus-5-5[1m]",
                           @"effort": @"high", @"mark": opened};
    NSDictionary *(^with)(NSDictionary *, NSDictionary *) = ^NSDictionary *(NSDictionary *given,
                                                                            NSDictionary *changed) {
        NSMutableDictionary *merged = [given mutableCopy];
        [merged addEntriesFromDictionary:changed];
        return merged;
    };
    NSDictionary *(^now)(NSDictionary *) = ^NSDictionary *(NSDictionary *changed) {
        return with(@{@"started": @2000000000123, @"model": @"claude-opus-5-5[1m]", @"effort": @"high",
                      @"mark": opened}, changed);
    };
    say(@"A follow-up into the open copy: waiting, its own process, the same model and effort, the session still",
        @(ClaudeAsideReuses(open, now(@{}))));
    say(@"…a fresh copy when it's still answering, its process ended or replaced, the model or effort changed, or the "
        @"session moved", @[@(ClaudeAsideReuses(with(open, @{@"busy": @YES}), now(@{}))),
                           @(ClaudeAsideReuses(open, now(@{@"started": @0}))),
                           @(ClaudeAsideReuses(open, now(@{@"started": @2000000000999}))),
                           @(ClaudeAsideReuses(open, now(@{@"model": @"claude-sonnet-5-5"}))),
                           @(ClaudeAsideReuses(open, now(@{@"effort": @"low"}))),
                           @(ClaudeAsideReuses(open, now(@{@"mark": @{@"size": @51840, @"at": @2000000000000}})))]);
    say(@"…a copy whose process was never told: a fresh copy",
        @(ClaudeAsideReuses(with(open, @{@"started": @0}), now(@{@"started": @0}))));
    NSArray *earlier = @[@{@"question": @"Why the cart?", @"text": @"Because it holds the order.",
                           @"at": @2000000000000},
                         @{@"question": @"And the queue?", @"text": @"It waits for the cart.", @"at": @2000000100000},
                         @{@"question": @"Which file?", @"text": @"src/cart.js.", @"at": @2000000200000}];
    say(@"The earlier side questions a fresh copy is told: all, the session never compacted",
        [ClaudeAsideCarried(earlier, 0) valueForKey:@"question"]);
    say(@"…only those since it compacted", [ClaudeAsideCarried(earlier, 2000000050000) valueForKey:@"question"]);
    say(@"…none, once it compacted after them all",
        [ClaudeAsideCarried(earlier, 2000000300000) valueForKey:@"question"]);
    NSString *longAnswer = [@"" stringByPaddingToLength:15000 withString:@"word " startingAtIndex:0];
    NSArray *wordy = @[@{@"question": @"First?", @"text": longAnswer, @"at": @2000000000000},
                       @{@"question": @"Second?", @"text": longAnswer, @"at": @2000000100000},
                       @{@"question": @"Third?", @"text": @"Short.", @"at": @2000000200000}];
    say(@"…the newest that fit in a few thousand words", [ClaudeAsideCarried(wordy, 0) valueForKey:@"question"]);
    say(@"A fresh copy's first message", ClaudeAsideWords(@"Is the cart saved?", ClaudeAsideCarried(earlier, 0), YES));
    say(@"…with nothing earlier", ClaudeAsideWords(@"Is the cart saved?", @[], YES));
    say(@"A follow-up into the open copy", ClaudeAsideWords(@"Is the cart saved?", earlier, NO));
    NSDictionary *environment = ClaudeAsideEnvironment(@{@"PATH": @"/usr/bin:/bin", @"HOME": home},
                                                       @"/Applications/Whozmove.app/Contents/MacOS/Whozmove", project);
    say(@"Its environment", environment);
    say(@"Without Apple's developer tools: no git", ClaudeAsideArguments(session, nil, nil, NO));

    printf("\n== A kept conversation, with a stand-in that answers each line it's sent\n");
    NSString *standIn = [home stringByAppendingPathComponent:@"answers.sh"];
    [@"#!/bin/sh\nn=0\nwhile IFS= read -r line; do n=$((n + 1)); echo \"{\\\"answer\\\":$n,\\\"pid\\\":$$}\"; done\n"
        writeToFile:standIn atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [files setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:standIn error:nil];
    NSMutableArray *answers = [NSMutableArray array];
    __block int asked = 1;
    NSDictionary *ran = RunConversationOn(standIn, @[], @{@"PATH": @"/usr/bin:/bin"}, home,
                                          [@"first\n" dataUsingEncoding:NSUTF8StringEncoding], ^BOOL(NSData *each) {
        NSDictionary *answer = [NSJSONSerialization JSONObjectWithData:each options:0 error:nil];
        if (answer) [answers addObject:answer];
        return answer != nil;
    }, 10, nil, ^NSData * {
        return asked++ < 3 ? [@"again\n" dataUsingEncoding:NSUTF8StringEncoding] : nil;
    });
    NSSet *pids = [NSSet setWithArray:[answers valueForKey:@"pid"]];
    say(@"Three lines sent, one after each answer: its answers, all from one process",
        @[[answers valueForKey:@"answer"], @(pids.count)]);
    say(@"…then its input closed, and it ended by itself", @[ran[@"status"] ?: NSNull.null, ran[@"timedOut"] ?: @NO]);
    [files removeItemAtPath:standIn error:nil];
    for (NSString *name in @[@"shop", @"outside", @".ssh", kClaudeCodeState, @".netrc"])
        [files removeItemAtPath:[home stringByAppendingPathComponent:name] error:nil];
    [files removeItemAtPath:[claude stringByAppendingPathComponent:kClaudeCodeLocalSettings] error:nil];

    printf("\n== Asked, with stand-ins for Claude Code that take or turn down its thinking's summaries\n");
    NSString *stands = [home stringByAppendingPathComponent:@"aside-stand-ins"];
    NSString *folder = [stands stringByAppendingPathComponent:@"project"];
    [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    // What it writes for each question: with the flag, its thinking's summary; without, the thinking's words empty.
    NSString *(^frames)(NSString *) = ^NSString *(NSString *thinking) {
        NSArray *each = @[@{@"type": @"system", @"subtype": @"init"},
                          said(@[@{@"type": @"thinking", @"thinking": thinking, @"signature": @"c2lnbg=="}]),
                          said(@[@{@"type": @"tool_use", @"id": @"toolu_1", @"name": kClaudeToolRead,
                                   @"input": @{kClaudeToolFilePath: [folder stringByAppendingPathComponent:@"cart.ts"]}}]),
                          @{@"type": @"user", @"message": @{@"content": @[@{@"type": @"tool_result",
                                                                             @"tool_use_id": @"toolu_1",
                                                                             @"content": @"export const cart"}]}},
                          said(@[@{@"type": @"text", @"text": @"It holds the cart."}]),
                          @{@"type": @"result", @"subtype": @"success", @"is_error": @NO,
                            @"result": @"It holds the cart."}];
        NSMutableString *out = [NSMutableString string];
        for (id frame in each)
            [out appendFormat:@"%@\n", [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:frame
                                                                                                       options:0
                                                                                                         error:nil]
                                                             encoding:NSUTF8StringEncoding]];
        return out;
    };
    // A stand-in that notes each run (whether it was given the flag, or turned it down), as Claude Code's version
    // named by where it is.
    NSString *(^standInAt)(NSString *, BOOL) = ^NSString *(NSString *where, BOOL refuses) {
        NSString *path = [stands stringByAppendingPathComponent:where];
        [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                          attributes:nil error:nil];
        NSString *script = [NSString stringWithFormat:@"#!/bin/sh\nflag=\nfor word in \"$@\"; do\n"
            "  if [ \"$word\" = \"%@\" ]; then\n"
            "    if [ %d = 1 ]; then echo 'turned it down' >> \"$0.runs\"; "
            "echo \"error: unknown option '%@'\" >&2; exit 1; fi\n"
            "    flag=1\n  fi\ndone\n"
            "if [ -n \"$flag\" ]; then echo 'with the flag' >> \"$0.runs\"; else echo 'without' >> \"$0.runs\"; fi\n"
            "while IFS= read -r line; do\n"
            "  if [ -n \"$flag\" ]; then cat \"$0.summaries\"; else cat \"$0.plain\"; fi\ndone\n",
            ClaudeAsideThinkingArguments().firstObject, refuses ? 1 : 0, ClaudeAsideThinkingArguments().firstObject];
        [script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [files setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:path error:nil];
        [frames(@"**Looking at the cart**\n\nIt adds each line.") writeToFile:[path stringByAppendingString:@".summaries"]
                                                                  atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [frames(@"") writeToFile:[path stringByAppendingString:@".plain"] atomically:YES encoding:NSUTF8StringEncoding
                           error:nil];
        return path;
    };
    NSArray *(^runs)(NSString *) = ^NSArray *(NSString *standIn) {
        NSString *noted = [NSString stringWithContentsOfFile:[standIn stringByAppendingString:@".runs"]
                                                    encoding:NSUTF8StringEncoding error:nil] ?: @"";
        return [[noted stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]
                componentsSeparatedByString:@"\n"];
    };
    // A question asked of a copy, waited for (its steps and its answer), and the copy ended.
    NSArray *(^askOf)(ClaudeAside *, NSString *) = ^NSArray *(ClaudeAside *aside, NSString *sessionId) {
        NSMutableArray *steps = [NSMutableArray array];
        __block NSDictionary *got = nil;
        NSString *askId = [aside ask:@"Why that file?" earlier:@[] running:nil sessionId:sessionId model:nil
                              effort:nil folder:folder mark:nil step:^(NSString *one) { [steps addObject:one]; }
                                done:^(NSDictionary *answer) { got = answer; }];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
        while (askId && !got && until.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        [aside end:sessionId];
        while (aside.openSince.count && until.timeIntervalSinceNow > 0)
            [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return @[steps, got[@"state"] ?: NSNull.null, got[@"text"] ?: NSNull.null];
    };
    NSString *checker = NSBundle.mainBundle.executablePath;
    NSString *turnsDown = standInAt(@"versions/2.1.319", YES);
    ClaudeAside *downs = [[ClaudeAside alloc] initWithChecker:checker program:turnsDown];
    say(@"A checked version that turns the flag down: its steps, and its answer, asked again without it",
        askOf(downs, @"3d0a6c11-5b2e-4f7a-9c41-0e8b7d6f5a21"));
    say(@"…its runs", runs(turnsDown));
    askOf(downs, @"7e4b2f90-1c3d-4a8e-b5f6-2d9c0a1e3b47");
    say(@"…the next question, from then on: without it, at once", runs(turnsDown));
    NSString *takes = standInAt(@"Caskroom/claude-code/2.1.319/claude", NO);
    say(@"A checked version that takes it: its thinking's summary, as a step",
        askOf([[ClaudeAside alloc] initWithChecker:checker program:takes], @"9a1f3e5c-7b2d-4c6e-8f0a-1b3d5e7f9a2c"));
    say(@"…its runs", runs(takes));
    NSString *later = standInAt(@"versions/2.1.999", NO);
    askOf([[ClaudeAside alloc] initWithChecker:checker program:later], @"2c4e6a8b-0d1f-4e3a-9b5c-7d9f1a3c5e7b");
    say(@"A version not checked: never given it", runs(later));
    [files removeItemAtPath:stands error:nil];

    printf("\n== Its process, kept out of Claude Code's registry while it runs\n");
    pid_t me = getpid();
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    [files createDirectoryAtPath:registry withIntermediateDirectories:YES attributes:nil error:nil];
    // Registered as a terminal's, so every reading would take it for one of the session's copies but for the hiding.
    NSDictionary *record = @{@"pid": @(me), @"sessionId": @"s-copy", @"cwd": home, @"entrypoint": @"cli",
                             @"kind": @"interactive", @"status": @"busy", @"startedAt": @(ProcessStartedAt(me) / 1000.0)};
    [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
        writeToFile:[registry stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.json", me]] atomically:YES];
    NSArray<Row *> *(^listed)(void) = ^NSArray<Row *> *(void) { return RunningSessions(nil); };
    say(@"Registered, not a side question: its session, listed, a copy in another terminal",
        @[SessionOfProcess(me) ?: NSNull.null, @(listed().count), @(InAnotherTerminal(@"s-copy", 0))]);
    say(@"…asking the panel in that session's name: the session, and why not",
        @[[AgentIn(core) sessionOfProcess:me] ?: NSNull.null, [AgentIn(core) whyNotAsker:me] ?: NSNull.null]);
    NoteAsideProcess(me, YES);
    say(@"A side question's: none of them", @[SessionOfProcess(me) ?: NSNull.null, @(listed().count),
                                               @(InAnotherTerminal(@"s-copy", 0))]);
    NoteAsideProcess(me, NO);
    say(@"Once it has ended: as before", @[SessionOfProcess(me) ?: NSNull.null, @(listed().count),
                                           @(InAnotherTerminal(@"s-copy", 0))]);
    for (NSString *path in @[[registry stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.json", me]],
                             installed, other, linked])
        [files removeItemAtPath:path error:nil];
    return 0;
}

static int PrintBetweenSteps(void) {
    void (^say)(NSString *, id) = ^(NSString *what, id value) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:value ?: NSNull.null
                                                       options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                         error:nil];
        NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        printf("%s: %s\n", what.UTF8String, line.UTF8String);
    };
    printf("== What the hook is handed\n");
    say(@"one", BetweenStepsHandOut(@[@"Do the smaller migration first."]));
    say(@"two, in the order sent", BetweenStepsHandOut(@[@"Do the smaller migration first.", @"Keep the old table."]));
    say(@"none", BetweenStepsHandOut(@[]));
    printf("\n== Whose hook may take a session's words (the session's process is 500)\n");
    say(@"started by the session's own process", @(BetweenStepsHookOf(500, 1, NO, 500)));
    say(@"under a shell it started", @(BetweenStepsHookOf(600, 500, YES, 500)));
    say(@"under something else it started", @(BetweenStepsHookOf(600, 500, NO, 500)));
    say(@"another session's", @(BetweenStepsHookOf(700, 1, NO, 500)));
    say(@"a tool's process, two levels down", @(BetweenStepsHookOf(800, 600, NO, 500)));
    say(@"no session process", @(BetweenStepsHookOf(500, 1, NO, 0)));

    printf("\n== Taken in, and what Claude wrote after them\n");
    NSString *words = @"Do the smaller migration first.";
    NSString *(^line)(NSDictionary *) = ^NSString *(NSDictionary *entry) {
        return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:entry options:0 error:nil]
                                     encoding:NSUTF8StringEncoding];
    };
    NSDictionary *(^added)(NSString *, NSString *, BOOL) = ^NSDictionary *(NSString *at, NSString *event, BOOL side) {
        return @{@"type": @"attachment", @"isSidechain": @(side), @"timestamp": at,
                 @"attachment": @{@"type": @"hook_additional_context", @"hookEvent": event,
                                  @"content": @[[kBetweenStepsLine stringByAppendingString:words]]}};
    };
    NSDictionary *(^claude)(NSString *, NSString *, NSString *) = ^NSDictionary *(NSString *at, NSString *mid,
                                                                                   NSString *text) {
        return @{@"type": @"assistant", @"timestamp": at,
                 @"message": @{@"id": mid, @"role": @"assistant", @"content": @[@{@"type": @"text", @"text": text}]}};
    };
    NSDictionary *prompt = @{@"type": @"user", @"timestamp": @"2026-01-02T10:00:00.000Z",
                             @"message": @{@"role": @"user", @"content": @"Add a coupon field"}};
    NSDictionary *tool = @{@"type": @"assistant", @"timestamp": @"2026-01-02T10:00:01.000Z",
                           @"message": @{@"id": @"m1", @"content": @[@{@"type": @"tool_use", @"name": @"Bash"}]}};
    NSDictionary *result = @{@"type": @"user", @"timestamp": @"2026-01-02T10:00:03.000Z",
                             @"message": @{@"role": @"user",
                                           @"content": @[@{@"type": @"tool_result", @"content": @"one"}]}};
    NSDictionary *next = @{@"type": @"user", @"timestamp": @"2026-01-02T10:01:00.000Z",
                           @"message": @{@"role": @"user", @"content": @"Now the docs"}};
    NSArray *turn = @[prompt, tool, result, added(@"2026-01-02T10:00:03.100Z", @"PostToolBatch", NO),
                      claude(@"2026-01-02T10:00:04.000Z", @"m2", @"Okay: the smaller migration first."), tool, result,
                      claude(@"2026-01-02T10:00:09.000Z", @"m3", @"Done: the migration runs on its own now.")];
    NSData *(^chunk)(NSArray *) = ^NSData *(NSArray *entries) {
        NSMutableArray *lines = [NSMutableArray array];
        for (NSDictionary *entry in entries) [lines addObject:line(entry)];
        return [[[lines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"]
                dataUsingEncoding:NSUTF8StringEncoding];
    };
    double before = 1767348000000;  // 2026-01-02 10:00:00 UTC
    say(@"between steps, its turn going on", AfterHandedWords(chunk(turn), YES, words, before));
    say(@"…its turn ended: you've sent another prompt since",
        AfterHandedWords(chunk([turn arrayByAddingObject:next]), YES, words, before));
    say(@"…read from its second line, as a part of the file", AfterHandedWords(chunk(turn), NO, words, before));
    say(@"…handed after what the transcript has: not yet", AfterHandedWords(chunk(turn), YES, words, before + 60000));
    say(@"…other words: not these", AfterHandedWords(chunk(turn), YES, @"Keep the old table.", before));
    say(@"taken in as its turn ended (Stop), no reply yet", AfterHandedWords(
        chunk(@[prompt, added(@"2026-01-02T10:00:05.000Z", @"Stop", NO)]), YES, words, before));
    say(@"a sub-agent's: not the session's", AfterHandedWords(
        chunk(@[prompt, added(@"2026-01-02T10:00:05.000Z", @"PostToolBatch", YES)]), YES, words, before));
    say(@"nothing", AfterHandedWords(NSData.data, YES, words, before));
    return 0;
}

// `Whozmove --print-writing-wait <session> <other session> [--times]`: whether the first thing `session` wrote for you
// to read comes back while another session's transcript is still being read, as when the reader asks for it just after
// Whozmove opens and reads every transcript from its start. Both are in $HOME's transcripts: the session's is read
// first, then both are read again, the other's for the first time, and the writing asked for at once. Its name, its
// length and whether it came back before that read was done, then quit; `--times` adds how long each took, on stderr.
static int PrintWritingWait(NSArray<NSString *> *arguments) {
    if (arguments.count < 2) {
        fprintf(stderr, "usage: --print-writing-wait <session> <other session> [--times]\n");
        return 2;
    }
    NSString *sid = arguments[0], *other = arguments[1];
    Transcripts *transcripts = [Transcripts new];
    void (^settle)(BOOL (^)(void)) = ^(BOOL (^waiting)(void)) {
        while (waiting()) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    };
    transcripts.sessionIds = @[sid];
    [transcripts readNew];
    settle(^{ return transcripts.reading; });
    NSDictionary *writing = RowWritings([transcripts stateOf:sid]).firstObject;
    if (!writing) {
        fprintf(stderr, "%s wrote nothing to read in its transcript\n", sid.UTF8String);
        return 1;
    }
    transcripts.sessionIds = @[sid, other];
    CFAbsoluteTime asked = CFAbsoluteTimeGetCurrent();
    [transcripts readNew];
    __block NSDictionary *read = nil;
    __block BOOL whileReading = NO;
    __block CFAbsoluteTime back = 0;
    [transcripts readWriting:writing[@"id"] of:sid done:^(NSDictionary *got) {
        read = got;
        whileReading = transcripts.reading;
        back = CFAbsoluteTimeGetCurrent();
    }];
    settle(^{ return (BOOL)(!read || transcripts.reading); });
    NSString *what = [read[@"text"] isKindOfClass:NSString.class]
        ? [NSString stringWithFormat:@"%lu characters", (unsigned long)[read[@"text"] length]] : read[@"missing"];
    printf("%s: %s, back while %s's transcript was still being read: %s\n", [writing[@"path"] lastPathComponent].UTF8String,
           what.UTF8String, other.UTF8String, whileReading ? "yes" : "no");
    if ([arguments containsObject:@"--times"])
        fprintf(stderr, "the writing back in %.3f s, the transcripts read in %.3f s\n", back - asked,
                CFAbsoluteTimeGetCurrent() - asked);
    return 0;
}

// `Whozmove --print-spent <transcript>`: what a transcript's replies and its sub-agents' (in the folder beside it) used
// today, as the panel counts it (SpentAdd), read three ways that must agree: whole; a line at a time, as reads that
// end between the lines of one reply; and whole again after that, as if the file had been rewritten. As JSON, then quit.
static int PrintSpent(NSArray<NSString *> *arguments) {
    NSString *path = arguments.firstObject;
    if (!path) {
        fprintf(stderr, "usage: --print-spent <transcript>\n");
        return 2;
    }
    double today = StartOfToday();
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    // A file read whole, then a line at a time, then whole again from its start.
    NSDictionary *(^ways)(NSString *) = ^NSDictionary *(NSString *file) {
        NSData *data = [NSData dataWithContentsOfFile:file] ?: NSData.data;
        NSDictionary *whole = SpentAdd(nil, data, data.length, YES, today), *byLine = nil;
        NSUInteger from = 0;
        while (from < data.length) {
            NSRange end = [data rangeOfData:newline options:0 range:NSMakeRange(from, data.length - from)];
            NSUInteger stop = end.location == NSNotFound ? data.length : NSMaxRange(end);
            NSData *line = [data subdataWithRange:NSMakeRange(from, stop - from)];
            byLine = SpentAdd(byLine, line, line.length, from == 0, today);
            from = stop;
        }
        NSDictionary *again = SpentAdd(byLine, data, data.length, YES, today);
        return @{@"whole": whole[@"tokens"], @"lineByLine": byLine[@"tokens"] ?: @0, @"rewritten": again[@"tokens"]};
    };
    NSMutableDictionary *subs = [NSMutableDictionary dictionary], *spentSubs = [NSMutableDictionary dictionary];
    NSString *folder = [[path stringByDeletingPathExtension] stringByAppendingPathComponent:kClaudeCodeSubagents];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]) {
        if (![name.pathExtension isEqualToString:@"jsonl"]) continue;
        NSString *file = [folder stringByAppendingPathComponent:name];
        subs[name] = ways(file);
        NSData *data = [NSData dataWithContentsOfFile:file];
        spentSubs[name] = SpentAdd(nil, data, data.length, YES, today);
    }
    NSData *data = [NSData dataWithContentsOfFile:path] ?: NSData.data;
    NSDictionary *spent = @{@"main": SpentAdd(nil, data, data.length, YES, today), @"subs": spentSubs};
    return PrintJSON(@{@"transcript": ways(path), @"subagents": subs, @"today": @(SpentToday(spent, today))});
}

// `Whozmove --print-trust [--trust <folder>] <folder>…`: whether Claude may work in each folder, as Claude Code's state
// file in $HOME has it, as JSON, then quit. With --trust, it's recorded for that folder first, and the result shows as
// "trusting": null once done, else why not.
static int PrintTrust(NSArray<NSString *> *arguments) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSMutableArray *folders = [arguments mutableCopy];
    NSUInteger at = [folders indexOfObject:@"--trust"];
    if (at != NSNotFound && at + 1 < folders.count) {
        out[@"trusting"] = TrustFolder(folders[at + 1]) ?: NSNull.null;
        [folders removeObjectsInRange:NSMakeRange(at, 2)];
    }
    for (NSString *folder in folders) out[folder] = @(FolderTrusted(folder));
    return PrintJSON(out);
}

// `Whozmove --print-kept`: what would be kept of each running terminal session in $HOME, so its row stays once it ends,
// with a stand-in for the terminal it runs in ("sample"), so it reads the same on every Mac; then which of the sessions
// kept there would be dropped, as their process has gone on to another conversation (`left`) or they've gone
// (`stale`), as JSON, then quit. Nothing is written: a print run keeps nothing. tests/rows.sh checks it.
static int PrintKept(Core *core) {
    ClaudeCode *agent = AgentIn(core);
    NSArray<Row *> *rows = SettledRows(core);
    NSMutableDictionary *keeps = [NSMutableDictionary dictionary];
    for (Row *row in rows) {
        NSDictionary *record = KeptRecord(row, [agent.transcripts stateOf:row.sessionId][@"path"], @"sample");
        if (record) keeps[row.sessionId] = record;
    }
    NSDictionary *kept = KeptIn(KeptFolder());
    return PrintJSON(@{@"keeps": keeps, @"left": LeftBehind(kept, rows),
                       @"stale": Stale(kept, [NSSet setWithArray:keeps.allKeys], NSDate.date.timeIntervalSince1970)});
}

// `Whozmove --print-kept-waits`: which made-up kept sessions have gone (Stale), for one that waits on someone else and
// one that doesn't, at a few ages, and one whose transcript has gone, with their transcripts in the throwaway home it
// runs in; each record's note that it waits as keep: writes it, for ended sessions and a running one, before the rows
// have said and as they say; and KeptNoting's cases; as JSON, then quit.
static int PrintKeptWaits(void) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-kept-waits writes in $HOME: give it a throwaway one\n");
        return 2;
    }
    NSString *transcript = [Home() stringByAppendingPathComponent:@"sample.jsonl"];
    [NSFileManager.defaultManager createFileAtPath:transcript contents:NSData.data attributes:nil];
    double now = 2e9, day = 24 * 3600;
    NSDictionary *(^kept)(double, BOOL, NSString *) = ^NSDictionary *(double days, BOOL waits, NSString *path) {
        NSMutableDictionary *record = [@{@"cwd": @"/tmp/sample", @"transcript": path,
                                         @"activeAt": @((now - days * day) * 1000)} mutableCopy];
        if (waits) record[@"waits"] = @YES;
        return record;
    };
    NSString *gone = [Home() stringByAppendingPathComponent:@"gone.jsonl"];
    NSDictionary *records = @{
        @"a, 2 days, not waiting": kept(2, NO, transcript), @"b, 4 days, not waiting": kept(4, NO, transcript),
        @"c, 4 days, waiting": kept(4, YES, transcript), @"d, 29 days, waiting": kept(29, YES, transcript),
        @"e, 31 days, waiting": kept(31, YES, transcript), @"f, 1 day, waiting, its transcript gone": kept(1, YES, gone),
    };
    // keep: itself, on kept files in the throwaway home: two ended sessions (no process) and one running, with the rows'
    // word on each waiting as `waits` gives it, or none yet (nil).
    NSMutableDictionary *keeps = [NSMutableDictionary dictionary];
    [NSFileManager.defaultManager createDirectoryAtPath:KeptFolder() withIntermediateDirectories:YES attributes:nil
                                                  error:nil];
    for (NSArray *one in @[@[@"e-1", @YES], @[@"e-2", @NO]]) {
        NSMutableDictionary *record = [kept(1, [one[1] boolValue], transcript) mutableCopy];
        record[@"sessionId"] = one[0];
        NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
        [json writeToFile:[KeptFolder() stringByAppendingPathComponent:[one[0] stringByAppendingPathExtension:@"json"]]
               atomically:YES];
    }
    Row *(^row)(NSString *, pid_t) = ^Row *(NSString *sessionId, pid_t pid) {
        Row *made = [Row new];
        made.sessionId = sessionId;
        made.pid = pid;
        made.procStart = @"1";
        made.cwd = @"/tmp/sample";
        made.entrypoint = kClaudeCodeTerminalEntrypoint;
        made.lastReplyAt = @(NSDate.date.timeIntervalSince1970 * 1000);
        return made;
    };
    NSArray<Row *> *rows = @[row(@"e-1", 0), row(@"e-2", 0), row(@"r-1", getpid())];
    KeptSessions *sessions = [KeptSessions new];
    [sessions readNow];
    NSDictionary *(^notes)(void) = ^NSDictionary * {
        [sessions written];
        NSMutableDictionary *now = [NSMutableDictionary dictionary];
        NSDictionary *files = KeptIn(KeptFolder());
        for (NSString *sessionId in @[@"e-1", @"e-2", @"r-1"])
            now[sessionId] = !files[sessionId] ? @"(not kept)" : [files[sessionId][@"waits"] isEqual:@YES] ? @"waits"
                                                                                                         : @"(no note)";
        return now;
    };
    void (^keep)(BOOL (^)(Row *)) = ^(BOOL (^waits)(Row *)) {
        [sessions keep:rows transcriptOf:^NSString *(Row *r) { return transcript; }
            terminalOf:^NSString *(Row *r) { return @"sample"; } waits:waits];
    };
    keep(nil);
    keeps[@"1, the rows not listed yet: every note stays"] = notes();
    keep(^BOOL(Row *r) { return [@[@"e-2", @"r-1"] containsObject:r.sessionId]; });
    keeps[@"2, e-2 and r-1 waiting, e-1 not"] = notes();
    keep(^BOOL(Row *r) { return NO; });
    keeps[@"3, none waiting"] = notes();
    NSDictionary *plain = kept(1, NO, transcript), *noted = KeptNoting(plain, YES);
    return PrintJSON(@{@"gone": Stale(records, [NSSet set], now), @"keep": keeps,
                       @"noted": @{@"a record whose row waits": noted[@"waits"] ?: @"(no note)",
                                   @"…and once it no longer waits": KeptNoting(noted, NO)[@"waits"] ?: @"(no note)",
                                   @"…a note already there, unchanged": @(KeptNoting(noted, YES) == noted)},
                       @"kept for (days)": @{@"waiting": @(kKeptWaitingFor / day), @"not": @(kKeptFor / day)}});
}

// `Whozmove --print-plugin-install [--answer <press>] [--before] <hooks>`: puts the hooks in the folder `hooks` into
// Claude Code as the app does as it opens (ConnectPlugin), with `claude` looked for on $INSTALL_PATH first and in the
// home folder in $HOME, and prints what it reached, as JSON, then quits. `--answer` is your press on the line (addBack,
// turnOn or retry), `--before` that they were put in once already. modules/claude-code/tests/test.sh runs it for each case,
// with a stand-in claude that writes down what it's asked. It changes Whozmove's folder there and runs the `claude` it
// finds, so it refuses to run in your own home folder.
static int PrintPluginInstall(NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-plugin-install changes Claude Code in $HOME: run it with a throwaway HOME, as "
                        "modules/claude-code/tests/test.sh does\n");
        return 2;
    }
    MachineFilesInHome = YES;
    NSMutableArray<NSString *> *rest = [arguments mutableCopy];
    NSString *answer = nil;
    NSUInteger at = [rest indexOfObject:@"--answer"];
    if (at != NSNotFound && at + 1 < rest.count) {
        answer = rest[at + 1];
        [rest removeObjectsInRange:NSMakeRange(at, 2)];
    }
    BOOL before = [rest containsObject:@"--before"];
    [rest removeObject:@"--before"];
    if (rest.count != 1) {
        fprintf(stderr, "usage: --print-plugin-install [--answer addBack|turnOn|retry] [--before] <hooks>\n");
        return 2;
    }
    NSString *path = NSProcessInfo.processInfo.environment[@"INSTALL_PATH"] ?: @"";
    return PrintJSON(ConnectPlugin(answer, before, rest[0], path));
}

// `Whozmove --print-held`: which sample sessions' requests the panel holds (AsksToHold), each second, with you at the
// Mac and away from it, as JSON. tests/rows.sh checks it: a request held while no one's there never goes, and one not
// held while you're answering it in its tab goes from under you, or is answered for you by a session you allow.
static int PrintHeld(void) {
    double now = 1e12;
    NSDictionary *samples = @{
        @"in-its-tab": @[@YES, @(now - 1000)], @"left-its-tab": @[@YES, @(now - 10000)],
        @"waits-on-you": @[@NO, @(now - 1000)], @"never-in-its-tab": @[@YES, NSNull.null],
    };
    NSMutableArray<Row *> *rows = [NSMutableArray array];
    for (NSString *name in samples) {
        Row *row = [Row new];
        row.sessionId = name;
        row.ask = [samples[name][0] boolValue] ? @{@"id": name, @"expiresAt": @(now + 60000)} : @{@"id": name};
        row.seenAt = AsNumber(samples[name][1]);
        [rows addObject:row];
    }
    NSArray *(^held)(NSTimeInterval) = ^(NSTimeInterval idle) {
        return [AsksToHold(rows, now, idle) sortedArrayUsingSelector:@selector(compare:)];
    };
    return PrintJSON(@{@"at the Mac (idle 5s)": held(5), @"away (idle 60s)": held(60)});
}

// `Whozmove --print-hook-line <seconds>`: the panel's end of the permission hook's line, in $HOME's Whozmove folder,
// as the app listens, noted as the panel there (panel.pid), for the hook's tests: each request is answered "deny", and
// once `hook-line.done` is in that folder, or `seconds` have gone, what each connection came to is printed, a line each:
// asked by its session, refused and why (its process doesn't run in the session it names), answered. It changes
// Whozmove's folder in $HOME, so it refuses your own.
static int PrintHookLine(NSArray<NSString *> *arguments) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-hook-line changes Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    [NSFileManager.defaultManager createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    [[NSString stringWithFormat:@"%d", getpid()] writeToFile:AppDir(@"panel.pid") atomically:YES
                                                    encoding:NSUTF8StringEncoding error:nil];
    HookLine *line = [HookLine shared];
    if (![line listenAt:AppDir(@"hook.sock") sessionOf:^NSString *(pid_t pid) { return SessionAbove(pid, NULL); }])
        return 1;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:arguments.firstObject.doubleValue ?: 30];
    NSString *done = AppDir(@"hook-line.done");
    while (until.timeIntervalSinceNow > 0 && ![NSFileManager.defaultManager fileExistsAtPath:done]) {
        for (NSString *askId in line.requests) [line answer:askId with:@{@"behavior": @"deny"}];
        [NSThread sleepForTimeInterval:0.1];
    }
    [line stop];
    for (NSString *told in line.told) printf("%s\n", told.UTF8String);
    return 0;
}

// `Whozmove --print-answer-for <seconds> <its pid> <another process's pid>`: what a session you allow may answer for
// you in a team member's session (May Send Back Plans, May Answer Questions, May Approve Plans), for the module's tests, in a sample home whose stand-in sessions
// (Wren, Bea, Ivy, Rex, Moss and Pip, members, in the project shop; Sol, a member whose seat a session the file doesn't
// name holds, in its workspace; a second session in Wren's workspace, a duplicate; Far, a member in another project;
// Mine, one of yours) each wait on what their real permission hook asked over its line, which this run listens on as
// the panel, noted in panel.pid: a plan, or Moss's, Pip's and Mine's questions (Moss's three: a choice, several picks
// and a number); and Long, one of yours, waits on two, a command and then a plan too long for the panel to show whole. Rex's session was started so it could switch to bypassing permissions; the hooks in Whozmove's
// folder have every part, put in place before the sessions started. Atlas leads the team, its pid given; the other pid is a process the
// registry also names as Atlas's session (its file kept aside, then put back, as anything could write it). Each case,
// what the panel answers; then, with every request's id in `ids.json` by session, it serves ask-panel.sh until
// `answer-for.done` is in Whozmove's folder, and says what came of it. Each request's id is shown as whose it is. It
// changes Whozmove's folder in $HOME, so it refuses your own.
// `Whozmove --print-askers <real> <inner> <other> <twin> <elsewhere> <forger> <usurper> <holder> <tucked> <npm>`: what
// the panel answers processes in the sample home that ask in a session's name, through the asks' own path
// (SessionAsks), with no socket: Real, Claude Code's program (the test's stand-in, WHOZMOVE_STAND_IN_CLAUDE); Inner,
// started from inside Real, its record its own; Other; Twin, its record saying it's Other while Other runs; Elsewhere,
// in another folder, its record saying it's Gone, which Whozmove kept working in shop once it ended; Forger, another
// program, its record saying it's Real. Each asks for a task's answer, the inbox, a message and a ticket. Then Real's
// record is rewritten to say it's another session and Usurper's to say it's Real, and Usurper asks (Real, seen as its
// session's own, still runs); Tucked, another program Holder started, asks with a record of its own; and Npm, a
// stand-in named as Node is, with nothing of Claude Code's in its arguments, as an older Claude Code from npm sets its
// title over them, asks with its record. Then the rule for what a process runs alone, on made-up facts, and the short
// names the system may keep for Claude Code's process. Then what the system's signature says of Forger's program and of
// the stand-in; last, the rule for who speaks for a session alone, on made-up facts.
static int PrintAskers(Core *core, NSArray<NSString *> *arguments) {
    if (arguments.count < 10) return 2;
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-askers reads Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    SettledRows(core);
    NSArray<NSString *> *names = @[@"Real", @"Inner", @"Other", @"Twin", @"Elsewhere", @"Forger"];
    NSArray<NSDictionary *> *asks = @[@{@"ask": @"task-answer", @"id": @"offline"}, @{@"ask": @"inbox"},
                                      @{@"ask": @"message"}, @{@"ask": @"ticket"}];
    ClaudeCode *agent = AgentIn(core);
    for (NSUInteger i = 0; i < names.count; i++) {
        pid_t pid = arguments[i].intValue;
        NSString *sessionId = [agent sessionOfProcess:pid], *why = [agent whyNotAsker:pid];
        printf("%s: its session %s%s%s\n", names[i].UTF8String, (sessionId ?: @"none").UTF8String,
               why ? ", but it can't ask: " : "", (why ?: @"").UTF8String);
        for (NSDictionary *asked in asks) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:asked options:NSJSONWritingSortedKeys error:nil];
            printf("  %s: %s\n", [asked[@"ask"] UTF8String],
                   [core.asks answer:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] from:pid]
                       .UTF8String);
        }
    }
    // Rewritten as a session could its own record, keeping the rest of what it says.
    NSString *(^recordOf)(NSString *) = ^NSString *(NSString *pid) {
        return [ClaudeDir(kClaudeCodeRegistry) stringByAppendingPathComponent:[pid stringByAppendingString:@".json"]];
    };
    void (^says)(NSString *, NSString *) = ^(NSString *pid, NSString *sessionId) {
        NSMutableDictionary *record = [AsRecord(ReadJSON(recordOf(pid))) mutableCopy];
        record[@"sessionId"] = sessionId;
        [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil] writeToFile:recordOf(pid) atomically:YES];
    };
    says(arguments[0], @"s-moved");
    says(arguments[6], @"s-real");
    void (^asking)(NSString *, pid_t) = ^(NSString *name, pid_t pid) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:asks[0] options:NSJSONWritingSortedKeys error:nil];
        printf("%s: %s\n", name.UTF8String,
               [core.asks answer:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] from:pid].UTF8String);
    };
    asking(@"Usurper, its record saying it's Real once Real's says it's another", arguments[6].intValue);
    asking(@"Tucked, inside Holder's session, with a record of its own", arguments[8].intValue);
    asking(@"Npm, Node with its arguments overwritten, with a record of its own", arguments[9].intValue);
    printf("\n== The rule for what a process runs, alone (ClaudeProgramFrom)\n");
    void (^program)(NSString *, NSString *, NSArray *, BOOL, BOOL) =
        ^(NSString *what, NSString *path, NSArray *arguments, BOOL hasRecord, BOOL signedByAnthropic) {
            ClaudeProgram it = ClaudeProgramFrom(path, arguments, hasRecord, signedByAnthropic, @"/work/bin/stand-in");
            printf("%s: %s\n", what.UTF8String, it == ClaudeProgramSigned ? "Claude Code's own build"
                                                 : it == ClaudeProgramByPath ? "an older one from npm" : "neither");
        };
    NSString *node = @"/work/node/bin/node", *entry = @"/work/npm/lib/node_modules/@anthropic-ai/claude-code/cli.js";
    program(@"Node running npm's cli.js", node, @[@"node", entry], NO, NO);
    program(@"Node whose title is over its arguments, with its record", node, @[@"claude"], YES, NO);
    program(@"…without one", node, @[@"claude"], NO, NO);
    program(@"Node, signed or not, is never the signed build", node, @[@"node", @"server.js"], NO, YES);
    NSString *npmBuild = @"/work/npm/claude-code/bin/claude.exe";
    program(@"npm's claude.exe, signed by Anthropic", npmBuild, @[@"claude"], YES, YES);
    program(@"…not signed by Anthropic, its record or not", npmBuild, @[@"claude"], YES, NO);
    program(@"The stand-in, by its path", @"/work/bin/stand-in", @[], NO, NO);
    printf("Short names that may be Claude Code's:");
    for (NSString *name in @[@"claude", @"claude.exe", @"node", @"2.1.316", @"sleep", @"claude-helper"])
        printf(" %s %s;", name.UTF8String, ClaudeProgramMayBe(name, nil) ? "yes" : "no");
    printf("\n");
    for (NSString *which in @[@"Forger", @"Real"]) {
        NSDictionary *signature = RunningSignature(arguments[[names indexOfObject:which]].intValue);
        printf("%s's program: valid %s, identifier %s, team %s, Developer ID %s%s%s\n", which.UTF8String,
               [signature[@"valid"] boolValue] ? "yes" : "no", [signature[@"identifier"] ?: @"none" UTF8String],
               [signature[@"team"] ?: @"none" UTF8String], [signature[@"developerID"] boolValue] ? "yes" : "no",
               signature[@"why"] ? ": " : "", [signature[@"why"] ?: @"" UTF8String]);
    }
    printf("\n== The rule for who speaks for a session, alone (WhyNotSpeakFrom), the asker being 7\n");
    NSDictionary *seen = @{@"pid": @7, @"origin": @"/work/shop", @"folder": @"/work/shop/site"};
    void (^rule)(NSString *, NSString *, NSArray *, NSDictionary *, BOOL, NSString *) =
        ^(NSString *what, NSString *working, NSArray *copies, NSDictionary *was, BOOL runs, NSString *recorded) {
            NSString *why = WhyNotSpeakFrom(7, working, copies, was, runs, recorded, @"Shop");
            printf("%s: %s\n", what.UTF8String, (why ?: @"it may").UTF8String);
        };
    rule(@"Another copy of Claude Code open for it", @"/work/shop", @[@41], seen, YES, nil);
    rule(@"The one seen as its own still runs, and asks", @"/work/elsewhere", @[], seen, YES, nil);
    rule(@"…another asks while it runs", @"/work/shop", @[], @{@"pid": @8, @"origin": @"/work/shop",
                                                               @"folder": @"/work/shop"}, YES, nil);
    rule(@"That one ended: one where it started", @"/work/shop", @[], seen, NO, nil);
    rule(@"…one in a worktree inside where it last was", @"/work/shop/site/.worktrees/fix", @[], seen, NO, nil);
    rule(@"…one elsewhere", @"/work/elsewhere", @[], seen, NO, nil);
    rule(@"…one in a folder whose name only starts the same", @"/work/shop-2", @[], seen, NO, nil);
    rule(@"…one whose folder can't be read", nil, @[], seen, NO, nil);
    rule(@"Not seen since Whozmove started: one where it was kept working", @"/work/shop", @[], nil, NO,
         @"/work/shop");
    rule(@"…with nowhere known", @"/work/shop", @[], nil, NO, nil);
    return 0;
}

// A module whose background waits put a word that isn't a flag after the first, which is never left out.
@interface SampleLooseWaits : NSObject <BackgroundWaits>
@end
@implementation SampleLooseWaits
- (NSArray<NSArray<NSString *> *> *)backgroundWaits {
    return @[@[@"task-answer", @"t1", @"--wait"], @[@"wait", @"-x"], @[@"look", @"--wait"]];
}
@end

// `Whozmove --print-own-waits`: each module's background waits as the agent's module gathers them (BackgroundWaits),
// one a line after "waits:", for the test to run each through ask-panel.sh; then whether each sample command a session
// left running in the background is one of them (ClaudeJobIsOwnWait), which its row doesn't show as a job, with the
// plugin's folder in the throwaway home it runs in, said as <copies> (and the marketplace's folder above it as
// <plugins>) so it reads the same on every run, each recorded just as written but where it says not; and that a
// module's wait with a word after its first that isn't a flag is never left out.
static int PrintOwnWaits(Core *core) {
    KeepOwnWaits([core modulesThat:@protocol(BackgroundWaits)]);
    NSArray<NSArray<NSString *> *> *waits = OwnWaits();
    for (NSArray<NSString *> *wait in waits) printf("waits: %s\n", [wait componentsJoinedByString:@" "].UTF8String);
    NSString *copies = WhozmovePluginCopies();
    NSString *real = [copies stringByAppendingPathComponent:@"0.2.0-abc123/scripts/ask-panel.sh"];
    NSArray<NSString *> *taken = @[
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait --comments",
        @"\"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh\" wait",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh ticket --wait",
        [real stringByAppendingString:@" wait"],
        [NSString stringWithFormat:@"'%@' ticket --wait", real],
    ];
    // A path under the home folder written with ~ for it, as a shell expands it only when it isn't quoted.
    NSString *home = [NSString pathWithComponents:Home().pathComponents];
    NSString *tilde = [real hasPrefix:[home stringByAppendingString:@"/"]]
        ? [@"~" stringByAppendingString:[real substringFromIndex:home.length]] : nil;
    NSMutableArray<NSString *> *refused = [@[
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task-answer passkeys-try --wait",
        [NSString stringWithFormat:@"'%@' task-answer t1 --wait", real],
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task-answer code --wait",
        @"'${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh' wait",
        [copies stringByAppendingString:@"/$X/scripts/ask-panel.sh wait"],
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait; rm -rf build",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait && npm run dev",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait | tee out.txt",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait > out.txt",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait\nnpm run dev",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task-answer $(cat id) --wait",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task-answer `cat id` --wait",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task-answer \"t 1\" --wait",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait &",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh task t1",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh ticket",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait --soon",
        @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh",
        @"sh ${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait",
        @"${OTHER_ROOT}/scripts/ask-panel.sh wait",
        [[copies stringByDeletingLastPathComponent]
         stringByAppendingPathComponent:@"other/0.2.0/scripts/ask-panel.sh wait"],
        [copies stringByAppendingString:@"/../scripts/ask-panel.sh wait"],
        [copies stringByAppendingString:@"/0.2.0-abc123/scripts/other.sh wait"],
        @"npm run dev",
        @"",
    ] mutableCopy];
    if (tilde) [refused addObject:[NSString stringWithFormat:@"\"%@\" wait", tilde]];
    // Each command on one line, its line breaks shown as \n.
    NSString *(^shown)(NSString *) = ^NSString *(NSString *command) {
        return [[[command stringByReplacingOccurrencesOfString:copies withString:@"<copies>"]
                 stringByReplacingOccurrencesOfString:copies.stringByDeletingLastPathComponent withString:@"<plugins>"]
                stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    };
    for (NSString *command in taken)
        printf("its own wait (%s): %s\n", ClaudeJobIsOwnWait(command, YES, copies, waits) ? "yes" : "NO",
               shown(command).UTF8String);
    for (NSString *command in refused)
        printf("not its own (%s): %s\n", ClaudeJobIsOwnWait(command, YES, copies, waits) ? "YES" : "no",
               shown(command).UTF8String);
    // Recorded not just as written (the hook said so): a line break, a tab or a doubled space folded, or a long one
    // cut. "ask-panel.sh" then "ticket --wait" on the next line runs a program named ticket, and its record reads as
    // a wait.
    for (NSString *command in @[@"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh ticket --wait",
                                @"${CLAUDE_PLUGIN_ROOT}/scripts/ask-panel.sh wait"])
        printf("not recorded as written, so not its own (%s): %s\n",
               ClaudeJobIsOwnWait(command, NO, copies, waits) ? "YES" : "no", shown(command).UTF8String);
    printf("with no plugin folder known, its real path: %s\n",
           ClaudeJobIsOwnWait([real stringByAppendingString:@" wait"], YES, nil, waits) ? "YES" : "no");
    KeepOwnWaits(@[[SampleLooseWaits new]]);
    printf("a module's waits with a word after the first that isn't a flag, kept: %lu of 3\n",
           (unsigned long)OwnWaits().count);
    return 0;
}

// `Whozmove --print-program <pid>…`: what each process runs, as the asks take it (ClaudeProgramOf): for the real
// Claude Code run, which checks a real session's program counts and others don't.
static int PrintProgram(NSArray<NSString *> *pids) {
    for (NSString *pid in pids) {
        ClaudeProgram program = ClaudeProgramOf(pid.intValue, nil);
        printf("%s\n", program == ClaudeProgramSigned ? "Claude Code's own build, signed by Anthropic"
                        : program == ClaudeProgramByPath ? "an older Claude Code from npm, run by Node"
                        : "not Claude Code's own program");
    }
    return 0;
}

static int PrintAnswerFor(Core *core, NSArray<NSString *> *arguments) {
    if (arguments.count < 3) return 2;
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-answer-for changes Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:AppDir(nil) withIntermediateDirectories:YES
                      attributes:@{NSFilePosixPermissions: @0700} error:nil];
    [[NSString stringWithFormat:@"%d", getpid()] writeToFile:AppDir(@"panel.pid") atomically:YES
                                                    encoding:NSUTF8StringEncoding error:nil];
    HookLine *line = [HookLine shared];
    line.printing = NO;
    if (![line listenAt:AppDir(@"hook.sock") sessionOf:^NSString *(pid_t pid) { return SessionAbove(pid, NULL); }])
        return 1;
    if (![core.asks listenAt:AppDir(@"ask.sock")]) return 1;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:arguments[0].doubleValue];
    BOOL (^waitFor)(BOOL (^)(void)) = ^BOOL(BOOL (^done)(void)) {
        while (!done() && until.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        return done();
    };
    if (!waitFor(^BOOL { return line.requests.count >= 12; })) {
        fprintf(stderr, "--print-answer-for: the stand-in sessions' requests didn't all come\n");
        return 1;
    }
    pid_t atlasPid = arguments[1].intValue, forged = arguments[2].intValue;
    __block NSDictionary<NSString *, Row *> *byId = nil;
    void (^read)(void) = ^{
        SettledRows(core);
        byId = core.rows.byId;
    };
    read();
    if (!byId[@"s-atlas"] || !byId[@"s-wren"] || !byId[@"s-bea"] || !byId[@"s-moss"] || !byId[@"s-pip"]
        || !byId[@"s-mine"] || !byId[@"s-far"] || !byId[@"s-sol"] || !byId[@"s-twin"]
        || byId[@"s-atlas"].pid != atlasPid) {
        fprintf(stderr, "--print-answer-for needs the stand-in sessions s-atlas (its pid given), s-wren, s-bea, "
                        "s-moss, s-pip, s-mine, s-far, s-sol and s-twin in $HOME\n");
        for (NSString *one in @[@"s-atlas", @"s-wren", @"s-bea", @"s-moss", @"s-pip", @"s-mine", @"s-far", @"s-sol",
                                @"s-twin"])
            if (!byId[one]) fprintf(stderr, "  %s isn't listed\n", one.UTF8String);
        if (byId[@"s-atlas"] && byId[@"s-atlas"].pid != atlasPid)
            fprintf(stderr, "  s-atlas's row follows another process than the one given\n");
        return 2;
    }
    NSMutableDictionary<NSString *, NSString *> *ids = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *hooks = [NSMutableDictionary dictionary];
    for (NSDictionary *request in line.requests.allValues) {
        ids[request[@"sessionId"]] = request[@"id"];
        hooks[request[@"sessionId"]] = request[@"pid"];
    }
    // Each request's id as whose it is, and the sample home as ~, as JSON writes it too, so the output is the same
    // each run.
    NSString *home = Home(), *homeInJSON = [Home() stringByReplacingOccurrencesOfString:@"/" withString:@"\\/"];
    NSString *(^named)(NSString *) = ^NSString *(NSString *said) {
        for (NSString *sessionId in ids)
            said = [said stringByReplacingOccurrencesOfString:ids[sessionId]
                                                   withString:[NSString stringWithFormat:@"<%@'s>", sessionId]];
        said = [said stringByReplacingOccurrencesOfString:homeInJSON withString:@"~"];
        said = [said stringByReplacingOccurrencesOfString:home withString:@"~"];
        return said ?: @"(nothing)";
    };
    void (^say)(NSString *, NSString *) = ^(NSString *what, NSString *said) {
        printf("%s: %s\n", what.UTF8String, named(said).UTF8String);
    };
    NSString *(^ask)(NSDictionary *, pid_t) = ^NSString *(NSDictionary *asked, pid_t pid) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:asked options:0 error:nil];
        return [core.asks answer:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] from:pid];
    };
    NSDictionary *waiting = @{@"ask": @"waiting"};
    NSDictionary *(^back)(NSString *, NSString *) = ^NSDictionary *(NSString *askId, NSString *note) {
        NSString *encoded = [[note dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        return @{@"ask": @"send-back", @"id": askId ?: @"", @"note64": encoded ?: @""};
    };
    NSDictionary *(^reply)(NSString *, NSString *) = ^NSDictionary *(NSString *askId, NSString *answers) {
        NSString *encoded = [[answers dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        return @{@"ask": @"answer", @"id": askId ?: @"", @"answers64": encoded ?: @""};
    };
    NSString *(^turnAnswering)(BOOL) = ^NSString *(BOOL on) {
        return [core.allowed set:kAnswerQuestionsKey for:byId[@"s-atlas"] on:on] ? (on ? @"on" : @"off")
                                                                                 : @"not changed";
    };
    SessionSwitch *sendBack = [core.allowed switchWithKey:kSendBackKey];
    NSString *(^menu)(Row *) = ^NSString *(Row *row) {
        if (sendBack.shown && !sendBack.shown(row)) return @"not in its mode menu";
        BOOL on = [core.allowed isOn:kSendBackKey for:row];
        NSString *why = on || !sendBack.whyNot ? nil : sendBack.whyNot(row);
        return [NSString stringWithFormat:@"%@%@", on ? @"✓ " : why ? @"(greyed) " : @"",
                                          why ?: (on && sendBack.says ? sendBack.says(row) : nil) ?: sendBack.line];
    };
    NSString *(^turn)(NSString *, BOOL) = ^NSString *(NSString *sessionId, BOOL on) {
        return [core.allowed set:kSendBackKey for:byId[sessionId] on:on] ? (on ? @"on" : @"off") : @"not changed";
    };
    NSString *note = @"Split step 2 first, and keep the results in one list.";
    NSString *registered = [Home() stringByAppendingPathComponent:
                            [NSString stringWithFormat:@".claude/sessions/%d.json", forged]];
    NSData *copy = [NSData dataWithContentsOfFile:registered];

    // A process that isn't Claude Code's own program, registered as Atlas's session, isn't a copy of it: it keeps
    // nothing from being turned on.
    say(@"Atlas's mode menu, with another process registered as its session (not Claude Code's)",
        menu(byId[@"s-atlas"]));
    say(@"Turned on then", turn(@"s-atlas", YES));
    say(@"…and off again, so no file can be what turns it on below", turn(@"s-atlas", NO));
    [files removeItemAtPath:registered error:nil];
    read();
    say(@"Atlas's mode menu, once that's gone", menu(byId[@"s-atlas"]));
    say(@"Wren's mode menu (a member)", menu(byId[@"s-wren"]));
    NSString *forgedFile = [AppDir(@"allowed") stringByAppendingPathComponent:@"s-atlas.json"];
    [files createDirectoryAtPath:AppDir(@"allowed") withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:@{kSendBackKey: @{@"at": @1, @"pid": @(atlasPid),
                                                               @"processStart": @(ProcessStartedAt(atlasPid))}}
                                     options:0 error:nil] writeToFile:forgedFile atomically:YES];
    say(@"Atlas asks what's waiting, May Send Back Plans off, with a file written to say it's on",
        ask(waiting, atlasPid));
    [files removeItemAtPath:forgedFile error:nil];
    say(@"Mine asks (May Send Back Plans isn't in its menu)", ask(waiting, byId[@"s-mine"].pid));
    say(@"Turned on", turn(@"s-atlas", YES));
    say(@"Atlas's mode menu then", menu(byId[@"s-atlas"]));
    say(@"…with nothing written in a file", [files fileExistsAtPath:forgedFile] ? @"a file" : @"none");
    HoldAsk(ids[@"s-bea"]);
    say(@"Atlas asks what's waiting, while the user answers Bea's", ask(waiting, atlasPid));
    say(@"It sends back Bea's plan then", ask(back(ids[@"s-bea"], note), atlasPid));
    say(@"It sends back Far's plan (a member in another project)", ask(back(ids[@"s-far"], note), atlasPid));
    say(@"It sends back the plan of a second session in Wren's workspace (a duplicate)",
        ask(back(ids[@"s-twin"], note), atlasPid));
    say(@"It sends back Sol's plan (holding Sol's seat, a session the file doesn't name)",
        ask(back(ids[@"s-sol"], note), atlasPid));
    say(@"It sends back Moss's question", ask(back(ids[@"s-moss"], note), atlasPid));
    say(@"It sends back Wren's plan with no note", ask(back(ids[@"s-wren"], @"  \n"), atlasPid));
    say(@"…with a note too long", ask(back(ids[@"s-wren"], [@"" stringByPaddingToLength:4001 withString:@"x"
                                                                       startingAtIndex:0]), atlasPid));
    say(@"It sends back a plan no one asked", ask(back(@"0123456789abcdef0123456789abcdef", note), atlasPid));
    say(@"It names a plan by something that isn't an id", ask(back(@"../asks", note), atlasPid));
    kill(hooks[@"s-far"].intValue, SIGTERM);
    waitFor(^BOOL { return !line.requests[ids[@"s-far"]]; });
    say(@"It sends back Far's plan once Far's hook has gone", ask(back(ids[@"s-far"], note), atlasPid));
    [copy writeToFile:registered atomically:YES];
    read();
    say(@"The other process registered as Atlas's session asks", ask(back(ids[@"s-wren"], note), forged));
    [files removeItemAtPath:registered error:nil];
    read();
    say(@"A process no session runs asks", ask(back(ids[@"s-wren"], note), 1));

    // May Answer Questions: Moss's questions, "Which index?" (Titles or Text), "Which pages?" (Docs, Blog and Shop,
    // several may be picked) and "How many results?" (a number from 1 to 50).
    NSString *moss = ids[@"s-moss"];
    say(@"Atlas answers Moss's question, May Answer Questions off", ask(reply(moss, @"{}"), atlasPid));
    say(@"May Answer Questions turned on", turnAnswering(YES));
    say(@"It answers Wren's plan", ask(reply(ids[@"s-wren"], @"{\"Which index?\": {\"option\": \"Titles\"}}"),
                                       atlasPid));
    say(@"It answers Moss's question with nothing", ask(reply(moss, @"{}"), atlasPid));
    say(@"…with an option it doesn't have", ask(reply(moss, @"{\"Which index?\": {\"option\": \"Both\"}}"),
                                                atlasPid));
    say(@"…with two options, where one is picked", ask(reply(moss, @"{\"Which index?\": {\"options\": "
                                                                   @"[\"Titles\", \"Text\"]}}"), atlasPid));
    say(@"…with a question it didn't ask", ask(reply(moss, @"{\"Which font?\": {\"option\": \"Titles\"}}"),
                                               atlasPid));
    say(@"…with words that aren't JSON", ask(reply(moss, @"Titles, please"), atlasPid));
    say(@"…with only its first question answered", ask(reply(moss, @"{\"Which index?\": {\"option\": "
                                                                    @"\"Titles\"}}"), atlasPid));
    NSString *(^three)(NSString *) = ^NSString *(NSString *results) {
        return [NSString stringWithFormat:@"{\"Which index?\": {\"option\": \"Titles\"}, \"Which pages?\": "
                                          @"{\"options\": [\"Docs\"]}, \"How many results?\": {\"written\": "
                                          @"\"%@\"}}", results];
    };
    say(@"…with a number past its most", ask(reply(moss, three(@"100")), atlasPid));
    say(@"…with words for its number", ask(reply(moss, three(@"many")), atlasPid));
    say(@"…with a number too big to be one", ask(reply(moss, three(@"1e999")), atlasPid));
    say(@"…with a pick its several-picks question doesn't have", ask(reply(moss,
        @"{\"Which index?\": {\"option\": \"Titles\"}, \"Which pages?\": {\"options\": [\"Docs\", \"Wiki\"]}, "
        @"\"How many results?\": {\"written\": \"20\"}}"), atlasPid));
    say(@"It answers Mine's question (one of the user's own)", ask(reply(ids[@"s-mine"],
        @"{\"Which index?\": {\"option\": \"Titles\"}}"), atlasPid));
    HoldAsk(ids[@"s-pip"]);
    say(@"It answers Pip's question, while the user answers it", ask(reply(ids[@"s-pip"],
        @"{\"Which index?\": {\"option\": \"Titles\"}}"), atlasPid));
    say(@"It sends back Moss's question", ask(back(moss, note), atlasPid));

    // May Approve Plans.
    NSString *ivy = ids[@"s-ivy"], *rex = ids[@"s-rex"];
    NSDictionary *(^approve)(NSString *, NSString *) = ^NSDictionary *(NSString *askId, NSString *digest) {
        return digest ? @{@"ask": @"approve", @"id": askId ?: @"", @"digest": digest}
                      : @{@"ask": @"approve", @"id": askId ?: @""};
    };
    NSString *(^turnApproving)(BOOL) = ^NSString *(BOOL on) {
        return [core.allowed set:kApprovePlansKey for:byId[@"s-atlas"] on:on] ? (on ? @"on" : @"off")
                                                                              : @"not changed";
    };
    NSDictionary *listed = AsRecord([NSJSONSerialization JSONObjectWithData:[ask(waiting, atlasPid)
        dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]);
    say(@"Atlas approves Ivy's plan, with only May Send Back Plans and May Answer Questions on",
        ask(approve(ivy, @"0123456789abcdef"), atlasPid));
    say(@"May Approve Plans turned on", turnApproving(YES));
    listed = AsRecord([NSJSONSerialization JSONObjectWithData:[ask(waiting, atlasPid)
        dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]);
    NSMutableDictionary<NSString *, NSString *> *digests = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in listed[@"waiting"]) {
        if (![entry[@"kind"] isEqual:@"plan"]) continue;
        if (entry[@"digest"]) digests[entry[@"sessionId"]] = entry[@"digest"];
        printf("waiting lists %s's plan: %s%s\n", [entry[@"name"] UTF8String],
               [[entry[@"may"] componentsJoinedByString:@", "] UTF8String],
               entry[@"approveWhyNot"] ? [[@"; approve: " stringByAppendingString:entry[@"approveWhyNot"]]
                                          UTF8String] : "");
    }
    say(@"It approves Ivy's plan with another plan's digest", ask(approve(ivy, @"0123456789abcdef"), atlasPid));
    say(@"…with no digest", ask(approve(ivy, nil), atlasPid));
    say(@"It approves Rex's plan (its session can switch to bypassing permissions)",
        ask(approve(rex, digests[@"s-rex"]), atlasPid));
    say(@"It approves Moss's question", ask(approve(moss, @"0123456789abcdef"), atlasPid));
    say(@"It approves Bea's plan, while the user answers it", ask(approve(ids[@"s-bea"], digests[@"s-bea"]), atlasPid));
    NSString *planFile = AsText(AsRecord(line.requests[ivy][@"input"])[@"planFilePath"]);
    NSString *planText = [NSString stringWithContentsOfFile:planFile encoding:NSUTF8StringEncoding error:nil];
    [@"# Search box, version 3\nText" writeToFile:planFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    say(@"It approves Ivy's plan, its file written again since Claude asked",
        ask(approve(ivy, digests[@"s-ivy"]), atlasPid));
    [planText writeToFile:planFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *hooksFile = [AppDir(@"plugin/hooks") stringByAppendingPathComponent:@"whozmove-claude-permission.py"];
    NSDate *placed = [files attributesOfItemAtPath:hooksFile error:nil].fileModificationDate;
    [files setAttributes:@{NSFileModificationDate: NSDate.date} ofItemAtPath:hooksFile error:nil];
    say(@"It approves Ivy's plan, once the hooks in place are newer than Ivy's session",
        ask(approve(ivy, digests[@"s-ivy"]), atlasPid));
    if (placed) [files setAttributes:@{NSFileModificationDate: placed} ofItemAtPath:hooksFile error:nil];
    // Your press on Approve beside the list (approveShownPlan): what the page is given with a plan first, then the same
    // check as a session's, that the plan wasn't cut short, and that the Mac had input from you just before (made up
    // here). Never counted to Atlas's May Approve Plans, which says one approved below.
    AnswerFor *mine = AgentIn(core).answerFor;
    __block NSTimeInterval idle = 0;
    mine.secondsIdle = ^NSTimeInterval { return idle; };
    NSDictionary *(^given)(NSString *) = ^NSDictionary *(NSString *sid) {
        return [mine approvalOf:PendingAsks()[sid] row:byId[sid]] ?: @{};
    };
    NSString *(^facts)(NSString *) = ^NSString *(NSString *sid) {
        NSDictionary *f = given(sid);
        NSString *why = f[@"approveWhyNot"] ? [@"; can't: " stringByAppendingString:f[@"approveWhyNot"]] : @"";
        return [([f[@"digest"] length] == 16 ? @"its digest" : @"no digest") stringByAppendingString:why];
    };
    say(@"What the page is given with Ivy's plan", facts(@"s-ivy"));
    say(@"…with Rex's", facts(@"s-rex"));
    say(@"…with Moss's question", facts(@"s-moss"));
    say(@"…its digest the one a session you allow is given", [given(@"s-ivy")[@"digest"] isEqual:digests[@"s-ivy"]]
                                                                 ? @"yes" : @"no");
    NSString *(^press)(NSString *, NSString *, NSString *) = ^NSString *(NSString *sid, NSString *askId,
                                                                          NSString *digest) {
        NSDictionary *said = [mine approveShown:@{@"sessionId": sid, @"id": askId ?: @"", @"digest": digest ?: @""}];
        if (said[@"approved"]) return @"approved";
        return [NSString stringWithFormat:@"not: %@%@", said[@"why"] ?: @"?",
                                          [said[@"again"] boolValue] ? @" (a second press may yet)" : @""];
    };
    say(@"You approve Ivy's plan beside the list, shown with another plan's digest",
        press(@"s-ivy", ivy, @"0123456789abcdef"));
    say(@"…shown with none", press(@"s-ivy", ivy, nil));
    say(@"…named as Rex's", press(@"s-rex", ivy, given(@"s-ivy")[@"digest"]));
    say(@"…Rex's (its session can switch to bypassing permissions)",
        press(@"s-rex", rex, given(@"s-rex")[@"digest"]));
    say(@"…Moss's question", press(@"s-moss", moss, @"0123456789abcdef"));
    [@"# Search box, version 3\nText" writeToFile:planFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    say(@"…Ivy's, its file written again since Claude asked", press(@"s-ivy", ivy, given(@"s-ivy")[@"digest"]));
    say(@"…Ivy's ask then tells the page", given(@"s-ivy")[@"approval"][@"why"] ?: @"nothing");
    [planText writeToFile:planFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // The second session in Wren's workspace: not one Atlas may answer for, but your press is yours.
    NSString *twin = ids[@"s-twin"], *twinDigest = given(@"s-twin")[@"digest"];
    idle = 60;
    say(@"…the plan of a second session in Wren's workspace, with no keyboard or mouse use for a minute",
        press(@"s-twin", twin, twinDigest));
    idle = 0;
    say(@"…the same plan", press(@"s-twin", twin, twinDigest));
    say(@"…again", press(@"s-twin", twin, twinDigest));
    // Long's plan, behind Long's command, the request its row shows: never drawn with Approve, and too long to be.
    NSString *longCommand = nil, *longPlan = nil;
    for (NSDictionary *request in line.requests.allValues)
        if ([request[@"sessionId"] isEqual:@"s-long"]) {
            if ([request[@"tool"] isEqual:@"ExitPlanMode"]) longPlan = request[@"id"];
            else longCommand = request[@"id"];
        }
    NSString *longDigest = [mine approvalOf:@{@"id": longPlan ?: @""} row:byId[@"s-long"]][@"digest"];
    say(@"…a plan too long to show whole, behind an older request of its session's",
        press(@"s-long", longPlan, longDigest));
    AnswerAsk(@{@"id": longCommand ?: @"", @"allow": @NO});
    waitFor(^BOOL { return !line.requests[longCommand ?: @""]; });
    say(@"…once that's answered, its row showing the plan", press(@"s-long", longPlan, longDigest));
    NSDictionary *mineSaid = byId[@"s-twin"].answeredFor;
    say(@"Its row then", [NSString stringWithFormat:@"%@ by %@, %@, %@, %@", mineSaid[@"what"], mineSaid[@"by"],
                                                    [mineSaid[@"yours"] boolValue] ? @"yours" : @"not yours",
                                                    mineSaid[@"state"], [mineSaid[@"askId"] isEqual:twin]
                                                        ? @"for that request" : @"for another"]);
    fflush(stdout);

    // An approval from the page: AnswerAsk builds its answers from {allow, answers, message, stop} only, so approvePlan
    // never goes down the line, and the hook drops a bare allow for a plan, its line staying open.
    AnswerAsk(@{@"id": rex ?: @"", @"allow": @YES, @"approvePlan": @YES});
    [NSThread sleepForTimeInterval:1.5];
    say(@"The page answers Rex's plan with allow and approvePlan: a second later, Rex's hook",
        [HookLine shared].requests[rex] ? @"is still on its line" : @"has gone");
    fflush(stdout);

    // ask-panel.sh, from inside Atlas and from outside any session, over the socket; Wren's real hook passes on what
    // it's sent.
    // Ivy has an earlier plan, approved before: the approval to come mustn't settle on it.
    byId[@"s-ivy"].writings = @[@{@"id": @"p1", @"kind": @"plan", @"status": @"approved"}];
    [[NSJSONSerialization dataWithJSONObject:ids options:0 error:nil] writeToFile:AppDir(@"ids.json") atomically:YES];
    [[NSJSONSerialization dataWithJSONObject:digests options:0 error:nil] writeToFile:AppDir(@"digests.json")
                                                                           atomically:YES];
    NSString *done = AppDir(@"answer-for.done");
    waitFor(^BOOL { return [files fileExistsAtPath:done]; });
    say(@"Atlas sends back Wren's plan again", ask(back(ids[@"s-wren"], note), atlasPid));
    read();
    NSDictionary *answered = byId[@"s-wren"].answeredFor;
    say(@"Wren's row then", answered ? [NSString stringWithFormat:@"%@ by %@: %@ (“%@”)", answered[@"what"],
                                                   answered[@"by"], answered[@"note"], answered[@"title"]]
                                     : @"nothing");
    answered = byId[@"s-moss"].answeredFor;
    say(@"Moss's row then", answered ? [NSString stringWithFormat:@"%@ by %@: %@", answered[@"what"], answered[@"by"],
                                                                   answered[@"note"]] : @"nothing");
    // Ivy's approval settles as her transcript's plan result says: not yet, then approved.
    ClaudeCode *agent = nil;
    for (id each in core.modules.all)
        if ([each isKindOfClass:ClaudeCode.class]) agent = each;
    Row *ivyRow = byId[@"s-ivy"];
    ivyRow.writings = @[@{@"id": @"p2", @"kind": @"plan", @"status": @"waiting"},
                        @{@"id": @"p1", @"kind": @"plan", @"status": @"approved"}];
    [agent.answerFor markRows:@[ivyRow]];
    say(@"Ivy's row, before Ivy's plan's result (an earlier plan approved before it)",
        [ivyRow.answeredFor[@"state"] description]);
    ivyRow.writings = @[@{@"id": @"p2", @"kind": @"plan", @"status": @"approved"},
                        @{@"id": @"p1", @"kind": @"plan", @"status": @"approved"}];
    [agent.answerFor markRows:@[ivyRow]];
    say(@"…once it says approved", [NSString stringWithFormat:@"%@ by %@: “%@”, %@, plan %@",
                                    ivyRow.answeredFor[@"what"], ivyRow.answeredFor[@"by"],
                                    ivyRow.answeredFor[@"title"], ivyRow.answeredFor[@"state"],
                                    ivyRow.answeredFor[@"planId"]]);
    SessionSwitch *approving = [core.allowed switchWithKey:kApprovePlansKey];
    say(@"Atlas's May Approve Plans then", approving.says(byId[@"s-atlas"]) ?: approving.line);
    say(@"May Approve Plans turned off", turnApproving(NO));
    say(@"It approves a plan then", ask(approve(ids[@"s-wren"], digests[@"s-wren"]), atlasPid));
    say(@"Atlas's mode menu then", menu(byId[@"s-atlas"]));
    SessionSwitch *answering = [core.allowed switchWithKey:kAnswerQuestionsKey];
    say(@"…and its May Answer Questions",
        answering.says ? answering.says(byId[@"s-atlas"]) ?: answering.line : answering.line);
    say(@"May Send Back Plans turned off", turn(@"s-atlas", NO));
    say(@"Atlas asks what's waiting, with only May Answer Questions on", ask(waiting, atlasPid));
    say(@"It sends back a plan then", ask(back(ids[@"s-bea"], note), atlasPid));
    say(@"May Answer Questions turned off", turnAnswering(NO));
    say(@"Atlas asks what's waiting then", ask(waiting, atlasPid));
    // Whozmove restarts with two of the switches ticked for Atlas's folder (ticked.json in the sample home): they wait
    // for a press, and one notice names them, Atlas and its folder, with no button.
    NSString *shop = RealPath([Home() stringByAppendingPathComponent:@"shop"]);
    NSDictionary *ticked = @{@"at": @1, @"held": @((long long)(NSDate.date.timeIntervalSince1970 * 1000))};
    [[NSJSONSerialization dataWithJSONObject:@{@"workspaces": @{shop: @{kAnswerQuestionsKey: ticked,
                                                                       kApprovePlansKey: ticked}}}
                                     options:0 error:nil] writeToFile:AppDir(@"ticked.json") atomically:YES];
    say(@"Whozmove restarts with May Answer Questions and May Approve Plans ticked on Atlas: waiting",
        [NSString stringWithFormat:@"%ld", (long)[core.allowed keepTickedAt:AppDir(@"ticked.json")]]);
    for (Notice *notice in agent.answerFor.notices)
        say(@"…its notice", [NSString stringWithFormat:@"%@ (soon %@, closes %@, button %@)", notice.text,
                             notice.level == NoticeSoon ? @"yes" : @"no", notice.closes ? @"yes" : @"no",
                             notice.button ?: @"none"]);
    // Your notes on a plan that has stopped asking in the panel, typed into its session as a message on your press
    // (typePlanNotes): the checks, on rows made up here (WhyNotTypePlanNotes); then the press, on Atlas's row made idle
    // with a plan left waiting, refused at each check, its last refusal that no keyboard or mouse use came just before
    // it, so nothing here ever reaches a terminal.
    Row *(^leftRow)(NSString *, NSString *, double) = ^Row *(NSString *status, NSString *planStatus, double typedAt) {
        Row *made = [[Row alloc] initWithFields:@{@"sessionId": @"s-left", @"status": status}];
        made.writings = @[@{@"id": @"tl2", @"kind": @"plan", @"status": planStatus, @"at": @2000},
                          @{@"id": @"tl1", @"kind": @"plan", @"status": @"declined", @"at": @1000}];
        made.lastPromptAt = @(typedAt);
        return made;
    };
    NSString *(^why)(NSString *) = ^NSString *(NSString *said) { return said ?: @"nothing in the way"; };
    say(@"Notes for a plan left waiting, its session idle at its prompt",
        why(WhyNotTypePlanNotes(leftRow(@"idle", @"waiting", 1500), @"tl2", nil)));
    say(@"…at its prompt with a shell command running", why(WhyNotTypePlanNotes(leftRow(@"shell", @"waiting", 0), @"tl2",
                                                                                   nil)));
    say(@"…held at the plan's own prompt", why(WhyNotTypePlanNotes(leftRow(@"waiting", @"waiting", 0), @"tl2", nil)));
    say(@"…at work", why(WhyNotTypePlanNotes(leftRow(@"busy", @"waiting", 0), @"tl2", nil)));
    Row *asking = leftRow(@"idle", @"waiting", 0);
    asking.ask = @{@"id": @"ab12", @"tool": @"Bash"};
    say(@"…a request up in it", why(WhyNotTypePlanNotes(asking, @"tl2", nil)));
    say(@"…one waiting in the panel for it", why(WhyNotTypePlanNotes(leftRow(@"idle", @"waiting", 0), @"tl2",
                                                                        @{@"id": @"ab12"})));
    say(@"…for its older plan", why(WhyNotTypePlanNotes(leftRow(@"idle", @"waiting", 0), @"tl1", nil)));
    say(@"…its plan answered", why(WhyNotTypePlanNotes(leftRow(@"idle", @"approved", 0), @"tl2", nil)));
    say(@"…something typed into it since the plan", why(WhyNotTypePlanNotes(leftRow(@"idle", @"waiting", 2500), @"tl2",
                                                                               nil)));
    say(@"…a session no longer listed", why(WhyNotTypePlanNotes(nil, @"tl2", nil)));
    Row *atlasRow = byId[@"s-atlas"];
    NSString *wasStatus = atlasRow.status;
    NSArray *wasWritings = atlasRow.writings;
    NSNumber *wasPrompt = atlasRow.lastPromptAt;
    NSDictionary *wasAsk = atlasRow.ask;
    atlasRow.status = @"idle";
    atlasRow.ask = nil;
    atlasRow.lastPromptAt = @0;
    atlasRow.writings = @[@{@"id": @"tl2", @"kind": @"plan", @"title": @"Search box", @"status": @"waiting",
                            @"at": @2000}];
    idle = 60;
    NSString *(^typeIn)(NSDictionary *) = ^NSString *(NSDictionary *msg) {
        return [mine typePlanNotes:msg] ?: @"on their way";
    };
    say(@"You send notes on Atlas's plan, none written", typeIn(@{@"sessionId": @"s-atlas", @"planId": @"tl2",
                                                                  @"words": @"  "}));
    say(@"…too long to type in", typeIn(@{@"sessionId": @"s-atlas", @"planId": @"tl2",
                                          @"words": [@"" stringByPaddingToLength:700 withString:@"a" startingAtIndex:0]}));
    say(@"…for a session not listed", typeIn(@{@"sessionId": @"s-gone", @"planId": @"tl2", @"words": @"Split step 2."}));
    say(@"…for another plan", typeIn(@{@"sessionId": @"s-atlas", @"planId": @"tl1", @"words": @"Split step 2."}));
    say(@"…with no keyboard or mouse use for a minute", typeIn(@{@"sessionId": @"s-atlas", @"planId": @"tl2",
                                                                 @"words": @"Split step 2."}));
    NSDictionary *notTyped = atlasRow.answeredFor;
    say(@"Atlas's row then", [NSString stringWithFormat:@"%@ by %@, %@, %@, for %@: %@", notTyped[@"what"],
                              notTyped[@"by"], [notTyped[@"yours"] boolValue] ? @"yours" : @"not yours",
                              notTyped[@"state"], notTyped[@"askId"], notTyped[@"why"]]);
    say(@"…its words in panel.log", [[NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                                  error:nil] containsString:@"Split step 2."]
                                        ? @"yes" : @"no");
    say(@"Claude Code's words that lead them", kClaudeCodePlanChangesWords);
    atlasRow.status = wasStatus;
    atlasRow.writings = wasWritings;
    atlasRow.lastPromptAt = wasPrompt;
    atlasRow.ask = wasAsk;
    [core.asks stop];
    [line stop];
    return 0;
}

// `Whozmove --print-record-how <transcript>`: for each line of a sample transcript, by its uuid, how Keys is told it
// got there (AgentRecords' about:line:): sent (you sent it), read (a tool read or returned it), wrote (Claude wrote
// it), or nobody when it doesn't say. Then quit.
static int PrintRecordHow(NSArray<NSString *> *arguments) {
    if (arguments.count < 1) {
        fprintf(stderr, "usage: --print-record-how <transcript>\n");
        return 2;
    }
    NSString *path = arguments[0];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    for (NSString *each in [text componentsSeparatedByString:@"\n"]) {
        NSData *data = [each dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *line = AsRecord(parsed);
        if (!line) continue;
        NSString *how = AsText(ClaudeRecordAbout(path, line)[@"how"]) ?: @"nobody";
        printf("%s: %s\n", (AsText(line[@"uuid"]) ?: @"?").UTF8String, how.UTF8String);
    }
    return 0;
}

// `Whozmove --print-reads <session> <grown folder> <keep folder> <day before> <day>`: what a session's reads keep
// across restarts, and that going on from it comes to what reading the transcript from its start does. A copy of the
// reader reads the session in $HOME's transcripts, today starting at <day before> (ms since 1970), and keeps what it
// found in <keep folder>, as it does as Whozmove quits. The transcript and each sub-agent's record then grow by what
// its copy in <grown folder> has past its end (keeping the file), and a new sub-agent's record comes; a second copy,
// today starting at <day>, goes on from what was kept, and a third reads it all from its start. As JSON: how much each
// read, whether the two came to the same (but for the edits' version, which counts reads), the kept file with its
// modes, its shape and a fingerprint of what it found (inodes and the home folder left out), the session as the agent
// gives it, why a kept read is read from its start once it or its files change, and which kept reads a prune takes
// away. Then quit. It writes in the home folder, so it refuses to run in your own. modules/claude-code/tests/test.sh
// runs it.
static int PrintReads(NSArray<NSString *> *arguments) {
    if (arguments.count < 5) {
        fprintf(stderr, "usage: --print-reads <session> <grown folder> <keep folder> <day before> <day>\n");
        return 2;
    }
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-reads changes the transcripts in $HOME: give it a throwaway one\n");
        return 2;
    }
    NSString *sid = arguments[0], *grown = arguments[1], *folder = arguments[2];
    double before = arguments[3].doubleValue, day = arguments[4].doubleValue;
    NSFileManager *files = NSFileManager.defaultManager;
    Transcripts *(^copyOf)(double, NSString *) = ^Transcripts *(double start, NSString *keep) {
        Transcripts *transcripts = [Transcripts new];
        transcripts.dayStart = ^double { return start; };
        if (keep) [transcripts keepIn:keep];
        transcripts.sessionIds = @[sid];
        [transcripts readNew];
        while (transcripts.reading) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        return transcripts;
    };
    // Each file grows by what its grown copy has past its end, written onto the same file.
    void (^grow)(NSString *, NSString *) = ^(NSString *path, NSString *from) {
        NSData *more = [NSData dataWithContentsOfFile:from];
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
        off_t size = fd >= 0 ? lseek(fd, 0, SEEK_END) : -1;
        if (size >= 0 && more.length > (NSUInteger)size)
            write(fd, (const char *)more.bytes + size, more.length - (NSUInteger)size);
        if (fd >= 0) close(fd);
    };
    // What a copy's read came to, as it would be kept, with the mode, the last move and the topic, which are read again
    // rather than kept, but for the edits' version, which counts the reads made.
    NSDictionary *(^cameTo)(Transcripts *) = ^NSDictionary *(Transcripts *transcripts) {
        NSDictionary *state = [transcripts stateOf:sid];
        NSMutableDictionary *kept = [KeptRead(state, sid, @"") mutableCopy];
        NSMutableDictionary *found = [kept[@"found"] mutableCopy];
        [found removeObjectForKey:@"editsVersion"];
        for (NSString *part in @[@"mode", @"modeAt", @"messageAt", @"title"]) found[part] = state[part];
        kept[@"found"] = found;
        return kept;
    };
    NSString *keptFile = [folder stringByAppendingPathComponent:[sid stringByAppendingPathExtension:@"json"]];

    Transcripts *first = copyOf(before, folder);
    [first keepNow];
    NSString *path = [first stateOf:sid][@"path"];
    if (!path || ![files fileExistsAtPath:keptFile]) {
        fprintf(stderr, "%s wasn't read and kept\n", sid.UTF8String);
        return 1;
    }
    grow(path, [grown stringByAppendingPathComponent:path.lastPathComponent]);
    NSString *subs = [[path stringByDeletingPathExtension] stringByAppendingPathComponent:kClaudeCodeSubagents];
    NSString *grownSubs = [grown stringByAppendingPathComponent:kClaudeCodeSubagents];
    for (NSString *name in [[files contentsOfDirectoryAtPath:grownSubs error:nil]
                            sortedArrayUsingSelector:@selector(compare:)])
        grow([subs stringByAppendingPathComponent:name], [grownSubs stringByAppendingPathComponent:name]);
    Transcripts *again = copyOf(day, folder), *whole = copyOf(day, nil);
    [again keepNow];

    NSMutableArray *differ = [NSMutableArray array];
    NSDictionary *wentOn = cameTo(again), *fromStart = cameTo(whole);
    for (NSString *part in [NSSet setWithArray:[[wentOn[@"found"] allKeys] arrayByAddingObjectsFromArray:
                                                    [fromStart[@"found"] allKeys]]])
        if (![wentOn[@"found"][part] isEqual:fromStart[@"found"][part]]) [differ addObject:part];
    if (![wentOn[@"files"] isEqual:fromStart[@"files"]]) [differ addObject:@"where each file was read to"];
    [differ sortUsingSelector:@selector(compare:)];

    // The kept file as written, but for what changes from run to run: the files' inodes, and the home folder.
    NSDictionary *kept = AsRecord(ReadJSON(keptFile));
    NSMutableDictionary *shown = [kept mutableCopy], *places = [NSMutableDictionary dictionary];
    NSDictionary *(^place)(NSDictionary *) = ^NSDictionary *(NSDictionary *was) {
        NSMutableDictionary *is = [was mutableCopy];
        is[@"inode"] = @"(its inode)";
        return is;
    };
    places[@"main"] = place(kept[@"files"][@"main"]);
    NSMutableDictionary *subPlaces = [NSMutableDictionary dictionary];
    for (NSString *name in kept[@"files"][@"subs"]) subPlaces[name] = place(kept[@"files"][@"subs"][name]);
    places[@"subs"] = subPlaces;
    shown[@"files"] = places;
    shown[@"path"] = [@"~" stringByAppendingString:[kept[@"path"] substringFromIndex:Home().length]];
    NSString *version = AsText(NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]) ?: @"";
    if ([kept[@"version"] isEqual:version]) shown[@"version"] = @"(this version)";
    // The plan's file is in the home folder too.
    NSData *plain = [NSJSONSerialization dataWithJSONObject:shown options:NSJSONWritingWithoutEscapingSlashes
                                                      error:nil];
    NSString *homeless = [[[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding]
                          stringByReplacingOccurrencesOfString:Home() withString:@"~"];
    NSDictionary *written = AsRecord([NSJSONSerialization JSONObjectWithData:[homeless dataUsingEncoding:
                                                                                  NSUTF8StringEncoding]
                                                                     options:0 error:nil]) ?: shown;
    // What it found, as the fingerprint the module's test holds to the shape: one changes only with the other.
    NSData *found = [NSJSONSerialization dataWithJSONObject:written[@"found"] ?: @{} options:NSJSONWritingSortedKeys
                                                      error:nil];
    NSString *what = [[NSString alloc] initWithData:found ?: NSData.data encoding:NSUTF8StringEncoding];
    NSDictionary *folderAttributes = [files attributesOfItemAtPath:folder error:nil];
    NSDictionary *fileAttributes = [files attributesOfItemAtPath:keptFile error:nil];

    // The session as the agent gives it, from the copy that went on.
    NSDictionary *state = [again stateOf:sid];
    NSMutableDictionary *edits = [NSMutableDictionary dictionary];
    [state[@"edits"] enumerateKeysAndObjectsUsingBlock:^(NSString *file, NSDictionary *edit, BOOL *stop) {
        edits[file.lastPathComponent] = @{@"edits": edit[@"edits"], @"created": edit[@"created"],
                                          @"added": @([edit[@"added"] count]), @"removed": @([edit[@"removed"] count])};
    }];
    NSMutableArray *writings = [NSMutableArray array];
    for (NSDictionary *writing in RowWritings(state)) {
        NSString *at = writing[@"url"] ? [@" at " stringByAppendingString:writing[@"url"]] : @"";
        [writings addObject:[NSString stringWithFormat:@"%@ %@ (%@)%@", writing[@"kind"], writing[@"title"],
                                                       writing[@"status"] ?: @"listed", at]];
    }
    NSDictionary *session = @{@"prs": [[state[@"prs"] allKeys] sortedArrayUsingSelector:@selector(compare:)],
                              @"title": state[@"title"] ?: NSNull.null, @"mode": state[@"mode"] ?: NSNull.null,
                              @"context": state[@"usage"][@"tokens"] ?: NSNull.null,
                              @"spentToday": @(SpentToday(state[@"spent"], day)), @"writings": writings,
                              @"edits": edits, @"changesAllKnown": @(SessionKnown(state, nil))};

    // Why a read starts again from the start once what was kept, or a file it read, isn't as it was.
    NSDictionary *now = KeptReadFilesNow(kept);
    NSMutableDictionary *(^changed)(NSDictionary *, NSArray<NSString *> *, id) =
        ^NSMutableDictionary *(NSDictionary *record, NSArray<NSString *> *keys, id value) {
            NSMutableDictionary *copy = [NSJSONSerialization JSONObjectWithData:
                [NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
                options:NSJSONReadingMutableContainers error:nil];
            NSMutableDictionary *at = copy;
            for (NSString *key in [keys subarrayWithRange:NSMakeRange(0, keys.count - 1)]) at = at[key];
            if (value) at[keys.lastObject] = value;
            else [at removeObjectForKey:keys.lastObject];
            return copy;
        };
    NSString *sub = [[kept[@"files"][@"subs"] allKeys] sortedArrayUsingSelector:@selector(compare:)].firstObject ?: @"";
    NSString *link = [[kept[@"found"][@"prs"] allKeys] sortedArrayUsingSelector:@selector(compare:)].firstObject ?: @"";
    NSString *writing = [[kept[@"found"][@"writings"] allKeys] sortedArrayUsingSelector:@selector(compare:)].firstObject
                        ?: @"";
    NSString *edited = [[kept[@"found"][@"edits"] allKeys] sortedArrayUsingSelector:@selector(compare:)].firstObject
                       ?: @"";
    NSMutableDictionary *drops = [NSMutableDictionary dictionary];
    NSArray *goesOn = @[
        @[@"as kept", kept, now, version],
        @[@"kept in another shape", changed(kept, @[@"shape"], @(kReadsShape - 1)), now, version],
        @[@"kept by another version", kept, now, @"0.0.1"],
        @[@"its transcript replaced", kept, changed(now, @[@"main", @"inode"], @0), version],
        @[@"its transcript shorter", kept, changed(now, @[@"main", @"size"], @1), version],
        @[@"its transcript written over", kept, changed(now, @[@"main", @"mark"], @"0000000000000000"), version],
        @[@"its transcript gone", kept, changed(now, @[@"main"], @{}), version],
        @[@"a sub-agent's record gone", kept, changed(now, @[@"subs", sub], @{}), version],
        @[@"a sub-agent's record replaced", kept, changed(now, @[@"subs", sub, @"inode"], @0), version],
    ];
    for (NSArray *each in goesOn) drops[each[0]] = WhyNotGoOnFrom(each[1], each[2], each[3]) ?: @"goes on";
    NSArray *readsBack = @[
        @[@"as kept", kept],
        @[@"a PR link that isn't https",
          changed(kept, @[@"found", @"prs", link, @"url"], @"http://example.com/pull/7")],
        @[@"a writing's title that isn't text", changed(kept, @[@"found", @"writings", writing, @"title"], @7)],
        @[@"an edit's lines that aren't keys", changed(kept, @[@"found", @"edits", edited, @"added"], @"!")],
        @[@"another session's", changed(kept, @[@"sessionId"], @"0b1c2d3e-0000-4000-8000-000000000000")],
        @[@"its transcript somewhere else", changed(kept, @[@"path"], @"/tmp/elsewhere.jsonl")],
        @[@"a part it doesn't know", changed(kept, @[@"found", @"usage", @"secret"], @"x")],
    ];
    for (NSArray *each in readsBack)
        drops[[@"reads back, " stringByAppendingString:each[0]]] = TakeBackRead(each[1], sid) ? @"goes on"
                                                                   : @"doesn't read back as it should";
    // The mode, the last move and the topic come from the transcript, read back from where the kept read stopped, never
    // from the kept file: what it says of them, or where they were, is refused.
    NSArray *readBack = @[
        @[@"as kept", kept],
        @[@"its mode named", changed(kept, @[@"found", @"mode"], @"bypassPermissions")],
        @[@"its topic's line named", changed(kept, @[@"found", @"lines"], @{@"title": @0})],
    ];
    for (NSArray *each in readBack) {
        NSString *why = nil;
        NSDictionary *state = GoOnFrom(each[1], sid, [again stateOf:sid][@"path"], version, &why);
        drops[[@"read back, " stringByAppendingString:each[0]]] = why ?: [NSString stringWithFormat:
            @"goes on, in %@, about %@", state[@"mode"], state[@"title"] ?: @"no topic"];
    }
    NSMutableDictionary *notPlain = [[again stateOf:sid] mutableCopy];
    drops[@"kept for a session id that isn't plain"] = KeptRead(notPlain, @"../elsewhere", version) ? @"kept"
                                                                                                    : @"not kept";
    // A writing's title shaped like a key: not kept, and what was kept before goes, in a folder of its own.
    NSString *secrets = [folder stringByAppendingString:@"-key-shaped"];
    NSString *secretFile = [secrets stringByAppendingPathComponent:keptFile.lastPathComponent];
    [files createDirectoryAtPath:secrets withIntermediateDirectories:YES attributes:nil error:nil];
    [files copyItemAtPath:keptFile toPath:secretFile error:nil];
    NSMutableDictionary *keyShaped = [notPlain mutableCopy], *titled = [notPlain[@"writings"] mutableCopy];
    NSMutableDictionary *named = [titled[writing] mutableCopy];
    named[@"title"] = @"Rotate sk-samplesamplesamplesample0000";
    titled[writing] = named;
    keyShaped[@"writings"] = titled;
    BOOL keptAnyway = KeepRead(secrets, KeptRead(keyShaped, sid, version));
    drops[@"a writing's title shaped like a key"] = keptAnyway ? @"kept"
        : [files fileExistsAtPath:secretFile] ? @"not kept, what was kept before still there"
                                              : @"not kept, and what was kept before has gone";

    // What a prune takes away, with the session listed, then not: one for a transcript that isn't there, and one not
    // named for a session, always; this session's, once it isn't listed and was kept longer ago than that keeps.
    for (NSString *name in @[@"00000000-0000-4000-8000-000000000000.json", @"not plain.json"])
        [@"{}" writeToFile:[folder stringByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding
                     error:nil];
    NSTimeInterval at = NSDate.date.timeIntervalSince1970;
    NSArray *listed = KeptReadsToDrop(folder, [NSSet setWithObject:sid], at + 4 * 24 * 3600);
    NSArray *unlisted = KeptReadsToDrop(folder, [NSSet set], at + 4 * 24 * 3600);
    NSArray *lately = KeptReadsToDrop(folder, [NSSet set], at);
    NSData *replaced = [NSJSONSerialization dataWithJSONObject:changed(kept, @[@"files", @"main", @"inode"], @0)
                                                       options:0 error:nil];
    [replaced writeToFile:keptFile atomically:NO];
    NSArray *afterReplaced = KeptReadsToDrop(folder, [NSSet setWithObject:sid], at);

    return PrintJSON(@{
        @"read": @{@"before the cut": @(first.bytesRead), @"going on": @(again.bytesRead),
                   @"from its start": @(whole.bytesRead)},
        @"the same as from its start": differ.count ? differ : @YES,
        @"kept": @{@"shape": kept[@"shape"] ?: NSNull.null, @"fingerprint": [NSString stringWithFormat:@"%016llx",
                                                                             HashBytes(what.UTF8String)],
                   @"folder": [NSString stringWithFormat:@"%lo", [folderAttributes[NSFilePosixPermissions] longValue]],
                   @"file": [NSString stringWithFormat:@"%lo", [fileAttributes[NSFilePosixPermissions] longValue]],
                   @"as written": written},
        @"session": session,
        @"why it's read from its start": drops,
        @"pruned": @{@"listed, days later": listed, @"not listed, days later": unlisted, @"not listed, now": lately,
                     @"listed, its transcript another file": afterReplaced},
    });
}

// `Whozmove --print-dont-wait-files`: Don't Wait on Me's files as the app opens, in $HOME's Whozmove folder: s-on's
// with the switch's record, and s-off's without one. Prints the files before and after, and those taken away. It
// changes Whozmove's folder in $HOME, so it refuses your own.
static int PrintDontWaitFiles(Core *core) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-dont-wait-files changes Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *dir in @[@"dont-wait", @"allowed"])
        [files createDirectoryAtPath:AppDir(dir) withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions: @0700} error:nil];
    for (NSString *sessionId in @[@"s-on", @"s-off"]) SetStopsWaiting(sessionId, YES);
    NSData *record = [NSJSONSerialization dataWithJSONObject:@{kDontWaitKey: @{@"at": @1}} options:0 error:nil];
    [record writeToFile:AppDir(@"allowed/s-on.json") atomically:YES];
    NSArray *(^now)(void) = ^NSArray * {
        return [[files contentsOfDirectoryAtPath:AppDir(@"dont-wait") error:nil]
                   sortedArrayUsingSelector:@selector(compare:)];
    };
    NSArray *before = now(), *dropped = [AgentIn(core) dropDontWaitWithoutSwitch];
    return PrintJSON(@{@"before": before, @"taken away": dropped, @"after": now()});
}

// `Whozmove --print-switch-holder <programs> <step>…`: which session holds the answer-for switches kept for its folder,
// by what the system says of each process, for the module's tests, in a sample home whose sessions are stand-in
// processes this run starts. `programs` is a folder of stand-ins (stand-in.c under each name), run as `-c 'sleep 600;
// :'`: `claude` counts as Claude Code's own signed build, `node` is given Claude Code's npm entry, `other` is any
// program. A step is words: `open <session> <folder> [as=<program>] [at=<folder>] [id=<session>] [bypass]` (a session
// starts, registered in Claude Code's registry as working in that folder under $HOME, running in `at` if given, as a
// copy of another conversation with `id`, started so it can bypass permissions), `orphan <session> <folder>` (one
// started by a shell that has exited), `clear <session> <new>` (a /clear: the same process registered as a new
// conversation), `pair <session> <inner> <folder>` (a session whose own commands start another, both stand-in Claude
// Codes working there, the outer one [as=<program>] and, with [unlisted], not in Claude Code's registry), `stops`
// (where the walk up a session's parents stops, in a print run and in the app), `rule` (the rule alone, WhyNotHold, on
// made-up facts), `close <session>` (its process ends, and what it started), `lead <session>` (the team file makes it
// the lead), `tick` and `untick <session>` (your press on all three, on its row), `why <session>` (each switch: on, or
// why not), `notices` (what's said under the header). It refuses your own home.
static int PrintSwitchHolder(Core *core, NSArray<NSString *> *arguments) {
    if (arguments.count < 1) return 2;
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-switch-holder changes Whozmove's folder in $HOME: give it a throwaway one\n");
        return 2;
    }
    NSString *programs = arguments[0];
    AnswerFor *answerFor = AgentIn(core).answerFor;
    NSArray<NSString *> *keys = @[kSendBackKey, kAnswerQuestionsKey, kApprovePlansKey];
    // Each session's stand-in by its pid, an orphan's too.
    NSMutableDictionary<NSString *, NSNumber *> *running = [NSMutableDictionary dictionary];
    // A stand-in started through the app's one way of starting programs (Processes.m): a shell that moves into `folder`
    // and becomes the stand-in, so the system says it works there and its parent is this run. Its pid, or 0.
    pid_t (^start)(NSString *, NSArray<NSString *> *, NSString *) = ^pid_t(NSString *program, NSArray<NSString *> *words,
                                                                         NSString *folder) {
        NSMutableArray<NSString *> *line = [@[@"cd", ShellWord(folder), @"&&", @"exec", ShellWord(program)] mutableCopy];
        for (NSString *word in words) [line addObject:ShellWord(word)];
        return SpawnDetached(@"/bin/sh", @[@"-c", [line componentsJoinedByString:@" "]], nil, nil, nil);
    };
    void (^stop)(pid_t) = ^(pid_t pid) {
        if (kill(pid, SIGTERM) == 0)
            for (int i = 0; i < 50 && ProcessAlive(pid); i++) [NSThread sleepForTimeInterval:0.1];
    };
    NSTimeInterval leads = 0;
    NSString *registry = ClaudeDir(kClaudeCodeRegistry);
    [NSFileManager.defaultManager createDirectoryAtPath:registry withIntermediateDirectories:YES attributes:nil error:nil];
    void (^registered)(pid_t, NSString *, NSString *) = ^(pid_t pid, NSString *sessionId, NSString *folder) {
        NSNumber *started = @(ProcessStartedAt(pid) / 1000);
        NSDictionary *record = @{@"pid": @(pid), @"sessionId": sessionId, @"name": sessionId, @"kind": @"interactive",
                                 @"entrypoint": @"cli", @"cwd": folder, @"status": @"idle", @"startedAt": started,
                                 @"statusUpdatedAt": started};
        [[NSJSONSerialization dataWithJSONObject:record options:0 error:nil]
            writeToFile:[registry stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.json", pid]]
             atomically:YES];
    };
    __block NSDictionary<NSString *, Row *> *byId = @{};
    void (^read)(void) = ^{
        SettledRows(core);
        byId = core.rows.byId;
        [answerFor forgetHolds];
    };
    for (NSString *step in [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]) {
        NSArray<NSString *> *w = [step componentsSeparatedByString:@" "];
        NSString *what = w[0], *which = w.count > 1 ? w[1] : nil;
        printf("> %s\n", step.UTF8String);
        if ([what isEqual:@"open"] && w.count >= 3) {
            NSString *folder = [Home() stringByAppendingPathComponent:w[2]], *at = folder, *program = @"claude";
            NSString *sessionId = which;
            for (NSString *word in w) {
                if ([word hasPrefix:@"as="]) program = [word substringFromIndex:3];
                if ([word hasPrefix:@"at="]) at = [Home() stringByAppendingPathComponent:[word substringFromIndex:3]];
                if ([word hasPrefix:@"id="]) sessionId = [word substringFromIndex:3];
            }
            [NSFileManager.defaultManager createDirectoryAtPath:at withIntermediateDirectories:YES attributes:nil
                                                           error:nil];
            NSMutableArray *words = [@[@"-c", @"sleep 600; :", [w containsObject:@"bypass"]
                                       ? @"--dangerously-skip-permissions" : @"stand-in"] mutableCopy];
            if ([program isEqual:@"node"])
                [words addObject:[@"/lib/node_modules/" stringByAppendingString:kClaudeCodeNodeEntry]];
            pid_t pid = start([programs stringByAppendingPathComponent:program], words, at);
            if (pid <= 0) {
                fprintf(stderr, "couldn't start %s\n", program.UTF8String);
                return 1;
            }
            // Until the shell has become the stand-in, its process is still the shell's, working wherever this run
            // does.
            for (int i = 0; i < 50 && ![ProcessPath(pid).lastPathComponent isEqual:program]; i++)
                [NSThread sleepForTimeInterval:0.02];
            running[which] = @(pid);
            registered(pid, sessionId, folder);
            read();
        } else if ([what isEqual:@"orphan"] && w.count >= 3) {
            // Started by a shell that has exited by the time it's checked, so its parent is the system's own.
            NSString *folder = [Home() stringByAppendingPathComponent:w[2]];
            NSString *line = [NSString stringWithFormat:@"cd '%@' || exit 1; '%@' -c 'sleep 600; :' stand-in >/dev/null "
                                                        @"2>&1 & echo $!", folder,
                                                        [programs stringByAppendingPathComponent:@"claude"]];
            NSDictionary *ran = RunTool(@"/bin/sh", @[@"-c", line], nil);
            NSString *said = [[NSString alloc] initWithData:ran[@"out"] ?: NSData.data encoding:NSUTF8StringEncoding];
            pid_t pid = [said stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].intValue;
            if (pid <= 0) {
                fprintf(stderr, "couldn't start %s\n", which.UTF8String);
                return 1;
            }
            running[which] = @(pid);
            registered(pid, which, folder);
            read();
        } else if ([what isEqual:@"clear"] && w.count >= 3 && running[which]) {
            // A /clear: the same process, a new conversation, as Claude Code's registry then says.
            registered(running[which].intValue, w[2], [Home() stringByAppendingPathComponent:@"shop"]);
            running[w[2]] = running[which];
            [running removeObjectForKey:which];
            read();
        } else if ([what isEqual:@"close"] && running[which]) {
            stop(running[which].intValue);
            [running removeObjectForKey:which];
            read();
        } else if ([what isEqual:@"stops"]) {
            printf("in a print run, the walk up a session's parents stops at: %s\n",
                   StartedWalkStopsAt(YES) == getpid() ? "this run's own process" : "somewhere else");
            printf("in the app, it stops at: %s\n",
                   StartedWalkStopsAt(NO) ? "a process short of the system's own" : "nothing short of the system's own");
        } else if ([what isEqual:@"rule"]) {
            // The rule alone (WhyNotHold), on made-up facts, each case on its own.
            NSString *shop = @"/work/shop", *npm = AtSentenceStart(ClaudeProgramCause(0, ClaudeProgramByPath));
            NSDictionary *rook = @{@"name": @"Rook", @"session": @"s-rook"};
            NSArray *cases = @[
                @[@"its folder can't be read", NSNull.null, shop, @(ClaudeProgramSigned), @NO, @[], NSNull.null,
                  NSNull.null],
                @[@"its process's folder can't be read", shop, NSNull.null, @(ClaudeProgramSigned), @NO, @[],
                  NSNull.null, NSNull.null],
                @[@"it works elsewhere", shop, @"/work/yard", @(ClaudeProgramSigned), @NO, @[], NSNull.null,
                  NSNull.null],
                @[@"it works in a folder inside", shop, @"/work/shop/site", @(ClaudeProgramSigned), @NO, @[],
                  NSNull.null, NSNull.null],
                @[@"it follows a copy that isn't Claude Code's", shop, shop, @(ClaudeProgramNone), @YES, @[],
                  NSNull.null, NSNull.null],
                @[@"an older one from npm", shop, shop, @(ClaudeProgramByPath), @NO, @[], NSNull.null, NSNull.null],
                @[@"another program", shop, shop, @(ClaudeProgramNone), @NO, @[], NSNull.null, NSNull.null],
                @[@"open twice", shop, shop, @(ClaudeProgramSigned), @YES, @[@4242], NSNull.null, NSNull.null],
                @[@"started inside a listed session", shop, shop, @(ClaudeProgramSigned), @NO, @[], rook,
                  NSNull.null],
                @[@"started inside one not listed", shop, shop, @(ClaudeProgramSigned), @NO, @[], @{}, NSNull.null],
                @[@"a listed session there too", shop, shop, @(ClaudeProgramSigned), @NO, @[], NSNull.null, rook],
                @[@"one not listed there too", shop, shop, @(ClaudeProgramSigned), @NO, @[], NSNull.null, @{}],
                @[@"all of them at once", shop, shop, @(ClaudeProgramSigned), @YES, @[@4242], rook, rook],
                @[@"none of them", shop, shop, @(ClaudeProgramSigned), @NO, @[], NSNull.null, NSNull.null],
            ];
            id (^given)(id) = ^id(id value) { return value == NSNull.null ? nil : value; };
            for (NSArray *c in cases) {
                ClaudeProgram program = [c[3] integerValue];
                NSString *why = program == ClaudeProgramByPath ? npm
                    : program == ClaudeProgramNone ? @"It isn't Claude Code's own program, signed by Anthropic" : nil;
                NSDictionary *hold = WhyNotHold(given(c[1]), given(c[2]), program, why, [c[4] boolValue], c[5],
                                                given(c[6]), given(c[7]));
                printf("%s: %s\n", [c[0] UTF8String], hold[@"why"]
                       ? [NSString stringWithFormat:@"%@ (%@%@)", hold[@"why"], hold[@"kind"],
                          hold[@"other"] ? [@", " stringByAppendingString:hold[@"other"]] : @""].UTF8String
                       : "may hold them");
            }
        } else if ([what isEqual:@"pair"] && w.count >= 4) {
            // The outer session's shell starts the inner one and says its pid, so the inner one's parent is the outer
            // one: run as `as=` (Claude Code's npm install, any other program), and not in Claude Code's registry at all
            // with `unlisted`.
            NSString *folder = [Home() stringByAppendingPathComponent:w[3]];
            NSString *said = [Home() stringByAppendingPathComponent:[w[2] stringByAppendingString:@".pid"]];
            NSString *claude = [programs stringByAppendingPathComponent:@"claude"], *outer = claude;
            for (NSString *word in w)
                if ([word hasPrefix:@"as="])
                    outer = [programs stringByAppendingPathComponent:[word substringFromIndex:3]];
            NSMutableArray *words = [@[@"-c", [NSString stringWithFormat:@"'%@' -c 'sleep 600; :' stand-in & echo $! > "
                                                                          @"'%@'; wait", claude, said], @"stand-in"]
                                       mutableCopy];
            if ([outer.lastPathComponent isEqual:@"node"])
                [words addObject:[@"/lib/node_modules/" stringByAppendingString:kClaudeCodeNodeEntry]];
            pid_t outerPid = start(outer, words, folder);
            if (outerPid <= 0) {
                fprintf(stderr, "couldn't start %s\n", which.UTF8String);
                return 1;
            }
            pid_t inner = 0;
            for (int i = 0; i < 50 && inner <= 0; i++) {
                [NSThread sleepForTimeInterval:0.1];
                inner = [[NSString stringWithContentsOfFile:said encoding:NSUTF8StringEncoding error:nil] intValue];
            }
            running[which] = @(outerPid);
            if (![w containsObject:@"unlisted"]) registered(outerPid, which, folder);
            if (inner > 0) registered(inner, w[2], folder);
            read();
        } else if ([what isEqual:@"lead"] && which) {
            NSString *path = AppDir(@"team/team.json");
            NSMutableDictionary *team = [AsRecord(ReadJSON(path)) mutableCopy];
            NSMutableDictionary *projects = [AsRecord(team[@"projects"]) mutableCopy];
            for (NSString *project in projects.allKeys) {
                NSMutableDictionary *one = [AsRecord(projects[project]) mutableCopy];
                NSMutableDictionary *lead = [AsRecord(one[@"lead"]) mutableCopy];
                lead[@"session"] = which;
                one[@"lead"] = lead;
                projects[project] = one;
            }
            team[@"projects"] = projects;
            [[NSJSONSerialization dataWithJSONObject:team options:0 error:nil] writeToFile:path atomically:YES];
            // The team module reads the file again once its date has changed, and looks at most twice a second: each
            // write here is given a date of its own, and the run waits that long.
            [NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:
                                                              [NSDate dateWithTimeIntervalSinceNow:++leads]}
                                           ofItemAtPath:path error:nil];
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
            read();
        } else if (([what isEqual:@"tick"] || [what isEqual:@"untick"]) && byId[which]) {
            for (NSString *key in keys) {
                BOOL done = [core.allowed set:key for:byId[which] on:[what isEqual:@"tick"]];
                printf("%s: %s\n", key.UTF8String, done ? what.UTF8String : "not changed");
            }
        } else if ([what isEqual:@"why"] && byId[which]) {
            Row *row = byId[which];
            for (NSString *key in keys) {
                NSString *why = [core.allowed whyOff:key for:row from:row.pid];
                printf("%s: %s\n", key.UTF8String, (why ?: @"on").UTF8String);
            }
        } else if ([what isEqual:@"notices"]) {
            for (Notice *notice in answerFor.notices)
                printf("%s: %s (button %s)\n", notice.title.UTF8String, notice.text.UTF8String,
                       notice.button.UTF8String ?: "none");
        } else {
            fprintf(stderr, "no such step, or no such session: %s\n", step.UTF8String);
            for (NSNumber *pid in running.allValues) stop(pid.intValue);
            return 2;
        }
    }
    for (NSNumber *pid in running.allValues) stop(pid.intValue);
    return 0;
}

NSDictionary<NSString *, PrintMode> *ClaudeCodePrintModes(void) {
    return @{
        @"--print-kept": ^(Core *core, NSArray *a) { return PrintKept(core); },
        @"--print-mode-moves": ^(Core *core, NSArray *a) { return PrintModeMoves(core); },
        @"--print-typing": ^(Core *core, NSArray *a) { return PrintTyping(); },
        @"--print-results": ^(Core *core, NSArray *a) { return PrintResults(a); },
        @"--print-usage": ^(Core *core, NSArray *a) { return PrintUsage(a); },
        @"--print-spent": ^(Core *core, NSArray *a) { return PrintSpent(a); },
        @"--print-reply": ^(Core *core, NSArray *a) { return PrintReply(a); },
        @"--print-between-steps": ^(Core *core, NSArray *a) { return PrintBetweenSteps(); },
        @"--print-aside": ^(Core *core, NSArray *a) { return PrintAside(core, a); },
        @"--print-writing-wait": ^(Core *core, NSArray *a) { return PrintWritingWait(a); },
        @"--print-record-how": ^(Core *core, NSArray *a) { return PrintRecordHow(a); },
        @"--print-reads": ^(Core *core, NSArray *a) { return PrintReads(a); },
        @"--print-trust": ^(Core *core, NSArray *a) { return PrintTrust(a); },
        @"--print-plugin-install": ^(Core *core, NSArray *a) { return PrintPluginInstall(a); },
        @"--print-held": ^(Core *core, NSArray *a) { return PrintHeld(); },
        @"--print-hook-line": ^(Core *core, NSArray *a) { return PrintHookLine(a); },
        @"--print-answer-for": ^(Core *core, NSArray *a) { return PrintAnswerFor(core, a); },
        @"--print-askers": ^(Core *core, NSArray *a) { return PrintAskers(core, a); },
        @"--print-program": ^(Core *core, NSArray *a) { return PrintProgram(a); },
        @"--print-own-waits": ^(Core *core, NSArray *a) { return PrintOwnWaits(core); },
        @"--print-kept-waits": ^(Core *core, NSArray *a) { return PrintKeptWaits(); },
        @"--print-switch-holder": ^(Core *core, NSArray *a) { return PrintSwitchHolder(core, a); },
        @"--print-dont-wait-files": ^(Core *core, NSArray *a) { return PrintDontWaitFiles(core); },
    };
}
