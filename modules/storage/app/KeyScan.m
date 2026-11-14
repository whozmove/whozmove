// KeyScan: the keys left where they shouldn't be on this Mac (KeyScan.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Betterleaks does the finding, with the key taken out of its report, so what comes back is only where each key is and
// its fingerprint. The last 4 characters come from the line it was found in, which Keys has itself: a file's line, a
// commit's, or the text it fed Betterleaks. A record (a JSON line an AI tool wrote) is fed as the text it holds, its
// escaped line breaks real again, so a key that starts a line is found as one.
#import "KeyScan.h"
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonHMAC.h>
#import <sys/file.h>
#import <sys/stat.h>
#import "KeyFacts.h"
#import "StorageFacts.h"
#import "Files.h"
#import "Git.h"
#import "Links.h"
#import "Log.h"
#import "Processes.h"

NSArray<NSString *> *const kKeyGroups = @[@"commit", @"pushed", @"claude", @"ai", @"readable", @"files"];

// How long one run of Betterleaks may take, in seconds (runFor's start); how much one run reads, fed as text or in
// files; how many files one run is given; and how many files of one checkout are looked at, at most.
static const NSTimeInterval kRunFor = 300;
static const NSUInteger kFeedAtOnce = 16 * 1024 * 1024, kFilesAtOnce = 200, kMostFiles = 50000;
// How large a record kept as plain text (a long paste, a tool's long output, a copy of an edited file) may be to be
// looked in.
static const unsigned long long kRecordLargest = 8 * 1024 * 1024;
// What Whozmove's own record of a session keeps of what was said, which the hook writes (whozmove-claude.py).
static NSArray<NSString *> *const kOwnFields = @[@"lastPrompt", @"lastReply", @"notice"];
// The shape of what a look keeps (found.json), written with it: a look kept by a build that kept another shape isn't
// shown, as the tab draws only this one (each key's ways, band and places as Settled makes them, and what it takes for
// a key), and a new look starts as soon as one may.
static const NSInteger kFoundShape = 5;
// The shape of what's kept of AI tools' records read before (records.json): what was found in them by a build that
// told keys apart another way is found again, by reading them again from their start. It goes up with every change to
// how a line is judged (WithLineFacts and what it asks), or what was found before by the old rules stays listed.
static const NSInteger kRecordsShape = 5;
// The places a look reads, one after the other: your projects, your credential files, your shell's history and
// settings and your Downloads, AI tools' records, and Whozmove's own.
static const NSUInteger kPlacesRead = 5;
// How many records a look reads between keeping how far it has got (keepEvery's start).
static const NSUInteger kKeepEvery = 300;

// Whether a file is kept only in the cloud (iCloud Drive's, or another File Provider's, not downloaded): reading it
// would fetch it, so Keys never does, as the map never does.
static BOOL OnlyInCloud(NSString *path) {
    struct stat info;
    return lstat(path.fileSystemRepresentation, &info) == 0 && (info.st_flags & SF_DATALESS);
}

// A path from the home folder as you'd write it: ~/.aws/credentials.
static NSString *Tilde(NSString *path) {
    NSString *home = Home();
    return [path hasPrefix:[home stringByAppendingString:@"/"]]
        ? [@"~" stringByAppendingString:[path substringFromIndex:home.length]] : path;
}

// JSON written so only you can read it, whole or not at all: through a file of its own each time, so a look on the
// queue and an action on the main thread never write through the same one.
static BOOL KeepJSON(id object, NSString *path) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:nil];
    if (!data) return NO;
    NSString *temporary = [NSString stringWithFormat:@"%@.%d.%08x.tmp", path, getpid(), arc4random()];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return NO;
    BOOL wrote = write(fd, data.bytes, data.length) == (ssize_t)data.length;
    close(fd);
    if (wrote && rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) == 0) return YES;
    unlink(temporary.fileSystemRepresentation);
    return NO;
}

// A text's HMAC-SHA256 with the secret, in hex.
static NSString *Fingerprint(NSString *secret, NSString *text) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    NSData *key = [secret dataUsingEncoding:NSUTF8StringEncoding], *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

// A key's id, from its fingerprint ("hmac-sha256:<hex>"): enough of it to tell keys apart, and nothing of the key.
static NSString *KeyId(NSString *fingerprint) {
    NSString *hex = [fingerprint componentsSeparatedByString:@":"].lastObject;
    return hex.length >= 16 ? [hex substringToIndex:16] : nil;
}

// The `line`th line of some text (from 1), without its line break; nil past its end.
static NSData *LineOf(NSData *text, NSInteger line) {
    const char *bytes = text.bytes, *end = bytes + text.length, *at = bytes;
    for (NSInteger n = 1; at <= end; n++) {
        const char *next = memchr(at, '\n', (size_t)(end - at));
        if (n == line) return [NSData dataWithBytes:at length:(NSUInteger)((next ?: end) - at)];
        if (!next) break;
        at = next + 1;
    }
    return nil;
}

// Where the key itself ends in its line, as bytes from its start, when what was found ends at byte `column` (from 1):
// without what the match took in after it (KeyMatchEdges), an escaped line break written out first.
static NSUInteger KeyEnd(NSData *line, NSInteger column) {
    if (!line || column < 1 || (NSUInteger)column > line.length) return 0;
    const char *bytes = line.bytes;
    NSCharacterSet *edges = KeyMatchEdges();
    NSUInteger end = (NSUInteger)column;
    for (;;) {
        if (end >= 2 && bytes[end - 2] == '\\' && (bytes[end - 1] == 'n' || bytes[end - 1] == 'r')) end -= 2;
        else if (end && [edges characterIsMember:(unichar)(unsigned char)bytes[end - 1]]) end--;
        else return end;
    }
}

// Where it starts, as bytes from the line's start, when what was found starts at byte `column` (from 1): without
// what the match took in before it.
static NSUInteger KeyStart(NSData *line, NSInteger column, NSUInteger end) {
    if (!line || column < 1) return end;
    const char *bytes = line.bytes;
    NSCharacterSet *edges = KeyMatchEdges();
    NSUInteger start = (NSUInteger)column - 1;
    while (start < end && [edges characterIsMember:(unichar)(unsigned char)bytes[start]]) start++;
    return start;
}

// The last 4 characters of a key found in a line, which what was found ends at byte `column` (from 1) of.
static NSString *LastFour(NSData *line, NSInteger column) {
    NSUInteger end = KeyEnd(line, column);
    if (!end) return @"";
    // In a record written as JSON, a "\" is the record's escape, not the key's: one left at the end goes with the quote
    // after it, and one before a character stands for that character.
    const char *bytes = line.bytes;
    while (end > 0 && bytes[end - 1] == '\\') end--;
    NSUInteger from = end >= 12 ? end - 12 : 0;
    NSData *tail = [line subdataWithRange:NSMakeRange(from, end - from)];
    NSString *text = [[NSString alloc] initWithData:tail encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:tail encoding:NSISOLatin1StringEncoding] ?: @"";
    static NSRegularExpression *escaped;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        escaped = [NSRegularExpression regularExpressionWithPattern:@"\\\\(.)" options:0 error:nil];
    });
    text = [escaped stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                                        withTemplate:@"$1"];
    return text.length > 4 ? [text substringFromIndex:text.length - 4] : text;
}

// When a sign-in token (JWT) found in a line stops working, by its own `exp`, in milliseconds since 1970: read from
// its middle part while the line is in hand, and only the date kept. Nil for any other kind, or one that doesn't say.
static NSNumber *TokenEnds(NSDictionary *finding, NSData *line) {
    if (![AsText(finding[@"rule_id"]) isEqualToString:@"jwt"]) return nil;
    NSDictionary *at = AsRecord(finding[@"location"]);
    NSInteger from = AsNumber(at[@"start_line"]).integerValue == AsNumber(at[@"end_line"]).integerValue
                   ? AsNumber(at[@"start_column"]).integerValue : 1;
    NSUInteger end = KeyEnd(line, AsNumber(at[@"end_column"]).integerValue), start = KeyStart(line, from, end);
    if (end <= start) return nil;
    NSString *token = [[NSString alloc] initWithData:[line subdataWithRange:NSMakeRange(start, end - start)]
                                            encoding:NSUTF8StringEncoding];
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count < 2) return nil;
    NSMutableString *middle = [[[parts[1] stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                                stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    while (middle.length % 4) [middle appendString:@"="];
    NSData *json = [[NSData alloc] initWithBase64EncodedString:middle options:0];
    id exp = json ? AsRecord([NSJSONSerialization JSONObjectWithData:json options:0 error:nil])[@"exp"] : nil;
    return [exp isKindOfClass:NSNumber.class] && [exp doubleValue] > 0 ? @([exp doubleValue] * 1000) : nil;
}

// The key found in a line, as bytes from the line's start: from KeyStart to KeyEnd; for a rule that matches the name
// before the key too (generic-api-key: `api_key: "…"`), what's after the last = or : in that.
static NSRange KeySpan(NSDictionary *finding, NSData *line, NSRange *matched) {
    NSDictionary *at = AsRecord(finding[@"location"]);
    NSInteger from = AsNumber(at[@"start_line"]).integerValue == AsNumber(at[@"end_line"]).integerValue
                   ? AsNumber(at[@"start_column"]).integerValue : 1;
    NSUInteger end = KeyEnd(line, AsNumber(at[@"end_column"]).integerValue), start = KeyStart(line, from, end);
    if (!line || end <= start) return NSMakeRange(NSNotFound, 0);
    if (matched) *matched = NSMakeRange(start, end - start);
    if ([AsText(finding[@"rule_id"]) isEqualToString:@"generic-api-key"]) {
        const char *bytes = line.bytes;
        for (NSUInteger i = end; i > start; i--)
            if (bytes[i - 1] == '=' || bytes[i - 1] == ':') {
                NSUInteger key = i;
                while (key < end && bytes[key] && strchr(" \t\"'", bytes[key])) key++;
                return NSMakeRange(key, end - key);
            }
    }
    return NSMakeRange(start, end - start);
}

// Whether a name is one: what a key is set as, never a value itself (as long as a key, letters and digits mixed), one
// that starts as a provider's keys do, nor a field of a scanner's report that a key was printed in.
static BOOL PlainName(NSString *name) {
    if (!name.length || name.length > 64 || KeyHasProviderStart(name) || KeyReportField(name)) return NO;
    BOOL letters = [name rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound;
    BOOL digits = [name rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;
    return !(name.length >= 20 && letters && digits);
}

// What a key found in a line is for, where the line says it plainly and it isn't secret: the name it's set as, right
// before an = or : ({as: "GITHUB_TOKEN"}, at most 64 letters, digits and . _ -), never a value (a name that itself
// follows an = or :, or looks like a key) nor anything inside a web address (its user name); or the host of the
// address after it, which it's the password for ({for: "db.example.dev"}, right after an @) or sent to ({to:
// "api.example.dev"}). Nothing else of the line is kept. Nil when neither is there.
static NSDictionary *NamedIn(NSDictionary *finding, NSData *line) {
    NSRange matched = NSMakeRange(NSNotFound, 0), key = KeySpan(finding, line, &matched);
    if (key.location == NSNotFound) return nil;
    NSUInteger start = matched.location, end = NSMaxRange(key);
    NSString *before = [[NSString alloc] initWithData:[line subdataWithRange:NSMakeRange(0, start)]
                                             encoding:NSUTF8StringEncoding];
    NSString *after = [[NSString alloc] initWithData:[line subdataWithRange:NSMakeRange(end, line.length - end)]
                                            encoding:NSUTF8StringEncoding];
    // The name inside what was matched, for a rule that matches it with the key.
    NSString *inside = key.location > start
        ? [[NSString alloc] initWithData:[line subdataWithRange:NSMakeRange(start, key.location - start)]
                                encoding:NSUTF8StringEncoding] : nil;
    static NSRegularExpression *setAs, *at_, *address, *whole;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        setAs = [NSRegularExpression regularExpressionWithPattern:@"(^|[^A-Za-z0-9_./-])([A-Za-z0-9_.-]{1,64})[\"']?"
                                                                  "[ \t]*[:=][ \t]*[\"']?$" options:0 error:nil];
        whole = [NSRegularExpression regularExpressionWithPattern:@"^[\"']?([A-Za-z0-9_.-]{1,64})[\"']?[ \t]*[:=][ \t]*"
                                                                  "[\"']?$" options:0 error:nil];
        at_ = [NSRegularExpression regularExpressionWithPattern:@"^@([A-Za-z0-9.-]{1,253})" options:0 error:nil];
        address = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z][A-Za-z0-9+.-]*://(?:[^/@\\s]*@)?"
                                                                    "([A-Za-z0-9.-]{1,253})" options:0 error:nil];
    });
    // Inside a web address (after its ://, with no space since), what comes before the key is the address's own.
    NSRange scheme = before ? [before rangeOfString:@"://" options:NSBackwardsSearch] : NSMakeRange(NSNotFound, 0);
    BOOL inAddress = scheme.location != NSNotFound
        && [[before substringFromIndex:NSMaxRange(scheme)] rangeOfCharacterFromSet:
            NSCharacterSet.whitespaceCharacterSet].location == NSNotFound;
    NSString *name = nil, *ahead = nil;
    NSTextCheckingResult *found = inside ? [whole firstMatchInString:inside options:0
                                                               range:NSMakeRange(0, inside.length)] : nil;
    if (found) {
        // The match can start inside the name (at "TOKEN" in GITLAB_TOKEN): the rest of it is just before.
        NSUInteger whole = before.length;
        while (whole > 0 && [[NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-"]
                             characterIsMember:[before characterAtIndex:whole - 1]]) whole--;
        name = [[before substringFromIndex:whole]
                stringByAppendingString:[inside substringWithRange:[found rangeAtIndex:1]]];
        ahead = [before substringToIndex:whole];
    }
    else if (before && !inside && (found = [setAs firstMatchInString:before options:0
                                                               range:NSMakeRange(0, before.length)])) {
        name = [before substringWithRange:[found rangeAtIndex:2]];
        ahead = [before substringToIndex:[found rangeAtIndex:2].location];
    }
    // A name that itself follows an = or : is a value (id:secret), not what the key is set as.
    NSString *lead = [ahead stringByTrimmingCharactersInSet:
                      [NSCharacterSet characterSetWithCharactersInString:@" \t\"'"]];
    BOOL value = [lead hasSuffix:@"="] || [lead hasSuffix:@":"];
    if (name && !inAddress && !value && PlainName(name)) return @{@"as": name};
    NSTextCheckingResult *host = after ? [at_ firstMatchInString:after options:0
                                                         range:NSMakeRange(0, after.length)] : nil;
    if (host) return @{@"for": [after substringWithRange:[host rangeAtIndex:1]]};
    host = after ? [address firstMatchInString:after options:0 range:NSMakeRange(0, after.length)] : nil;
    if (host) return @{@"to": [after substringWithRange:[host rangeAtIndex:1]]};
    return nil;
}

// Whether what was found sits inside a longer run of base64 (a picture's data, the signature an AI's reply carries):
// at least 32 more of its characters around it, a + or a / among them. A rule that looks only at the key's own
// characters (BSA and 28 more) matches such a run anywhere a + or a / stands for a word's edge; a key itself stands
// apart from what's around it, by a space, a quote, a = or a : (a name's, or an address's).
static BOOL InBlob(NSData *line, NSRange key) {
    const char *bytes = line.bytes;
    BOOL (^base64)(char) = ^BOOL(char c) { return isalnum((unsigned char)c) || c == '+' || c == '/' || c == '='
                                                   || c == '_' || c == '-'; };
    NSUInteger from = key.location, to = NSMaxRange(key);
    BOOL slash = NO;
    for (; from > 0 && base64(bytes[from - 1]); from--) slash |= bytes[from - 1] == '+' || bytes[from - 1] == '/';
    for (; to < line.length && base64(bytes[to]); to++) slash |= bytes[to] == '+' || bytes[to] == '/';
    return slash && (key.location - from) + (to - NSMaxRange(key)) >= 32;
}

// The value a rule of a kind with no provider found (`rule`), without the name it matched before it (`password = `,
// `me:`): what follows the last = or : that has more than = after it (a key's base64 ends in = of its own); in an
// address (postgres://me:…@db/app), its password, between the user's name and the @.
static NSString *KeyValue(NSData *line, NSRange key, NSString *rule) {
    NSString *text = [[NSString alloc] initWithData:[line subdataWithRange:key] encoding:NSUTF8StringEncoding] ?: @"";
    // A user and password given to curl's -u (or --user), as that rule finds them: what it's given (user:password, its
    // quotes and a record's \ aside) is what's judged, its password when it has one, else its user; never the address
    // the command names before it. Another rule's find in a curl command (its header's token) is judged as itself.
    static NSRegularExpression *user;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        user = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)(?:-u|--user)(?:\\s+|=)\\\\?[\"']?"
                                                                  "([^\\s\"'\\\\]+)" options:0 error:nil];
    });
    NSTextCheckingResult *given = [rule isEqualToString:@"curl-auth-user"] && [text hasPrefix:@"curl "]
        ? [user matchesInString:text options:0 range:NSMakeRange(0, text.length)].lastObject : nil;
    if (given) {
        NSString *pair = [text substringWithRange:[given rangeAtIndex:1]];
        NSRange colon = [pair rangeOfString:@":"];
        if (colon.location == NSNotFound) return pair;
        NSString *password = [pair substringFromIndex:NSMaxRange(colon)];
        return password.length ? password : [pair substringToIndex:colon.location];
    }
    NSRange scheme = [text rangeOfString:@"://"];
    if (scheme.location != NSNotFound) {
        NSString *rest = [text substringFromIndex:NSMaxRange(scheme)];
        NSRange at = [rest rangeOfString:@"@"], colon = [rest rangeOfString:@":"];
        if (at.location != NSNotFound && colon.location < at.location)
            return [rest substringWithRange:NSMakeRange(NSMaxRange(colon), at.location - NSMaxRange(colon))];
    }
    NSCharacterSet *edges = [NSCharacterSet characterSetWithCharactersInString:@" \t\"'`="];
    NSUInteger bare = NSNotFound;
    for (NSUInteger i = text.length; i > 0; i--) {
        unichar c = [text characterAtIndex:i - 1];
        if (c != '=' && c != ':') continue;
        NSString *after = [[text substringFromIndex:i] stringByTrimmingCharactersInSet:edges];
        if (after.length) return [[text substringFromIndex:i] stringByTrimmingCharactersInSet:
                                  [NSCharacterSet characterSetWithCharactersInString:@" \t\"'`"]];
        if (bare == NSNotFound) bare = i - 1;
    }
    // A curl command's match with no colon left in it (-u "$API_KEY:", its end taken off): its last word, the user.
    if (bare == NSNotFound && [text hasPrefix:@"curl "])
        bare = text.length;
    // Nothing after its colon (a user given to curl -u with no password: -u "$API_KEY:"): the word before it.
    if (bare != NSNotFound && bare > 0) {
        NSString *before = [text substringToIndex:bare];
        NSRange gap = [before rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\"'`="]
                                              options:NSBackwardsSearch];
        NSString *word = gap.location == NSNotFound ? before : [before substringFromIndex:NSMaxRange(gap)];
        if (word.length) return word;
    }
    return text;
}

