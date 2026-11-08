// Text: shell words, colour codes, hashes, line keys, one line of words, plain ids and secrets' shapes.
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

NSString *AtSentenceStart(NSString *reason) {
    if (!reason.length) return reason;
    return [[reason substringToIndex:1].uppercaseString stringByAppendingString:[reason substringFromIndex:1]];
}

NSString *AfterColon(NSString *reason) {
    if (!reason.length) return reason;
    NSCharacterSet *ends = [NSCharacterSet characterSetWithCharactersInString:@" ,:;'’"];
    NSString *first = [reason componentsSeparatedByCharactersInSet:ends].firstObject;
    if ([first isEqualToString:@"Whozmove"]) return reason;
    if (first.length > 1
        && [first rangeOfCharacterFromSet:NSCharacterSet.uppercaseLetterCharacterSet options:0
                                    range:NSMakeRange(1, first.length - 1)].location != NSNotFound)
        return reason;
    return [[reason substringToIndex:1].lowercaseString stringByAppendingString:[reason substringFromIndex:1]];
}

NSString *OneLine(NSString *words, NSUInteger most) {
    return Clip([[[words componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
                  componentsJoinedByString:@" "]
                 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], most);
}

NSString *PlainOneLine(NSString *words, NSUInteger most) {
    NSString *one = [words ?: @"" stringByReplacingOccurrencesOfString:@"[ \\t]*[\\r\\n\\p{Zl}\\p{Zp}]+[ \\t]*"
                                                            withString:@" " options:NSRegularExpressionSearch
                                                                 range:NSMakeRange(0, (words ?: @"").length)];
    NSString *plain = [one stringByReplacingOccurrencesOfString:@"[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}]" withString:@""
                                                        options:NSRegularExpressionSearch
                                                          range:NSMakeRange(0, one.length)];
    return Clip([plain stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet], most);
}

BOOL IsPlainId(NSString *text, NSUInteger most) {
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:
                                 @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-"].invertedSet;
    return text.length && text.length <= most && [text rangeOfCharacterFromSet:other].location == NSNotFound;
}

BOOL LooksLikeSecret(NSString *text) {
    static NSRegularExpression *shapes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *each = @[
            @"sk-[A-Za-z0-9_-]{20,}",                                       // API keys (OpenAI's, Anthropic's, others')
            @"gh[pousr]_[A-Za-z0-9]{20,}", @"github_pat_[A-Za-z0-9_]{20,}",  // GitHub's tokens
            @"AKIA[0-9A-Z]{16}",                                            // an AWS access key
            @"-----BEGIN [A-Z ]*PRIVATE KEY-----",                          // a private key's first line
            @"xox[abprs]-[A-Za-z0-9-]{10,}", @"\\bxapp-[A-Za-z0-9-]{10,}",  // Slack's tokens, and its app tokens
            @"\\b[sr]k_(live|test)_[A-Za-z0-9]{16,}",                       // Stripe's keys
            @"\\bAIza[0-9A-Za-z_-]{30,}",                                   // a Google API key
            @"\\bGOCSPX-[A-Za-z0-9_-]{20,}",                                // a Google client secret
            @"\\bglpat-[A-Za-z0-9_-]{20,}",                                 // GitLab's
            @"\\bnpm_[A-Za-z0-9]{30,}",                                     // npm's
            @"\\bhf_[A-Za-z0-9]{30,}",                                      // Hugging Face's
            @"\\bSG\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}",             // SendGrid's
            @"\\b(?i:bearer)\\s+[A-Za-z0-9._~+/=-]{16,}",                   // a bearer token, as a header has it
        ];
        shapes = [NSRegularExpression regularExpressionWithPattern:[each componentsJoinedByString:@"|"] options:0 error:nil];
    });
    return text.length && [shapes firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
}

NSArray<NSDictionary *> *ReplyParts(NSString *reply) {
    NSMutableArray *parts = [NSMutableArray array], *prose = [NSMutableArray array], *code = nil;
    NSString *fence = nil, *lang = nil;
    void (^keepProse)(void) = ^{
        NSString *words = [[prose componentsJoinedByString:@"\n"]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (words.length) [parts addObject:@{@"prose": words}];
        [prose removeAllObjects];
    };
    NSString *text = [reply isKindOfClass:NSString.class] ? reply : @"";
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *bare = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!fence && ([bare hasPrefix:@"```"] || [bare hasPrefix:@"~~~"])) {
            keepProse();
            fence = [bare substringToIndex:3];
            lang = [[bare substringFromIndex:3] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            code = [NSMutableArray array];
        } else if (fence && [bare hasPrefix:fence]
                   && ![[bare substringFromIndex:3] stringByTrimmingCharactersInSet:
                        [NSCharacterSet characterSetWithCharactersInString:[fence substringToIndex:1]]].length) {
            [parts addObject:@{@"code": [code componentsJoinedByString:@"\n"], @"lang": lang ?: @""}];
            fence = nil;
            code = nil;
        } else if (fence) {
            [code addObject:line];
        } else {
            [prose addObject:line];
        }
    }
    if (fence) [parts addObject:@{@"code": [code componentsJoinedByString:@"\n"], @"lang": lang ?: @""}];
    keepProse();
    return parts;
}
