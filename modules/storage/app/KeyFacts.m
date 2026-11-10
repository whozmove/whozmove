// KeyFacts: what Keys relies on about other programs (KeyFacts.h). Checked with Betterleaks 2.0.0-rc.4 and 1.9.0,
// and with Codex CLI's and Gemini CLI's documented folders and Aider's documented history file as they were then.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "KeyFacts.h"

NSString *const kBetterleaksInBundle = @"Contents/Helpers/betterleaks";

static NSDictionary *Kinds(void);

NSInteger BetterleaksMajor(NSString *said) {
    NSString *version = [said stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([version hasPrefix:@"v"]) version = [version substringFromIndex:1];
    NSInteger major = [version componentsSeparatedByString:@"."].firstObject.integerValue;
    return major == 1 || major == 2 ? major : 0;
}

// Version 2: `--redact` keeps the key out of the report (its fingerprint stays), made with a secret of this Mac's
// (BetterleaksEnvironment), `--validate` and `--analyze` would ask each key's provider about it, `--exit-code` is
// what it ends with on finding one, and only its own rules are read unless it's given others. Files over 8 MB aren't
// looked in, each mode saying so its own way; a checkout that's a worktree keeps its history in its repo's folder,
// which git mode reads only when let. Version 1: `dir` for fs, its report one JSON list, online checks only with
// `--validation`, a project's own .betterleaks.toml read unless `--config` names the rules, a .betterleaksignore read
// from where it runs unless `--gitleaks-ignore-path` names another folder, and git mode's commits given as git log's.
NSArray<NSString *> *BetterleaksArguments(NSInteger major, NSString *mode, NSDictionary *with) {
    BOOL files = [mode isEqualToString:@"fs"], git = [mode isEqualToString:@"git"];
    if (major == 1) {
        NSMutableArray *arguments = [@[files ? @"dir" : mode, @"--no-banner", @"--no-color", @"--log-level=error",
                                       @"--report-format=json", @"--report-path=-", @"--exit-code=0",
                                       [@"--config=" stringByAppendingString:with[@"rules"] ?: @""],
                                       [@"--gitleaks-ignore-path=" stringByAppendingString:with[@"empty"] ?: @""]]
                                     mutableCopy];
        if (files || git) [arguments addObject:@"--max-target-megabytes=8"];
        if (git) [arguments addObject:[@"--log-opts=" stringByAppendingString:with[@"range"] ?: @""]];
        return arguments;
    }
    NSMutableArray *arguments = [@[mode, @"--no-banner", @"--no-color", @"--log-level=error", @"--jsonl", @"--output=-",
                                   @"--redact", @"--validate=false", @"--analyze=false", @"--exit-code=0"]
                                 mutableCopy];
    if (files) [arguments addObject:@"--max-target-megabytes=8"];
    if (git) [arguments addObjectsFromArray:@[@"--git-max-blob-mib=8", @"--allow-external-objects",
                                              [@"--revision=" stringByAppendingString:with[@"range"] ?: @""]]];
    return arguments;
}

// Version 2 takes the fingerprints' secret from its environment as well as from `--hmac-key`: there, it isn't in the
// command line a list of processes shows. Either version, a Go program, looks with a thread for each core it sees
// (as many as 6 cores at once on a folder) unless GOMAXPROCS says how many: one, so a look never takes more than a
// core, however long it takes.
NSDictionary<NSString *, NSString *> *BetterleaksEnvironment(NSInteger major, NSString *secret) {
    NSMutableDictionary *environment = [@{@"GOMAXPROCS": @"1"} mutableCopy];
    if (major == 2 && secret.length) environment[@"BETTERLEAKS_FINGERPRINT_HMAC_KEY"] = secret;
    return environment;
}

BOOL BetterleaksReportsLines(NSInteger major) {
    return major != 1;
}

// The kind a key is by how it starts, for a start only one kind has and long enough to tell (ghp_, sk-ant-); nil for
// none.
static NSString *KindByStart(NSString *key) {
    static NSDictionary<NSString *, NSString *> *byStart;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *starts = [NSMutableDictionary dictionary];
        NSCountedSet *seen = [NSCountedSet set];
        for (NSString *rule in Kinds()) {
            NSString *start = KeyKind(rule)[@"start"];
            if (start.length < 4) continue;
            [seen addObject:start];
            starts[start] = rule;
        }
        for (NSString *start in seen)
            if ([seen countForObject:start] > 1) [starts removeObjectForKey:start];
        byStart = starts;
    });
    NSString *found = nil;
    for (NSString *start in byStart)
        if ([key hasPrefix:start] && start.length > [KeyKind(found)[@"start"] length]) found = byStart[start];
    return found;
}

