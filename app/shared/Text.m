// Text: shell words, colour codes, hashes, line keys, one line of words and plain ids.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Text.h"
#import "Files.h"

NSString *ShellWord(NSString *text) {
    return [NSString stringWithFormat:@"'%@'", [text stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

NSString *WithoutColours(NSString *text) {
    if (!text) return nil;
    return [text stringByReplacingOccurrencesOfString:@"\\x1b\\[[0-9;]*m" withString:@""
                                              options:NSRegularExpressionSearch range:NSMakeRange(0, text.length)];
}

uint64_t HashBytes(const char *bytes) {
    uint64_t hash = 14695981039346656037ULL;
    for (const char *c = bytes; c && *c; c++) hash = (hash ^ (uint8_t)*c) * 1099511628211ULL;
    return hash;
}

NSNumber *LineKey(NSString *line) {
    NSString *text = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return nil;
    return @(HashBytes(text.UTF8String));
}

NSString *OneLine(NSString *words, NSUInteger most) {
    return Clip([[[words componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                  componentsJoinedByString:@" "]
                 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], most);
}

BOOL IsPlainId(NSString *text, NSUInteger most) {
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:
                                 @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"].invertedSet;
    return text.length && text.length <= most && [text rangeOfCharacterFromSet:other].location == NSNotFound;
}