// Whether a private key found in one line (a record's, its line breaks written out as \n) has a key after its
// header: a run of at least 64 of base64's characters before its footer, or the line's end. Its header alone, in a
// test's words or a note about keys, is none.
static BOOL PrivateKeyHasBody(NSData *line, NSRange key) {
    NSString *text = [[NSString alloc] initWithData:[line subdataWithRange:key] encoding:NSUTF8StringEncoding];
    NSRange header = [text rangeOfString:@"PRIVATE KEY-----"];
    if (header.location == NSNotFound) return YES;
    NSString *body = [text substringFromIndex:NSMaxRange(header)];
    NSRange footer = [body rangeOfString:@"-----END"];
    if (footer.location != NSNotFound) body = [body substringToIndex:footer.location];
    // A JSON writer may escape its slashes (\/): each is one of base64's own.
    body = [body stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    for (NSString *escape in @[@"\\n", @"\\r", @"\n", @"\r", @" ", @"\t"])
        body = [body stringByReplacingOccurrencesOfString:escape withString:@""];
    NSCharacterSet *base64 = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="];
    NSUInteger run = 0;
    for (NSUInteger i = 0; i < body.length; i++) {
        run = [base64 characterIsMember:[body characterAtIndex:i]] ? run + 1 : 0;
        if (run >= 64) return YES;
    }
    return NO;
}

// Whether a key counts up a character at a time for 8 or more (1234567890, abcdefgh): a placeholder written to show
// where a key goes, as no key made at random does.
static BOOL CountsUp(NSString *text) {
    NSUInteger run = 1;
    for (NSUInteger i = 1; i < text.length; i++) {
        unichar was = [text characterAtIndex:i - 1], now = [text characterAtIndex:i];
        BOOL next = (was < 128 && now < 128 && isalnum(was) && isalnum(now) && now == was + 1)
                 || (was == '9' && now == '0');
        run = next ? run + 1 : 1;
        if (run >= 8) return YES;
    }
    return NO;
}

// Whether a value found by a rule of a kind with no provider is no key: a word, shorter than 8 characters, or letters
// only (and _ . - and brackets: "forward).") and shorter than 12, as a long passphrase is a password; a variable's
// name, whose value isn't in the line (a shell's $API_KEY or ${API_KEY}, Windows' %API_KEY%, a name in capitals with
// an underscore, R2_SECRET_KEY, or one reached through others, process.env.API_KEY), but not a password that only
// starts with a $; or a hash written out (only hex digits, as long as an MD5's, a SHA-1's or a SHA-256's), set as no
// name that says anything of a key, a token, a secret, a sign-in, a password or a credential (a file's name, such as
// "logo.svg", says nothing of one), since a service's key in hex is set as one ("api_key": …).
static BOOL NotAKey(NSData *line, NSRange key, NSString *value, NSDictionary *named) {
    static NSRegularExpression *letters, *words, *prose, *variable, *name, *hex, *secret, *file;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        letters = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z_.()-]+$" options:0 error:nil];
        words = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z]+([_-][A-Za-z]+)+$" options:0 error:nil];
        prose = [NSRegularExpression regularExpressionWithPattern:
                 @"^[A-Za-z][A-Za-z'’-]*([,;:]?\\s+\\(?[A-Za-z][A-Za-z.'’-]*\\)?)+[).,;:?!]*$" options:0 error:nil];
        variable = [NSRegularExpression regularExpressionWithPattern:
                    @"^\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?$|^%[A-Za-z_][A-Za-z0-9_]*%$|"
                     "^([A-Za-z_][A-Za-z0-9_]*\\.)*[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$|^[A-Z][A-Z0-9]*KEYS?$" options:0
                                                               error:nil];
        name = [NSRegularExpression regularExpressionWithPattern:@"^\\{?[A-Za-z_][A-Za-z0-9_]*\\}?$" options:0
                                                           error:nil];
        hex = [NSRegularExpression regularExpressionWithPattern:
               @"^([0-9a-f]{32}|[0-9a-f]{40}|[0-9a-f]{64}|[0-9A-F]{32}|[0-9A-F]{40}|[0-9A-F]{64})$" options:0
                                                          error:nil];
        secret = [NSRegularExpression regularExpressionWithPattern:@"key|token|secret|auth|pass|credential"
                                                           options:NSRegularExpressionCaseInsensitive error:nil];
        file = [NSRegularExpression regularExpressionWithPattern:@"^.+\\.([A-Za-z0-9]{1,5})$" options:0 error:nil];
    });
    BOOL (^is)(NSRegularExpression *, NSString *) = ^BOOL(NSRegularExpression *pattern, NSString *text) {
        return text && [pattern numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0;
    };
    // What's around it in a record written as JSON (\"…\") is the line's, not the value's.
    // A user and password given as one ($API_KEY: to curl -u) ends in its colon.
    NSString *bare = [[value stringByTrimmingCharactersInSet:
                       [NSCharacterSet characterSetWithCharactersInString:@"\\\"'`"]]
                      stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]];
    BOOL dollar = key.location > 0 && ((const char *)line.bytes)[key.location - 1] == '$';
    // Words, a short run of letters or several joined by dashes or underscores (your-api-key-here), aren't a key; a
    // long run of letters with nothing between is a passphrase, which is.
    if (bare.length < 8 || (is(letters, bare) && bare.length < 12) || is(words, bare) || is(variable, bare)
        || (dollar && is(name, bare)))
        return YES;
    // Prose, a sentence a match ran into ("Password managers such as … (com.example.marker)."), isn't a password: two
    // words or more, of letters only (commas between them, bracketed or dotted ones among them), maybe ending as a
    // sentence or a bracket does. A password with a digit or a sign in it is one, whatever it ends with.
    if (is(prose, bare)) return YES;
    // A path's last part is what's tested (/_blob/<hex>): what's before it isn't the key's. Not a hook's address,
    // which often carries its secret as its last part, nor one set as a name that says it's secret.
    NSString *as = named[@"as"];
    NSRange slash = [bare rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location != NSNotFound && slash.location + 1 < bare.length) {
        if ([bare rangeOfString:@"hook" options:NSCaseInsensitiveSearch].location != NSNotFound || is(secret, as))
            return NO;
        bare = [bare substringFromIndex:slash.location + 1];
    }
    if (!is(hex, bare)) return NO;
    NSTextCheckingResult *extension = as ? [file firstMatchInString:as options:0 range:NSMakeRange(0, as.length)] : nil;
    BOOL fileName = extension && ![KeyFileExtensions() containsObject:
                                   [as substringWithRange:[extension rangeAtIndex:1]].lowercaseString];
    return !is(secret, as) || fileName;
}

// A finding with what its line says of it besides its last 4 characters, read while the line is in hand: when its
// key stops working (TokenEnds), what it's for (NamedIn), whether it starts as a provider's keys do (`shaped`), and,
// for a kind with no provider that isn't so, whether it's only an id (`isId`: a UUID it isn't set as a name for), which
// only a yes is kept of. Nil when it's no key at all: inside a run of base64, a GitHub token whose checksum fails, a
// placeholder that counts up, a private key's header with no key after it, or, of a kind with no provider, a word, a
// variable's name or a hash.
// Called wherever LastFour is. A change to what it decides puts kRecordsShape up, so records read before are judged
// again.
static NSDictionary *WithLineFacts(NSDictionary *finding, NSData *line) {
    NSNumber *ends = TokenEnds(finding, line);
    NSDictionary *named = NamedIn(finding, line);
    NSRange key = KeySpan(finding, line, NULL);
    NSString *rule = AsText(finding[@"rule_id"]);
    BOOL oneLine = AsNumber(AsRecord(finding[@"location"])[@"start_line"]).integerValue
                == AsNumber(AsRecord(finding[@"location"])[@"end_line"]).integerValue;
    if (key.location == NSNotFound) return finding;
    if (oneLine && ![rule isEqualToString:@"private-key"] && InBlob(line, key)) return nil;
    if (oneLine && [rule isEqualToString:@"private-key"] && !PrivateKeyHasBody(line, key)) return nil;
    NSString *text = [[NSString alloc] initWithData:[line subdataWithRange:key] encoding:NSUTF8StringEncoding];
    BOOL shaped = text && KeyHasProviderStart(text), id = NO;
    if (text && (KeyFailsItsChecksum(text) || (![rule isEqualToString:@"private-key"] && CountsUp(text)))) return nil;
    text = nil;
    if (KeyKindHasNoProvider(rule) && ![rule hasPrefix:@"jwt"] && !shaped) {
        NSString *value = KeyValue(line, key, rule);
        if (NotAKey(line, key, value, named)) return nil;
        // A UUID is an id when it's set as no name, or one that says nothing secret (a lookup's `key`, a dict's), as
        // some services' keys are UUIDs (HEROKU_API_KEY); and so is what a Spotify address names (spotify:track:…).
        id = ([[NSUUID alloc] initWithUUIDString:value] && !KeyNameSaysSecret(named[@"as"]))
          || KeyAfterIdPrefix(line, key);
        value = nil;
    }
    if (!ends && !named && !shaped && !id) return finding;
    NSMutableDictionary *with = [finding mutableCopy];
    if (ends) with[@"ends"] = ends;
    if (named) with[@"named"] = named;
    if (shaped) with[@"shaped"] = @YES;
    if (id) with[@"isId"] = @YES;
    return with;
}

// What a key shows: the part every key of its kind starts with, and its last 4 characters. A private key shows
// neither: its start says only that it's a private key, and its end is the same in every one.
static NSString *Masked(NSString *rule, NSString *last) {
    if ([rule isEqualToString:@"private-key"]) return @"";
    return [NSString stringWithFormat:@"%@…%@", KeyKind(rule)[@"start"] ?: @"", last];
}

// A kind Keys has no name for, named from its rule: generic-api-key is a "Generic api key".
static NSString *KindName(NSString *rule) {
    NSString *name = KeyKind(rule)[@"name"];
    if (name) return name;
    if ([rule isEqualToString:@"generic-credential-uri"]) return @"Password in an address";
    NSString *words = [[rule componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-."]]
                       componentsJoinedByString:@" "];
    return words.length ? [[words substringToIndex:1].uppercaseString stringByAppendingString:[words substringFromIndex:1]]
                        : @"Key";
}

// A key's text again, from a line it was found in, by its id: the part of the line that ends in its last 4
// characters and has its fingerprint. For a check made while the line is in hand, never kept.
static NSString *KeyAgain(NSData *line, NSString *keyId, NSString *last, NSString *secret) {
    NSData *tail = [last dataUsingEncoding:NSUTF8StringEncoding];
    if (!line.length || !tail.length || !keyId.length || !secret) return nil;
    NSRange search = NSMakeRange(0, line.length);
    for (;;) {
        NSRange at = [line rangeOfData:tail options:0 range:search];
        if (at.location == NSNotFound) return nil;
        NSUInteger end = NSMaxRange(at);
        for (NSUInteger start = at.location + 1; start-- > 0 && end - start <= 600;) {
            NSString *text = [[NSString alloc] initWithData:[line subdataWithRange:NSMakeRange(start, end - start)]
                                                   encoding:NSUTF8StringEncoding];
            if (text && [KeyId([@"hmac-sha256:" stringByAppendingString:Fingerprint(secret, text)]) isEqual:keyId])
                return text;
        }
        search = NSMakeRange(end, line.length - end);
    }
}

// The line (from 1) a file holds a text on, or 0 when it doesn't hold it, or can't be read. It's opened without
// waiting and read through the descriptor that was checked as a plain file, so one changed for a pipe since never
// holds a look up.
static NSInteger LineHolding(NSString *path, NSString *text) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NONBLOCK);
    if (fd < 0) return 0;
    struct stat info;
    if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || (unsigned long long)info.st_size > kRecordLargest) {
        close(fd);
        return 0;
    }
    NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    NSData *data = [handle readDataToEndOfFileAndReturnError:nil];
    NSData *wanted = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSRange at = data.length && wanted.length ? [data rangeOfData:wanted options:0 range:NSMakeRange(0, data.length)]
                                              : NSMakeRange(NSNotFound, 0);
    if (at.location == NSNotFound) return 0;
    NSInteger line = 1;
    const char *bytes = data.bytes;
    for (NSUInteger i = 0; i < at.location; i++) if (bytes[i] == '\n') line++;
    return line;
}

// Every string a JSON value holds, as text.
static void StringsIn(id value, NSMutableArray<NSString *> *into) {
    if ([value isKindOfClass:NSString.class]) [into addObject:value];
    else if ([value isKindOfClass:NSArray.class]) for (id each in value) StringsIn(each, into);
    else if ([value isKindOfClass:NSDictionary.class]) for (id each in [value allValues]) StringsIn(each, into);
}

// Text to feed Betterleaks, a line at a time, each line knowing what it came from (its origin: a record's file and
// line, a remote's name, a field of Whozmove's own record), so a finding can be put back where it was.
// Whether what's said around a key calls it made up: a sample, made up, fake, a dummy, a placeholder, a test's key or
// token, or not real. A word that's denied just before it (not, isn't, no, never, instead of, rather than) or that
// sits beside "real" doesn't count: "my real key, not a test key" says it's real. Only the yes or no is kept.
static BOOL SaysMadeUp(NSString *text) {
    static NSRegularExpression *words, *denied, *real;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSRegularExpressionOptions any = NSRegularExpressionCaseInsensitive;
        words = [NSRegularExpression regularExpressionWithPattern:@"\\b(samples?|made[ -]up|fake|dummy|placeholders?|"
                                                                  "not (a )?real|test (keys?|tokens?|secrets?))\\b"
                                                          options:any error:nil];
        denied = [NSRegularExpression regularExpressionWithPattern:
                  @"\\b(not|isn't|no|never|instead of|rather than)\\b[^.!?\\n]{0,12}$" options:any error:nil];
        real = [NSRegularExpression regularExpressionWithPattern:@"\\breal\\b" options:any error:nil];
    });
    if (!text) return NO;
    for (NSTextCheckingResult *word in [words matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSRange at = word.range;
        if ([[text substringWithRange:at].lowercaseString hasPrefix:@"not"]) return YES;
        NSUInteger from = at.location > 24 ? at.location - 24 : 0, to = MIN(NSMaxRange(at) + 24, text.length);
        if ([denied numberOfMatchesInString:text options:0 range:NSMakeRange(from, at.location - from)]) continue;
        if ([real numberOfMatchesInString:text options:0 range:NSMakeRange(from, to - from)]) continue;
        return YES;
    }
    return NO;
}

@interface KeyFeed : NSObject
@property (strong) NSMutableData *text, *starts, *owners;  // the text; where each line starts in it; each one's origin
@property (strong) NSMutableData *texts;                    // which text each line is of
@property (assign) NSUInteger textCount;                    // the texts added so far, the next one's number
@property (strong) NSMutableArray<NSDictionary *> *origins;
@end

@implementation KeyFeed
- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.text = [NSMutableData data];
    self.starts = [NSMutableData data];
    self.owners = [NSMutableData data];
    self.texts = [NSMutableData data];
    self.origins = [NSMutableArray array];
    return self;
}

- (NSUInteger)origin:(NSDictionary *)origin {
    [self.origins addObject:origin];
    return self.origins.count - 1;
}

// Some text, as lines of its own: a line break in it starts a new one. Then a line that's only a separator (neither a
// space nor a character a key or a name has), which ends any match made of a key's or a name's characters, so a
// record's text ending "…tokens>" and the next one, a session's id, are never taken together for a key. A rule whose
// pattern takes any character (a private key's, from its header to a footer) can still run over it: look: drops such
// a match and looks through the texts it ran over again.
- (void)add:(NSString *)text from:(NSUInteger)origin {
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    const char *at = bytes.bytes, *end = at + bytes.length;
    while (at <= end) {
        const char *next = memchr(at, '\n', (size_t)(end - at)) ?: end;
        [self line:at length:(NSUInteger)(next - at) from:origin];
        at = next + 1;
    }
    [self line:"\x1f" length:1 from:origin];
    self.textCount++;
}

- (void)line:(const char *)bytes length:(NSUInteger)length from:(NSUInteger)origin {
    NSUInteger start = self.text.length;
    [self.starts appendBytes:&start length:sizeof start];
    [self.owners appendBytes:&origin length:sizeof origin];
    NSUInteger text = self.textCount;
    [self.texts appendBytes:&text length:sizeof text];
    [self.text appendBytes:bytes length:length];
    [self.text appendBytes:"\n" length:1];
}

- (NSUInteger)lines {
    return self.starts.length / sizeof(NSUInteger);
}

// The fed line `line` (from 1), and its origin.
- (NSData *)line:(NSInteger)line {
    if (line < 1 || (NSUInteger)line > self.lines) return nil;
    const NSUInteger *starts = self.starts.bytes;
    NSUInteger start = starts[line - 1], end = (NSUInteger)line < self.lines ? starts[line] - 1 : self.text.length - 1;
    return [self.text subdataWithRange:NSMakeRange(start, end - start)];
}

- (NSDictionary *)originOf:(NSInteger)line {
    if (line < 1 || (NSUInteger)line > self.lines) return nil;
    return self.origins[((const NSUInteger *)self.owners.bytes)[line - 1]];
}

// Which text a fed line is of: each text added has its own number, though several share an origin (a record line's
// strings), and keeps it in a feed made of some of its lines.
- (NSUInteger)textOf:(NSInteger)line {
    if (line < 1 || (NSUInteger)line > self.lines) return NSNotFound;
    return ((const NSUInteger *)self.texts.bytes)[line - 1];
}