NSDictionary *BetterleaksFinding(NSInteger major, NSDictionary *record, NSString *(^fingerprint)(NSString *key)) {
    if (major != 1) return [record[@"finding"] isKindOfClass:NSDictionary.class] ? record[@"finding"] : nil;
    NSString *rule = record[@"RuleID"], *key = record[@"Secret"];
    if (![rule isKindOfClass:NSString.class] || ![key isKindOfClass:NSString.class] || !key.length) return nil;
    // Version 1's generic rule can win over the one for the key's own kind (on `TOKEN=ghp_…`, say): a key that starts
    // as only one kind's keys do is that kind, as version 2 names it.
    if ([rule hasPrefix:@"generic-"]) rule = KindByStart(key) ?: rule;
    NSMutableDictionary *about = [NSMutableDictionary dictionary];
    if ([record[@"Commit"] isKindOfClass:NSString.class] && [record[@"Commit"] length]) about[@"git.sha"] = record[@"Commit"];
    return @{@"rule_id": rule, @"match": @{@"fingerprint": fingerprint(key)}, @"attributes": about,
             @"location": @{@"path": [record[@"File"] isKindOfClass:NSString.class] ? record[@"File"] : @"",
                            @"start_line": record[@"StartLine"] ?: @0, @"end_line": record[@"EndLine"] ?: @0,
                            @"start_column": record[@"StartColumn"] ?: @0, @"end_column": record[@"EndColumn"] ?: @0}};
}

BOOL BetterleaksFinished(NSDictionary *record) {
    return [record[@"scan"] isKindOfClass:NSDictionary.class] && [record[@"scan"][@"state"] isEqual:@"complete"];
}

// What a rule's match takes in around a key to tell where it ends, which the match's place counts too: a quote, a
// space, a closing bracket, or an escaped line break written out (\n).
NSCharacterSet *KeyMatchEdges(void) {
    return [NSCharacterSet characterSetWithCharactersInString:@"\"'`;,: \t\r\n)]}>"];
}

