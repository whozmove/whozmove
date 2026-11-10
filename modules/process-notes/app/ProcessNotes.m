// ProcessNotes: the plain functions of a project's note (ProcessNotes.h says what each does).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ProcessNotes.h"
#import "Files.h"
#import "Text.h"

const NSUInteger kProcessMostCharacters = 4000, kProcessMostLines = 40, kProcessMostInLine = 400;

@implementation ProcessDraft
@end

NSString *ProcessProject(NSDictionary *git, NSString *cwd) {
    NSString *folder = AsText(git[@"mainRoot"]) ?: AsText(git[@"root"]) ?: cwd;
    return folder.length && folder.isAbsolutePath ? folder.stringByStandardizingPath : nil;
}

NSString *ProcessProjectName(NSString *project) {
    return project.lastPathComponent;
}

NSString *ProcessCheckout(NSDictionary *git, NSString *cwd) {
    NSString *folder = AsText(git[@"root"]) ?: cwd;
    return folder.length && folder.isAbsolutePath ? folder.stringByStandardizingPath : nil;
}

// A page by its place in the checkout, if it's a plain file there, by its real path.
static BOOL PlainPageIn(NSString *checkout, NSString *relative) {
    NSString *path = [checkout stringByAppendingPathComponent:relative];
    BOOL folder = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&folder] || folder) return NO;
    return PathWithin(path, checkout);
}

// Whether a docs/ page's name says it's on contributing, reviewing or releasing.
static BOOL NamesTheWay(NSString *name) {
    NSString *lower = name.lowercaseString;
    if (![lower.pathExtension isEqual:@"md"]) return NO;
    for (NSString *word in @[@"contribut", @"review", @"releas"])
        if ([lower containsString:word]) return YES;
    return NO;
}

NSArray<NSString *> *ProcessPages(NSString *checkout, NSArray<NSString *> *instructions) {
    if (!checkout.length) return @[];
    NSMutableArray<NSString *> *pages = [NSMutableArray array];
    NSMutableArray<NSString *> *named = [NSMutableArray arrayWithObject:@"CONTRIBUTING.md"];
    [named addObjectsFromArray:instructions ?: @[]];
    [named addObject:@".github/pull_request_template.md"];
    for (NSString *page in named)
        if (page.length && !page.isAbsolutePath && ![pages containsObject:page] && PlainPageIn(checkout, page))
            [pages addObject:page];
    // docs/ and the folders inside it, one deep: a project's guides are there, and a deeper search would read a whole
    // documentation site each time a session asks.
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    NSArray *top = [[files contentsOfDirectoryAtPath:[checkout stringByAppendingPathComponent:@"docs"] error:nil]
                    sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in top) {
        NSString *relative = [@"docs" stringByAppendingPathComponent:name];
        BOOL folder = NO;
        [files fileExistsAtPath:[checkout stringByAppendingPathComponent:relative] isDirectory:&folder];
        if (!folder) {
            if (NamesTheWay(name) && PlainPageIn(checkout, relative)) [found addObject:relative];
            continue;
        }
        if ([name hasPrefix:@"."]) continue;
        NSArray *inside = [[files contentsOfDirectoryAtPath:[checkout stringByAppendingPathComponent:relative]
                                                      error:nil] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *each in inside) {
            NSString *deeper = [relative stringByAppendingPathComponent:each];
            if (NamesTheWay(each) && PlainPageIn(checkout, deeper)) [found addObject:deeper];
        }
    }
    // Ten from docs/ at most: past that, a session reads the project's guides from their own index.
    [pages addObjectsFromArray:[found subarrayWithRange:NSMakeRange(0, MIN(found.count, (NSUInteger)10))]];
    return pages;
}

// Whether a character may be in a note: printable text, a tab or a line break, never a control character or one that
// hides or turns text (Unicode's format characters), which could make a line read differently from what's kept.
static BOOL PlainText(NSString *text) {
    static NSCharacterSet *bad;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSCharacterSet.controlCharacterSet mutableCopy];
        [set removeCharactersInString:@"\n\t\r"];
        [set formUnionWithCharacterSet:NSCharacterSet.illegalCharacterSet];
        bad = set;
    });
    return [text rangeOfCharacterFromSet:bad].location == NSNotFound;
}