// The files its lines are from, in the order they were fed, with "" standing for all the origins that name none.
- (NSArray<NSString *> *)files {
    NSMutableOrderedSet<NSString *> *files = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *origin in self.origins) [files addObject:AsText(origin[@"file"]) ?: @""];
    return files.array;
}

// A feed of only the lines `keep` takes (by the line, from 1, and its origin), each from the same origin and of the
// same text as here.
- (KeyFeed *)only:(BOOL (^)(NSInteger line, NSDictionary *origin))keep {
    KeyFeed *some = [[KeyFeed alloc] init];
    const NSUInteger *owners = self.owners.bytes, *texts = self.texts.bytes;
    NSMutableDictionary<NSNumber *, NSNumber *> *origins = [NSMutableDictionary dictionary];
    for (NSInteger line = 1; (NSUInteger)line <= self.lines; line++) {
        NSNumber *owner = @(owners[line - 1]);
        if (!keep(line, self.origins[owner.unsignedIntegerValue])) continue;
        if (!origins[owner]) origins[owner] = @([some origin:self.origins[owner.unsignedIntegerValue]]);
        NSData *bytes = [self line:line];
        some.textCount = texts[line - 1];
        [some line:bytes.bytes length:bytes.length from:origins[owner].unsignedIntegerValue];
    }
    return some;
}

// Which line of its own text a fed line is (from 1): of a whole file fed as it is, its line in the file.
- (NSInteger)lineInOrigin:(NSInteger)line {
    if (line < 1 || (NSUInteger)line > self.lines) return 0;
    const NSUInteger *owners = self.owners.bytes;
    NSInteger first = line;
    while (first > 1 && owners[first - 2] == owners[line - 1]) first--;
    return line - first + 1;
}

// What was fed around a key found from line `from`, byte `start`, to line `to`, byte `end` (each from 1): up to
// `before` bytes ahead of it, over the lines before it of the same origin (one record's), and `after` past it, to its
// line's end. Read only to tell what's said of the key there.
- (NSString *)around:(NSInteger)from at:(NSInteger)start to:(NSInteger)to at:(NSInteger)end
              before:(NSUInteger)before after:(NSUInteger)after {
    if (from < 1 || to < from || (NSUInteger)to > self.lines) return nil;
    const NSUInteger *starts = self.starts.bytes, *owners = self.owners.bytes;
    NSUInteger last = (NSUInteger)to < self.lines ? starts[to] - 1 : self.text.length - 1;
    NSUInteger key = starts[from - 1] + (NSUInteger)MAX(start - 1, 0);
    NSUInteger past = MIN(starts[to - 1] + (NSUInteger)MAX(end, 0), last);
    NSInteger first = from;
    while (first > 1 && owners[first - 2] == owners[from - 1] && key - starts[first - 2] <= before) first--;
    NSUInteger low = MAX(starts[first - 1], key > before ? key - before : 0), high = MIN(past + after, last);
    if (high <= low) return nil;
    return [[NSString alloc] initWithData:[self.text subdataWithRange:NSMakeRange(low, high - low)]
                                 encoding:NSISOLatin1StringEncoding];
}
@end

@interface KeyScan ()
@property (copy) NSString *folder;
@property (strong) dispatch_queue_t queue;
@property (readwrite, copy) NSDictionary *found;
@property (readwrite) BOOL looking;
@property (assign) BOOL again;                        // another look was asked for while one was under way
@property (copy) NSArray<NSString *> *againIn;
@property (strong) NSMutableArray<NSString *> *problems;  // what one look couldn't finish, said with what it found
@property (assign) NSUInteger recordsRead;
@property (assign) NSInteger major;                      // the version of Betterleaks the app carries, as it says
@property (copy) NSString *said;                         // and its whole version, as it says it
@property (copy) NSString *why;                          // why it didn't run, when it didn't
@property (strong) NSMutableDictionary *skipped;         // what one look left out, and why
@property (copy) NSDictionary *soFar;                    // what the look under way has found, as each place is read
@property (strong) NSMutableDictionary *recordsNow;      // each agent's records, as asked once this look
@end

@implementation KeyScan

- (instancetype)initWithFolder:(NSString *)folder {
    if (!(self = [super init])) return nil;
    self.folder = folder;
    self.runFor = kRunFor;
    self.keepEvery = kKeepEvery;
    // In the background, as Betterleaks runs (`run:`): a look waits behind whatever you're doing, on the efficiency
    // cores, however long that makes it.
    self.queue = dispatch_queue_create("whozmove.keys", dispatch_queue_attr_make_with_qos_class(
        DISPATCH_QUEUE_SERIAL, QOS_CLASS_BACKGROUND, 0));
    NSDictionary *kept = AsRecord(ReadJSON([folder stringByAppendingPathComponent:@"found.json"]));
    self.found = [AsNumber(kept[@"shape"]) integerValue] == kFoundShape ? kept : nil;
    return self;
}

- (NSString *)file:(NSString *)name {
    return [self.folder stringByAppendingPathComponent:name];
}

// Its folder, readable by you only, made if it isn't there (with Whozmove's own, the first time).
- (BOOL)ready {
    for (NSString *folder in @[self.folder, [self file:@"home"]]) {
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES
                                                 attributes:@{NSFilePosixPermissions: @0700} error:nil];
        chmod(folder.fileSystemRepresentation, 0700);
    }
    BOOL folder = NO;
    return [NSFileManager.defaultManager fileExistsAtPath:self.folder isDirectory:&folder] && folder;
}

// The secret the fingerprints are made with: made once, 32 random bytes in hex, and kept readable by you only.
- (NSString *)secret {
    NSString *path = [self file:@"secret"];
    NSString *kept = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    kept = [kept stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (kept.length == 64) return kept;
    uint8_t random[32];
    arc4random_buf(random, sizeof random);
    NSMutableString *hex = [NSMutableString string];
    for (size_t i = 0; i < sizeof random; i++) [hex appendFormat:@"%02x", random[i]];
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return nil;
    NSData *data = [hex dataUsingEncoding:NSUTF8StringEncoding];
    BOOL wrote = write(fd, data.bytes, data.length) == (ssize_t)data.length;
    close(fd);
    return wrote ? hex : nil;
}

#pragma mark Running Betterleaks

// Its own home folder, so it reads no settings of yours and keeps its cache with Whozmove's, and nothing of the app's
// environment, so no setting there can turn on its online checks or name other rules.
- (NSDictionary *)environment {
    return @{@"HOME": [self file:@"home"], @"PATH": @"/usr/bin:/bin", @"TMPDIR": NSTemporaryDirectory()};
}

// Why a run of Betterleaks didn't end well, in macOS's own words where it has some (an error's, a signal's): it
// couldn't start, ran past its time, was stopped by a signal, or ended with an exit code of its own. Never what a run
// over your files printed, which could hold a key.
static NSString *WhyItEnded(NSDictionary *ran, NSString *path, NSTimeInterval seconds) {
    if (!ran) {
        int error = access(path.fileSystemRepresentation, X_OK) == 0 ? 0 : errno;
        return error ? [NSString stringWithFormat:@"it couldn't start (%s)", strerror(error)] : @"it couldn't start";
    }
    if ([ran[@"timedOut"] boolValue]) return [NSString stringWithFormat:@"it ran past %.0f seconds", seconds];
    int status = [ran[@"status"] intValue];
    if (status > 128) return [NSString stringWithFormat:@"it was stopped (%s)", strsignal(status - 128)];
    return [NSString stringWithFormat:@"it ended with exit code %d", status];
}

// Which version of Betterleaks the app carries, asked of it once a look (KeyFacts has each one's spelling): its major
// version, 0 for one Keys doesn't know, or -1 if it didn't run.
- (NSInteger)askVersion {
    self.why = nil;
    NSDictionary *said = RunBriefly(self.scanner, @[@"version"], self.environment, 20, 4096, NO);
    if (!said || [said[@"status"] intValue] != 0) {
        // Asked again with its errors, for the last thing it said: a version's run reads none of your files.
        NSString *why = WhyItEnded(said, self.scanner, 20);
        NSDictionary *again = said && ![said[@"timedOut"] boolValue]
            ? RunBriefly(self.scanner, @[@"version"], self.environment, 20, 4096, YES) : nil;
        NSString *out = again ? [[NSString alloc] initWithData:again[@"out"] encoding:NSUTF8StringEncoding] : nil;
        NSString *last = [[out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
                          componentsSeparatedByString:@"\n"].lastObject;
        if (last.length > 160) last = [[last substringToIndex:160] stringByAppendingString:@"…"];
        self.why = last.length ? [NSString stringWithFormat:@"%@, saying “%@”", why, last] : why;
        return -1;
    }
    NSString *text = [[[NSString alloc] initWithData:said[@"out"] encoding:NSUTF8StringEncoding]
                      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.said = text;
    return BetterleaksMajor(text);
}

// Version 1's own rules, which it's always given: written once for each version, as it shows them run in an empty
// folder (where no project's settings file is), into Keys' own, readable by you only. Nil if they couldn't be.
- (NSString *)versionOneRules {
    NSCharacterSet *plain = [NSCharacterSet characterSetWithCharactersInString:
                             @"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-"];
    NSString *version = [[self.said componentsSeparatedByCharactersInSet:plain.invertedSet] componentsJoinedByString:@""];
    NSString *path = [self file:[NSString stringWithFormat:@"home/rules-%@.toml", version.length ? version : @"1"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:path]) return path;
    NSString *empty = [self file:@"home/empty"];
    [NSFileManager.defaultManager createDirectoryAtPath:empty withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSMutableData *rules = [NSMutableData data];
    NSDictionary *ran = RunConversation(self.scanner, @[@"config", @"show", @"--no-color", @"--log-level=error",
                                                        kBetterleaksMatcher],
                                        self.environment, empty, NSData.data, ^BOOL(NSData *line) {
        [rules appendData:line];
        [rules appendBytes:"\n" length:1];
        return NO;
    }, 30, nil);
    NSString *text = [[NSString alloc] initWithData:rules encoding:NSUTF8StringEncoding];
    if ([ran[@"status"] intValue] != 0 || ![text containsString:@"[[rules]]"]) {
        LogProblem([@"Keys: Betterleaks didn't show its rules: " stringByAppendingString:
                    ran && [ran[@"status"] intValue] == 0 ? @"they weren't there" : WhyItEnded(ran, self.scanner, 30)]);
        return nil;
    }
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) return nil;
    BOOL wrote = write(fd, rules.bytes, rules.length) == (ssize_t)rules.length;
    close(fd);
    return wrote ? path : nil;
}

// Runs Betterleaks in `mode`, given `targets` (and git mode its commits, `range`), and fed `feed`'s text if there is
// one: each finding, in one shape whichever version reports it, without the key. NO if it didn't run to its end,
// which the look says.
- (BOOL)run:(NSString *)mode targets:(NSArray<NSString *> *)targets range:(NSString *)range feed:(KeyFeed *)feed
     secret:(NSString *)secret each:(void (^)(NSDictionary *finding))each {
    NSInteger major = self.major;
    NSMutableDictionary *with = [@{@"empty": [self file:@"home/empty"]} mutableCopy];
    if (range) with[@"range"] = range;
    if (major == 1) {
        NSString *rules = [self versionOneRules];
        if (!rules) return NO;
        with[@"rules"] = rules;
    }
    NSMutableArray *arguments = [BetterleaksArguments(major, mode, with) mutableCopy];
    [arguments addObjectsFromArray:targets];
    NSString *(^fingerprint)(NSString *) = ^NSString *(NSString *key) {
        return [@"hmac-sha256:" stringByAppendingString:Fingerprint(secret, key)];
    };
    __block NSUInteger fed = 0;
    NSData *(^more)(void) = ^NSData * {
        if (!feed || fed >= feed.text.length) return nil;
        NSUInteger length = MIN((NSUInteger)(1024 * 1024), feed.text.length - fed);
        NSData *piece = [feed.text subdataWithRange:NSMakeRange(fed, length)];
        fed += length;
        return piece;
    };
    // Version 2 reports a record a line as it goes, and says at the end that it finished; version 1, its whole report
    // at its end, which is read once it has ended. Either way, what's kept of a record is what BetterleaksFinding
    // gives, without the key.
    BOOL lines = BetterleaksReportsLines(major);
    __block BOOL complete = NO;
    NSMutableData *report = [NSMutableData data];
    NSMutableDictionary *environment = [self.environment mutableCopy];
    [environment addEntriesFromDictionary:BetterleaksEnvironment(major, secret)];
    NSDictionary *ran = RunFeeding(self.scanner, arguments, environment, more, ^(NSData *line) {
        if (!lines) {
            [report appendData:line];
            [report appendBytes:"\n" length:1];
            return;
        }
        NSDictionary *record = AsRecord([NSJSONSerialization JSONObjectWithData:line options:0 error:nil]);
        NSDictionary *finding = record ? BetterleaksFinding(major, record, fingerprint) : nil;
        if (finding) each(finding);
        else if (BetterleaksFinished(record)) complete = YES;
    }, self.runFor, YES);
    if (!lines) {
        NSArray *all = AsList([NSJSONSerialization JSONObjectWithData:report options:0 error:nil]);
        complete = all != nil;
        for (id record in all) {
            NSDictionary *finding = AsRecord(record) ? BetterleaksFinding(major, record, fingerprint) : nil;
            if (finding) each(finding);
        }
        [report resetBytesInRange:NSMakeRange(0, report.length)];
    }
    BOOL finished = ran && [ran[@"status"] intValue] == 0 && complete;
    if (!finished)
        LogProblem([NSString stringWithFormat:@"Keys: Betterleaks didn't finish looking (%@): %@", mode,
                    ran && [ran[@"status"] intValue] == 0 && ![ran[@"timedOut"] boolValue]
                        ? @"its report was cut short" : WhyItEnded(ran, self.scanner, self.runFor)]);
    return finished;
}

// The files, in their order, a run's worth at a time: kFilesAtOnce files, or kFeedAtOnce bytes of what Betterleaks
// reads, whichever comes first, so a run of large files stays as short as a run of fed text. A file is counted at its
// own size, not where a link leads (lstat), and one larger than Betterleaks looks in at its limit at most, which it
// skips unread or reads only up to, as counting a little too much costs only another run. Every run takes at least
// one file, so a large one never stops the rest.
static NSArray<NSArray<NSString *> *> *FileRuns(NSArray<NSString *> *paths) {
    NSMutableArray *runs = [NSMutableArray array];
    NSMutableArray *run = [NSMutableArray array];
    unsigned long long bytes = 0;
    for (NSString *path in paths) {
        struct stat info;
        unsigned long long size =
            lstat(path.fileSystemRepresentation, &info) == 0 ? (unsigned long long)info.st_size : 0;
        size = MIN(size, kBetterleaksLargestFile);
        if (run.count && (run.count == kFilesAtOnce || bytes + size > kFeedAtOnce)) {
            [runs addObject:run];
            run = [NSMutableArray array];
            bytes = 0;
        }
        [run addObject:path];
        bytes += size;
    }
    if (run.count) [runs addObject:run];
    return runs;
}

// Files, a few hundred to a run (FileRuns): each finding, with the file and its line, read again for its last 4
// characters.
- (void)scanFiles:(NSArray<NSString *> *)all secret:(NSString *)secret what:(NSString *)what
             each:(void (^)(NSDictionary *finding, NSString *path, NSInteger line, NSString *last))each {
    NSArray *paths = [all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *path, id _) {
        return !OnlyInCloud(path);
    }]];
    for (NSArray *some in FileRuns(paths)) {
        BOOL ran = [self run:@"fs" targets:some range:nil feed:nil secret:secret each:^(NSDictionary *finding) {
            NSDictionary *at = AsRecord(finding[@"location"]);
            NSString *path = AsText(at[@"path"]);
            if (!path) return;
            NSInteger line = AsNumber(at[@"end_line"]).integerValue;
            NSData *text = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
            NSData *found = LineOf(text, line);
            NSDictionary *key = WithLineFacts(finding, found);
            if (key) each(key, path, AsNumber(at[@"start_line"]).integerValue,
                          LastFour(found, AsNumber(at[@"end_column"]).integerValue));
        }];
        if (!ran) [self couldNotFinish:what];
    }
}

// A run that didn't go to its end: its place named once in what the look says.
- (void)couldNotFinish:(NSString *)what {
    if (![self.problems containsObject:what]) [self.problems addObject:what];
}

// How many times a run's spanning finds have their texts run again together before what's still left is run a text at
// a time: each time leaves at least a text out, so it ends anyway, but a page made to need many isn't given a run for
// each it leaves out.
static const NSUInteger kSpanRounds = 8;

// One run over a feed, its findings given out only once it has finished, so one cut short gives none. A run that
// doesn't finish is run again in halves, by the files its lines are from, down to one file a run, so only a file
// Betterleaks can't get through goes unread: the files given back. A finding whose first and last lines are of
// different texts isn't a key, whatever a rule's pattern lets it take: a private key's header with no end, in a tool's
// output, runs on to the next text's footer, and Betterleaks then reports no match of that rule overlapping it. So it's
// dropped, and the texts after its first, to its last, are run again for that rule (`wanted`: the others' finds there
// were given out already), after which a run that doesn't finish is one for their files. A find there of that rule
// after the span's end, given out already too, comes again, and each record keeps it once. Texts still spanning after
// kSpanRounds are run one at a time, as a text on its own can't span, so a run of planted headers can't keep the keys
// after them from being found.
- (NSSet<NSString *> *)look:(KeyFeed *)feed secret:(NSString *)secret rounds:(NSUInteger)rounds
                      rules:(NSSet<NSString *> *)wanted each:(void (^)(NSDictionary *finding, KeyFeed *fed))each {
    NSMutableArray<NSDictionary *> *held = [NSMutableArray array];
    BOOL ran = [self run:@"stdin" targets:@[] range:nil feed:feed secret:secret each:^(NSDictionary *finding) {
        if (!wanted || [wanted containsObject:finding[@"rule_id"]]) [held addObject:finding];
    }];
    if (!ran) {
        NSArray<NSString *> *files = feed.files;
        if (files.count < 2) return [NSSet setWithArray:files.count ? files : @[@""]];
        NSSet<NSString *> *first = [NSSet setWithArray:[files subarrayWithRange:NSMakeRange(0, files.count / 2)]];
        NSMutableSet<NSString *> *failed = [NSMutableSet set];
        for (NSNumber *half in @[@YES, @NO])
            [failed unionSet:[self look:[feed only:^BOOL(NSInteger line, NSDictionary *origin) {
                return [first containsObject:AsText(origin[@"file"]) ?: @""] == half.boolValue;
            }] secret:secret rounds:rounds rules:wanted each:each]];
        return failed;
    }
    NSMutableIndexSet *again = [NSMutableIndexSet indexSet];
    NSMutableSet<NSString *> *rules = [NSMutableSet set];
    for (NSDictionary *finding in held) {
        NSDictionary *at = AsRecord(finding[@"location"]);
        NSUInteger from = [feed textOf:AsNumber(at[@"start_line"]).integerValue],
                   to = [feed textOf:AsNumber(at[@"end_line"]).integerValue];
        if (from == to) {
            each(finding, feed);
            continue;
        }
        if (from == NSNotFound || to == NSNotFound || to < from || !AsText(finding[@"rule_id"])) continue;
        [again addIndexesInRange:NSMakeRange(from + 1, to - from)];
        [rules addObject:finding[@"rule_id"]];
    }
    [held removeAllObjects];
    if (!again.count) return [NSSet set];
    KeyFeed *spanned = [feed only:^BOOL(NSInteger line, NSDictionary *origin) {
        return [again containsIndex:[feed textOf:line]];
    }];
    if (rounds) return [self look:spanned secret:secret rounds:rounds - 1 rules:rules each:each];
    NSMutableIndexSet *left = [NSMutableIndexSet indexSet];
    for (NSInteger line = 1; (NSUInteger)line <= spanned.lines; line++) [left addIndex:[spanned textOf:line]];
    NSMutableSet<NSString *> *failed = [NSMutableSet set];
    [left enumerateIndexesUsingBlock:^(NSUInteger text, BOOL *stop) {
        [failed unionSet:[self look:[spanned only:^BOOL(NSInteger line, NSDictionary *origin) {
            return [spanned textOf:line] == text;
        }] secret:secret rounds:0 rules:rules each:each]];
    }];
    return failed;
}

// What a feed holds, a run at a time once it's grown big enough, or now if `now`: each finding with the origin of its
// line, and its last 4 characters. The feed is emptied once it's been looked through. Gives back the files whose lines
// a run couldn't look through (none if it could), each said as its app's or as `what`, or nil when it hasn't run.
- (NSSet<NSString *> *)scanFeed:(KeyFeed *)feed now:(BOOL)now secret:(NSString *)secret what:(NSString *)what
            each:(void (^)(NSDictionary *finding, NSDictionary *origin, NSString *last, KeyFeed *feed))each {
    if (!feed.text.length || (!now && feed.text.length < kFeedAtOnce)) return nil;
    NSSet<NSString *> *failed = [self look:feed secret:secret rounds:kSpanRounds rules:nil
                                      each:^(NSDictionary *finding, KeyFeed *fed) {
        NSDictionary *at = AsRecord(finding[@"location"]);
        NSInteger line = AsNumber(at[@"end_line"]).integerValue;
        NSMutableDictionary *origin = [[fed originOf:AsNumber(at[@"start_line"]).integerValue] mutableCopy];
        // The line in its own text, for a whole file fed as it is (an instruction file's, opened at it).
        origin[@"textLine"] = @([fed lineInOrigin:AsNumber(at[@"start_line"]).integerValue]);
        NSData *found = [fed line:line];
        NSDictionary *key = WithLineFacts(finding, found);
        NSString *around = key ? [fed around:AsNumber(at[@"start_line"]).integerValue
                                          at:AsNumber(at[@"start_column"]).integerValue to:line
                                          at:AsNumber(at[@"end_column"]).integerValue before:240 after:80] : nil;
        if (SaysMadeUp(around)) {
            NSMutableDictionary *with = [key mutableCopy];
            with[@"madeUp"] = @YES;
            key = with;
        }
        around = nil;
        if (origin && key) each(key, origin, LastFour(found, AsNumber(at[@"end_column"]).integerValue), fed);
    }];
    for (NSDictionary *origin in feed.origins)
        if ([failed containsObject:AsText(origin[@"file"]) ?: @""])
            [self couldNotFinish:AsText(origin[@"app"]) ?: what];
    feed.text.length = 0;
    feed.starts.length = 0;
    feed.owners.length = 0;
    feed.texts.length = 0;
    [feed.origins removeAllObjects];
    return failed;
}

#pragma mark What's found, put together

// A key found in a place: its item, made the first time it's seen, with the place added once. Found by a generic
// rule in one place and by its own kind's in another, it's named as its kind.
static void AddPlace(NSMutableDictionary *keys, NSDictionary *finding, NSString *last, NSDictionary *place) {
    NSString *id = KeyId(AsText(AsRecord(finding[@"match"])[@"fingerprint"])), *rule = AsText(finding[@"rule_id"]);
    if (!id || !rule) return;
    NSMutableDictionary *item = keys[id];
    if (!item || ([item[@"rule"] hasPrefix:@"generic-"] && ![rule hasPrefix:@"generic-"])) {
        NSMutableArray *places = item[@"places"] ?: [NSMutableArray array];
        BOOL onlyId = (!item || [item[@"onlyId"] boolValue]) && [finding[@"isId"] boolValue];
        BOOL madeUp = [item[@"madeUp"] boolValue], agentFirst = [item[@"agentFirst"] boolValue],
             otherFirst = [item[@"otherFirst"] boolValue];
        keys[id] = item = [@{@"id": id, @"rule": rule, @"name": KindName(rule), @"masked": Masked(rule, last),
                             @"places": places, @"onlyId": @(onlyId)} mutableCopy];
        if (madeUp) item[@"madeUp"] = @YES;
        if (agentFirst) item[@"agentFirst"] = @YES;
        if (otherFirst) item[@"otherFirst"] = @YES;
    }
    // Called made up where it was said, in a conversation.
    if ([finding[@"madeUp"] boolValue] && [@[@"claude", @"ai"] containsObject:place[@"group"]]) item[@"madeUp"] = @YES;
    // Who first said it in each record it's in: the agent, in its own words, or anyone else, anywhere.
    if ([finding[@"firstBy"] isEqual:@"agent"]) item[@"agentFirst"] = @YES;
    else if (finding[@"firstBy"]) item[@"otherFirst"] = @YES;
    // Only an id while every place found it as one: one that sets it as a name says it's a key.
    if (![finding[@"isId"] boolValue]) item[@"onlyId"] = @NO;
    if (finding[@"ends"]) item[@"ends"] = finding[@"ends"];
    if ([finding[@"shaped"] boolValue]) item[@"shaped"] = @YES;
    if (finding[@"named"] && !place[@"named"]) {
        NSMutableDictionary *with = [place mutableCopy];
        with[@"named"] = finding[@"named"];
        place = with;
    }
    NSMutableArray *places = item[@"places"];
    if ([places containsObject:place]) return;
    // One place once, whichever rule found it there: two rules can match the same line, and only one may leave what
    // the key is set as plain to read, so the place that says it is kept. Only places that say one differ that way.
    NSMutableDictionary *bare = [place mutableCopy];
    [bare removeObjectForKey:@"named"];
    for (NSUInteger i = 0; i < places.count; i++) {
        if (!place[@"named"] && !places[i][@"named"]) continue;
        NSMutableDictionary *was = [places[i] mutableCopy];
        [was removeObjectForKey:@"named"];
        if (![was isEqualToDictionary:bare]) continue;
        if (place[@"named"] && !places[i][@"named"]) places[i] = place;
        return;
    }
    [places addObject:place];
}

// Each key's places, most exposed first, and the group it's filed under, its most exposed; what can be done with each
// place (`can`): a file that only holds what was said or downloaded, or that git doesn't have yet, can go to the Trash
// (`trash`, with which file it is, so only that one goes); one with the key at a line opens there (`open`); a
// credential file others can read is made yours only (`private`); an agent's record opens its session's conversation
// (`conversation`) and has the agent's command that clears it (`clear`). And with the key itself (`actions`):
// replacing it at its provider, where there's a page for that, which comes first for a key that has left the Mac
// (`left`), and ignoring it.
static NSArray<NSDictionary *> *Ways(NSDictionary *item);

// Keys most exposed first, then by kind and how they start.
static NSArray *SortedKeys(NSArray *keys) {
    return [keys sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSUInteger x = [kKeyGroups indexOfObject:a[@"group"]], y = [kKeyGroups indexOfObject:b[@"group"]];
        if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult name = [a[@"name"] compare:b[@"name"]];
        return name != NSOrderedSame ? name : [a[@"masked"] compare:b[@"masked"]];
    }];
}