// The kinds people most often have, by Betterleaks' rule: its provider, how every key of the kind starts, and where
// it's replaced. A rule not here is still found and listed, by its own words, with no page to replace it at.
static NSDictionary *Kinds(void) {
    static NSDictionary *kinds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *(^kind)(NSString *, NSString *, NSString *) = ^(NSString *name, NSString *start, NSString *page) {
            return @{@"name": name, @"start": start, @"replace": page};
        };
        NSString *github = @"https://github.com/settings/tokens", *gitlab =
            @"https://gitlab.com/-/user_settings/personal_access_tokens", *aws =
            @"https://console.aws.amazon.com/iam/home#/security_credentials", *google =
            @"https://console.cloud.google.com/apis/credentials", *slack = @"https://api.slack.com/apps", *vercel =
            @"https://vercel.com/account/settings/tokens";
        kinds = @{
            @"anthropic-api-key": kind(@"Anthropic", @"sk-ant-", @"https://console.anthropic.com/settings/keys"),
            @"anthropic-admin-api-key": kind(@"Anthropic", @"sk-ant-admin", @"https://console.anthropic.com/settings/admin-keys"),
            @"openai-api-key": kind(@"OpenAI", @"sk-", @"https://platform.openai.com/api-keys"),
            @"github-pat": kind(@"GitHub", @"ghp_", github),
            @"github-fine-grained-pat": kind(@"GitHub", @"github_pat_", @"https://github.com/settings/personal-access-tokens"),
            @"github-oauth": kind(@"GitHub", @"gho_", @"https://github.com/settings/applications"),
            @"github-app-token": kind(@"GitHub", @"", @"https://github.com/settings/apps"),
            @"github-refresh-token": kind(@"GitHub", @"ghr_", @"https://github.com/settings/applications"),
            @"gitlab-pat": kind(@"GitLab", @"glpat-", gitlab),
            @"gitlab-pat-routable": kind(@"GitLab", @"glpat-", gitlab),
            @"gitlab-pat-routable-versioned": kind(@"GitLab", @"glpat-", gitlab),
            @"aws-access-token": kind(@"AWS", @"", aws),
            @"aws-secret-access-key": kind(@"AWS", @"", aws),
            @"aws-amazon-bedrock-api-key-long-lived": kind(@"AWS Bedrock", @"ABSK", aws),
            @"gcp-api-key": kind(@"Google Cloud", @"AIza", google),
            @"gcp-gemini-api": kind(@"Google Gemini", @"AIza", @"https://aistudio.google.com/apikey"),
            @"gcp-service-account": kind(@"Google Cloud", @"", @"https://console.cloud.google.com/iam-admin/serviceaccounts"),
            @"stripe-access-token": kind(@"Stripe", @"", @"https://dashboard.stripe.com/apikeys"),
            @"slack-bot-token": kind(@"Slack", @"xoxb-", slack),
            @"slack-user-token": kind(@"Slack", @"xoxp-", slack),
            @"slack-app-token": kind(@"Slack", @"xapp-", slack),
            @"slack-webhook-url": kind(@"Slack", @"https://hooks.slack.com/", slack),
            @"npm-access-token": kind(@"npm", @"npm_", @"https://www.npmjs.com/settings/~/tokens"),
            @"pypi-upload-token": kind(@"PyPI", @"pypi-", @"https://pypi.org/manage/account/token/"),
            @"huggingface-access-token": kind(@"Hugging Face", @"hf_", @"https://huggingface.co/settings/tokens"),
            @"openrouter-api-key": kind(@"OpenRouter", @"sk-or-", @"https://openrouter.ai/settings/keys"),
            @"groq-api-key": kind(@"Groq", @"gsk_", @"https://console.groq.com/keys"),
            @"xai-api-key": kind(@"xAI", @"xai-", @"https://console.x.ai"),
            @"mistral-api-key": kind(@"Mistral", @"", @"https://console.mistral.ai/api-keys"),
            @"deepseek-api-key": kind(@"DeepSeek", @"sk-", @"https://platform.deepseek.com/api_keys"),
            @"perplexity-api-key": kind(@"Perplexity", @"pplx-", @"https://www.perplexity.ai/settings/api"),
            @"cohere-api-token": kind(@"Cohere", @"", @"https://dashboard.cohere.com/api-keys"),
            @"replicate-api-token": kind(@"Replicate", @"r8_", @"https://replicate.com/account/api-tokens"),
            @"cursor-api-key": kind(@"Cursor", @"", @"https://cursor.com/dashboard"),
            @"vercel-api-token": kind(@"Vercel", @"", vercel),
            @"vercel-personal-access-token": kind(@"Vercel", @"", vercel),
            @"vercel-ai-gateway-key": kind(@"Vercel", @"", vercel),
            @"supabase-management-token": kind(@"Supabase", @"sbp_", @"https://supabase.com/dashboard/account/tokens"),
            @"cloudflare-api-key.1": kind(@"Cloudflare", @"", @"https://dash.cloudflare.com/profile/api-tokens"),
            @"cloudflare-global-api-key": kind(@"Cloudflare", @"", @"https://dash.cloudflare.com/profile/api-tokens"),
            @"digitalocean-pat": kind(@"DigitalOcean", @"dop_v1_", @"https://cloud.digitalocean.com/account/api/tokens"),
            @"heroku-api-key-v2": kind(@"Heroku", @"HRKU-", @"https://dashboard.heroku.com/account/applications"),
            @"sendgrid-api-token": kind(@"SendGrid", @"SG.", @"https://app.sendgrid.com/settings/api_keys"),
            @"twilio-api-key": kind(@"Twilio", @"SK", @"https://console.twilio.com/us1/account/keys-credentials/api-keys"),
            @"dockerhub-personal-access-token": kind(@"Docker Hub", @"dckr_pat_", @"https://app.docker.com/settings/personal-access-tokens"),
            @"private-key": kind(@"Private key", @"-----BEGIN", @""),
            @"jwt": kind(@"Sign-in token (JWT)", @"eyJ", @""),
        };
    });
    return kinds;
}

