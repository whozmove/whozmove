// ProcessNotesPrints: --print-process, the process-notes module driven as the core and the page would drive it, step
// by step, with a clock of its own, in a throwaway home only: made-up projects (acme-web, a worktree of it, a folder
// outside git) with their own pages; drafts asked for, shown, turned away, kept with Keep It, declined with Not Now and
// drafted again; Keep It that can't write, then Try Again; the rows' `processDraft` and each session's way; what's kept,
// and read back after a restart; the plain functions over made-up cases; and panel.log, which carries no word of a note.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ProcessNotesModule.h"
#import "ProcessNotes.h"
#import "Core.h"
#import "Row.h"
#import "Files.h"
#import "Printing.h"

static void PrintLine(NSString *text) {
    printf("%s\n", text.UTF8String);
}

// As JSON on one line, keys sorted, the home folder written as ~, so a run reads the same in any throwaway home.
static NSString *JSONLine(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object ?: NSNull.null
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingFragmentsAllowed
                                                         | NSJSONWritingWithoutEscapingSlashes error:nil];
    NSString *line = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"?";
    // The home folder as it's given and as a path standardized from it says it (without /private), as a project's is.
    line = [line stringByReplacingOccurrencesOfString:Home() withString:@"~"];
    return [line stringByReplacingOccurrencesOfString:Home().stringByStandardizingPath withString:@"~"];
}

// The made-up notes a session drafts, by name: what the pages don't say, each line with where it came from.
static NSString *const kDocker = @"Start Docker before npm test: the tests need its database, and the pages don't say "
                                 @"so. (found running the tests on PAY-142)";
static NSString *const kStaging = @"Staging link: QA wants it in each pull request's description. (you, on PAY-142)";
static NSString *const kScreens = @"Screenshots: a before and an after in the pull request for anything people see. "
                                  @"(the review on #57)";
static NSString *const kCards = @"Saved cards: clear the test card store with npm run cards:reset first. (found on "
                                @"PAY-148)";
// Made-up keys, made as the cases run so no file holds one, and never printed: what's shown is only whether a note
// with one is turned away. MadeUp is `n` letters and digits picked at random each run, two letters and two digits
// first, so it always looks like a key.
static NSString *MadeUp(NSUInteger n) {
    NSString *letters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", *digits = @"0123456789";
    NSString *from = [letters stringByAppendingString:digits];
    NSString *(^one)(NSString *) = ^(NSString *set) {
        return [set substringWithRange:NSMakeRange(arc4random_uniform((uint32_t)set.length), 1)];
    };
    NSMutableString *made = [NSMutableString stringWithFormat:@"%@%@%@%@", one(letters), one(digits), one(letters),
                                                                one(digits)];
    while (made.length < n) [made appendString:one(from)];
    return made;
}

// Made the same way from other characters: hex digits only, a digit and a letter first; and a password, with a symbol
// after its first two letters and two digits.
static NSString *MadeUpFrom(NSString *first, NSString *from, NSUInteger n) {
    NSMutableString *made = [NSMutableString string];
    for (NSUInteger i = 0; i < first.length; i++) [made appendString:[first substringWithRange:NSMakeRange(i, 1)]];
    while (made.length < n)
        [made appendString:[from substringWithRange:NSMakeRange(arc4random_uniform((uint32_t)from.length), 1)]];
    return made;
}

static NSString *MadeUpHex(NSUInteger n) {
    NSString *first = [NSString stringWithFormat:@"%u%c", arc4random_uniform(10), (char)('a' + arc4random_uniform(6))];
    return MadeUpFrom(first, @"0123456789abcdef", n);
}

static NSString *MadeUpPassword(NSUInteger n) {
    return MadeUpFrom([NSString stringWithFormat:@"%@!", MadeUp(4)],
                      @"abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#&*", n);
}

static NSString *MadeUpToken(void) {
    return [@"gh" stringByAppendingFormat:@"p_%@", MadeUp(36)];
}