// What to do about a key in a place, in a few words, for a place whose line has nothing else to say it: git has it,
// it's your shell history, an agent keeps it, it's in a remote's address, or it's already masked; nil for a credential
// file, whose fix says it, and for a file that's nothing but the key.
static NSString *KeepsIt(NSDictionary *place) {
    NSString *group = place[@"group"];
    if ([group isEqual:@"readable"]) return nil;  // its fix, Make It Yours Only, says what to do
    if ([place[@"app"] isEqual:@"Whozmove"]) return @"Masked in Whozmove's record already";
    if ([place[@"kind"] isEqual:@"instructions"])
        return [NSString stringWithFormat:@"%@ reads it into its sessions: take the key out of this file",
                place[@"app"]];
    if ([group isEqual:@"claude"])
        return [NSString stringWithFormat:place[@"clear"] ? @"%@ keeps it: its clear-up command takes it out"
                                                          : @"%@ keeps it: replace the key", place[@"app"]];
    if (place[@"remote"]) return @"In the remote's address: take the token out of it";
    if ([place[@"trash"] boolValue]) return nil;  // nothing but the key: its menu moves it to the Trash
    if ([group isEqual:@"pushed"]) return @"Git has it, and it's pushed: replace the key";
    if ([group isEqual:@"commit"])
        return @"In a commit not pushed yet: change that commit (amend or rebase it) before you push";
    if ([group isEqual:@"ai"]) return [NSString stringWithFormat:@"%@ keeps it: replace the key", place[@"app"]];
    if ([place[@"untracked"] boolValue]) return @"Not in git yet: take the key out before it's committed";
    if (place[@"checkout"]) return @"Git has this file: take the key out of it";
    if ([place[@"downloads"] boolValue]) return @"It holds more than the key: take the key out of it";
    if ([place[@"startup"] boolValue])
        return @"Every terminal you open gets it from here: put the new key in its place once you've replaced it";
    return @"Your shell history: take the line out";
}

static BOOL ReadableByOthers(NSString *path, NSString *home);

static NSDictionary *Settled(NSMutableDictionary *item) {
    NSArray *sorted = [item[@"places"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSUInteger x = [kKeyGroups indexOfObject:a[@"group"]], y = [kKeyGroups indexOfObject:b[@"group"]];
        return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : [a[@"where"] compare:b[@"where"]];
    }];
    NSString *group = [sorted.firstObject objectForKey:@"group"];
    BOOL page = [KeyKind(item[@"rule"])[@"replace"] length] > 0, left = NO;
    NSMutableArray *places = [NSMutableArray array];
    for (NSDictionary *each in sorted) {
        NSMutableDictionary *place = [each mutableCopy];
        // A file that could go to the Trash and has gone since (moved there while the look ran) isn't listed.
        struct stat gone;
        if ([place[@"trash"] boolValue] && place[@"file"] && lstat([place[@"file"] fileSystemRepresentation], &gone) != 0)
            continue;
        if ([@[@"pushed", @"claude", @"ai"] containsObject:place[@"group"]]) left = YES;
        NSMutableArray *can = [NSMutableArray array];
        struct stat info;
        if ([place[@"trash"] boolValue] && place[@"file"]
            && lstat([place[@"file"] fileSystemRepresentation], &info) == 0 && S_ISREG(info.st_mode)) {
            place[@"item"] = [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev,
                              (unsigned long long)info.st_ino];
            [can addObject:@"trash"];
        }
        if ([place[@"group"] isEqual:@"readable"]) [can addObject:@"private"];
        else if (place[@"file"] && place[@"line"]) [can addObject:@"open"];
        // Your shell's settings, which other accounts on this Mac can read: made yours only, as a credential file is.
        if ([place[@"startup"] boolValue] && ReadableByOthers(place[@"file"], Home())) [can addObject:@"private"];
        if (place[@"session"]) [can addObject:@"conversation"];
        if (place[@"clear"]) [can addObject:@"clear"];
        // A file with no line to open at (a credential file, an SSH key), but not an agent's record, which opens as
        // its conversation.
        if (place[@"file"] && !place[@"line"] && ![place[@"group"] isEqual:@"claude"]) [can addObject:@"reveal"];
        place[@"can"] = can;
        NSString *keep = KeepsIt(place);
        if (keep) place[@"keep"] = keep;
        [places addObject:place];
    }
    // Most likely made up for a test (`sample`): in a project's files only where they're its tests' or examples'
    // (judged by the path inside the checkout), and elsewhere only where an agent's tool read it or its copy of a file
    // it edited (reading a sample doesn't make it real, but sending it does); of a kind with no provider (KeyFacts'
    // list: any key-like text, a password, a sign-in token, a sign-in sent with curl), and not starting as a provider's
    // keys do, as a provider's own key or a private key always counts. Or, of such a kind, called made up where it was
    // said, in a conversation (`said`), and found nowhere but in conversations and a project's tests' or examples'
    // files: a key that's in a file of its own too counts, and a provider's own shape is never folded on words alone.
    // Or most likely an id, not a key (`id`, folded as a sample is): of such a kind, a UUID wherever it was found, set
    // as no name. And how likely it is to be real (`real`), from what's known of it without asking anyone: an id
    // (`id`), made up for a test (`sample`), said to be made up (`said`), its own end date passed (`ended`), a
    // provider's own shape but only in tests' files (`test`), a provider's own shape (`shape`), in a credential file
    // (`kept`), typed in your shell (`typed`), sent in a message (`sent`), or a likely key in a file (`file`). And how
    // soon it needs you (`band`): now when it has left this Mac or is about to, unless it's ended; soon when it's only
    // on this Mac; never for a sample or an id.
    BOOL tests = NO, others = NO, elsewhere = NO;
    for (NSDictionary *place in places) {
        BOOL said = [@[@"claude", @"ai"] containsObject:place[@"group"]];
        if (place[@"inProject"] && !place[@"remote"]) {
            if (KeyInTestOrExample(place[@"inProject"])) tests = YES;
            else others = elsewhere = YES;
        } else if (!(said && ([place[@"how"] isEqual:@"read"] || [place[@"kind"] isEqual:@"edits"]))) others = YES;
        if (!said && !(place[@"inProject"] && !place[@"remote"] && KeyInTestOrExample(place[@"inProject"])))
            elsewhere = YES;
    }
    tests = tests && !others;
    NSString *rule = item[@"rule"];
    BOOL provider = !KeyKindHasNoProvider(rule) || [item[@"shaped"] boolValue];
    BOOL onlyId = [item[@"onlyId"] boolValue] && !provider;
    BOOL forTests = tests && !provider && ![rule isEqualToString:@"readable"];
    BOOL said = [item[@"madeUp"] boolValue] && !elsewhere && !onlyId && !forTests && !provider;
    // Made by the agent (`made`): in every record it's in, first in the agent's own words, and nowhere else: never in a
    // message you sent, in what an agent reads as its instructions, or in a file of yours. Whatever its shape: what an
    // agent made up for a test, a fixture or a demo isn't anyone's key. But never of a kind whose checksum Keys checks
    // (GitHub's): one that passes it was made by GitHub, whatever the agent said.
    BOOL made = [item[@"agentFirst"] boolValue] && ![item[@"otherFirst"] boolValue] && !onlyId && !forTests && !said
             && !KeyKindHasChecksum(rule);
    for (NSDictionary *place in places)
        if (![@[@"claude", @"ai"] containsObject:place[@"group"]] || [place[@"how"] isEqual:@"sent"]
            || [place[@"kind"] isEqual:@"instructions"])
            made = NO;
    BOOL sample = forTests || onlyId || said || made;
    BOOL ended = item[@"ends"] && [item[@"ends"] doubleValue] < NSDate.date.timeIntervalSince1970 * 1000;
    BOOL typed = NO, sent = NO;
    for (NSDictionary *place in places) {
        if ([place[@"history"] boolValue]) typed = YES;
        if ([place[@"how"] isEqual:@"sent"]) sent = YES;
    }
    item[@"sample"] = @(sample);
    [item removeObjectForKey:@"onlyId"];
    [item removeObjectForKey:@"madeUp"];
    [item removeObjectForKey:@"agentFirst"];
    [item removeObjectForKey:@"otherFirst"];
    item[@"real"] = onlyId ? @"id" : said ? @"said" : made ? @"made" : sample ? @"sample" : ended ? @"ended"
                  : [rule isEqualToString:@"readable"] ? @"kept" : tests && provider ? @"test" : provider ? @"shape"
                  : typed ? @"typed" : sent ? @"sent" : @"file";
    BOOL gone = [@[@"commit", @"pushed", @"claude", @"ai"] containsObject:group];
    item[@"band"] = sample ? @"sample" : ended ? @"soon" : gone ? @"now" : @"soon";
    NSMutableArray *actions = [NSMutableArray array];
    if (page && ![group isEqualToString:@"readable"]) [actions addObject:@"replace"];
    // Marked replaced: any key but a credential file others can read, which is about who can read it.
    if (![group isEqualToString:@"readable"]) [actions addObject:@"replaced"];
    [actions addObject:@"ignore"];
    item[@"places"] = places;
    item[@"group"] = group;
    item[@"left"] = @(left);
    item[@"actions"] = actions;
    item[@"ways"] = Ways(item);
    return item;
}

