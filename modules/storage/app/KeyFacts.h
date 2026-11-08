// KeyFacts: what Keys relies on about other programs, which they could change: Betterleaks' flags and where it sits in
// the app, the kinds of key it names and where each one is replaced, where credential files, shell histories and
// other AI tools' records are kept, and macOS's folders Keys doesn't open without Full Disk Access. What these were
// last checked with is in docs/using/install.md ("What it's tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Betterleaks inside the app's bundle, where the build puts it (tools/bundle.sh).
extern NSString *const kBetterleaksInBundle;

// Betterleaks' major version, from what `betterleaks version` says ("2.0.0-rc.4", "1.9.0"); 0 for one it can't tell.
// Keys works with versions 1 and 2, whichever the app carries (tools/betterleaks.txt names it).
NSInteger BetterleaksMajor(NSString *said);

// The arguments version `major` is run with for `mode` (stdin, fs or git), before the files or the checkout it's
// given: its report on its output, nothing checked online, its own rules only, and an exit code that says only whether
// it ran. `with` has what they need: `rules` (version 1's own rules, which it's always given, so a project's settings
// file is never read), `empty` (an empty folder, where version 1 would look for a file of findings to ignore) and
// `range` (the commits git mode looks in, A..B). Each version's spelling is written here.
NSArray<NSString *> *BetterleaksArguments(NSInteger major, NSString *mode, NSDictionary *with);

// What version `major` is run with in its environment besides a home folder and a PATH: version 2 makes the
// fingerprints itself, with every key taken out of its report, from the secret given here.
NSDictionary<NSString *, NSString *> *BetterleaksEnvironment(NSInteger major, NSString *secret);

// Whether version `major` reports a JSON record a line as it goes (2), or one JSON list at its end (1).
BOOL BetterleaksReportsLines(NSInteger major);

// One finding of its report in one shape, version 2's: {rule_id, match: {fingerprint}, location: {path, start_line,
// end_line, start_column, end_column}, attributes: {git.sha, git.blob_sha}}. Version 1 gives the key itself: its
// fingerprint is made with `fingerprint`, and the key is left out. Nil for a record that isn't a finding.
NSDictionary *BetterleaksFinding(NSInteger major, NSDictionary *record, NSString *(^fingerprint)(NSString *key));
// Whether one of version 2's records says the run went to its end.
BOOL BetterleaksFinished(NSDictionary *record);
// The characters a match can take in at its edges that aren't the key's.
NSCharacterSet *KeyMatchEdges(void);

// What a kind of key is, by Betterleaks' rule: {name, start, replace}, its provider's name ("Anthropic"), the part
// every key of the kind starts with ("sk-ant-"), and the page where it's replaced; or nil for a kind it doesn't know,
// shown by its rule's own words.
NSDictionary *KeyKind(NSString *rule);

// The kinds with no provider, which a test can make up as easily as anything: any key-like text, a password, a
// sign-in token (JWT), a sign-in sent with curl, a password in an address (every rule Betterleaks names generic-…).
// Only one of these can be taken for a test's sample, an id or a word; any other kind, a provider's own or a private
// key, always counts.
BOOL KeyKindHasNoProvider(NSString *rule);

// Whether a name is one of the fields a scanner's report holds a key in (Betterleaks' match.full and match.value,
// version 1's Secret and Match): a key read there, in a report an agent's tool printed, isn't set as it.
BOOL KeyReportField(NSString *name);

// Whether a key starts as a provider's keys do (sk-, AKIA, ghp_…, each kind's start Keys knows), however it was
// found: version 1 can name such a key by a rule for any key-like text. Only the yes or no is kept.
BOOL KeyHasProviderStart(NSString *text);

// Whether a key starts as one of GitHub's tokens do (ghp_, gho_, ghu_, ghs_, ghr_) and can't be one: GitHub's are 36
// letters and digits after it, the last 6 a checksum of the 30 before. One too short, too long or whose checksum
// fails was made up, or cut short, so it's no key. Only the yes or no is kept.
BOOL KeyFailsItsChecksum(NSString *text);
// Whether Keys checks a kind's keys by their checksum (GitHub's ghp_, gho_, ghu_, ghs_ and ghr_): one that passes it
// was made by its provider, whatever an agent says of it.
BOOL KeyKindHasChecksum(NSString *rule);

// Whether a file is one of a project's tests' or examples' files, by its path inside the checkout: in a folder
// projects keep them in (test, tests, spec, fixtures, testdata, __snapshots__, examples…), or named as a test or a
// test's recorded output (.test., _test., .spec., .expected., .snap, .golden). A template (.env.example) isn't one:
// real values get pasted into those. A key found there, of a kind with no provider, is most likely made up for the
// test.
BOOL KeyInTestOrExample(NSString *path);

// The credential files kept in the home folder, each {path, name} (path from the home folder), which only you should
// be able to read; and ~/.ssh, whose private keys are each one, and the names of what's in it that isn't a key.
NSArray<NSDictionary *> *KeyCredentialFiles(void);
extern NSString *const kKeySSHFolder;
NSSet<NSString *> *KeySSHNotKeys(void);

// The shell histories, from the home folder; and the files a shell reads as it starts (zsh's, bash's, a login
// shell's and fish's), where a key set for every terminal (export OPENAI_API_KEY=…) lives.
NSArray<NSString *> *KeyShellHistories(void);
NSArray<NSString *> *KeyShellStartupFiles(void);

// Whether a name a key is set as says it's secret (api, token, secret, auth, pass, credential, access or private in
// it): a bare `key`, a lookup's or a dict's, doesn't. And whether what's in a line right before a key is a Spotify
// address's (spotify:track:, album, artist, playlist, episode or show), which names a track, never a key.
BOOL KeyNameSaysSecret(NSString *name);
BOOL KeyAfterIdPrefix(NSData *line, NSRange key);

// Whether Docker's settings (~/.docker/config.json) hold a sign-in: a registry in `auths` with its own `auth`,
// `identitytoken` or `registrytoken`. One that only names where macOS keeps them (`credsStore`) holds none. Only
// whether is read, never what.
BOOL KeyDockerConfigHoldsSignIn(NSString *path);

// Other AI tools' records of what was said and read, each {app, path, deep, kind}: path from the home folder, deep for
// a folder whose files are looked through at any depth, and kind `jsonl` (a JSON record a line) or `json` (one each).
NSArray<NSDictionary *> *KeyAgentRecords(void);

// Files inside a project that hold what was said to an AI tool, each {path, app}: path from the checkout's top.
NSArray<NSDictionary *> *KeyAgentFilesInProjects(void);

// MCP settings files inside a project (from the checkout's top), which often hold a server's key.
NSArray<NSString *> *KeyMCPFiles(void);

// The kinds of file in Downloads that can hold a key (by extension), and how large one may be to be looked in.
NSSet<NSString *> *KeyDownloadsExtensions(void);
extern const unsigned long long kKeyDownloadsLargest;

// The kinds of file a key comes in by itself (a private key, a service's credentials, a downloaded .env), by
// extension, and how large one is at most: such a file in Downloads is nothing but the key, so it can go to the Trash
// as a whole. Any other file holds more than the key, and is opened at its line instead.
NSSet<NSString *> *KeyFileExtensions(void);
extern const unsigned long long kKeyFileLargest;