// Whether a line holds something shaped like a key: what LooksLikeSecret knows (each provider's own shapes), and the
// shapes a page or a person writes one in, which only a note needs, as it's made of what a session read.
static BOOL ProcessHoldsSecret(NSString *text) {
    static NSArray<NSRegularExpression *> *shapes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // What a value looks like when it's a key rather than words: a run of a key's own characters, 8 or more with
        // two letters and two digits in it, or 20 or more with a digit; or a password's, 8 or more with a letter, a
        // digit and a symbol inside it (not only ending it, as a sentence's ! or ? does). Never a variable, a name
        // made of words joined by _ (S3_UPLOAD_TOKEN_2), a path, a link, an email or *emphasis*. So "Token:
        // regenerated each week", "the token is OAuth2-based!", "Staging password: 1Password" are steps, and a
        // random string isn't.
        NSString *run = @"[A-Za-z0-9+/=_]";
        NSString *named = @"(?!(?:[A-Za-z0-9]+_)+[A-Za-z0-9]+(?![A-Za-z0-9+/=]))";
        NSString *symbolic = @"(?![$<{%~/.*_])(?!\\S*://)(?![^\\s@]+@[^\\s@]+\\.[A-Za-z]{2,})"
                             @"(?![^\\s/]+\\.[A-Za-z]{2,}/)(?=[^\\s\"'`]*[A-Za-z])(?=[^\\s\"'`]*[0-9])"
                             @"(?=[^\\s\"'`]*[!@#$%^&*?~][^\\s\"'`!?.,;:)])[^\\s\"'`]{8,}";
        NSString *value = [NSString stringWithFormat:@"[\"'`]?%3$@(?:(?=%1$@*[0-9]%1$@*[0-9])(?=%1$@*[A-Za-z]"
                                                     @"%1$@*[A-Za-z])%1$@{8,}|(?=%1$@*[0-9])%1$@{20,}|%2$@)",
                                                     run, symbolic, named];
        // A long key's own shape alone, as after a name with only a space (the API key 3f9a…).
        NSString *longKey = [NSString stringWithFormat:@"[\"'`]?%2$@(?=%1$@*[0-9])%1$@{20,}", run, named];
        // A name a key goes by, at the end of a longer one too (DB_PASSWORD, client_secret, SECRET_KEY, SIGNING_KEY,
        // SSHPASS), and camel-cased (AccountKey, masterKey): no \b before it, which fails after "_".
        NSString *names = @"(?:sshpass|pass(?:word|wd|phrase)|pwd|secret|token|credentials?|(?:api|access|private|"
                          @"secret|account|shared|master|auth|signing|encryption)[_ -]?key|[_-]key|key_base)";
        NSString *curl = @"\\bcurl\\b[^;|&]*?\\s(?:-[uU]\\s*|--(?:proxy-)?user(?:\\s+|=))[\"']?(?![0-9]+:[0-9]+\\b)"
                         @"[^\\s:\"']+:(?![$<{%])(?!(?:pass(?:word)?|PASS(?:WORD)?)\\b)[^\\s\"']+";
        NSString *mysql = @"\\bmysql(?:dump|admin)?\\b[^;|&]*?\\s-p[\"']?(?![$<{%])(?![0-9]+(?::[0-9]+)?\\b)"
                          @"(?!r(?:int|une)\\b)[^\\s\"']{4,}";
        NSString *header = @"(?i)authorization[\"']?\\s*:\\s*[\"']?(?:token|basic|bearer)\\s+(?![$<{%])"
                           @"(?!(?-i:[A-Z]+(?:_[A-Z0-9]+)+)\\b)[A-Za-z0-9._~+/=-]{16,}";
        NSArray *each = @[
            // Set with =, as code and .env files write it, to anything 8 or more long but a variable ($TOKEN,
            // ${TOKEN}, %TOKEN%), a placeholder (<token>, {token}) or words joined by hyphens (your-key-here).
            [NSString stringWithFormat:@"(?i)%@[\"'`]?\\s*=\\s*[\"'`]?(?![$<{%%])(?![a-z]+(?:-[a-z]+)+(?:[\"'`\\s.,;]|$))"
                                       @"[^\\s\"'`]{8,}", names],
            // With a colon, or "is", as prose or YAML writes it, and after a command's flag: only what looks like a key.
            [NSString stringWithFormat:@"(?i)%@[\"'`]?\\s*(?::|\\s(?:is|was)\\s)\\s*%@", names, value],
            [NSString stringWithFormat:@"(?i)--(?:password|passwd|token|secret|api[_-]?key)\\s+%@", value],
            // After only a space, when what follows is a long key (the API key 3f9a…).
            [NSString stringWithFormat:@"(?i)%@[\"'`]?\\s+%@", names, longKey],
            // A password given to a command, within that command (up to a ; | or &): curl's user and password (-u,
            // joined on or not, --user, its proxy's -U and --proxy-user), MySQL's -p with it joined on, and sshpass's
            // own -p. Never a variable, a placeholder (user:password), a user and group's ids (-u 1000:1000), a port
            // (-p3306, -p2222), find's -print, or -p alone, which asks for it.
            curl,
            mysql,
            @"\\bsshpass\\s+-p\\s*[\"']?(?![$<{%])(?![a-z]+\\b)[^\\s\"']{4,}",
            // A sign-in sent as a header, by its name: a token, Basic's base64 or a bearer token, in a key's own
            // characters, never a placeholder in capitals (YOUR_GITHUB_TOKEN) or a template (base64(user:password)).
            header,
            // A sign-in sent as a header: Basic, then its user and password in base64.
            @"(?i)\\bbasic\\s+(?:(?=[A-Za-z0-9+/]*[0-9+/])[A-Za-z0-9+/]{12,}={0,2}|[A-Za-z0-9+/]{12,}={1,2})",
            // AWS's secret after its own name, set or not: 40 characters of its own. Its name is a key's name too, so
            // the shapes above find most of these as well.
            @"(?i)aws_secret_access_key[\"'`]?\\s*[:=]?\\s*[\"'`]?[A-Za-z0-9+/]{30,}",
            // A password in a link, with a user or without (postgres://app:…@db, redis://:…@cache).
            @"[A-Za-z][A-Za-z0-9+.-]*://[^\\s/:@]*:[^\\s/@]+@",
            @"eyJ[A-Za-z0-9_-]{10,}\\.eyJ",  // a signed token's first two parts (a JWT)
            @"ATATT[A-Za-z0-9_=-]{20,}",     // Atlassian's API tokens
            // Webhook addresses, which are their own keys: Slack's (its services, triggers and workflows), Discord's
            // (with its API's version or without), and Stripe's signing secret.
            @"(?i)hooks\\.slack\\.com/(?:services|triggers|workflows)/[A-Za-z0-9_/-]{20,}",
            @"(?i)discord(?:app)?\\.com/api/(?:v[0-9]+/)?webhooks/[0-9]+/[A-Za-z0-9_-]{20,}",
            @"whsec_[A-Za-z0-9+/=]{16,}",
        ];
        NSMutableArray *made = [NSMutableArray array];
        for (NSString *shape in each) [made addObject:[NSRegularExpression regularExpressionWithPattern:shape options:0
                                                                                                  error:nil]];
        shapes = made;
    });
    if (!text.length) return NO;
    if (LooksLikeSecret(text)) return YES;
    for (NSRegularExpression *shape in shapes)
        if ([shape firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    return NO;
}

NSArray<NSString *> *ProcessDraftLines(NSString *text, NSString **why) {
    NSString *reason = nil;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSRegularExpression *mark = [NSRegularExpression regularExpressionWithPattern:@"^(?:[-*•]|[0-9]{1,2}[.)])(?:\\s+|$)"
                                                                          options:0 error:nil];
    if (text.length > kProcessMostCharacters)
        reason = [NSString stringWithFormat:@"a note may be %lu characters at most",
                                            (unsigned long)kProcessMostCharacters];
    else if (!PlainText(text ?: @""))
        reason = @"a note is plain text: it has a character that isn't";
    for (NSString *raw in reason ? @[] : [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        line = [mark stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0, line.length) withTemplate:@""];
        if (!line.length) continue;
        if (line.length > kProcessMostInLine) {
            reason = [NSString stringWithFormat:@"a line may be %lu characters at most", (unsigned long)kProcessMostInLine];
            break;
        }
        // Each line on its own, as it's checked again when it's read back, saying which, so the session knows what
        // to take out, but never repeating it.
        if (ProcessHoldsSecret(line)) {
            reason = [NSString stringWithFormat:@"line %lu holds something shaped like a key or a token, which never "
                                                @"goes in a note", (unsigned long)lines.count + 1];
            break;
        }
        [lines addObject:line];
    }
    if (!reason && !lines.count) reason = @"there's nothing in it";
    if (!reason && lines.count > kProcessMostLines)
        reason = [NSString stringWithFormat:@"a note may be %lu lines at most", (unsigned long)kProcessMostLines];
    if (why) *why = reason;
    return reason ? nil : lines;
}

NSArray<NSDictionary *> *ProcessChanges(NSArray<NSString *> *kept, NSArray<NSString *> *draft) {
    kept = kept ?: @[];
    draft = draft ?: @[];
    // The longest run of lines both share, in order, as a table of how many from each point on.
    NSUInteger n = kept.count, m = draft.count;
    NSMutableArray<NSMutableArray<NSNumber *> *> *shared = [NSMutableArray arrayWithCapacity:n + 1];
    for (NSUInteger i = 0; i <= n; i++) {
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:m + 1];
        for (NSUInteger j = 0; j <= m; j++) [row addObject:@0];
        [shared addObject:row];
    }
    for (NSInteger i = (NSInteger)n - 1; i >= 0; i--)
        for (NSInteger j = (NSInteger)m - 1; j >= 0; j--)
            shared[i][j] = [kept[i] isEqual:draft[j]] ? @(shared[i + 1][j + 1].integerValue + 1)
                                                      : @(MAX(shared[i + 1][j].integerValue, shared[i][j + 1].integerValue));
    NSMutableArray<NSDictionary *> *lines = [NSMutableArray array];
    NSUInteger i = 0, j = 0;
    while (i < n || j < m) {
        if (i < n && j < m && [kept[i] isEqual:draft[j]]) {
            [lines addObject:@{@"text": draft[j]}];
            i++, j++;
        } else if (i < n && (j == m || shared[i + 1][j].integerValue >= shared[i][j + 1].integerValue)) {
            [lines addObject:@{@"text": kept[i], @"mark": @"removed"}];
            i++;
        } else {
            [lines addObject:@{@"text": draft[j], @"mark": @"added"}];
            j++;
        }
    }
    return lines;
}