// What can be done about a key, its best first, each {action, place (an index in its places, or -1 for the key), title
// (on its button), menu (in the menu of the rest)}: replacing a key that has left the Mac at its provider; taking one
// in a commit not pushed yet out, at its line; making a credential file yours only; then opening the rest of its places
// at the line; replacing a key that hasn't left; opening the conversations it was in, and copying the agent's command
// that clears its records of those folders; moving a file that's nothing but the key to the Trash, which is never the
// first, as such a file always opens at its line first, and which is asked on the file's own line before it goes;
// marking it replaced; and Not a Key, which comes first for a key most likely made up for a test.
static NSArray<NSDictionary *> *Ways(NSDictionary *item) {
    NSString *provider = KeyKind(item[@"rule"])[@"name"];
    NSArray *places = item[@"places"];
    BOOL left = [item[@"left"] boolValue];
    NSMutableArray *ways = [NSMutableArray array];
    void (^add)(NSString *, NSInteger, NSString *, NSString *) = ^(NSString *action, NSInteger place, NSString *title,
                                                                  NSString *menu) {
        // Once each: the same place, or the same words (a file in every copy of a project opens the same way).
        for (NSDictionary *way in ways)
            if ([way[@"action"] isEqual:action]
                && ([way[@"place"] integerValue] == place || [way[@"menu"] isEqual:menu])) return;
        [ways addObject:@{@"action": action, @"place": @(place), @"title": title, @"menu": menu}];
    };
    NSString *(^name)(NSDictionary *) = ^NSString *(NSDictionary *place) {
        if (place[@"inProject"] && !place[@"remote"])
            return [NSString stringWithFormat:@"%@/%@", place[@"project"], place[@"inProject"]];
        return [place[@"file"] lastPathComponent] ?: @"the file";
    };
    // A file of a project is opened once, however many copies and commits it's in: its main copy's, else the first
    // worktree's, at its first line. Show Where lists every copy.
    NSString *(^fileOf)(NSDictionary *) = ^NSString *(NSDictionary *place) {
        return [NSString stringWithFormat:@"%@/%@", place[@"repo"] ?: place[@"project"], place[@"inProject"]];
    };
    NSMutableDictionary<NSString *, NSNumber *> *first = [NSMutableDictionary dictionary];
    [places enumerateObjectsUsingBlock:^(NSDictionary *place, NSUInteger i, BOOL *stop) {
        if (!place[@"inProject"] || place[@"remote"] || ![place[@"can"] containsObject:@"open"]) return;
        NSString *file = fileOf(place);
        NSDictionary *was = first[file] ? places[first[file].unsignedIntegerValue] : nil;
        BOOL main = [place[@"copy"] isEqual:@"main"], wasMain = [was[@"copy"] isEqual:@"main"];
        if (!was || (main && !wasMain)
            || (main == wasMain && [place[@"line"] integerValue] < [was[@"line"] integerValue]))
            first[file] = @(i);
    }];
    BOOL (^opens)(NSDictionary *, NSUInteger) = ^BOOL(NSDictionary *place, NSUInteger i) {
        if (![place[@"can"] containsObject:@"open"]) return NO;
        // An agent's copy of a file opens the file itself: not again where the file is a place of its own.
        if ([place[@"group"] isEqual:@"claude"])
            for (NSDictionary *other in places)
                if (![other[@"group"] isEqual:@"claude"] && [other[@"file"] isEqual:place[@"file"]]
                    && [other[@"can"] containsObject:@"open"])
                    return NO;
        NSNumber *only = place[@"inProject"] ? first[fileOf(place)] : nil;
        return !(place[@"inProject"] && !place[@"remote"]) || !only || only.unsignedIntegerValue == i;
    };
    NSString *replace = [NSString stringWithFormat:@"Replace at %@ ↗", provider ?: @"its provider"];
    if (left && [item[@"actions"] containsObject:@"replace"]) add(@"replace", -1, replace, replace);
    [places enumerateObjectsUsingBlock:^(NSDictionary *place, NSUInteger i, BOOL *stop) {
        if ([place[@"group"] isEqual:@"commit"] && opens(place, i))
            add(@"open", i, @"Open at the Line", [NSString stringWithFormat:@"Open %@ at Line %@", name(place),
                                                  place[@"line"]]);
        if ([place[@"can"] containsObject:@"private"])
            add(@"private", i, @"Make It Yours Only", [NSString stringWithFormat:@"Make %@ Yours Only", name(place)]);
    }];
    [places enumerateObjectsUsingBlock:^(NSDictionary *place, NSUInteger i, BOOL *stop) {
        if (opens(place, i))
            add(@"open", i, @"Open at the Line", [NSString stringWithFormat:@"Open %@ at Line %@", name(place),
                                                  place[@"line"]]);
    }];
    if (!left && [item[@"actions"] containsObject:@"replace"]) add(@"replace", -1, replace, replace);
    // An agent's records: each conversation opened, and each folder's clear-up command copied, once.
    NSMutableSet *sessions = [NSMutableSet set], *folders = [NSMutableSet set];
    [places enumerateObjectsUsingBlock:^(NSDictionary *place, NSUInteger i, BOOL *stop) {
        NSString *in = [place[@"folder"] lastPathComponent];
        if ([place[@"can"] containsObject:@"conversation"] && ![sessions containsObject:place[@"session"]]) {
            [sessions addObject:place[@"session"]];
            [ways addObject:@{@"action": @"conversation", @"place": @(i), @"title": @"Open the Conversation",
                              @"menu": in ? [@"Open the Conversation in " stringByAppendingString:in]
                                          : @"Open the Conversation", @"session": place[@"session"]}];
        }
        if ([place[@"can"] containsObject:@"clear"] && ![folders containsObject:place[@"clear"]]) {
            [folders addObject:place[@"clear"]];
            [ways addObject:@{@"action": @"clear", @"place": @(i), @"title": @"Copy Clear-Up Command",
                              @"menu": [NSString stringWithFormat:@"Copy Clear-Up Command for %@", in]}];
        }
    }];
    [places enumerateObjectsUsingBlock:^(NSDictionary *place, NSUInteger i, BOOL *stop) {
        if ([place[@"can"] containsObject:@"trash"] && ways.count)
            add(@"trash", i, @"Move to Trash…", [NSString stringWithFormat:@"Move %@ to the Trash…", name(place)]);
    }];
    if ([item[@"actions"] containsObject:@"replaced"]) add(@"replaced", -1, @"Mark Replaced", @"Mark Replaced");
    add(@"ignore", -1, @"Not a Key", @"Not a Key");
    // A key most likely made up for a test: Not a Key first, and the rest in its menu.
    if ([item[@"sample"] boolValue]) {
        NSDictionary *notAKey = ways.lastObject;
        [ways removeLastObject];
        [ways insertObject:notAKey atIndex:0];
    }
    return ways;
}

#pragma mark The places

// Whether a path is one of `roots`, or inside one.
static BOOL Inside(NSString *path, NSArray<NSString *> *roots) {
    for (NSString *root in roots)
        if ([path isEqualToString:root] || [path hasPrefix:[root stringByAppendingString:@"/"]]) return YES;
    return NO;
}

// What apps keep for themselves: the agents' records (AgentRecords) and Whozmove's own folder. A checkout can hold them
// (a home folder, or the agent's own folder, kept in git), but they're only ever read as records, never taken for a
// project's files, and nothing in them goes to the Trash.
- (NSArray<NSString *> *)keptByApps {
    NSMutableArray *roots = [NSMutableArray arrayWithObject:AppDir(nil)];
    for (id<AgentRecords> agent in self.agents)
        for (NSDictionary *record in [self recordsOf:agent])
            // What an agent reads as its instructions is a file of yours (a project's CLAUDE.md among them), not its
            // own record: in a checkout, it's one of the project's files too.
            if (AsText(record[@"path"]) && ![record[@"kind"] isEqual:@"instructions"])
                [roots addObject:record[@"path"]];
    return roots;
}

// An agent's records, asked of it once a look (they list folders, which takes a moment), and each time outside one.
- (NSArray<NSDictionary *> *)recordsOf:(id<AgentRecords>)agent {
    NSString *name = agent.name ?: @"";
    if (!self.recordsNow) return agent.records;
    if (!self.recordsNow[name]) self.recordsNow[name] = agent.records ?: @[];
    return self.recordsNow[name];
}

// A checkout's files that git has or would add, its commits not pushed yet, its AI tools' files and its remotes'
// addresses.
- (void)lookInCheckout:(NSString *)root secret:(NSString *)secret into:(NSMutableDictionary *)keys {
    NSString *name = root.lastPathComponent;
    NSArray<NSString *> *(^files)(NSArray *) = ^NSArray<NSString *> *(NSArray *which) {
        NSMutableArray *arguments = [@[@"--no-optional-locks", @"-C", root, @"ls-files", @"-z"] mutableCopy];
        [arguments addObjectsFromArray:which];
        NSDictionary *run = RunGit(arguments);
        if ([run[@"status"] intValue] != 0) return nil;
        NSString *text = [[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding];
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *each in [text componentsSeparatedByString:@"\0"])
            if (each.length) [list addObject:each];
        return list;
    };
    NSArray *listed = files(@[@"-co", @"--exclude-standard"]);
    if (!listed) return;
    NSSet *tracked = [NSSet setWithArray:files(@[]) ?: @[]];
    NSDictionary *state = FetchCheckoutState(root, nil);
    BOOL remote = [state[@"remotes"] integerValue] > 0;
    NSString *(^git)(NSArray *) = ^NSString *(NSArray *arguments) {
        NSMutableArray *all = [@[@"--no-optional-locks", @"-C", root] mutableCopy];
        [all addObjectsFromArray:arguments];
        NSDictionary *run = RunGit(all);
        if ([run[@"status"] intValue] != 0) return nil;
        return [[[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    };

    // The project it's a copy of, and which copy this is, so a key in every copy is said once, with how many it's in:
    // the project is the folder its shared git folder is in (…/shop/.git), or that folder's own name without .git; and
    // it's a worktree, named by its folder, when its own git folder isn't the shared one, else main.
    NSArray *dirs = [git(@[@"rev-parse", @"--path-format=absolute", @"--git-dir", @"--git-common-dir"])
                     componentsSeparatedByString:@"\n"];
    NSString *own = dirs.count == 2 ? dirs[0] : nil, *common = dirs.count == 2 ? dirs[1] : nil;
    NSString *project = [common.lastPathComponent isEqualToString:@".git"]
        ? common.stringByDeletingLastPathComponent.lastPathComponent
        : [common.lastPathComponent hasSuffix:@".git"] ? common.lastPathComponent.stringByDeletingPathExtension : name;
    NSString *copy = own && common && ![own isEqualToString:common] ? name : @"main";
    NSDictionary *(^ofProject)(NSString *, NSDictionary *) = ^NSDictionary *(NSString *relative, NSDictionary *place) {
        NSMutableDictionary *with = [place mutableCopy];
        with[@"project"] = project;
        if (common) with[@"repo"] = common;
        with[@"copy"] = copy;
        if (relative) with[@"inProject"] = relative;
        return with;
    };

    // Its files: committed and pushed, committed only here, changed since, or new and not ignored.
    NSMutableArray *paths = [NSMutableArray array];
    NSArray *kept = [self keptByApps];
    for (NSString *each in listed) {
        if (paths.count >= kMostFiles) {
            self.skipped[@"most"] = [self.skipped[@"most"] ?: @[] arrayByAddingObject:name];
            break;
        }
        BOOL folder = NO;
        NSString *path = [root stringByAppendingPathComponent:each];
        if (Inside(path, kept)) continue;
        if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&folder] && !folder) [paths addObject:path];
    }
    NSSet *mcp = [NSSet setWithArray:KeyMCPFiles()];
    [self scanFiles:paths secret:secret what:name each:^(NSDictionary *finding, NSString *path, NSInteger line,
                                                         NSString *last) {
        NSString *relative = [path substringFromIndex:MIN(root.length + 1, path.length)];
        NSString *where = [NSString stringWithFormat:@"%@ · %@:%ld", name, relative, (long)line];
        NSString *group = @"files", *how = [tracked containsObject:relative] ? nil : @"git would add it";
        NSString *commit = nil;
        if (!how) {
            NSString *blame = git(@[@"blame", @"--porcelain", @"-L",
                                    [NSString stringWithFormat:@"%ld,%ld", (long)line, (long)line], @"--", relative]);
            commit = [blame componentsSeparatedByString:@" "].firstObject;
            if (commit.length != 40 || [commit stringByTrimmingCharactersInSet:
                                        [NSCharacterSet characterSetWithCharactersInString:@"0"]].length == 0) {
                commit = nil;
                how = @"not committed yet";
            } else if ([git(@[@"branch", @"-r", @"--contains", commit]) length]) {
                group = @"pushed";
                how = [@"pushed in " stringByAppendingString:[commit substringToIndex:7]];
            } else if (remote) {
                group = @"commit";
                how = [@"commit " stringByAppendingString:[commit substringToIndex:7]];
            } else how = @"committed, on this Mac only";
        }
        if ([mcp containsObject:relative]) how = [@"MCP settings, " stringByAppendingString:how];
        NSMutableDictionary *place = [@{@"group": group, @"how": @"kept", @"file": path, @"line": @(line),
                                        @"checkout": root,
                                        @"where": [NSString stringWithFormat:@"%@ · %@", where, how]} mutableCopy];
        if (commit) place[@"commit"] = [commit substringToIndex:7];
        if (![tracked containsObject:relative]) place[@"untracked"] = @YES;
        AddPlace(keys, finding, last, ofProject(relative, place));
    }];

    // Its AI tools' files that git ignores (Aider's history), which hold what was said.
    for (NSDictionary *known in KeyAgentFilesInProjects()) {
        NSString *path = [root stringByAppendingPathComponent:known[@"path"]];
        if ([listed containsObject:known[@"path"]] || ![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        [self scanFiles:@[path] secret:secret what:known[@"app"] each:^(NSDictionary *finding, NSString *file,
                                                                         NSInteger line, NSString *last) {
            AddPlace(keys, finding, last, ofProject(known[@"path"], @{
                @"group": @"ai", @"how": @"sent", @"app": known[@"app"], @"file": file, @"line": @(line),
                @"checkout": root, @"where": [NSString stringWithFormat:@"%@ · %@ · %@:%ld", known[@"app"], name,
                                              known[@"path"], (long)line]}));
        }];
    }

    // Its commits not pushed yet, as a row's ↑N counts them: past the upstream when there's one, else past the base
    // branch's GitHub copy; none without a remote.
    if (remote) {
        NSArray *base = [state[@"upstream"] boolValue] ? nil : BaseBranch(root);
        NSString *baseRef = base.count > 1 ? base[1] : nil;
        NSString *from = git(@[@"rev-parse", [state[@"upstream"] boolValue] ? @"@{upstream}" : baseRef ?: @"HEAD"]);
        NSString *head = git(@[@"rev-parse", @"HEAD"]);
        if (from.length == 40 && head.length == 40 && ![from isEqualToString:head]) {
            NSString *range = [NSString stringWithFormat:@"%@..%@", from, head];
            BOOL ran = [self run:@"git" targets:@[root] range:range feed:nil secret:secret
                            each:^(NSDictionary *finding) {
                NSDictionary *at = AsRecord(finding[@"location"]), *about = AsRecord(finding[@"attributes"]);
                NSString *path = AsText(at[@"path"]), *commit = AsText(about[@"git.sha"]),
                         *blob = AsText(about[@"git.blob_sha"]);
                if (!path || commit.length < 7) return;
                NSInteger line = AsNumber(at[@"start_line"]).integerValue;
                // The file as that commit left it: by its blob where the report names it (version 2), else by the
                // commit and its path.
                NSString *object = blob ?: [NSString stringWithFormat:@"%@:%@", commit, path];
                NSDictionary *read = RunGit(@[@"--no-optional-locks", @"-C", root, @"cat-file", @"blob", object]);
                NSData *found = LineOf(read[@"out"], AsNumber(at[@"end_line"]).integerValue);
                NSString *last = LastFour(found, AsNumber(at[@"end_column"]).integerValue);
                NSDictionary *key = WithLineFacts(finding, found);
                if (!key) return;
                AddPlace(keys, key, last, ofProject(path, @{
                    @"group": @"commit", @"how": @"kept", @"file": [root stringByAppendingPathComponent:path],
                    @"line": @(line), @"checkout": root, @"commit": [commit substringToIndex:7],
                    @"where": [NSString stringWithFormat:@"%@ · %@:%ld · commit %@", name, path, (long)line,
                               [commit substringToIndex:7]]}));
            }];
            if (!ran) [self couldNotFinish:[name stringByAppendingString:@"'s commits"]];
        }
    }

    // Its remotes' addresses, which can carry a token (https://<token>@github.com/…).
    NSString *addresses = git(@[@"config", @"--get-regexp", @"^remote\\..*\\.(url|pushurl)$"]);
    if (addresses.length) {
        KeyFeed *feed = [[KeyFeed alloc] init];
        for (NSString *line in [addresses componentsSeparatedByString:@"\n"]) {
            NSArray *parts = [line componentsSeparatedByString:@"."];
            NSString *remoteName = parts.count > 2 ? parts[1] : @"its remote";
            [feed add:line from:[feed origin:@{@"remote": remoteName}]];
        }
        [self scanFeed:feed now:YES secret:secret what:[name stringByAppendingString:@"'s remotes"]
                  each:^(NSDictionary *finding, NSDictionary *origin, NSString *last, KeyFeed *fed) {
            // Where the address is: the repo's settings file, at its remote's section, which Open at the Line opens.
            NSString *config = common.length ? [common stringByAppendingPathComponent:@"config"] : nil;
            NSString *text = config ? [NSString stringWithContentsOfFile:config encoding:NSUTF8StringEncoding error:nil]
                                    : nil;
            NSString *section = [NSString stringWithFormat:@"[remote \"%@\"]", origin[@"remote"]];
            __block NSInteger at = 0, n = 0;
            [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
                n++;
                if ([[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                        isEqualToString:section]) at = n, *stop = YES;
            }];
            NSMutableDictionary *place = [@{
                @"group": @"files", @"how": @"kept", @"checkout": root, @"remote": origin[@"remote"],
                @"where": [NSString stringWithFormat:@"%@ · the address of its remote %@", name,
                           origin[@"remote"]]} mutableCopy];
            if (config && at) [place addEntriesFromDictionary:@{@"file": config, @"line": @(at)}];
            AddPlace(keys, finding, last, ofProject(nil, place));
        }];
    }
}

// Whether another account can read a file of yours: it lets your group or everyone read it, and every folder from it up
// to the home folder lets them in (a key in a private ~/.ssh is safe whatever its own mode says).
static BOOL ReadableByOthers(NSString *path, NSString *home) {
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != getuid())
        return NO;
    BOOL group = info.st_mode & S_IRGRP, others = info.st_mode & S_IROTH;
    for (NSString *folder = path.stringByDeletingLastPathComponent; folder.length >= home.length && (group || others);
         folder = folder.stringByDeletingLastPathComponent) {
        if (stat(folder.fileSystemRepresentation, &info) != 0) return NO;
        group = group && (info.st_mode & S_IXGRP);
        others = others && (info.st_mode & S_IXOTH);
        if ([folder isEqualToString:home]) break;
    }
    return group || others;
}

// The credential files, and the private keys in ~/.ssh, that other accounts on this Mac can read. What's in them isn't
// read: a key in its own file is where it belongs, as long as it's yours only.
- (void)lookAtCredentialFiles:(NSString *)secret into:(NSMutableDictionary *)keys {
    NSString *home = Home();
    NSMutableArray<NSDictionary *> *files = [KeyCredentialFiles() mutableCopy];
    NSString *ssh = [home stringByAppendingPathComponent:kKeySSHFolder];
    NSSet *notKeys = KeySSHNotKeys();
    for (NSString *each in [NSFileManager.defaultManager contentsOfDirectoryAtPath:ssh error:nil] ?: @[])
        if (![each hasSuffix:@".pub"] && ![notKeys containsObject:each] && ![each hasPrefix:@"."])
            [files addObject:@{@"path": [kKeySSHFolder stringByAppendingPathComponent:each], @"name": @"SSH private key"}];
    for (NSDictionary *each in files) {
        NSString *path = [home stringByAppendingPathComponent:each[@"path"]];
        if (!ReadableByOthers(path, home)) continue;
        // Docker's settings with no sign-in in them (only where macOS keeps them) hold nothing to keep from others.
        if ([each[@"docker"] boolValue] && !KeyDockerConfigHoldsSignIn(path)) continue;
        NSString *id = [Fingerprint(secret, [@"readable:" stringByAppendingString:path]) substringToIndex:16];
        keys[id] = [@{@"id": id, @"rule": @"readable", @"name": each[@"name"], @"masked": Tilde(path),
                      @"places": [@[@{@"group": @"readable", @"how": @"kept", @"file": path,
                                      @"where": @"Other accounts on this Mac can read it"}]
                                  mutableCopy]} mutableCopy];
    }
}

// Shell histories, the files your shell reads as it starts, and what can hold a key in Downloads (with Full Disk
// Access only, as macOS keeps it from apps).
- (void)lookInFiles:(NSString *)secret into:(NSMutableDictionary *)keys {
    NSString *home = Home();
    NSMutableArray *histories = [NSMutableArray array];
    for (NSString *each in KeyShellHistories()) {
        NSString *path = [home stringByAppendingPathComponent:each];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) [histories addObject:path];
    }
    [self scanFiles:histories secret:secret what:@"your shell history" each:^(NSDictionary *finding, NSString *path,
                                                                             NSInteger line, NSString *last) {
        AddPlace(keys, finding, last, @{@"group": @"files", @"how": @"kept", @"file": path, @"line": @(line),
                                        @"history": @YES,
                                        @"where": [NSString stringWithFormat:@"%@:%ld · your shell history",
                                                   Tilde(path), (long)line]});
    }];
    // The files your shell reads as it starts, where a key set for every terminal lives: where it's fixed.
    NSMutableArray *startup = [NSMutableArray array];
    for (NSString *each in KeyShellStartupFiles()) {
        NSString *path = [home stringByAppendingPathComponent:each];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) [startup addObject:path];
    }
    [self scanFiles:startup secret:secret what:@"your shell's settings" each:^(NSDictionary *finding, NSString *path,
                                                                               NSInteger line, NSString *last) {
        AddPlace(keys, finding, last, @{@"group": @"files", @"how": @"kept", @"file": path, @"line": @(line),
                                        @"startup": @YES,
                                        @"where": [NSString stringWithFormat:@"%@:%ld · your shell's settings",
                                                   Tilde(path), (long)line]});
    }];
    NSString *downloads = [home stringByAppendingPathComponent:@"Downloads"];
    if (!self.fullDiskAccess) {
        if ([NSFileManager.defaultManager fileExistsAtPath:downloads]) self.skipped[@"downloads"] = @YES;
        return;
    }
    NSDirectoryEnumerator *walk = [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:downloads]
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey]
        options:NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSMutableArray *paths = [NSMutableArray array];
    NSSet *kinds = KeyDownloadsExtensions();
    for (NSURL *url in walk) {
        if (walk.level > 2) [walk skipDescendants];
        NSNumber *regular = nil, *size = nil;
        [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (regular.boolValue && size.unsignedLongLongValue <= kKeyDownloadsLargest
            && [kinds containsObject:url.pathExtension.lowercaseString])
            [paths addObject:url.path];
    }
    [self scanFiles:paths secret:secret what:@"Downloads" each:^(NSDictionary *finding, NSString *path, NSInteger line,
                                                                 NSString *last) {
        // A key's own file (one of its kinds, small) can go to the Trash as a whole; anything else holds more.
        struct stat info;
        BOOL keyFile = [KeyFileExtensions() containsObject:path.pathExtension.lowercaseString]
                    && lstat(path.fileSystemRepresentation, &info) == 0
                    && (unsigned long long)info.st_size <= kKeyFileLargest;
        AddPlace(keys, finding, last, @{@"group": @"files", @"how": @"kept", @"file": path, @"line": @(line),
                                        @"downloads": @YES, @"trash": @(keyFile),
                                        @"where": [NSString stringWithFormat:@"%@:%ld", Tilde(path), (long)line]});
    }];
}