NSDictionary *KeyKind(NSString *rule) {
    return rule ? Kinds()[rule] : nil;
}

BOOL KeyKindHasNoProvider(NSString *rule) {
    return [rule hasPrefix:@"generic-"]
        || [[NSSet setWithArray:@[@"jwt", @"jwt-base64", @"curl-auth-header", @"curl-auth-user"]] containsObject:rule];
}

BOOL KeyReportField(NSString *name) {
    return name && [[NSSet setWithArray:@[@"full", @"value", @"match", @"Match", @"Secret"]] containsObject:name];
}

BOOL KeyHasProviderStart(NSString *text) {
    static NSArray<NSString *> *starts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *all = [NSMutableSet setWithArray:@[@"sk-", @"sk_live_", @"sk_test_", @"rk_live_", @"pk_live_",
                                                         @"AKIA", @"ASIA", @"AIza", @"xoxb-", @"xoxp-", @"xapp-",
                                                         @"lin_api_", @"shpat_", @"PMAK-", @"sntrys_"]];
        for (NSDictionary *kind in Kinds().allValues)
            if ([kind[@"start"] length] >= 3 && ![kind[@"start"] isEqualToString:@"eyJ"]
                && ![kind[@"start"] hasPrefix:@"-"])
                [all addObject:kind[@"start"]];
        starts = all.allObjects;
    });
    for (NSString *start in starts)
        if ([text hasPrefix:start]) return YES;
    return NO;
}

// GitHub's token formats (github.blog, "Behind GitHub's new authentication token formats"): the last 6 characters are
// a 32-bit checksum, CRC-32 in base 62 padded with 0s, of the 30 random ones between the start and them. A fine-grained
// token's (github_pat_) isn't documented, so it isn't checked.
BOOL KeyFailsItsChecksum(NSString *text) {
    static NSRegularExpression *token;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        token = [NSRegularExpression regularExpressionWithPattern:@"(?:^|[^A-Za-z0-9_])(gh[pousr]_[A-Za-z0-9]*)"
                                                          options:0 error:nil];
    });
    NSTextCheckingResult *found = [token matchesInString:text options:0 range:NSMakeRange(0, text.length)].lastObject;
    if (!found) return NO;
    NSData *bytes = [[text substringWithRange:[found rangeAtIndex:1]] dataUsingEncoding:NSASCIIStringEncoding];
    if (bytes.length != 40) return YES;
    const unsigned char *at = bytes.bytes;
    uint32_t crc = 0xFFFFFFFF;
    for (NSUInteger i = 4; i < 34; i++) {
        crc ^= at[i];
        for (int bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
    }
    crc = ~crc;
    static const char digits[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    char sum[6];
    for (int i = 5; i >= 0; i--, crc /= 62) sum[i] = digits[crc % 62];
    return memcmp(sum, at + 34, 6) != 0;
}

BOOL KeyKindHasChecksum(NSString *rule) {
    return rule && [@[@"github-pat", @"github-oauth", @"github-app-token", @"github-refresh-token"]
                    containsObject:rule];
}

BOOL KeyInTestOrExample(NSString *path) {
    static NSSet *folders;
    static NSArray *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        folders = [NSSet setWithArray:@[@"test", @"tests", @"__tests__", @"spec", @"specs", @"fixtures",
                                        @"__fixtures__", @"testdata", @"test-data", @"__snapshots__", @"__mocks__",
                                        @"mocks", @"examples", @"example", @"samples"]];
        names = @[@".test.", @"_test.", @".spec.", @"_spec.", @".expected.", @".snap", @".golden"];
    });
    NSArray *parts = [path.lowercaseString componentsSeparatedByString:@"/"];
    for (NSUInteger i = 0; i + 1 < parts.count; i++)
        if ([folders containsObject:parts[i]]) return YES;
    NSString *name = parts.lastObject;
    for (NSString *each in names)
        if ([name containsString:each] || [name hasSuffix:each]) return YES;
    return NO;
}