static NSString *SampleNote(NSString *name) {
    NSDictionary *notes = @{
        @"first": [@[kDocker, kStaging] componentsJoinedByString:@"\n"],
        // A list as a session may write one, its own marks taken off, with a blank line and spaces round the lines.
        @"listed": [NSString stringWithFormat:@"1. %@\n\n  - %@  \n", kDocker, kStaging],
        @"again": [@[kStaging, kScreens] componentsJoinedByString:@"\n"],
        @"newline": [@[kDocker, kStaging, kScreens] componentsJoinedByString:@"\n"],
        @"cards": [@[kDocker, kStaging, kCards] componentsJoinedByString:@"\n"],
        @"empty": @"  \n\n - \n",
        @"secret": [kStaging stringByAppendingFormat:@"\nDeploys: the token is %@", MadeUpToken()],
        @"control": [kStaging stringByAppendingString:@"\nReviews: one approval‮ from the web team."],
    };
    if ([name isEqual:@"long"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (int i = 1; i <= 41; i++) [lines addObject:[NSString stringWithFormat:@"Step %d: as docs/part-%d.md says.", i, i]];
        return [lines componentsJoinedByString:@"\n"];
    }
    if ([name isEqual:@"forty"]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (int i = 1; i <= 40; i++) [lines addObject:[NSString stringWithFormat:@"Step %d: as docs/part-%d.md says.", i, i]];
        return [lines componentsJoinedByString:@"\n"];
    }
    if ([name isEqual:@"wide"]) return [@"Fixtures: " stringByPaddingToLength:401 withString:@"x" startingAtIndex:0];
    if ([name isEqual:@"huge"]) return [@"" stringByPaddingToLength:4001 withString:@"Checks: npm test. " startingAtIndex:0];
    return notes[name];
}

// Made-up projects in the throwaway home: acme-web with its own pages (one a link to a file outside it, never listed,
// and its instructions in AGENTS.md), a worktree of it with pages of its own (every file its agent, `agent`, says holds
// its instructions, so each is listed as the agent names it, and none by this module), and a folder outside git with
// none.
static NSString *MakeProjects(id<Agent> agent) {
    NSString *code = [Home() stringByAppendingPathComponent:@"code"];
    NSString *web = [code stringByAppendingPathComponent:@"acme-web"];
    NSString *tree = [code stringByAppendingPathComponent:@"acme-web-worktrees/pay-148"];
    NSString *outside = [Home() stringByAppendingPathComponent:@"elsewhere.md"];
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *folder in @[@"docs/guides", @"docs/.hidden", @".github"])
        [files createDirectoryAtPath:[web stringByAppendingPathComponent:folder] withIntermediateDirectories:YES
                          attributes:nil error:nil];
    [files createDirectoryAtPath:tree withIntermediateDirectories:YES attributes:nil error:nil];
    [files createDirectoryAtPath:[code stringByAppendingPathComponent:@"scratch"] withIntermediateDirectories:YES
                      attributes:nil error:nil];
    NSData *words = [@"How work is done here.\n" dataUsingEncoding:NSUTF8StringEncoding];
    [files createFileAtPath:outside contents:words attributes:nil];
    for (NSString *page in @[@"CONTRIBUTING.md", @"AGENTS.md", @".github/pull_request_template.md",
                             @"docs/reviewing.md", @"docs/guides/releasing.md", @"docs/guides/install.md",
                             @"docs/architecture.md", @"docs/.hidden/reviewing.md"])
        [files createFileAtPath:[web stringByAppendingPathComponent:page] contents:words attributes:nil];
    // Pages that are links: one to a file outside the checkout (CLAUDE.md, and one in docs/), never listed, and a
    // folder named like a page, never listed either.
    [files createSymbolicLinkAtPath:[web stringByAppendingPathComponent:@"CLAUDE.md"] withDestinationPath:outside
                              error:nil];
    [files createSymbolicLinkAtPath:[web stringByAppendingPathComponent:@"docs/contributing-more.md"]
                withDestinationPath:outside error:nil];
    [files createDirectoryAtPath:[web stringByAppendingPathComponent:@"docs/release-notes.md"]
     withIntermediateDirectories:YES attributes:nil error:nil];
    [files createFileAtPath:[tree stringByAppendingPathComponent:@"CONTRIBUTING.md"] contents:words attributes:nil];
    for (NSString *page in agent.instructionPages) {
        NSString *path = [tree stringByAppendingPathComponent:page];
        [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                          attributes:nil error:nil];
        [files createFileAtPath:path contents:words attributes:nil];
    }
    return code;
}