// The records AI tools keep of what was said and read, each {app, path, deep, format, within, group, kind, agent}:
// other tools' (KeyFacts), filed as theirs, and each agent's own (AgentRecords), filed as sent to Claude.
- (NSArray<NSDictionary *> *)recordSources {
    NSMutableArray *sources = [NSMutableArray array];
    for (NSDictionary *record in KeyAgentRecords())
        [sources addObject:@{@"app": record[@"app"], @"path": [Home() stringByAppendingPathComponent:record[@"path"]],
                             @"deep": record[@"deep"] ?: @NO, @"format": record[@"kind"], @"group": @"ai"}];
    for (id<AgentRecords> agent in self.agents)
        for (NSDictionary *record in [self recordsOf:agent]) {
            NSMutableDictionary *source = [record mutableCopy];
            source[@"app"] = agent.name;
            source[@"group"] = @"claude";
            source[@"agent"] = agent;
            [sources addObject:source];
        }
    return sources;
}

// Where a key in an agent's record is, in a few words: in a conversation (your message, what a tool read, or a reply),
// in the history of your messages, in a long paste, or in a copy of a file it edited; in its project's folder, when
// that's known.
static NSString *RecordWhere(NSDictionary *place) {
    NSString *app = place[@"app"], *kind = place[@"kind"], *how = place[@"how"];
    NSString *in = place[@"folder"] ? [@" in " stringByAppendingString:Tilde(place[@"folder"])] : @"";
    if ([kind isEqual:@"prompts"])
        return [NSString stringWithFormat:@"%@'s history of your messages%@", app,
                place[@"folder"] ? [@", for " stringByAppendingString:Tilde(place[@"folder"])] : @""];
    if ([kind isEqual:@"pastes"]) return [NSString stringWithFormat:@"A long paste %@ keeps", app];
    // A copy of a file it edited, by the file when that's known: its copy while the file still holds the key (which
    // then opens at its line), else an earlier one.
    if ([kind isEqual:@"edits"] && place[@"copyOf"])
        return [NSString stringWithFormat:@"%@'s %@copy of %@", app, place[@"line"] ? @"" : @"earlier ",
                Tilde(place[@"copyOf"])];
    if ([kind isEqual:@"edits"]) return [NSString stringWithFormat:@"%@'s copy of a file it edited%@", app, in];
    if ([kind isEqual:@"instructions"])
        return [NSString stringWithFormat:@"%@:%@ · what %@ reads as its instructions", Tilde(place[@"file"]),
                place[@"line"] ?: @"", app];
    NSString *what = [how isEqual:@"sent"] ? @"Your message" : [how isEqual:@"read"] ? @"What a tool read"
                   : [how isEqual:@"wrote"] ? ([place[@"toAgent"] boolValue] ? @"A task given to one of its agents"
                                                                             : @"A reply")
                   : @"Something said";
    return [NSString stringWithFormat:@"%@ in a %@ conversation%@", what, app, in];
}

// AI tools' records, each read on from where the last look stopped while it has only grown: a JSONL record only ever
// has lines added. What was found in the part read before is kept with how far it was read, never the text. A key in
// an agent's record is tied to its session and its project's folder, as far as the agent can tell, a folder known for
// a session in one record standing for it in the rest (a copy of a file it edited, say).
- (void)lookInRecords:(NSString *)secret into:(NSMutableDictionary *)keys {
    NSString *kept = [self file:@"records.json"];
    NSDictionary *was = AsRecord(ReadJSON(kept));
    NSDictionary *before = [AsNumber(was[@"shape"]) integerValue] == kRecordsShape ? AsRecord(was[@"files"]) ?: @{}
                                                                                   : @{};
    NSMutableDictionary *now = [NSMutableDictionary dictionary];
    KeyFeed *feed = [[KeyFeed alloc] init];
    NSMutableDictionary<NSString *, NSMutableArray *> *found = [NSMutableDictionary dictionary];
    // Held in memory while this look reads, and let go of as it ends, never kept: each key's text as it was found (by
    // its id), the keys found in each session, and the Spotify ids each session names. A copy cut short joins the whole
    // key it's the start of, and a Spotify id is an id, within one session.
    NSMutableDictionary<NSString *, NSString *> *texts = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *inSession = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *spotify = [NSMutableDictionary dictionary];
    void (^each)(NSDictionary *, NSDictionary *, NSString *, KeyFeed *) =
        ^(NSDictionary *finding, NSDictionary *origin, NSString *last, KeyFeed *fed) {
            NSString *path = origin[@"file"];
            NSMutableDictionary *place;
            if ([origin[@"group"] isEqual:@"claude"]) {
                // Never to the Trash: an agent's records are its own, cleared by its own command.
                place = [@{@"group": @"claude", @"app": origin[@"app"], @"kind": origin[@"kind"], @"file": path}
                         mutableCopy];
                for (NSString *field in @[@"how", @"session", @"folder", @"summary", @"toAgent", @"copyOf"])
                    if (origin[field]) place[field] = origin[field];
                // A copy of a file it edited never changes: the line the key is on in it is kept, to find it again.
                if (origin[@"copyOf"] && [origin[@"textLine"] integerValue] > 0) place[@"copyAt"] = origin[@"textLine"];
                // What the agent reads as its instructions is a file you keep: it opens at the key's line.
                if ([origin[@"kind"] isEqual:@"instructions"] && [origin[@"textLine"] integerValue] > 0)
                    place[@"line"] = origin[@"textLine"];
            } else {
                place = [@{@"group": @"ai", @"how": @"sent", @"app": origin[@"app"], @"file": path,
                           @"where": [NSString stringWithFormat:@"%@ · %@", origin[@"app"], Tilde(path)]} mutableCopy];
                if (origin[@"line"]) {
                    place[@"line"] = origin[@"line"];
                    place[@"where"] = [place[@"where"] stringByAppendingFormat:@":%@", origin[@"line"]];
                }
            }
            if (finding[@"named"]) place[@"named"] = finding[@"named"];
            NSString *id = KeyId(AsText(AsRecord(finding[@"match"])[@"fingerprint"]));
            NSMutableDictionary *seen = [@{@"id": id ?: @"", @"rule": AsText(finding[@"rule_id"]) ?: @"",
                                           @"masked": Masked(AsText(finding[@"rule_id"]), last), @"place": place}
                                         mutableCopy];
            if (finding[@"ends"]) seen[@"ends"] = finding[@"ends"];
            if (finding[@"shaped"]) seen[@"shaped"] = @YES;
            if (finding[@"isId"]) seen[@"isId"] = @YES;
            if (finding[@"madeUp"]) seen[@"madeUp"] = @YES;
            // Which line of its record it's on, to tell where in each record a key first appears.
            if (origin[@"line"]) seen[@"at"] = origin[@"line"];
            NSString *session = AsText(origin[@"session"]);
            NSDictionary *at = AsRecord(finding[@"location"]);
            NSData *line = [fed line:AsNumber(at[@"end_line"]).integerValue];
            NSRange span = line ? KeySpan(finding, line, NULL) : NSMakeRange(NSNotFound, 0);
            if (id && session && span.location != NSNotFound) {
                NSString *text = [[NSString alloc] initWithData:[line subdataWithRange:span]
                                                       encoding:NSUTF8StringEncoding];
                if (text.length > texts[id].length) texts[id] = text;
                if (!inSession[session]) inSession[session] = [NSMutableSet set];
                [inSession[session] addObject:id];
            }
            if (id && ![found[path] containsObject:seen]) [found[path] addObject:seen];
        };
    NSMutableDictionary<NSString *, id<AgentRecords>> *agents = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *pictures = [NSMutableDictionary dictionary];
    // Each record read whose lines are still in the feed: how it was read, kept once the run that looks through them
    // has, or the last look's if that run, or any other its lines were in, couldn't (`unread`). Records share runs,
    // so Betterleaks starts once for many of them, not once for each.
    NSMutableDictionary<NSString *, NSDictionary *> *pending = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *unread = [NSMutableSet set];
    void (^settle)(NSString *) = ^(NSString *path) {
        NSDictionary *waiting = pending[path], *last = waiting[@"last"];
        [pending removeObjectForKey:path];
        // A run over it that didn't finish leaves it as the last look read it, so what it didn't look through is
        // looked through next time, and what it found then still counts.
        if ([unread containsObject:path]) {
            if (last) now[path] = last;
            if (AsNumber(last[@"picture"])) pictures[path] = AsNumber(last[@"picture"]);
            found[path] = [AsList(last[@"found"]) mutableCopy] ?: [NSMutableArray array];
            return;
        }
        NSMutableDictionary *read = [waiting[@"read"] mutableCopy];
        read[@"found"] = found[path];
        if (read[@"picture"]) pictures[path] = read[@"picture"];
        now[path] = read;
        // How far this look has got, kept as it goes, with what it hasn't reached, or is still waiting on a run, as
        // the last look left it: a look a restart cuts off goes on from here next time, rather than reading every
        // record again. What it found so far is settled first (joined and marked as the whole look would, over
        // what's read so far, which only ever does less than over all of it); what's in memory for it stays for the
        // rest.
        if (![waiting[@"same"] boolValue] && ++self.recordsRead % MAX(self.keepEvery, (NSUInteger)1) == 0) {
            [self settleFound:found texts:texts inSession:inSession spotify:spotify];
            NSMutableDictionary *sofar = [before mutableCopy];
            [sofar addEntriesFromDictionary:now];
            KeepJSON(@{@"shape": @(kRecordsShape), @"files": sofar}, kept);
            if (self.stopAfter && self.recordsRead >= self.stopAfter && self.stopped)
                self.stopped(self.recordsRead);
        }
    };
    void (^scan)(BOOL, NSString *) = ^(BOOL all, NSString *what) {
        NSSet<NSString *> *failed = [self scanFeed:feed now:all secret:secret what:what each:each];
        if (!failed) return;
        [unread unionSet:failed];
        for (NSString *path in [pending.allKeys sortedArrayUsingSelector:@selector(compare:)]) settle(path);
    };
    for (NSDictionary *record in [self recordSources]) {
        id<AgentRecords> agent = record[@"agent"];
        if (agent) agents[record[@"app"]] = agent;
        NSString *top = record[@"path"], *format = record[@"format"], *within = record[@"within"];
        BOOL text = [format isEqualToString:@"text"], lines = [format isEqualToString:@"jsonl"];
        // What every part of it says it's about, told by the agent for a whole file, and added to by each of its lines.
        NSDictionary *(^about)(NSString *, NSDictionary *) = ^NSDictionary *(NSString *path, NSDictionary *line) {
            NSMutableDictionary *origin = [@{@"file": path, @"app": record[@"app"], @"group": record[@"group"]}
                                           mutableCopy];
            if (record[@"kind"]) origin[@"kind"] = record[@"kind"];
            if (agent) [origin addEntriesFromDictionary:[agent about:path line:line] ?: @{}];
            return origin;
        };
        NSMutableArray *paths = [NSMutableArray array];
        if ([record[@"deep"] boolValue]) {
            NSString *suffix = [@"." stringByAppendingString:format];
            for (NSURL *url in [NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:top]
                    includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsPackageDescendants
                                                           errorHandler:nil])
                if (text ? !within || [url.path.pathComponents containsObject:within] : [url.path hasSuffix:suffix])
                    [paths addObject:url.path];
        } else if ([NSFileManager.defaultManager fileExistsAtPath:top]) [paths addObject:top];
        for (NSString *path in [paths sortedArrayUsingSelector:@selector(compare:)]) {
            // Each file's reading lets go of what it made once it's done: a first look reads them all.
            @autoreleasepool {
                struct stat info;
                if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)
                    || (info.st_flags & SF_DATALESS) || (text && (unsigned long long)info.st_size > kRecordLargest))
                    continue;
                NSDictionary *last = AsRecord(before[path]);
                BOOL grown = lines && [last[@"inode"] unsignedLongLongValue] == info.st_ino
                          && [last[@"size"] unsignedLongLongValue] <= (unsigned long long)info.st_size;
                BOOL same = grown && [last[@"size"] unsignedLongLongValue] == (unsigned long long)info.st_size;
                if (!lines && [last[@"inode"] unsignedLongLongValue] == info.st_ino
                    && [last[@"size"] unsignedLongLongValue] == (unsigned long long)info.st_size
                    && [last[@"modified"] longLongValue] == info.st_mtimespec.tv_sec)
                    same = grown = YES;
                found[path] = grown ? [AsList(last[@"found"]) mutableCopy] ?: [NSMutableArray array]
                                    : [NSMutableArray array];
                NSUInteger from = grown ? [last[@"size"] unsignedLongLongValue] : 0;
                NSInteger counted = grown ? [last[@"lines"] integerValue] : 0;
                // Each session's folder, as the lines read so far say it, kept with how far it was read.
                NSMutableDictionary *learned = grown ? [AsRecord(last[@"sessions"]) mutableCopy] ?: [NSMutableDictionary
                                                       dictionary] : [NSMutableDictionary dictionary];
                // The first line holding a picture or a document, as the lines read so far say it.
                NSNumber *picture = grown ? AsNumber(last[@"picture"]) : nil;
                if (!same) {
                    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
                    const char *bytes = data.bytes, *end = bytes + data.length, *at = bytes + MIN(from, data.length);
                    if (text) {
                        // Plain text as it is; one that isn't text (a picture a tool returned, say) holds no key to
                        // find.
                        NSString *words = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        if (words.length) [feed add:words from:[feed origin:about(path, nil)]];
                        scan(NO, record[@"app"]);
                    } else if (!lines) {
                        NSMutableArray *strings = [NSMutableArray array];
                        StringsIn([NSJSONSerialization JSONObjectWithData:data options:0 error:nil], strings);
                        NSUInteger origin = [feed origin:about(path, nil)];
                        for (NSString *string in strings) [feed add:string from:origin];
                        scan(NO, record[@"app"]);
                    } else {
                        // Only whole lines: one still being written is read next time.
                        while (at < end) {
                            @autoreleasepool {
                                const char *next = memchr(at, '\n', (size_t)(end - at));
                                if (!next) break;
                                counted++;
                                NSData *line = [NSData dataWithBytesNoCopy:(void *)at length:(NSUInteger)(next - at)
                                                              freeWhenDone:NO];
                                id parsed = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                                NSMutableArray *strings = [NSMutableArray array];
                                StringsIn(parsed, strings);
                                if (strings.count) {
                                    NSMutableDictionary *origin = [about(path, AsRecord(parsed)) mutableCopy];
                                    origin[@"line"] = @(counted);
                                    if ([origin[@"picture"] boolValue] && !picture) picture = @(counted);
                                    [origin removeObjectForKey:@"picture"];
                                    NSString *session = AsText(origin[@"session"]);
                                    if (session) [self spotifyIdsIn:strings into:spotify session:session];
                                    // A session's folder is where it started, as its first line says: a later
                                    // line's is where a command had taken it by then.
                                    if (AsText(origin[@"session"]) && AsText(origin[@"folder"])
                                        && !learned[origin[@"session"]])
                                        learned[origin[@"session"]] = origin[@"folder"];
                                    NSUInteger index = [feed origin:origin];
                                    for (NSString *string in strings) [feed add:string from:index];
                                }
                                at = next + 1;
                                scan(NO, record[@"app"]);
                            }
                        }
                        from = (NSUInteger)(at - bytes);
                    }
                } else from = (NSUInteger)info.st_size;
                NSUInteger size = lines ? from : (NSUInteger)info.st_size;
                NSMutableDictionary *read = [@{@"inode": @(info.st_ino), @"size": @(size), @"lines": @(counted),
                                               @"modified": @(info.st_mtimespec.tv_sec)} mutableCopy];
                if (learned.count) read[@"sessions"] = learned;
                if (picture) read[@"picture"] = picture;
                pending[path] = last ? @{@"read": read, @"last": last, @"same": @(same)}
                                     : @{@"read": read, @"same": @(same)};
                // Waiting on the next run while its last lines are in the feed (the newest origins are its), and
                // settled now otherwise.
                if (![AsText(feed.origins.lastObject[@"file"]) isEqualToString:path]) settle(path);
            }
        }
    }
    scan(YES, @"AI tools' records");
    for (NSString *path in [pending.allKeys sortedArrayUsingSelector:@selector(compare:)]) settle(path);
    [self settleFound:found texts:texts inSession:inSession spotify:spotify];
    [texts removeAllObjects];
    KeepJSON(@{@"shape": @(kRecordsShape), @"files": now}, kept);
    NSMutableDictionary<NSString *, NSString *> *folders = [NSMutableDictionary dictionary];
    // Each session's project folder: the one your typed prompts name, or the one its transcript started in. It stands
    // for every place of the session's, as a line's own folder can be one a command had moved to.
    for (NSString *path in [now.allKeys sortedArrayUsingSelector:@selector(compare:)])
        for (NSString *session in AsRecord(now[path][@"sessions"]))
            if (AsText(now[path][@"sessions"][session]) && !folders[session])
                folders[session] = now[path][@"sessions"][session];
    for (NSString *path in found)
        for (NSDictionary *seen in found[path]) {
            NSMutableDictionary *finding = [@{@"rule_id": seen[@"rule"], @"match": @{@"fingerprint":
                                                  [@"hmac-sha256:" stringByAppendingString:seen[@"id"]]}} mutableCopy];
            if (seen[@"ends"]) finding[@"ends"] = seen[@"ends"];
            if (seen[@"shaped"]) finding[@"shaped"] = @YES;
            if (seen[@"isId"]) finding[@"isId"] = @YES;
            if (seen[@"madeUp"]) finding[@"madeUp"] = @YES;
            NSMutableDictionary *place = [AsRecord(seen[@"place"]) mutableCopy];
            // Where it first appears in this record: in the agent's own words, or anyone else's. Not the agent's own
            // once a picture or a document came before it in the record, as it may have been read off one, nor one
            // whose line isn't known.
            if ([seen[@"first"] boolValue]) {
                NSInteger at = [AsNumber(seen[@"at"]) integerValue];
                BOOL own = [place[@"how"] isEqual:@"wrote"] && ![place[@"summary"] boolValue] && at > 0
                        && !(pictures[path] && at > pictures[path].integerValue);
                finding[@"firstBy"] = own ? @"agent" : @"other";
            }
            // A copy of a file it edited is filed under that file while the file still holds the key, opening at its
            // line: the key is found again on its line of the copy, by its fingerprint, and looked for in the file, in
            // memory only. (A project's file that holds it is a place of its own too, found in its checkout, which is
            // what tells a key in its tests' files: the copy never does.)
            NSString *last = [AsText(seen[@"masked"]) componentsSeparatedByString:@"…"].lastObject ?: @"";
            if (place[@"copyOf"] && [place[@"copyAt"] integerValue] > 0) {
                NSData *copy = [NSData dataWithContentsOfFile:place[@"file"] options:NSDataReadingMappedIfSafe error:nil];
                NSString *text = KeyAgain(LineOf(copy, [place[@"copyAt"] integerValue]), seen[@"id"], last, secret);
                NSInteger at = text ? LineHolding(place[@"copyOf"], text) : 0;
                text = nil;
                if (at) {
                    place[@"file"] = place[@"copyOf"];
                    place[@"line"] = @(at);
                }
            }
            [place removeObjectForKey:@"copyAt"];
            if ([place[@"group"] isEqual:@"claude"]) {
                NSString *session = AsText(place[@"session"]);
                if (session && folders[session]) place[@"folder"] = folders[session];
                place[@"where"] = RecordWhere(place);
                NSString *clear = place[@"folder"] ? [agents[place[@"app"]] clearCommandFor:place[@"folder"]] : nil;
                if (clear) place[@"clear"] = clear;
            }
            NSString *masked = seen[@"masked"];
            AddPlace(keys, finding, [masked componentsSeparatedByString:@"…"].lastObject ?: @"", place);
        }
}

