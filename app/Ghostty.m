// Ghostty: finding a session's Ghostty tab, focusing it and typing into it, through AppleScript.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Ghostty.h"
#import "Row.h"
#import "Log.h"
#import "Processes.h"
#import "Transcripts.h"
#import "Upstream.h"

// Drop Claude Code's status glyph ("✳ ", spinner characters) from the front of a tab title.
static NSString *BareTitle(NSString *title) {
    NSUInteger i = 0;
    while (i < title.length && ![NSCharacterSet.alphanumericCharacterSet characterIsMember:[title characterAtIndex:i]])
        i++;
    return [[title substringFromIndex:i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

@interface Ghostty ()
@property (strong) Transcripts *transcripts;
@end

@implementation Ghostty

- (instancetype)initWithTranscripts:(Transcripts *)transcripts {
    if (!(self = [super init])) return nil;
    self.transcripts = transcripts;
    return self;
}

- (NSString *)appId {
    return kGhosttyAppId;
}

- (NSString *)name {
    return @"Ghostty";
}

// Ghostty's scripting exposes each terminal's title and working directory but not its tty, so the session is
// matched by folder, then by the tab title Claude Code sets (its topic, else its name, else "Claude Code").
// *unique says whether nothing else in that folder fits as well, which typing into it requires.
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique {
    *unique = NO;
    // `sep` is bound outside the tell block: inside it, `tab` names Ghostty's tab class, not the character.
    NSString *list = RunAppleScript(@"set out to \"\"\n"
                                    @"set sep to tab\n"
                                    @"tell application \"Ghostty\"\n"
                                    @"  repeat with t in terminals\n"
                                    @"    set out to out & (id of t) & sep & (working directory of t) & sep"
                                    @" & (name of t) & linefeed\n"
                                    @"  end repeat\n"
                                    @"end tell\n"
                                    @"return out");
    NSMutableArray<NSArray<NSString *> *> *sameFolder = [NSMutableArray array];
    for (NSString *line in [list componentsSeparatedByString:@"\n"]) {
        NSArray *fields = [line componentsSeparatedByString:@"\t"];
        if (fields.count >= 3 && [fields[1] isEqualToString:row.cwd])
            [sameFolder addObject:@[fields[0], BareTitle(fields[2])]];
    }

    NSMutableArray *wanted = [NSMutableArray array];
    NSString *topic = [self.transcripts topicOf:row.sessionId];
    if (topic.length) [wanted addObject:topic];
    if ([row.name length]) [wanted addObject:row.name];
    if (!topic.length) [wanted addObject:@"Claude Code"];

    NSString *match = nil;
    for (NSString *title in wanted) {
        NSArray *hits = [sameFolder filteredArrayUsingPredicate:
                             [NSPredicate predicateWithBlock:^BOOL(NSArray *t, id _) {
            return [t[1] isEqualToString:title];
        }]];
        if (hits.count) { match = hits[0][0]; *unique = hits.count == 1; break; }
    }
    if (!match && sameFolder.count == 1) { match = sameFolder[0][0]; *unique = YES; }

    NSCharacterSet *notId =
        [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef-"] invertedSet];
    if (!match.length || [match rangeOfCharacterFromSet:notId].location != NSNotFound) {
        PanelLog(@"terminal session pid %d -> no Ghostty tab matched (topic %@)", row.pid, topic);
        *unique = NO;
        return nil;
    }
    return match;
}

- (BOOL)focus:(Row *)row {
    BOOL unique;
    NSString *match = [self tabFor:row unique:&unique];
    if (!match) return NO;
    RunAppleScript([NSString stringWithFormat:@"tell application \"Ghostty\"\n"
                                              @"  focus (first terminal whose id is \"%@\")\n"
                                              @"  activate\n"
                                              @"end tell", match]);
    PanelLog(@"open terminal session pid %d -> focused Ghostty terminal %@", row.pid, match);
    return YES;
}

// Runs AppleScript in Ghostty with `t` set to the tab.
- (void)run:(NSString *)body inTab:(NSString *)tab {
    RunAppleScript([NSString stringWithFormat:@"tell application \"Ghostty\"\n"
                                              @"  set t to first terminal whose id is \"%@\"\n"
                                              @"%@\n"
                                              @"end tell", tab, body]);
}

- (void)newTabIn:(NSString *)folder {
    NSString *quoted = [[folder stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                        stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    // `nl` is bound outside the tell block, where `linefeed` can't be shadowed by Ghostty's terms.
    RunAppleScript([NSString stringWithFormat:@"set nl to linefeed\n"
                                              @"tell application \"Ghostty\"\n"
                                              @"  set cfg to new surface configuration\n"
                                              @"  set initial working directory of cfg to \"%@\"\n"
                                              @"  set initial input of cfg to \"claude\" & nl\n"
                                              @"  if (count of windows) > 0 then\n"
                                              @"    new tab in front window with configuration cfg\n"
                                              @"  else\n"
                                              @"    new window with configuration cfg\n"
                                              @"  end if\n"
                                              @"  activate\n"
                                              @"end tell", quoted]);
    PanelLog(@"new terminal session in %@", folder);
}

- (void)type:(NSString *)text inTab:(NSString *)tab {
    // A /compact's focus is free text, so its quotes and backslashes are escaped.
    NSString *quoted = [[text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                        stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [self run:[NSString stringWithFormat:@"input text \"%@\" to t", quoted] inTab:tab];
}

- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab {
    NSString *once = key == TerminalKeyReturn ? @"send key \"enter\" to t"
                   : key == TerminalKeyBackspace ? @"send key \"backspace\" to t"
                   : key == TerminalKeyShiftTab ? @"send key \"tab\" modifiers \"shift\" to t"
                   : @"perform action \"text:\\\\x13\" on t";  // Ctrl+S, sent as its control character
    [self run:times == 1 ? once : [NSString stringWithFormat:@"repeat %ld times\n"
                                                            @"  %@\n"
                                                            @"  delay 0.05\n"
                                                            @"end repeat", (long)times, once]
        inTab:tab];
}

@end