NSArray<NSDictionary *> *KeyCredentialFiles(void) {
    return @[
        @{@"path": @".aws/credentials", @"name": @"AWS credentials"},
        @{@"path": @".npmrc", @"name": @"npm's settings"},
        @{@"path": @".netrc", @"name": @".netrc"},
        @{@"path": @".git-credentials", @"name": @"git's saved passwords"},
        @{@"path": @".docker/config.json", @"name": @"Docker's sign-ins", @"docker": @YES},
        @{@"path": @".pypirc", @"name": @"PyPI's settings"},
        @{@"path": @".codex/auth.json", @"name": @"Codex's sign-in"},
        @{@"path": @".config/gh/hosts.yml", @"name": @"GitHub CLI's sign-in"},
        @{@"path": @".kube/config", @"name": @"Kubernetes' settings"},
    ];
}

NSString *const kKeySSHFolder = @".ssh";

// What's in ~/.ssh that isn't a private key, as OpenSSH names it: public keys end in .pub, and these are its settings
// and lists.
NSSet<NSString *> *KeySSHNotKeys(void) {
    return [NSSet setWithArray:@[@"known_hosts", @"known_hosts.old", @"known_hosts2", @"config", @"authorized_keys",
                                 @"authorized_keys2", @"allowed_signers", @"environment", @"rc"]];
}

NSArray<NSString *> *KeyShellStartupFiles(void) {
    return @[@".zshrc", @".zprofile", @".zshenv", @".zlogin", @".bashrc", @".bash_profile", @".profile",
             @".config/fish/config.fish"];
}

BOOL KeyNameSaysSecret(NSString *name) {
    if (!name.length) return NO;
    for (NSString *word in @[@"api", @"token", @"secret", @"auth", @"pass", @"credential", @"access", @"private"])
        if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

BOOL KeyAfterIdPrefix(NSData *line, NSRange key) {
    static NSRegularExpression *spotify;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        spotify = [NSRegularExpression
                   regularExpressionWithPattern:@"spotify:(track|album|artist|playlist|episode|show):$" options:0
                                          error:nil];
    });
    if (key.location == NSNotFound || key.location > line.length) return NO;
    NSUInteger from = key.location > 32 ? key.location - 32 : 0;
    NSString *before = [[NSString alloc] initWithData:[line subdataWithRange:NSMakeRange(from, key.location - from)]
                                             encoding:NSISOLatin1StringEncoding];
    return before && [spotify numberOfMatchesInString:before options:0 range:NSMakeRange(0, before.length)] > 0;
}

BOOL KeyDockerConfigHoldsSignIn(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *config = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![config isKindOfClass:NSDictionary.class]) return YES;  // what it holds can't be told: it counts
    NSDictionary *auths = config[@"auths"];
    if (![auths isKindOfClass:NSDictionary.class]) return NO;
    for (id registry in auths.allValues) {
        if (![registry isKindOfClass:NSDictionary.class]) continue;
        for (NSString *field in @[@"auth", @"identitytoken", @"registrytoken"])
            if ([registry[field] isKindOfClass:NSString.class] && [registry[field] length]) return YES;
    }
    return NO;
}

NSArray<NSString *> *KeyShellHistories(void) {
    return @[@".zsh_history", @".bash_history", @".local/share/fish/fish_history", @".python_history",
             @".node_repl_history", @".psql_history", @".mysql_history"];
}