// The Spotify ids a record's texts name (spotify:track:… and the rest), kept in memory for its session.
- (void)spotifyIdsIn:(NSArray<NSString *> *)strings into:(NSMutableDictionary *)spotify session:(NSString *)session {
    static NSRegularExpression *address;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        address = [NSRegularExpression regularExpressionWithPattern:
                   @"spotify:(?:track|album|artist|playlist|episode|show):([A-Za-z0-9]{22})" options:0 error:nil];
    });
    for (NSString *text in strings) {
        if ([text rangeOfString:@"spotify:"].location == NSNotFound) continue;
        for (NSTextCheckingResult *match in [address matchesInString:text options:0
                                                               range:NSMakeRange(0, text.length)]) {
            if (!spotify[session]) spotify[session] = [NSMutableSet set];
            [spotify[session] addObject:[text substringWithRange:[match rangeAtIndex:1]]];
        }
    }
}

// Once every record is read: a key found cut short (16 characters at least, the start of a whole key found in the same
// session, of a rule with no provider or the whole key's own) is that key, and each record's finds of it say so, kept
// that way; a key a session also names as a Spotify id is an id in that session, unless it's set as a name that says
// it's secret; and in each record, the line a key first appears on is marked (`first`), to tell who first said it.
- (void)settleFound:(NSMutableDictionary<NSString *, NSMutableArray *> *)found
              texts:(NSDictionary<NSString *, NSString *> *)texts
          inSession:(NSDictionary<NSString *, NSSet<NSString *> *> *)inSession
            spotify:(NSDictionary<NSString *, NSSet<NSString *> *> *)spotify {
    NSMutableDictionary<NSString *, NSString *> *joins = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *ids = [NSMutableDictionary dictionary];
    for (NSString *session in inSession) {
        for (NSString *cut in inSession[session]) {
            NSString *start = texts[cut], *whole = nil;
            if (start.length < 16) continue;
            for (NSString *other in inSession[session])
                if (texts[other].length > start.length && [texts[other] hasPrefix:start]
                    && texts[other].length > texts[whole].length)
                    whole = other;
            if (whole) joins[cut] = whole;
        }
        for (NSString *id in inSession[session])
            if (texts[id] && [spotify[session] containsObject:texts[id]]) {
                if (!ids[session]) ids[session] = [NSMutableSet set];
                [ids[session] addObject:id];
            }
    }
    // How the whole key shows, for the copies that join it.
    NSMutableDictionary<NSString *, NSDictionary *> *shown = [NSMutableDictionary dictionary];
    for (NSString *path in found)
        for (NSDictionary *seen in found[path]) shown[seen[@"id"]] = seen;
    for (NSString *path in found) {
        NSMutableArray *list = found[path];
        NSMutableDictionary<NSString *, NSNumber *> *firstAt = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < list.count; i++) {
            NSMutableDictionary *seen = [list[i] mutableCopy];
            NSString *whole = joins[seen[@"id"]];
            if (whole && shown[whole] && (KeyKindHasNoProvider(seen[@"rule"])
                                          || [seen[@"rule"] isEqual:shown[whole][@"rule"]])) {
                seen[@"id"] = whole;
                seen[@"rule"] = shown[whole][@"rule"];
                seen[@"masked"] = shown[whole][@"masked"];
            }
            NSDictionary *place = AsRecord(seen[@"place"]);
            NSString *session = AsText(place[@"session"]), *as = AsText(AsRecord(place[@"named"])[@"as"]);
            if (session && [ids[session] containsObject:seen[@"id"]] && !KeyNameSaysSecret(as)) seen[@"isId"] = @YES;
            [seen removeObjectForKey:@"first"];
            list[i] = seen;
            NSInteger at = [AsNumber(seen[@"at"]) integerValue];
            if (!firstAt[seen[@"id"]] || at < firstAt[seen[@"id"]].integerValue) firstAt[seen[@"id"]] = @(at);
        }
        NSMutableSet<NSString *> *marked = [NSMutableSet set];
        for (NSMutableDictionary *seen in list)
            if ([AsNumber(seen[@"at"]) integerValue] == firstAt[seen[@"id"]].integerValue
                && ![marked containsObject:seen[@"id"]]) {
                seen[@"first"] = @YES;
                [marked addObject:seen[@"id"]];
            }
    }
}

// Whozmove's own records of each session (the start of your last message, of Claude's last reply, and a notice): a
// key there is masked in the record at once, as it's Whozmove's own copy, under the lock the hook writes it under.
- (void)lookInOwnRecords:(NSString *)secret into:(NSMutableDictionary *)keys {
    NSString *folder = AppDir(@"sessions");
    KeyFeed *feed = [[KeyFeed alloc] init];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] ?: @[]) {
        if (![name hasSuffix:@".json"]) continue;
        NSString *path = [folder stringByAppendingPathComponent:name];
        NSDictionary *record = AsRecord(ReadJSON(path));
        for (NSString *field in kOwnFields)
            if (AsText(record[field]).length)
                [feed add:record[field] from:[feed origin:@{@"file": path, @"field": field}]];
    }
    NSMutableDictionary<NSString *, NSMutableArray *> *masks = [NSMutableDictionary dictionary];
    [self scanFeed:feed now:YES secret:secret what:@"Whozmove's records" each:^(NSDictionary *finding,
                                                                               NSDictionary *origin, NSString *last,
                                                                               KeyFeed *fed) {
        NSDictionary *at = AsRecord(finding[@"location"]);
        NSInteger line = AsNumber(at[@"start_line"]).integerValue;
        NSString *text = [[NSString alloc] initWithData:[fed line:line] encoding:NSUTF8StringEncoding];
        NSString *masked = Masked(AsText(finding[@"rule_id"]), last);
        NSString *what = [origin[@"field"] isEqualToString:@"lastReply"] ? @"Claude's last reply"
                       : [origin[@"field"] isEqualToString:@"lastPrompt"] ? @"your last message" : @"a notice";
        AddPlace(keys, finding, last, @{@"group": @"claude", @"how": @"sent", @"app": @"Whozmove",
                                        @"where": [NSString stringWithFormat:@"Whozmove's record of %@ (now masked)",
                                                   what]});
        if (text && AsNumber(at[@"start_line"]).integerValue == AsNumber(at[@"end_line"]).integerValue) {
            NSData *bytes = [fed line:line];
            NSUInteger end = KeyEnd(bytes, AsNumber(at[@"end_column"]).integerValue);
            NSUInteger start = KeyStart(bytes, AsNumber(at[@"start_column"]).integerValue, end);
            NSMutableArray *list = masks[origin[@"file"]] ?: (masks[origin[@"file"]] = [NSMutableArray array]);
            if (end > start)
                [list addObject:@{@"field": origin[@"field"], @"line": text, @"masked": masked.length ? masked : @"…",
                                  @"from": @(start + 1), @"to": @(end)}];
        }
    }];
    for (NSString *path in masks) [self mask:masks[path] in:path];
    // Once masked, the record no longer shows the key, but the key still went to Claude: what was found in Whozmove's
    // records is kept (never the key), and listed with every look until it's ignored or marked replaced, or Keys'
    // folder is deleted.
    NSString *kept = [self file:@"own.json"];
    NSMutableArray *own = [AsList(ReadJSON(kept)) mutableCopy] ?: [NSMutableArray array];
    for (NSString *id in keys) {
        for (NSDictionary *place in keys[id][@"places"]) {
            if (![place[@"app"] isEqual:@"Whozmove"]) continue;
            NSMutableDictionary *seen = [@{@"id": id, @"rule": keys[id][@"rule"], @"masked": keys[id][@"masked"],
                                           @"place": place} mutableCopy];
            if (keys[id][@"ends"]) seen[@"ends"] = keys[id][@"ends"];
            if (keys[id][@"shaped"]) seen[@"shaped"] = @YES;
            if (![own containsObject:seen]) [own addObject:seen];
        }
    }
    KeepJSON(own, kept);
    for (NSDictionary *seen in own) {
        NSMutableDictionary *finding = [@{@"rule_id": AsText(seen[@"rule"]) ?: @"",
                                          @"match": @{@"fingerprint": [@"hmac-sha256:" stringByAppendingString:
                                                                       AsText(seen[@"id"]) ?: @""]}} mutableCopy];
        if (AsNumber(seen[@"ends"])) finding[@"ends"] = seen[@"ends"];
        if ([AsNumber(seen[@"shaped"]) boolValue]) finding[@"shaped"] = @YES;
        AddPlace(keys, finding, [AsText(seen[@"masked"]) componentsSeparatedByString:@"…"].lastObject ?: @"",
                 AsRecord(seen[@"place"]));
    }
}

// Takes each key found out of a record of Whozmove's own, putting its masked form in its place, if the record still
// says what was looked at.
- (void)mask:(NSArray<NSDictionary *> *)keys in:(NSString *)path {
    int lock = open([path stringByAppendingString:@".lock"].fileSystemRepresentation, O_WRONLY | O_CREAT, 0600);
    if (lock < 0) return;
    flock(lock, LOCK_EX);
    NSMutableDictionary *record = [AsRecord(ReadJSON(path)) mutableCopy];
    BOOL changed = NO;
    // The last in a line first, so the earlier ones' places don't move.
    NSArray *sorted = [keys sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"from"] compare:a[@"from"]];
    }];
    for (NSDictionary *key in sorted) {
        NSString *field = key[@"field"], *now = AsText(record[field]);
        NSData *bytes = [now dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger from = [key[@"from"] unsignedIntegerValue], to = [key[@"to"] unsignedIntegerValue];
        if (!now || from < 1 || to > bytes.length || to < from) continue;
        // The record changed since this line was looked at only if the field no longer starts as it did.
        NSData *was = [key[@"line"] dataUsingEncoding:NSUTF8StringEncoding];
        if (bytes.length < to || was.length < to || memcmp(bytes.bytes, was.bytes, to) != 0) continue;
        NSMutableData *masked = [bytes mutableCopy];
        NSData *put = [key[@"masked"] dataUsingEncoding:NSUTF8StringEncoding];
        [masked replaceBytesInRange:NSMakeRange(from - 1, to - from + 1) withBytes:put.bytes length:put.length];
        record[field] = [[NSString alloc] initWithData:masked encoding:NSUTF8StringEncoding] ?: @"…";
        changed = YES;
    }
    if (changed) KeepJSON(record, path);
    flock(lock, LOCK_UN);
    close(lock);
}

#pragma mark Looking

- (void)lookIn:(NSArray<NSString *> *)checkouts {
    if (self.looking) {
        self.again = YES;
        self.againIn = checkouts;
        return;
    }
    self.looking = YES;
    self.soFar = @{@"keys": @[], @"putAway": @[], @"read": @0, @"of": @(kPlacesRead), @"found": @0};
    [self tell];
    dispatch_async(self.queue, ^{
        NSDictionary *found = [self lookNowIn:checkouts soFar:^(NSDictionary *soFar) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self.looking) return;
                self.soFar = soFar;
                [self tell];
            });
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.looking = NO;
            self.soFar = nil;
            self.found = found;
            [self tell];
            if (self.again) {
                self.again = NO;
                [self lookIn:self.againIn];
            }
        });
    });
}

- (NSDictionary *)lookNowIn:(NSArray<NSString *> *)checkouts {
    return [self lookNowIn:checkouts soFar:nil];
}

// A look, telling `soFar` what it has found each time it has read one of its places. Each agent's records are asked
// for once in it, and let go once it's done.
- (NSDictionary *)lookNowIn:(NSArray<NSString *> *)checkouts soFar:(void (^)(NSDictionary *))soFar {
    self.recordsNow = [NSMutableDictionary dictionary];
    NSDictionary *found = [self lookIn:checkouts since:NSDate.date soFar:soFar];
    self.recordsNow = nil;
    return found;
}