// A row in one of the made-up places: `repo` (acme-web's main checkout), `tree` (its worktree), `plain` (a folder
// outside git) or `none` (no folder).
static Row *SampleRow(NSString *sessionId, NSString *place, NSString *code) {
    Row *row = [Row new];
    row.sessionId = sessionId;
    row.pid = 4100;
    NSString *web = [code stringByAppendingPathComponent:@"acme-web"];
    NSString *tree = [code stringByAppendingPathComponent:@"acme-web-worktrees/pay-148"];
    if ([place isEqual:@"repo"]) {
        row.cwd = web;
        row.git = @{@"branch": @"pay-142", @"root": web, @"mainRoot": web};
    } else if ([place isEqual:@"tree"]) {
        row.cwd = [tree stringByAppendingPathComponent:@"src"];
        row.git = @{@"branch": @"pay-148", @"root": tree, @"worktree": @YES, @"worktreeOf": @"acme-web",
                    @"mainRoot": web};
    } else if ([place isEqual:@"plain"]) {
        row.cwd = [code stringByAppendingPathComponent:@"scratch"];
    }
    return row;
}

// The plain functions over made-up cases.
static void PrintCases(void) {
    PrintLine(@"== What changed, against the note as kept");
    NSArray *cases = @[
        @[@"nothing kept: every line added", @[], @[@"A", @"B"]],
        @[@"the same", @[@"A", @"B"], @[@"A", @"B"]],
        @[@"one taken out, one added", @[@"A", @"B", @"C"], @[@"A", @"C", @"D"]],
        @[@"one changed in place", @[@"A", @"B", @"C"], @[@"A", @"B2", @"C"]],
        @[@"moved to the end", @[@"A", @"B", @"C"], @[@"B", @"C", @"A"]],
        @[@"everything new", @[@"A"], @[@"B"]],
    ];
    for (NSArray *each in cases) {
        NSMutableArray *said = [NSMutableArray array];
        for (NSDictionary *line in ProcessChanges(each[1], each[2]))
            [said addObject:[NSString stringWithFormat:@"%@%@", [line[@"mark"] isEqual:@"added"] ? @"+"
                                                              : [line[@"mark"] isEqual:@"removed"] ? @"-" : @" ",
                                                              line[@"text"]]];
        printf("%s: %s\n", [each[0] UTF8String], [said componentsJoinedByString:@" "].UTF8String);
    }
    PrintLine(@"== Whether a draft after Not Now holds anything new");
    printf("the same lines: %s\n", ProcessHoldsNew(@[@"A", @"B"], @[@"A", @"B"], nil) ? "yes" : "no");
    printf("fewer lines: %s\n", ProcessHoldsNew(@[@"A"], @[@"A", @"B"], nil) ? "yes" : "no");
    printf("the same, in another order: %s\n", ProcessHoldsNew(@[@"B", @"A"], @[@"A", @"B"], nil) ? "yes" : "no");
    printf("a line that wasn't there: %s\n", ProcessHoldsNew(@[@"A", @"C"], @[@"A", @"B"], nil) ? "yes" : "no");
    printf("against a note kept, a kept line taken out the declined one kept: %s\n",
           ProcessHoldsNew(@[@"A", @"C"], @[@"A", @"B", @"C"], @[@"A", @"B"]) ? "yes" : "no");
    printf("against a note kept, the same line taken out as the declined one: %s\n",
           ProcessHoldsNew(@[@"A"], @[@"A", @"C"], @[@"A", @"B"]) ? "yes" : "no");
    printf("against a note kept, keeping a line the declined one took out, and nothing else: %s\n",
           ProcessHoldsNew(@[@"A", @"B"], @[@"A", @"C"], @[@"A", @"B"]) ? "yes" : "no");
    PrintLine(@"== A draft checked");
    for (NSString *name in @[@"listed", @"empty", @"secret", @"control", @"long", @"forty", @"wide", @"huge"]) {
        NSString *why = nil;
        NSArray *lines = ProcessDraftLines(SampleNote(name), &why);
        printf("%s: %s\n", name.UTF8String,
               (lines ? [NSString stringWithFormat:@"%lu lines, the first: %@", (unsigned long)lines.count,
                         Clip(lines.firstObject, 60)] : [@"turned away: " stringByAppendingString:why]).UTF8String);
    }
    PrintLine(@"== A key in a note, in the shapes a page or a person writes one: turned away");
    NSString *jwt = [NSString stringWithFormat:@"ey%@.ey%@.%@", [@"J" stringByAppendingString:MadeUp(20)],
                                               [@"J" stringByAppendingString:MadeUp(24)], MadeUp(30)];
    NSString *atlassian = [@"ATA" stringByAppendingFormat:@"TT3x%@", MadeUp(40)];
    // Each made so that only the shape it's named for finds it, but AWS's, whose name is a key's name too.
    NSArray *keys = @[
        @[@"a password exported", [NSString stringWithFormat:@"Tests: export DB_PASSWORD=%@ first.", MadeUp(16)]],
        @[@"a password in words", [NSString stringWithFormat:@"Staging: the staging password is %@.", MadeUp(16)]],
        @[@"an API key set", [NSString stringWithFormat:@"Setup: API_KEY=%@ in .env.", MadeUp(30)]],
        @[@"a secret key set, in words joined by hyphens and more",
          [NSString stringWithFormat:@"Django: SECRET_KEY=django-insecure-%@", MadeUp(20)]],
        @[@"a signing key, as YAML", [NSString stringWithFormat:@"Webhooks: signing_key: %@", MadeUp(24)]],
        @[@"a client secret, with a colon", [NSString stringWithFormat:@"Sign-in: client_secret: %@", MadeUp(24)]],
        @[@"a password given to a command", [NSString stringWithFormat:@"Database: mysql --password %@", MadeUp(16)]],
        @[@"a sign-in header", [NSString stringWithFormat:@"API: send Authorization: Basic %@==", MadeUp(22)]],
        @[@"Atlassian's token, on its own", [NSString stringWithFormat:@"Jira: use %@ for the board.", atlassian]],
        @[@"Atlassian's token, after an underscore", [NSString stringWithFormat:@"Jira: use KEY_%@", atlassian]],
        @[@"a signed token", [NSString stringWithFormat:@"Auth: send %@ with each call.", jwt]],
        @[@"a signed token, after an underscore", [NSString stringWithFormat:@"Auth: AUTH_%@", jwt]],
        @[@"AWS's secret, after its name alone", [NSString stringWithFormat:@"Deploys: aws_secret_access_key %@",
                                                                          MadeUp(40)]],
        @[@"a password in a link", [NSString stringWithFormat:@"Database: postgres://app:%@@db.example.invalid/app",
                                                            MadeUp(16)]],
        @[@"only a password in a link", [NSString stringWithFormat:@"Cache: redis://:%@@cache.example.invalid:6379",
                                                                 MadeUp(16)]],
        @[@"a provider's own shape, on its own", [NSString stringWithFormat:@"Deploys: use %@ there.", MadeUpToken()]],
        @[@"a password with symbols, after a colon",
          [NSString stringWithFormat:@"Staging: admin password: %@", MadeUpPassword(16)]],
        @[@"a password with symbols, after \"is\"", [NSString stringWithFormat:@"The admin password is %@",
                                                                            MadeUpPassword(14)]],
        @[@"curl's user and password", [NSString stringWithFormat:@"API: curl -u admin:%@ https://api.example.invalid",
                                                                MadeUp(16)]],
        @[@"MySQL's password, joined on", [NSString stringWithFormat:@"Database: mysql -u root -p%@ acme", MadeUp(12)]],
        @[@"mysqldump's", [NSString stringWithFormat:@"Backups: mysqldump -u root -p%@ acme > dump.sql", MadeUp(12)]],
        @[@"mysqladmin's", [NSString stringWithFormat:@"Database: mysqladmin -u root -p%@ status", MadeUp(12)]],
        @[@"sshpass's", [NSString stringWithFormat:@"Deploys: sshpass -p %@ ssh deploy@host", MadeUp(12)]],
        @[@"a token sent as a header, by its name",
          [NSString stringWithFormat:@"API: send Authorization: token %@.%@", MadeUp(10), MadeUp(10)]],
        @[@"a camel-cased account key", [NSString stringWithFormat:@"Storage: AccountKey=%@==;", MadeUp(42)]],
        @[@"a camel-cased master key, with a colon", [NSString stringWithFormat:@"Search: masterKey: %@", MadeUp(24)]],
        @[@"Slack's webhook", [@"Alerts: post to hooks.sl" stringByAppendingFormat:@"ack.com/services/T%@/B%@/%@",
                                                                           MadeUp(8), MadeUp(8), MadeUp(24)]],
        @[@"Discord's webhook", [@"Alerts: post to disc" stringByAppendingFormat:@"ord.com/api/webhooks/%@/%@",
                                                                             MadeUpFrom(@"", @"0123456789", 18),
                                                                             MadeUp(60)]],
        @[@"Stripe's webhook secret", [@"Payments: whs" stringByAppendingFormat:@"ec_%@ in .env", MadeUp(32)]],
        @[@"a key after its name and a space", [NSString stringWithFormat:@"Setup: the API key %@ goes in .env.",
                                                                        MadeUpHex(32)]],
        @[@"…in quotes", [NSString stringWithFormat:@"Setup: the API key \"%@\" goes in .env.", MadeUpHex(32)]],
        @[@"curl's, joined on", [NSString stringWithFormat:@"API: curl -uadmin:%@ https://api.example.invalid",
                                                         MadeUp(16)]],
        @[@"curl's, its user a variable", [NSString stringWithFormat:@"API: curl -u $API_USER:%@ https://api.example.invalid",
                                                                   MadeUp(16)]],
        @[@"curl's proxy's", [NSString stringWithFormat:@"API: curl --proxy-user ops:%@ https://api.example.invalid",
                                                      MadeUp(16)]],
        @[@"sshpass's, set for it", [NSString stringWithFormat:@"Deploys: SSHPASS=%@ sshpass -e ssh deploy@host",
                                                             MadeUp(12)]],
        @[@"Slack's workflow webhook", [@"Alerts: post to hooks.sl" stringByAppendingFormat:@"ack.com/triggers/T%@/%@/%@",
                                                                                    MadeUp(8), MadeUp(12), MadeUp(24)]],
        @[@"Discord's webhook, by its API's version",
          [@"Alerts: post to disc" stringByAppendingFormat:@"ord.com/api/v10/webhooks/%@/%@",
                                                                   MadeUpFrom(@"", @"0123456789", 18), MadeUp(60)]],
    ];
    for (NSArray *each in keys) {
        NSString *why = nil;
        BOOL kept = ProcessDraftLines([kStaging stringByAppendingFormat:@"\n%@", each[1]], &why) != nil;
        printf("%s: %s\n", [each[0] UTF8String],
               (kept ? @"kept in the draft" : [@"turned away: " stringByAppendingString:why]).UTF8String);
    }
    PrintLine(@"== Words about keys, with none in them: kept");
    for (NSString *line in @[
             @"Token: regenerated each week by ops. (CONTRIBUTING.md)",
             @"API key: ask the user for one; it's never in the repo. (you, on PAY-142)",
             @"Secrets: never in the repo. (CONTRIBUTING.md)",
             @"Passwords: the staging password is in the team's vault. (you, on PAY-142)",
             @"Checks: npm test with NODE_ENV=test. (CONTRIBUTING.md)",
             @"Links: the API docs at https://example.invalid/docs/v2 say how. (found on PAY-148)",
             @"Staging: the API key is environment-specific, ask ops for one. (you, on PAY-142)",
             @"Staging password: 1Password, under Staging. (you, on PAY-142)",
             @"Auth: the token is OAuth2-based. (CONTRIBUTING.md)",
             @"Uploads: the secret is base64-encoded in CI. (found on PAY-148)",
             @"API key: https://console.example.invalid/settings/api-keys has the button. (you)",
             @"Token: ~/.config/acme/credentials.json, made by make login. (found on PAY-148)",
             @"Tests: export API_KEY=$STAGING_API_KEY first. (CONTRIBUTING.md)",
             @"CI: GITHUB_TOKEN=${GITHUB_TOKEN} is set by the runner. (found on PAY-148)",
             @"Setup: set API_KEY=your-key-here in .env, then ask for a real one. (CONTRIBUTING.md)",
             @"Deploys: aws_secret_access_key comes from the team's vault. (you, on PAY-142)",
             @"Basic checks: lint and typecheck pass. (CONTRIBUTING.md)",
             @"Repos: clone with ssh://git@git.example.invalid:22/acme/web.git (CONTRIBUTING.md)",
             @"Staging password: ask ops; it rotates weekly! (you, on PAY-142)",
             @"Accounts: the admin password is changed each sprint, by ops! (you)",
             @"Tokens: the token is v2-style now? Ask ops. (you, on PAY-142)",
             @"API: curl -u $API_USER:$API_PASS https://api.example.invalid (CONTRIBUTING.md)",
             @"API: curl -u admin, then type the password it asks for. (you)",
             @"Database: mysql -u root -p, then type the password. (you, on PAY-142)",
             @"Database: mysql -h db -P3306 -u app -p acme (CONTRIBUTING.md)",
             @"Backups: mysqldump -p --all-databases asks for it. (found on PAY-148)",
             @"Deploys: sshpass -f with the file ops gives you, never -p. (you)",
             @"API: send Authorization: Bearer ${API_TOKEN} from the runner. (found on PAY-148)",
             @"API: the Authorization: token header comes from the vault. (you)",
             @"Storage: the AccountKey comes from the portal. (found on PAY-148)",
             @"Search: the masterKey is set by ops, never by a session. (you)",
             @"Alerts: post to the team's Slack webhook; ops has its address. (you)",
             @"Alerts: Discord webhooks go in the team's vault. (you, on PAY-142)",
             @"Payments: whsec_ comes from Stripe's dashboard. (CONTRIBUTING.md)",
             @"Setup: the API key rotation is quarterly. (CONTRIBUTING.md)",
             @"Setup: the API key generation_handled_by_ops_team is in docs. (CONTRIBUTING.md)",
             @"Storage: the access key S3_BUCKET_ACCESS_KEY_ID is set in CI. (found on PAY-148)",
             @"CI: the token S3_UPLOAD_ACCESS_TOKEN comes from the runner. (found on PAY-148)",
             @"Payments: the secret STRIPE_WEBHOOK_SECRET_V2 is in the vault. (you)",
             @"Deploys: the password DEPLOY_PASSWORD_2024 lives in the vault. (you)",
             @"Tokens: Token: S3_UPLOAD_TOKEN_2 is set by CI. (found on PAY-148)",
             @"Deploys: sshpass -f ~/.pw ssh -p 2222 deploy@host (CONTRIBUTING.md)",
             @"Deploys: sshpass -p with a password is banned; use -f. (you)",
             @"Database: mysql runs in Docker: docker run -p3306:3306 mysql:8 (CONTRIBUTING.md)",
             @"Database: mysql over the tunnel: ssh -p2222 db.example.invalid (you)",
             @"Backups: mysqldump for MySQL, pg_dump -p5432 for Postgres. (CONTRIBUTING.md)",
             @"Database: mysql dumps: find dumps -name '*.sql' -print | xargs ls (found on PAY-148)",
             @"Docker: curl the compose file, then docker run -u 1000:1000 app. (CONTRIBUTING.md)",
             @"API: curl -u user:password https://api.example.invalid is the shape. (CONTRIBUTING.md)",
             @"API: curl -u USER:PASS, with your own. (CONTRIBUTING.md)",
             @"Staging password: 1Password! (you, on PAY-142)",
             @"Staging password: 1Password? Ask ops. (you, on PAY-142)",
             @"Auth: the token is OAuth2-based! (CONTRIBUTING.md)",
             @"Tokens: the token is v2-style? Ask ops. (you)",
             @"Auth: the token is **OAuth2**. (CONTRIBUTING.md)",
             @"Credentials: ops2@example.invalid has them. (you, on PAY-142)",
             @"API key: console.example.invalid/keys?env=2 has the button. (you)",
             @"API: send Authorization: Basic base64(user:password). (CONTRIBUTING.md)",
             @"API: send Authorization: token YOUR_GITHUB_TOKEN, your own. (CONTRIBUTING.md)"]) {
        printf("%s: %s\n", Clip(line, 40).UTF8String, ProcessDraftLines(line, NULL) ? "kept" : "turned away");
    }
    PrintLine(@"== A note kept with a key in it, read back: that line left out");
    {
        double at = 0;
        NSArray *read = ProcessKeptLines(@{@"project": @"/work/acme-web", @"keptAt": @5,
                                           @"note": @[kStaging, [NSString stringWithFormat:@"Tests: DB_PASSWORD=%@",
                                                                                           MadeUp(16)], kScreens]},
                                         @"/work/acme-web", &at);
        printf("%lu of 3 lines handed on, the key's not among them: %s\n", (unsigned long)read.count,
               [read isEqual:@[kStaging, kScreens]] ? "yes" : "no");
    }
    PrintLine(@"== The project a folder is in, and the file its note is kept in");
    printf("a worktree: %s\n", ProcessProject(@{@"root": @"/work/acme-web-wt", @"mainRoot": @"/work/acme-web"},
                                              @"/work/acme-web-wt/src").UTF8String);
    printf("its main checkout: %s\n", ProcessProject(@{@"root": @"/work/acme-web"}, @"/work/acme-web").UTF8String);
    printf("outside git: %s\n", ProcessProject(nil, @"/work/scratch/").UTF8String);
    printf("no folder: %s\n", ProcessProject(nil, nil) ? "a project" : "none");
    printf("a folder that isn't a full path: %s\n", ProcessProject(nil, @"work") ? "a project" : "none");
    printf("the file names nothing of the path: %s\n",
           [ProcessRecordName(@"/work/acme-web") containsString:@"acme"] ? "NO" : "yes");
    printf("one file for each project: %s\n",
           [ProcessRecordName(@"/work/acme-web") isEqual:ProcessRecordName(@"/work/acme-api")] ? "NO" : "yes");
    printf("a record read back only for its own project: %s\n",
           ProcessKeptLines(ProcessRecord(@"/work/acme-web", @[@"A"], 1), @"/work/acme-api", NULL) ? "NO" : "yes");
}