BOOL ProcessHoldsNew(NSArray<NSString *> *draft, NSArray<NSString *> *declined, NSArray<NSString *> *kept) {
    NSSet *before = [NSSet setWithArray:declined ?: @[]], *now = [NSSet setWithArray:kept ?: @[]],
          *drafted = [NSSet setWithArray:draft ?: @[]];
    // A line added that the declined draft didn't add: a kept line it took out and this one keeps changes nothing.
    for (NSString *line in draft)
        if (![before containsObject:line] && ![now containsObject:line]) return YES;
    // A kept line taken out that the declined draft kept: a wrong line can always be taken out after Not Now.
    for (NSString *line in kept)
        if ([before containsObject:line] && ![drafted containsObject:line]) return YES;
    return NO;
}

NSDictionary *ProcessDraftShown(ProcessDraft *draft, NSArray<NSString *> *kept, double keptAt, double declinedAt) {
    if (!draft) return nil;
    NSMutableDictionary *shown = [@{@"at": @(draft.at), @"project": draft.name ?: @"",
                                    @"lines": kept ? ProcessChanges(kept, draft.lines)
                                                   : ProcessChanges(@[], draft.lines)} mutableCopy];
    // A first note's lines are all new, so none is marked: the card shows them as the note, not as changes.
    if (!kept) {
        NSMutableArray *plain = [NSMutableArray array];
        for (NSString *line in draft.lines) [plain addObject:@{@"text": line}];
        shown[@"lines"] = plain;
    }
    if (kept && keptAt > 0) shown[@"keptAt"] = @(keptAt);
    if (declinedAt > 0) shown[@"declinedAt"] = @(declinedAt);
    if (draft.keeping) shown[@"keeping"] = @YES;
    if (draft.problem.length) shown[@"problem"] = draft.problem;
    return shown;
}