- (NSDictionary *)lookIn:(NSArray<NSString *> *)checkouts since:(NSDate *)started
                   soFar:(void (^)(NSDictionary *))soFar {
    NSMutableDictionary *found = [@{@"lookedAt": @((long long)(started.timeIntervalSince1970 * 1000)),
                                    @"keys": @[]} mutableCopy];
    NSString *secret = [self ready] ? [self secret] : nil;
    if (!secret) {
        found[@"stopped"] = @"Keys couldn't make its folder in Whozmove's";
        PanelLog(@"Keys couldn't look: %@", found[@"stopped"]);
        return found;
    }
    // What stops a look before it starts is kept as what it found, so the card says so after a restart too.
    // Each of these is put right by getting this copy of Whozmove again (the card offers it: WhozmoveAgain).
    NSString *stopped = nil;
    if (![NSFileManager.defaultManager isExecutableFileAtPath:self.scanner])
        stopped = @"This copy of Whozmove doesn't have Betterleaks, which Keys looks with";
    else if ((self.major = [self askVersion]) < 0)
        stopped = @"Betterleaks, which Keys looks with, didn't run";
    else if (!self.major)
        stopped = [NSString stringWithFormat:@"This copy of Whozmove carries Betterleaks %@, which Keys doesn't know",
                   self.said ?: @""];
    if (stopped) {
        PanelLog(@"Keys couldn't look: %@%@", stopped, self.why ? [@": " stringByAppendingString:self.why] : @"");
        found[@"stopped"] = stopped;
        found[@"getAgain"] = @YES;
        KeepJSON(found, [self file:@"found.json"]);
        return found;
    }
    self.problems = [NSMutableArray array];
    self.recordsRead = 0;
    self.skipped = [NSMutableDictionary dictionary];
    NSMutableDictionary *keys = [NSMutableDictionary dictionary];
    void (^read)(NSUInteger) = ^(NSUInteger places) {
        if (!soFar) return;
        NSMutableDictionary *told = [[self listed:keys] mutableCopy];
        NSUInteger counted = 0;
        for (NSDictionary *item in told[@"keys"]) if (![item[@"band"] isEqual:@"sample"]) counted++;
        told[@"found"] = @(counted);
        told[@"read"] = @(places);
        told[@"of"] = @(kPlacesRead);
        soFar(told);
    };
    NSString *home = Home();
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *checkout in checkouts) {
        NSString *root = RealPath(checkout) ?: checkout;
        if ([seen containsObject:root]) continue;
        [seen addObject:root];
        BOOL kept = NO, cloud = NO;
        for (NSString *folder in kProtectedFolders)
            if ([root hasPrefix:[[home stringByAppendingPathComponent:folder] stringByAppendingString:@"/"]]) kept = YES;
        for (NSString *folder in kCloudFolders)
            if ([root hasPrefix:[[home stringByAppendingPathComponent:folder] stringByAppendingString:@"/"]]) cloud = YES;
        // A checkout kept in the cloud is never looked through, as the map never opens one: it could fetch it.
        if (cloud) continue;
        if (kept && !self.fullDiskAccess) {
            self.skipped[@"protected"] = @([self.skipped[@"protected"] integerValue] + 1);
            continue;
        }
        if (DeveloperToolsReady()) [self lookInCheckout:root secret:secret into:keys];
    }
    read(1);
    [self lookAtCredentialFiles:secret into:keys];
    read(2);
    [self lookInFiles:secret into:keys];
    read(3);
    [self lookInRecords:secret into:keys];
    read(4);
    [self lookInOwnRecords:secret into:keys];

    NSDictionary *listed = [self listed:keys];
    NSArray *list = listed[@"keys"], *away = listed[@"putAway"];
    found[@"keys"] = list;
    found[@"putAway"] = away;
    if (self.problems.count)
        found[@"problem"] = [@"Couldn't finish looking in " stringByAppendingString:
                             [self.problems componentsJoinedByString:@", "]];
    if (!DeveloperToolsReady() && checkouts.count) found[@"tools"] = @YES;
    if (self.skipped.count) found[@"skipped"] = self.skipped;
    found[@"fullDiskAccess"] = @(self.fullDiskAccess);
    found[@"shape"] = @(kFoundShape);
    KeepJSON(found, [self file:@"found.json"]);
    // How long it took, so what a look costs shows; and how many, never which: no key, nor how one starts or ends, nor
    // where it is.
    NSUInteger counted = 0;
    for (NSDictionary *item in list) if (![item[@"band"] isEqual:@"sample"]) counted++;
    NSTimeInterval took = -started.timeIntervalSinceNow;
    PanelLog(@"Keys looked for %@, with Betterleaks %@: %lu keys, %lu counted, %lu put away%@",
             took < 90 ? [NSString stringWithFormat:@"%.0f s", took]
                       : [NSString stringWithFormat:@"%.0f min", round(took / 60)], self.said,
             (unsigned long)list.count, (unsigned long)counted, (unsigned long)away.count,
             self.problems.count ? [NSString stringWithFormat:@"; couldn't finish %lu", (unsigned long)
                                    self.problems.count] : @"");
    return found;
}

// The keys found, each settled as it stands (a copy, so a look can go on adding to them), and those put away (replaced
// or not a key, each saying which) kept apart, so they can be shown and brought back: {keys, putAway}, each sorted.
- (NSDictionary *)listed:(NSDictionary<NSString *, NSMutableDictionary *> *)keys {
    NSSet *ignored = [NSSet setWithArray:AsList(ReadJSON([self file:@"ignored.json"])) ?: @[]];
    NSSet *replaced = [NSSet setWithArray:AsList(ReadJSON([self file:@"replaced.json"])) ?: @[]];
    NSMutableArray *list = [NSMutableArray array], *away = [NSMutableArray array];
    for (NSString *id in keys) {
        NSMutableDictionary *item = [Settled([keys[id] mutableCopy]) mutableCopy];
        if (![item[@"places"] count]) continue;  // every place it was in has gone since
        if ([replaced containsObject:id] || [ignored containsObject:id]) {
            item[@"put"] = [replaced containsObject:id] ? @"replaced" : @"ignored";
            [away addObject:item];
        } else [list addObject:item];
    }
    return @{@"keys": SortedKeys(list), @"putAway": SortedKeys(away)};
}

- (NSDictionary *)told {
    NSMutableDictionary *told = [self.found mutableCopy] ?: [NSMutableDictionary dictionary];
    told[@"looking"] = @(self.looking);
    if (self.looking && self.soFar) {
        NSDictionary *now = [self withLastLook:self.soFar];
        told[@"keys"] = now[@"keys"];
        told[@"putAway"] = now[@"putAway"];
        told[@"soFar"] = @{@"read": self.soFar[@"read"], @"of": self.soFar[@"of"], @"found": self.soFar[@"found"]};
    }
    return told;
}

- (void)tell {
    if (self.onChange) self.onChange([self told]);
}

// The keys as they're told: while a look is under way, what it has found so far with the last look's it hasn't come
// to yet; else what the last look found.
- (NSDictionary *)shown {
    return self.looking && self.soFar ? [self withLastLook:self.soFar] : self.found;
}

// What a look has found so far, with the last look's keys it hasn't found yet (they're in places it hasn't read, or
// gone, which its whole list will say), so no key leaves the list while it reads and comes back.
- (NSDictionary *)withLastLook:(NSDictionary *)soFar {
    NSMutableSet *now = [NSMutableSet set];
    for (NSString *list in @[@"keys", @"putAway"])
        for (NSDictionary *key in AsList(soFar[list])) if (key[@"id"]) [now addObject:key[@"id"]];
    NSMutableDictionary *with = [soFar mutableCopy];
    for (NSString *list in @[@"keys", @"putAway"]) {
        NSMutableArray *keys = [AsList(soFar[list]) mutableCopy] ?: [NSMutableArray array];
        for (NSDictionary *key in AsList(self.found[list])) if (![now containsObject:key[@"id"]]) [keys addObject:key];
        with[list] = SortedKeys(keys);
    }
    return with;
}

#pragma mark Acting

// A key put away, replaced or ignored, brought back onto the list, as the last look found it.
- (NSString *)bringBack:(NSString *)keyId {
    NSDictionary *item = nil;
    for (NSDictionary *each in AsList([self shown][@"putAway"]))
        if ([each[@"id"] isEqual:keyId]) item = each;
    if (!item || ![self ready]) return @"It's no longer listed: look again.";
    for (NSString *name in @[@"ignored.json", @"replaced.json"]) {
        NSMutableArray *ids = [AsList(ReadJSON([self file:name])) mutableCopy];
        if (![ids containsObject:keyId]) continue;
        [ids removeObject:keyId];
        if (!KeepJSON(ids, [self file:name])) return @"Couldn't keep that.";
    }
    NSMutableDictionary *back = [item mutableCopy];
    [back removeObjectForKey:@"put"];
    // In what the last look found, and in what the look under way has found so far, wherever it's put away.
    NSDictionary *(^bring)(NSDictionary *) = ^NSDictionary *(NSDictionary *found) {
        NSMutableArray *away = [AsList(found[@"putAway"]) mutableCopy];
        NSUInteger at = [away indexOfObjectPassingTest:^BOOL(NSDictionary *each, NSUInteger i, BOOL *stop) {
            return [each[@"id"] isEqual:keyId];
        }];
        if (!found || at == NSNotFound) return found;
        [away removeObjectAtIndex:at];
        NSMutableDictionary *now = [found mutableCopy];
        now[@"putAway"] = away;
        now[@"keys"] = SortedKeys([AsList(found[@"keys"]) ?: @[] arrayByAddingObject:back]);
        return now;
    };
    self.found = bring(self.found);
    if (self.soFar) self.soFar = bring(self.soFar);
    if (self.found) KeepJSON(self.found, [self file:@"found.json"]);
    [self tell];
    return nil;
}

// A list of keys with a press's change made to it, where it has the key: put away (`put`), with the places it has
// left, or gone; else as it was.
static NSDictionary *Changed(NSDictionary *found, NSDictionary *item, NSString *put, NSArray *places) {
    NSMutableArray *keys = [AsList(found[@"keys"]) mutableCopy];
    NSUInteger at = [keys indexOfObjectPassingTest:^BOOL(NSDictionary *each, NSUInteger i, BOOL *stop) {
        return [each[@"id"] isEqual:item[@"id"]];
    }];
    if (!found || at == NSNotFound) return found;
    NSMutableDictionary *changed = [found mutableCopy];
    if (put) {
        NSMutableDictionary *away = [item mutableCopy];
        away[@"put"] = put;
        changed[@"putAway"] = SortedKeys([AsList(found[@"putAway"]) ?: @[] arrayByAddingObject:away]);
        [keys removeObjectAtIndex:at];
    } else if (places.count) {
        NSMutableDictionary *left = [item mutableCopy];
        left[@"places"] = places;
        keys[at] = Settled(left);
    } else [keys removeObjectAtIndex:at];
    changed[@"keys"] = keys;
    return changed;
}

- (NSString *)act:(NSString *)action on:(NSString *)keyId place:(NSInteger)index file:(NSString *)file
            busy:(NSArray<NSString *> *)busy {
    if ([action isEqualToString:@"undo"]) return [self bringBack:keyId];
    NSDictionary *item = nil;
    for (NSDictionary *each in AsList([self shown][@"keys"]))
        if ([each[@"id"] isEqual:keyId]) item = each;
    if (!item) return @"It's no longer listed: look again.";
    NSString *home = Home();
    NSMutableArray *places = [item[@"places"] mutableCopy];
    NSDictionary *place = index >= 0 && (NSUInteger)index < places.count ? places[index] : nil;
    BOOL onKey = [@[@"replace", @"replaced", @"ignore"] containsObject:action];
    // A file that holds more than the key is never offered for the Trash: said plainly, should anything ask.
    if ([action isEqualToString:@"trash"] && place && ![place[@"can"] containsObject:@"trash"])
        return @"Only a file that's nothing but the key goes to the Trash: open this one at the line instead.";
    if (onKey ? ![item[@"actions"] containsObject:action] : ![place[@"can"] containsObject:action])
        return @"It's no longer listed: look again.";
    // The file the press was about, if it named one, must still be the one at that place: a look since can have changed
    // the key's places.
    if (file && ![place[@"file"] isEqual:file]) return @"It has changed since: look at it again.";
    if ([action isEqualToString:@"replace"]) {
        NSString *page = KeyKind(item[@"rule"])[@"replace"];
        return page.length && OpenLink(page) ? nil : @"Couldn't open the page to replace it.";
    }
    if ([action isEqualToString:@"reveal"]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:place[@"file"]]) return @"The file isn't there any more.";
        [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:place[@"file"]]]];
        return nil;
    }
    if ([action isEqualToString:@"conversation"])
        return self.openConversation ? self.openConversation(place[@"session"]) : @"Whozmove can't open it from here.";
    if ([action isEqualToString:@"clear"]) {
        // Only ever copied: you run it, and the agent's command asks before it clears anything.
        [NSPasteboard.generalPasteboard clearContents];
        [NSPasteboard.generalPasteboard setString:place[@"clear"] forType:NSPasteboardTypeString];
        return [NSString stringWithFormat:@"Copied %@. Paste it in a terminal to clear what %@ keeps of %@.",
                place[@"clear"], place[@"app"], [place[@"folder"] lastPathComponent]];
    }
    if ([action isEqualToString:@"open"]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:place[@"file"]]) return @"The file isn't there any more.";
        if (self.openAtLine && self.openAtLine(place[@"file"], [place[@"line"] integerValue])) return nil;
        // No editor chosen yet: TextEdit, without its line. Never the app macOS opens the file's kind in, which for a
        // key's file can be one that takes the key in (Keychain Access offers to import a .pem).
        NSURL *url = [NSURL fileURLWithPath:place[@"file"]];
        NSURL *edit = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.TextEdit"];
        if (edit) {
            OpenInOtherAppWith(@[url], edit, [NSWorkspaceOpenConfiguration configuration], nil);
            return nil;
        }
        return @"Nothing on this Mac opens it: choose an editor in Settings' Open Files With.";
    }
    NSString *path = place[@"file"];
    if ([action isEqualToString:@"ignore"] || [action isEqualToString:@"replaced"]) {
        // Put away for good: ignored, or replaced at its provider, which Whozmove can't see happen.
        NSString *kept = [self file:[action isEqualToString:@"ignore"] ? @"ignored.json" : @"replaced.json"];
        NSMutableArray *ids = [AsList(ReadJSON(kept)) mutableCopy] ?: [NSMutableArray array];
        if (![ids containsObject:keyId]) [ids addObject:keyId];
        if (![self ready] || !KeepJSON(ids, kept)) return @"Couldn't keep that.";
        [places removeAllObjects];
    } else if ([action isEqualToString:@"private"]) {
        // Opened without following a link, and changed through what was opened, so it's the file looked at.
        struct stat info;
        int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
        if (fd < 0 || fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_uid != getuid()) {
            if (fd >= 0) close(fd);
            return @"The file isn't there any more, or isn't yours.";
        }
        BOOL changed = fchmod(fd, info.st_mode & 0700) == 0;
        close(fd);
        if (!changed) return @"macOS didn't let it change.";
        // Your shell's settings still hold the key, now yours only: the place stays, without the way it took.
        if ([place[@"startup"] boolValue]) {
            NSMutableDictionary *now = [place mutableCopy];
            NSMutableArray *can = [AsList(place[@"can"]) mutableCopy];
            [can removeObject:@"private"];
            now[@"can"] = can;
            places[[places indexOfObject:place]] = now;
        } else [places removeObject:place];
    } else if ([action isEqualToString:@"trash"]) {
        // Checked again just before it goes: inside your home folder and not in a checkout's .git, nowhere an agent is
        // at work, and still the very file the look found; then to the Trash, never deleted outright.
        struct stat info;
        if (![path hasPrefix:[home stringByAppendingString:@"/"]] || [path.pathComponents containsObject:@".git"])
            return @"Keys moves only files in your home folder to the Trash.";
        if (Inside(path, [self keptByApps])) return @"That's an app's own record, which Keys never moves to the Trash.";
        for (NSString *folder in busy)
            if ([path hasPrefix:[folder stringByAppendingString:@"/"]])
                return [NSString stringWithFormat:@"An agent is at work in %@: try again once it's done.",
                        folder.lastPathComponent];
        if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)
            || ![[NSString stringWithFormat:@"%llu:%llu", (unsigned long long)info.st_dev,
                  (unsigned long long)info.st_ino] isEqual:place[@"item"]])
            return @"The file isn't there any more, or it's another file now: look again.";
        if (![NSFileManager.defaultManager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:nil error:nil])
            return @"It couldn't go to the Trash.";
        NSIndexSet *same = [places indexesOfObjectsPassingTest:^BOOL(NSDictionary *each, NSUInteger i, BOOL *stop) {
            return [each[@"file"] isEqual:path];
        }];
        [places removeObjectsAtIndexes:same];
    } else return @"Keys can't do that.";
    NSString *put = [action isEqualToString:@"ignore"] ? @"ignored" : [action isEqualToString:@"replaced"] ? @"replaced"
                  : nil;
    // Made to what the last look found, and to what the look under way has found so far, wherever the key is: the
    // look's next list works it out again from the files (what's put away, gone to the Trash or made yours only).
    self.found = Changed(self.found, item, put, places);
    if (self.soFar) self.soFar = Changed(self.soFar, item, put, places);
    if ([self ready] && self.found) KeepJSON(self.found, [self file:@"found.json"]);
    [self tell];
    return nil;
}

@end

NSDictionary *KeyJudged(NSString *rule, NSString *line, NSString *match) {
    NSData *bytes = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSRange at = [bytes rangeOfData:[match dataUsingEncoding:NSUTF8StringEncoding] options:0
                              range:NSMakeRange(0, bytes.length)];
    if (at.location == NSNotFound) return @{@"judged": @"not in the line"};
    NSDictionary *finding = @{@"rule_id": rule, @"location": @{@"start_line": @1, @"end_line": @1,
                                                               @"start_column": @(at.location + 1),
                                                               @"end_column": @(NSMaxRange(at))}};
    NSDictionary *key = WithLineFacts(finding, bytes);
    if (!key) return @{@"judged": @"no key"};
    return @{@"judged": [key[@"isId"] boolValue] ? @"id" : @"counts", @"last": LastFour(bytes, NSMaxRange(at)),
             @"named": key[@"named"] ?: NSNull.null};
}