// Steps, each one argument: `row <id> <repo|tree|plain|none>`, a session's row; `ended <id>`, its session ended;
// `draft <id> <note>`, process-draft with one of the made-up notes (SampleNote); `keep <id>`, `notnow <id>`, your
// press on its card, for the draft it shows; `stale <id>`, Keep It for a draft that has gone since; `locked`, the
// note's place made a folder, so Keep It can't write it, and `unlocked`, put right; `later <seconds>`, the clock on;
// `rows`, each row's processDraft; `way <id>`, its way (ProjectWay); `kept`, what's in the folder; `relaunch`, a new
// copy of the module, reading it back; `cases`, the plain functions; `log`, whether panel.log has a word of a note;
// and `logged`, its lines since the last, without their times.
static int PrintProcess(Core *core, NSArray<NSString *> *steps) {
    if (HomeIsYourOwn()) {
        fprintf(stderr, "--print-process runs only in a throwaway home\n");
        return 2;
    }
    __block double now = 2e12;
    NSString *code = MakeProjects(core.agents.firstObject), *folder = AppDir(@"process-notes");
    // Whozmove's own folder, as the app has it from its start, so panel.log is written from the first step.
    [NSFileManager.defaultManager createDirectoryAtPath:folder.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSMutableSet<NSString *> *ended = [NSMutableSet set];
    ProcessNotesModule *(^make)(void) = ^ProcessNotesModule *{
        ProcessNotesModule *module = [[ProcessNotesModule alloc] initWithCore:core];
        module.clock = ^double { return now; };
        module.givenRuns = ^BOOL(Row *row) { return ![ended containsObject:row.sessionId]; };
        [module keepIn:folder];
        return module;
    };
    ProcessNotesModule *notes = make();
    NSMutableDictionary<NSString *, Row *> *rows = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSUInteger logRead = 0;
    NSArray<Row *> *(^listed)(void) = ^NSArray<Row *> * {
        NSMutableArray *all = [NSMutableArray array];
        for (NSString *sessionId in order) [all addObject:rows[sessionId]];
        return all;
    };
    for (NSString *step in steps) {
        NSArray<NSString *> *words = [step componentsSeparatedByString:@" "];
        NSString *verb = words.firstObject, *sessionId = words.count > 1 ? words[1] : @"";
        NSString *rest = words.count > 2 ? words[2] : @"";
        printf("== %s\n", step.UTF8String);
        if ([verb isEqual:@"row"]) {
            if (!rows[sessionId]) [order addObject:sessionId];
            rows[sessionId] = SampleRow(sessionId, rest, code);
            [ended removeObject:sessionId];
        } else if ([verb isEqual:@"ended"]) {
            [ended addObject:sessionId];
        } else if ([verb isEqual:@"draft"]) {
            NSString *note = SampleNote(rest) ?: rest;
            NSString *note64 = [[note dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            PrintLine([notes draft:@{@"ask": @"process-draft", @"note64": note64} from:rows[sessionId]]);
        } else if ([@[@"keep", @"notnow", @"stale"] containsObject:verb]) {
            NSDictionary *shown = nil;
            [notes rows:listed() phase:RowPhaseListed];
            shown = rows[sessionId].processDraft;
            NSNumber *at = [verb isEqual:@"stale"] ? @(now - 1000) : shown[@"at"] ?: @0;
            __block BOOL done = NO;
            [notes answer:[verb isEqual:@"notnow"] ? @"notNow" : @"keep" for:sessionId at:at done:^{ done = YES; }];
            // While Keep It writes, the card says so.
            [notes rows:listed() phase:RowPhaseListed];
            if (rows[sessionId].processDraft[@"keeping"]) PrintLine(@"   (the card: Keeping it…)");
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
            while (!done && until.timeIntervalSinceNow > 0)
                [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        } else if ([verb isEqual:@"locked"] || [verb isEqual:@"unlocked"]) {
            // The note's file made a folder, so it can't be written in its place.
            NSString *project = ProcessProject(nil, [code stringByAppendingPathComponent:@"acme-web"]);
            NSString *path = [folder stringByAppendingPathComponent:ProcessRecordName(project)];
            if ([verb isEqual:@"locked"]) {
                [NSFileManager.defaultManager createDirectoryAtPath:[path stringByAppendingPathComponent:@"in-the-way"]
                                        withIntermediateDirectories:YES attributes:nil error:nil];
            } else [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        } else if ([verb isEqual:@"later"]) {
            now += sessionId.doubleValue * 1000;
        } else if ([verb isEqual:@"rows"]) {
            [notes rows:listed() phase:RowPhaseListed];
            for (NSString *each in order) {
                NSMutableDictionary *shown = [rows[each].processDraft mutableCopy];
                // Times as seconds from now, so a run reads the same every time.
                for (NSString *key in @[@"at", @"keptAt", @"declinedAt"])
                    if (shown[key]) shown[key] = [NSString stringWithFormat:@"%+.0fs", ([shown[key] doubleValue] - now) / 1000];
                printf("%s: %s\n", each.UTF8String, shown ? JSONLine(shown).UTF8String : "no card");
            }
        } else if ([verb isEqual:@"way"]) {
            NSMutableDictionary *way = [[notes wayFor:rows[sessionId]] mutableCopy];
            if (way[@"keptAt"]) way[@"keptAt"] = [NSString stringWithFormat:@"%+.0fs", ([way[@"keptAt"] doubleValue] - now) / 1000];
            PrintLine(way ? JSONLine(way) : @"none");
        } else if ([verb isEqual:@"kept"]) {
            NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]
                              sortedArrayUsingSelector:@selector(compare:)];
            printf("%lu file%s\n", (unsigned long)names.count, names.count == 1 ? "" : "s");
            for (NSString *name in names) {
                NSString *path = [folder stringByAppendingPathComponent:name];
                NSDictionary *about = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
                NSMutableDictionary *record = [AsRecord(ReadJSON(path)) mutableCopy];
                if (record[@"keptAt"]) record[@"keptAt"] = [NSString stringWithFormat:@"%+.0fs", ([record[@"keptAt"] doubleValue] - now) / 1000];
                NSString *mode = about.filePosixPermissions == 0600 ? @"only you can read it"
                    : [NSString stringWithFormat:@"mode %lo", (unsigned long)about.filePosixPermissions];
                BOOL named = [name isEqual:ProcessRecordName(AsText(record[@"project"]) ?: @"")];
                printf("   %s, %s: %s\n", mode.UTF8String, named ? "named for its project" : "named otherwise",
                       JSONLine(record).UTF8String);
            }
        } else if ([verb isEqual:@"relaunch"]) {
            notes = make();
        } else if ([verb isEqual:@"cases"]) {
            PrintCases();
        } else if ([verb isEqual:@"log"]) {
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"";
            BOOL said = NO;
            for (NSString *word in @[@"Docker", @"Staging", @"Screenshots", @"Saved cards", @"QA"])
                said = said || [log containsString:word];
            printf("panel.log %s a word of a note\n", said ? "HAS" : "has none of");
        } else if ([verb isEqual:@"logged"]) {
            NSString *log = [NSString stringWithContentsOfFile:AppDir(@"panel.log") encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"";
            NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
            for (NSUInteger i = logRead; i < lines.count; i++) {
                NSRange gap = [lines[i] rangeOfString:@"  "];
                if (gap.location != NSNotFound) printf("%s\n", [lines[i] substringFromIndex:NSMaxRange(gap)].UTF8String);
            }
            logRead = lines.count ? lines.count - 1 : 0;
        } else {
            fprintf(stderr, "--print-process: no step %s\n", verb.UTF8String);
            return 2;
        }
    }
    return 0;
}

NSDictionary<NSString *, PrintMode> *ProcessNotesPrintModes(void) {
    return @{@"--print-process": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintProcess(core, arguments); }};
}