// Codex CLI keeps each session a JSONL file a day's folder down, and the messages you typed in history.jsonl; Gemini
// CLI keeps each project's logs and checkpoints as JSON under tmp.
NSArray<NSDictionary *> *KeyAgentRecords(void) {
    return @[
        @{@"app": @"Codex", @"path": @".codex/sessions", @"deep": @YES, @"kind": @"jsonl"},
        @{@"app": @"Codex", @"path": @".codex/history.jsonl", @"deep": @NO, @"kind": @"jsonl"},
        @{@"app": @"Gemini CLI", @"path": @".gemini/tmp", @"deep": @YES, @"kind": @"json"},
    ];
}

// Aider writes its chat history into the project, and keeps it out of git only if its own .gitignore line is there.
NSArray<NSDictionary *> *KeyAgentFilesInProjects(void) {
    return @[@{@"path": @".aider.chat.history.md", @"app": @"Aider"},
             @{@"path": @".aider.input.history", @"app": @"Aider"}];
}

NSArray<NSString *> *KeyMCPFiles(void) {
    return @[@".mcp.json", @".cursor/mcp.json", @".vscode/mcp.json"];
}

NSSet<NSString *> *KeyDownloadsExtensions(void) {
    return [NSSet setWithArray:@[@"json", @"pem", @"key", @"p8", @"env", @"txt", @"yaml", @"yml", @"toml", @"ini",
                                 @"cfg", @"conf", @"csv", @"sh"]];
}

const unsigned long long kKeyDownloadsLargest = 2 * 1024 * 1024;

NSSet<NSString *> *KeyFileExtensions(void) {
    return [NSSet setWithArray:@[@"pem", @"key", @"p8", @"json", @"env"]];
}

const unsigned long long kKeyFileLargest = 16 * 1024;

NSArray<NSString *> *KeyPlacesInHome(void) {
    NSMutableArray<NSString *> *places = [@[kKeySSHFolder, @".aws", @".gnupg", @".config/gh"] mutableCopy];
    [places addObjectsFromArray:[KeyCredentialFiles() valueForKey:@"path"]];
    [places addObjectsFromArray:KeyShellHistories()];
    [places addObjectsFromArray:KeyShellStartupFiles()];
    [places addObjectsFromArray:[KeyAgentRecords() valueForKey:@"path"]];
    return places;
}

BOOL KeyFileByName(NSString *path) {
    path = [path componentsSeparatedByString:@":"].lastObject.lowercaseString;
    NSArray<NSString *> *parts = [path.pathComponents filteredArrayUsingPredicate:
                                  [NSPredicate predicateWithFormat:@"SELF != '/'"]];
    NSString *name = parts.lastObject;
    if (!name.length) return NO;
    // By its last parts, as a project keeps it: matched from the end, so one in a folder of a larger checkout counts.
    NSMutableArray<NSString *> *inProjects = [KeyMCPFiles() mutableCopy];
    [inProjects addObjectsFromArray:[KeyAgentFilesInProjects() valueForKey:@"path"]];
    for (NSString *each in inProjects) {
        NSArray<NSString *> *end = each.lowercaseString.pathComponents;
        if (parts.count >= end.count
            && [[parts subarrayWithRange:NSMakeRange(parts.count - end.count, end.count)] isEqualToArray:end])
            return YES;
    }
    if ([@[@".envrc", @".npmrc", @".pypirc", @".netrc", @".git-credentials", @".dev.vars", @"credentials.json",
           @"id_rsa", @"id_dsa", @"id_ecdsa", @"id_ed25519"] containsObject:name])
        return YES;
    // A key's own kinds of file, but JSON, which most JSON files aren't; .env alone counts too.
    for (NSString *kind in KeyFileExtensions())
        if (![kind isEqualToString:@"json"] && [name hasSuffix:[@"." stringByAppendingString:kind]]) return YES;
    for (NSString *end in @[@".p12", @".pfx", @".jks", @".keystore", @".tfstate", @".tfstate.backup"])
        if ([name hasSuffix:end]) return YES;
    return [name hasPrefix:@".env."] || [name hasPrefix:@"secrets."]
        || ([name hasSuffix:@".json"] && ([name containsString:@"service-account"]
                                         || [name containsString:@"service_account"]));
}
