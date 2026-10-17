// Results: a command's result, read and understood.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Results.h"
#import "Files.h"
#import "Text.h"

// A slash command's result in a transcript, among what was written after `from`: the output
// (<local-command-stdout>) after the command's own record (<command-name>/model</command-name>), written as a
// message or as a system note (a declined switch says "Kept model as …"). When the command left no record there
// (Claude Desktop may not write one), the first output after `from`.
NSString *CommandResult(NSString *path, unsigned long long from, NSString *command) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) return nil;
    [fh seekToFileOffset:from];
    NSString *text = [[NSString alloc] initWithData:[fh readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    [fh closeFile];
    NSString *name = [command componentsSeparatedByString:@" "].firstObject;
    NSString *record = [NSString stringWithFormat:@"<command-name>%@</command-name>", name];
    BOOL seen = NO;
    NSString *first = nil;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (![line containsString:@"<local-command-stdout>"] && ![line containsString:@"<command-name>"]) continue;
        NSDictionary *entry = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                              options:0 error:nil];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id message = entry[@"message"];
        id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : entry[@"content"];
        if (![content isKindOfClass:NSString.class]) continue;
        if ([content containsString:record]) { seen = YES; continue; }
        NSRange open = [content rangeOfString:@"<local-command-stdout>"],
                close = [content rangeOfString:@"</local-command-stdout>"];
        if (open.location == NSNotFound || close.location == NSNotFound || close.location < NSMaxRange(open)) continue;
        NSString *output = [content substringWithRange:NSMakeRange(NSMaxRange(open),
                                                                    close.location - NSMaxRange(open))];
        if (seen) return output;
        if (!first) first = output;
    }
    return seen ? nil : first;
}

// "Set model to `Sonnet 5.5` …", "Set effort level to high …", or for an effort above the model's cap, "… set to
// 'xhigh' instead". Anything else (declined: "Kept model as …", failed) changed nothing.
NSString *ResultApplies(NSString *field, NSString *value, NSString *result) {
    if ([field isEqual:@"model"] && [result hasPrefix:@"Set model to"]) return value;
    if ([field isEqual:@"mode"] && [result.lowercaseString containsString:@"plan mode"]) return @"plan";
    if ([field isEqual:@"effort"] && result) {
        NSRegularExpression *re =
            [NSRegularExpression regularExpressionWithPattern:@"(?:Set effort level to |set to ')([a-z]+)"
                                                      options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:result options:0 range:NSMakeRange(0, result.length)];
        if (m) return [result substringWithRange:[m rangeAtIndex:1]];
    }
    return nil;
}

// In a terminal the result says whether the pick was saved as the default ("… and saved as your default for new
// sessions", or "(saved as your default …)").
BOOL ResultSavedDefault(NSString *result) {
    return [result containsString:@"saved as your default"];
}

NSString *CompactNote(NSString *result) {
    NSString *plain = WithoutColours(result);
    if ([plain containsString:@"Compacted"]) return nil;
    return plain.length ? Clip(plain, 200) : @"";
}