NSDictionary *ProcessWay(NSString *name, NSArray<NSString *> *pages, NSArray<NSString *> *kept, double keptAt,
                         NSString *draft) {
    if (!name.length) return nil;
    NSMutableDictionary *way = [@{@"project": name, @"pages": pages ?: @[]} mutableCopy];
    if (kept.count) {
        way[@"note"] = kept;
        way[@"keptAt"] = @(keptAt);
    }
    if (draft.length) way[@"draft"] = draft;
    return way;
}

NSString *ProcessRecordName(NSString *project) {
    return [NSString stringWithFormat:@"%016llx.json", HashBytes(project.UTF8String)];
}

NSDictionary *ProcessRecord(NSString *project, NSArray<NSString *> *lines, double keptAt) {
    return @{@"project": project ?: @"", @"note": lines ?: @[], @"keptAt": @(keptAt)};
}

NSArray<NSString *> *ProcessKeptLines(NSDictionary *record, NSString *project, double *keptAt) {
    NSDictionary *kept = AsRecord(record);
    if (!project.length || ![AsText(kept[@"project"]) isEqual:project]) return nil;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    // Checked again as it's read, as a draft is: a note changed by hand, or kept when the check knew fewer shapes, is
    // never handed on with a key in it or a character that isn't plain text. Such a line is left out; the rest is the
    // note.
    for (id line in AsList(kept[@"note"]) ?: @[]) {
        NSString *text = AsText(line);
        if (text.length && PlainText(text) && !ProcessHoldsSecret(text)) [lines addObject:text];
    }
    if (!lines.count) return nil;
    if (keptAt) *keptAt = AsNumber(kept[@"keptAt"]).doubleValue;
    return lines;
}
