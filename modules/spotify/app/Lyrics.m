// Lyrics: the words of the song Spotify is playing, from LRCLIB, for the now-playing strip and the lyrics beside the
// list.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// LRCLIB is asked only once you've said yes (on the strip, or Spotify ▸ Show Lyrics in the pawn menu), and only with
// what it needs to find the song: its name, artist, album and length. Its connection keeps nothing on disk (no cookies,
// no cache). What it finds is kept on this Mac (LyricsStore), so a song played again needs no asking: lyrics with times
// for as long as the song is among the last 1,000 played, and lyrics without times, or none, for a week, as LRCLIB may
// have them by then. Turning lyrics off forgets it all.
//
// A song is asked about once it has played a moment, so songs skipped past aren't, and one ask at a time, each only if
// the ones before found no lyrics with times (LyricsAsksFor). An answer that comes once the song has changed, or lyrics
// have been turned off, is dropped. When LRCLIB has trouble answering (it's busy, it's asked too often, or nothing
// comes back), the same ask goes again, later each time and never sooner than LRCLIB asks (LyricsWaitBefore). After
// half a minute or so of that, the page is told there are none to be had for now (or gets the lyrics without times
// found already), and LRCLIB is asked once a minute while the song plays, so they still come if it answers. A question
// LRCLIB won't take is never asked again: the next ask goes.
//
// The page gets {state}: 'ask' until you've answered the strip's question, 'off', or 'on' with nothing playing; and for
// the song playing, {state, track}: 'looking', 'timed' with `lrc` (the words with when each line starts, as LRCLIB has
// them), 'plain' with `plain` (the words alone), 'none' (LRCLIB doesn't know it, it has no words, or it isn't a song)
// or 'failed' (LRCLIB hasn't answered for a while). Null while Spotify is removed from Whozmove.
#import "Lyrics.h"
#import "LyricsStore.h"
#import "Page.h"
#import "Files.h"
#import "Log.h"
#import "LRCLIBFacts.h"
#import "SpotifyFacts.h"

// A song is asked about once it has played this long, so songs skipped past aren't asked about at all.
static const NSTimeInterval kLyricsWait = 0.8;
// LRCLIB's answer is waited for this long.
static const NSTimeInterval kLyricsTimeout = 10;
// When LRCLIB has trouble answering, it's asked again this many times, quickly, then once a minute; and never later
// than an hour, whatever it asks.
static const NSUInteger kLyricsQuickTries = 5;
static const NSTimeInterval kLyricsSlowWait = 60, kLyricsMostWait = 3600;
// The most of an answer taken (bytes), and of lyrics sent to the page (characters).
static const NSUInteger kMostAnswer = 1024 * 1024, kMostLyrics = 64 * 1024;
// How many songs' lyrics are kept in memory too, for the songs played lately; and how long lyrics without times, or
// none, are kept on this Mac before the song is asked about again (ms).
static const NSUInteger kKept = 32;
static const double kKeptUntimedMs = 7 * 24 * 3600 * 1000.0;

static NSString *Trimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL Same(NSString *a, NSString *b) {
    return a == b || [a isEqual:b];
}

static double NowMs(void) { return NSDate.date.timeIntervalSince1970 * 1000; }

// From 0 to 1, at random: how much a wait is shortened or stretched.
static double Chance(void) {
    return arc4random_uniform(1001) / 1000.0;
}

// A query's value with everything but unreserved ASCII percent-encoded: a "+", which LRCLIB would read as a space, and
// an "&" or "?" that would end the value are encoded too.
static NSString *QueryValue(NSString *text) {
    static NSCharacterSet *plain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [NSCharacterSet characterSetWithCharactersInString:
                 @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [text stringByAddingPercentEncodingWithAllowedCharacters:plain];
}

// One of LRCLIB's addresses with its query, from names and values in turn; a value that's empty is left out, its name
// with it.
static NSURL *Address(NSString *base, NSArray<NSString *> *pairs) {
    NSMutableArray *query = [NSMutableArray array];
    for (NSUInteger i = 0; i + 1 < pairs.count; i += 2)
        if (pairs[i + 1].length)
            [query addObject:[NSString stringWithFormat:@"%@=%@", pairs[i], QueryValue(pairs[i + 1])]];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@", base, [query componentsJoinedByString:@"&"]]];
}

// A song's name without what Spotify adds to say which version it is: whatever follows a dash between spaces
// (" - Remastered 2011", " - Live at …", " – From …"), and the parts in brackets at its end ("(feat. …)", "[Mono]").
// Nil when that leaves it as it was or empty, and for an instrumental or karaoke version, which the words of the song
// it's a version of would be wrong for. LRCLIB's songs still have to match its length, so a live version isn't taken
// for the one in the studio.
static NSString *TitleCleaned(NSString *title) {
    static NSRegularExpression *dash, *brackets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dash = [NSRegularExpression regularExpressionWithPattern:@"\\s+[-\\x{2013}\\x{2014}]\\s+.*$" options:0
                                                           error:nil];
        brackets = [NSRegularExpression regularExpressionWithPattern:@"\\s*[(\\[][^()\\[\\]]*[)\\]]\\s*$" options:0
                                                               error:nil];
    });
    if (!title.length) return nil;
    for (NSString *version in @[@"instrumental", @"karaoke"])
        if ([title rangeOfString:version options:NSCaseInsensitiveSearch].location != NSNotFound) return nil;
    NSString *cleaned = [dash stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length)
                                                  withTemplate:@""];
    for (NSString *was = nil; ![was isEqual:cleaned];) {
        was = cleaned;
        cleaned = [brackets stringByReplacingMatchesInString:was options:0 range:NSMakeRange(0, was.length)
                                                withTemplate:@""];
    }
    cleaned = Trimmed(cleaned);
    return cleaned.length && ![cleaned isEqual:title] ? cleaned : nil;
}

// A song's name as it's compared with one LRCLIB found: tidied (TitleCleaned), and only its letters and digits, without
// case or accents, as LRCLIB compares names, near enough.
static NSString *Bare(NSString *name) {
    NSString *folded = [(TitleCleaned(name) ?: name) stringByFoldingWithOptions:NSCaseInsensitiveSearch
                                                                                | NSDiacriticInsensitiveSearch
                                                                         locale:nil];
    return [[folded componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
            componentsJoinedByString:@""];
}

NSArray<NSURL *> *LyricsAsksFor(NSDictionary *song) {
    NSString *track = AsText(song[@"track"]);
    if (![track hasPrefix:kSpotifySongIdPrefix] && ![track hasPrefix:kSpotifyLocalIdPrefix]) return @[];
    NSString *title = Trimmed(AsText(song[@"title"])), *artist = Trimmed(AsText(song[@"artist"]));
    NSString *album = Trimmed(AsText(song[@"album"])) ?: @"";
    long seconds = lround(AsNumber(song[@"durationMs"]).doubleValue / 1000);
    if (!title.length || !artist.length || seconds <= 0) return @[];
    NSString *length = [NSString stringWithFormat:@"%ld", seconds], *cleaned = TitleCleaned(title);
    NSURL *search = Address(kLRCLIBSearch, @[kLRCLIBTrack, cleaned ?: title, kLRCLIBArtist, artist]);
    if (seconds > kLRCLIBLongest) return @[search];
    NSMutableArray *asks = [NSMutableArray arrayWithObject:Address(kLRCLIBGet, @[
        kLRCLIBTrack, title, kLRCLIBArtist, artist, kLRCLIBAlbum, album, kLRCLIBDuration, length])];
    if (album.length)
        [asks addObject:Address(kLRCLIBGet, @[kLRCLIBTrack, title, kLRCLIBArtist, artist, kLRCLIBDuration, length])];
    if (cleaned)
        [asks addObject:Address(kLRCLIBGet, @[kLRCLIBTrack, cleaned, kLRCLIBArtist, artist, kLRCLIBDuration, length])];
    [asks addObject:search];
    return asks;
}

// `text` cut to at most `most` characters, at the end of a line, so no line is left half there.
static NSString *UpToLine(NSString *text, NSUInteger most) {
    if (text.length <= most) return text;
    NSString *cut = Clip(text, most);
    NSRange end = [cut rangeOfString:@"\n" options:NSBackwardsSearch];
    return end.location == NSNotFound ? cut : [cut substringToIndex:end.location];
}

// Whether LRC has a line to sing: one with a time at its start ("[01:02.50]") and words after it, without word timings
// ("<01:02.50>") or control characters, as the page reads it (lyrics.js). Without one, the page would have nothing to
// show.
static BOOL HasSungLine(NSString *lrc) {
    static NSRegularExpression *timed, *unread;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        timed = [NSRegularExpression regularExpressionWithPattern:
                 @"^(?:[ \\t]*\\[\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?\\])+(.*)$"
                                                         options:NSRegularExpressionAnchorsMatchLines error:nil];
        unread = [NSRegularExpression regularExpressionWithPattern:
                  @"<\\d{1,3}:\\d{1,2}(?:[.:]\\d{1,3})?>|[\\x{0000}-\\x{001f}\\x{007f}]" options:0 error:nil];
    });
    for (NSTextCheckingResult *line in [timed matchesInString:lrc options:0 range:NSMakeRange(0, lrc.length)]) {
        NSString *words = [lrc substringWithRange:[line rangeAtIndex:1]];
        words = [unread stringByReplacingMatchesInString:words options:0 range:NSMakeRange(0, words.length)
                                            withTemplate:@""];
        if (Trimmed(words).length) return YES;
    }
    return NO;
}

// One song's lyrics, as LRCLIB has them: with times, else without, else that it has no words; nil when it has nothing.
// Lyrics with times but no line to sing count as none with times.
static NSDictionary *LyricsOfRecord(NSDictionary *record) {
    if ([AsNumber(record[kLRCLIBInstrumental]) boolValue]) return @{@"kind": @"instrumental"};
    NSString *synced = UpToLine(Trimmed(AsText(record[kLRCLIBSynced])) ?: @"", kMostLyrics);
    if (HasSungLine(synced)) return @{@"kind": @"timed", @"lrc": synced};
    NSString *plain = Trimmed(AsText(record[kLRCLIBPlain]));
    if (plain.length) return @{@"kind": @"plain", @"plain": UpToLine(plain, kMostLyrics)};
    return nil;
}

NSDictionary *LyricsAnswerOf(NSInteger status, NSData *body, NSDictionary *song) {
    NSDictionary *missing = @{@"kind": @"missing"}, *trouble = @{@"kind": @"trouble"};
    // A song LRCLIB doesn't have, a question it won't take, or an answer too big to read is the same each time it's
    // asked: nothing to be found that way. What may pass is trouble: busy, asked too often, too slow, failing, or
    // nothing back at all.
    BOOL refused = status >= 400 && status < 500 && status != 408 && status != 429;
    if (status == kLRCLIBNotFound || refused || (status == 200 && body.length > kMostAnswer)) return missing;
    if (status != 200 || !body) return trouble;
    id answer = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (AsRecord(answer)) return LyricsOfRecord(answer) ?: missing;
    if (!AsList(answer)) return trouble;
    // A search's answer: only the songs of the same name, once tidied, within LRCLIB's leeway of its length; the first
    // with times, else the first without. One with no words says nothing about the song, as a search by name finds its
    // instrumental versions too.
    NSString *name = Bare(Trimmed(AsText(song[@"title"])));
    double seconds = AsNumber(song[@"durationMs"]).doubleValue / 1000;
    NSDictionary *plain = nil;
    for (id item in answer) {
        NSDictionary *record = AsRecord(item);
        NSString *found = AsText(record[kLRCLIBFoundName]);
        NSNumber *length = AsNumber(record[kLRCLIBDuration]);
        if (!name.length || !found || !length || fabs(length.doubleValue - seconds) > kLRCLIBLeeway
            || ![Bare(found) isEqual:name])
            continue;
        NSDictionary *lyrics = LyricsOfRecord(record);
        if ([lyrics[@"kind"] isEqual:@"timed"]) return lyrics;
        if ([lyrics[@"kind"] isEqual:@"plain"] && !plain) plain = lyrics;
    }
    return plain ?: missing;
}

NSTimeInterval LyricsWaitBefore(NSUInteger tries, NSTimeInterval asked, double chance) {
    NSTimeInterval wait = tries > kLyricsQuickTries ? kLyricsSlowWait : (NSTimeInterval)(1u << (MAX(tries, 1) - 1));
    return MIN(MAX(wait * (0.8 + 0.4 * chance), asked), kLyricsMostWait);
}

NSDictionary *LyricsFromKept(NSDictionary *kept, NSString *track, double nowMs) {
    NSString *state = AsText(kept[@"state"]), *lrc = AsText(kept[@"lrc"]), *plain = AsText(kept[@"plain"]);
    if (!track || !Same(AsText(kept[@"track"]), track)) return nil;
    if ([state isEqual:@"timed"])
        return lrc.length <= kMostLyrics && HasSungLine(lrc ?: @"") ? @{@"state": state, @"track": track, @"lrc": lrc}
                                                                    : nil;
    if (!(nowMs - AsNumber(kept[@"keptAt"]).doubleValue < kKeptUntimedMs)) return nil;
    if ([state isEqual:@"plain"])
        return plain.length && plain.length <= kMostLyrics ? @{@"state": state, @"track": track, @"plain": plain} : nil;
    return [state isEqual:@"none"] ? @{@"state": state, @"track": track} : nil;
}

@interface Lyrics ()
@property (strong) Page *page;
@property (strong) LyricsStore *store;            // what LRCLIB found, kept on this Mac
@property (strong) NSURLSession *session;
@property (assign) BOOL shown, on, asked;
@property (copy) NSDictionary *song;              // the song as Spotify.m last said
@property (copy) NSDictionary *found;             // what the page has about it, or is to get
@property (strong) id sent;                       // as the page was last sent it, so it's called only on a change
@property (strong) NSMutableDictionary *kept;     // track -> what's known of its lyrics, for the last kKept songs
@property (strong) NSMutableArray *keptOrder;     // their tracks, the one played longest ago first
// How far the song playing has been looked up: what this Mac keeps of it being read (`reading`), or read (`checked`);
// which of its asks goes next (`step`); lyrics without times found on the way (`plain`), in case none with times are;
// and how many of its asks LRCLIB had trouble with (`troubles`), the first of which is logged (`logged`), as is its
// answer after trouble (`troubled`: the last ask had some).
@property (copy) NSString *reading, *checked, *plain, *logged;
@property (assign) NSUInteger step, troubles;
@property (assign) BOOL troubled;
@property (strong) NSURLSessionDataTask *task;    // LRCLIB being asked
@property (strong) NSTimer *next;                 // the next ask
@property (strong) NSDate *notBefore;             // until when LRCLIB asked to be left alone
@property (assign) BOOL following;
@end

@implementation Lyrics

- (instancetype)initWithPage:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.store = [[LyricsStore alloc] initWithFolder:AppDir(@"lyrics")];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    configuration.HTTPShouldSetCookies = NO;
    configuration.URLCache = nil;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = kLyricsTimeout;
    configuration.timeoutIntervalForResource = kLyricsTimeout * 2;
    self.session = [NSURLSession sessionWithConfiguration:configuration];
    self.kept = [NSMutableDictionary dictionary];
    self.keptOrder = [NSMutableArray array];
    return self;
}

- (void)shown:(BOOL)shown on:(BOOL)on asked:(BOOL)asked {
    self.shown = shown;
    self.on = on;
    self.asked = asked;
    if (!shown || !on) {
        [self startOver];
        [self.kept removeAllObjects];
        [self.keptOrder removeAllObjects];
    }
    if (!on) [self.store forgetAll];
    [self look];
}

- (void)songIs:(NSDictionary *)song {
    NSString *was = AsText(self.song[@"track"]);
    self.song = song;
    if (!Same(was, AsText(song[@"track"]))) [self startOver];
    [self look];
}

- (void)resend {
    self.sent = nil;
    [self send];
}

// What the page has about the song now, from what's known: the question or the switch, what's kept, or the song looked
// up. Called at every news of the song, so it only ever starts what isn't started.
- (void)look {
    if (!self.shown) return [self show:nil];
    if (!self.on) return [self show:@{@"state": self.asked ? @"off" : @"ask"}];
    NSString *track = AsText(self.song[@"track"]);
    if (!track) return [self show:@{@"state": @"on"}];
    NSDictionary *kept = [self recall:track];
    if (kept) return [self show:kept];
    if (!LyricsAsksFor(self.song).count) return [self show:@{@"state": @"none", @"track": track}];
    // Looking, until LRCLIB has had trouble for a while: then that's said, or the lyrics without times found already
    // show, while LRCLIB is still asked now and then.
    if (!Same(self.found[@"track"], track) || ![@[@"failed", @"plain"] containsObject:self.found[@"state"] ?: @""])
        [self show:@{@"state": @"looking", @"track": track}];
    if (self.task || self.next || Same(self.reading, track)) return;
    if (!Same(self.checked, track)) return [self readKept:track];
    // Only a song that plays is asked about: one paused before it has been waits until it plays again.
    if (![self.song[@"playing"] boolValue]) return;
    [self askIn:(self.troubles ? LyricsWaitBefore(self.troubles, 0, Chance()) : kLyricsWait) whilePlaying:YES];
}

// What this Mac keeps of the song, read off the main thread: what's there and still good shows at once, and otherwise
// it's looked up.
- (void)readKept:(NSString *)track {
    self.reading = track;
    __weak typeof(self) weakSelf = self;
    [self.store read:track then:^(NSDictionary *record) {
        Lyrics *lyrics = weakSelf;
        if (!Same(lyrics.reading, track)) return;  // the song changed meanwhile, or lyrics went off
        lyrics.reading = nil;
        lyrics.checked = track;
        NSDictionary *found = LyricsFromKept(record, track, NowMs());
        if (found) [lyrics remember:found keptAt:AsNumber(record[@"keptAt"]).doubleValue];
        [lyrics look];
    }];
}

// The song's next ask, after `delay`, or later if LRCLIB asked to be left alone longer; `whilePlaying`, only if the
// song is playing by then (the first ask, and those once a minute).
- (void)askIn:(NSTimeInterval)delay whilePlaying:(BOOL)whilePlaying {
    NSString *track = AsText(self.song[@"track"]);
    __weak typeof(self) weakSelf = self;
    self.next = [NSTimer scheduledTimerWithTimeInterval:MAX(delay, self.notBefore.timeIntervalSinceNow) repeats:NO
                                                  block:^(NSTimer *timer) {
        Lyrics *lyrics = weakSelf;
        lyrics.next = nil;
        if (!lyrics.shown || !lyrics.on || !Same(AsText(lyrics.song[@"track"]), track)) return;
        if (whilePlaying && ![lyrics.song[@"playing"] boolValue]) return;
        [lyrics ask];
    }];
}

// LRCLIB asked about the song playing now, the ask its step has come to. What it answers counts only if that's still
// the song, and lyrics are still on: startOver cancels it otherwise.
- (void)ask {
    NSArray<NSURL *> *asks = LyricsAsksFor(self.song);
    if (self.task || self.step >= asks.count) return;
    NSDictionary *song = self.song;
    NSString *track = AsText(song[@"track"]);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:asks[self.step]];
    [request setValue:LRCLIBUserAgent() forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf = self;
    __block NSURLSessionDataTask *task = nil;
    task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response,
                                                                         NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        NSInteger status = error ? 0 : http.statusCode;
        NSDictionary *answer = LyricsAnswerOf(status, error ? nil : data, song);
        NSTimeInterval asked = [[http valueForHTTPHeaderField:kLRCLIBRetryAfter] doubleValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf answered:answer about:track task:task status:status error:error asked:asked];
        });
    }];
    self.task = task;
    [task resume];
}

// On the main thread: one of LRCLIB's answers about `track`. Lyrics with times end the looking; lyrics without are kept
// aside in case no ask finds any with times; with nothing found, the next ask goes at once; a song with no words ends
// it; and trouble asks again, later.
- (void)answered:(NSDictionary *)answer about:(NSString *)track task:(NSURLSessionDataTask *)task
          status:(NSInteger)status error:(NSError *)error asked:(NSTimeInterval)asked {
    if (task != self.task) return;  // cancelled: the song changed, or lyrics went off
    self.task = nil;
    if (asked > 0) self.notBefore = [NSDate dateWithTimeIntervalSinceNow:MIN(asked, kLyricsMostWait)];
    if (!self.shown || !self.on || !Same(AsText(self.song[@"track"]), track)) return;
    NSString *kind = answer[@"kind"];
    if ([kind isEqual:@"trouble"]) return [self troubled:track status:status error:error asked:asked];
    if (self.troubled) PanelLog(@"LRCLIB answered after %lu failed tries", (unsigned long)self.troubles);
    self.troubled = NO;
    if ([kind isEqual:@"timed"]) return [self settle:@{@"state": @"timed", @"track": track, @"lrc": answer[@"lrc"]}];
    if ([kind isEqual:@"plain"] && !self.plain) self.plain = answer[@"plain"];
    if (![kind isEqual:@"instrumental"] && ++self.step < LyricsAsksFor(self.song).count)
        return [self askIn:0 whilePlaying:NO];
    [self settle:[self foundSoFar:track]];
}

// LRCLIB had trouble answering: the same ask goes again, later each time. Once the quick tries are used up, the page is
// told (failed), or gets the lyrics without times found already, and LRCLIB is asked once a minute while the song
// plays, for the asks still to go. Nothing is kept until they've all been answered, so a song played again is looked up
// again.
- (void)troubled:(NSString *)track status:(NSInteger)status error:(NSError *)error asked:(NSTimeInterval)asked {
    if (!Same(self.logged, track)) {
        self.logged = track;
        PanelLog(@"LRCLIB didn't answer: %@", error ? error.localizedDescription
                                                : status != 200 ? [NSString stringWithFormat:@"status %ld", (long)status]
                                                                : @"an answer it couldn't read");
    }
    self.troubled = YES;
    BOOL slow = ++self.troubles > kLyricsQuickTries;
    if (slow) {
        if (self.troubles == kLyricsQuickTries + 1) PanelLog(@"LRCLIB still hasn't answered: asking once a minute");
        [self show:self.plain ? [self foundSoFar:track] : @{@"state": @"failed", @"track": track}];
    }
    [self askIn:LyricsWaitBefore(self.troubles, asked, Chance()) whilePlaying:slow];
}

// What the asks found, once none found lyrics with times: lyrics without, or none.
- (NSDictionary *)foundSoFar:(NSString *)track {
    return self.plain ? @{@"state": @"plain", @"track": track, @"plain": self.plain}
                      : @{@"state": @"none", @"track": track};
}

// The song's looked up: what was found is kept, in memory and on this Mac, and shown.
- (void)settle:(NSDictionary *)found {
    [self remember:found keptAt:NowMs()];
    [self.store keep:found];
    [self show:found];
}

// What was found about a song (`keptAt`, when LRCLIB found it), in memory too, for the songs played lately: the one
// played longest ago goes once there are more than kKept.
- (void)remember:(NSDictionary *)found keptAt:(double)keptAt {
    NSString *track = found[@"track"];
    NSMutableDictionary *record = [found mutableCopy];
    record[@"keptAt"] = @(keptAt);
    self.kept[track] = record;
    [self.keptOrder removeObject:track];
    [self.keptOrder addObject:track];
    while (self.keptOrder.count > kKept) {
        [self.kept removeObjectForKey:self.keptOrder.firstObject];
        [self.keptOrder removeObjectAtIndex:0];
    }
}

// What's in memory about a song, as the page gets it, or nil: it counts for as long as it would on this Mac
// (LyricsFromKept), so lyrics without times, or none, are asked about again after a week, however long Whozmove has
// been running; and played again, it's kept longer.
- (NSDictionary *)recall:(NSString *)track {
    NSDictionary *record = self.kept[track];
    if (!record) return nil;
    NSDictionary *found = LyricsFromKept(record, track, NowMs());
    [self.keptOrder removeObject:track];
    if (found) [self.keptOrder addObject:track];
    else [self.kept removeObjectForKey:track];
    return found;
}

// Nothing more is asked of LRCLIB, or read, about the song: it changed, or lyrics went off. A new one starts from its
// first ask.
- (void)startOver {
    [self.task cancel];
    self.task = nil;
    [self.next invalidate];
    self.next = nil;
    self.reading = nil;
    self.checked = nil;
    self.plain = nil;
    self.logged = nil;
    self.step = 0;
    self.troubles = 0;
    self.troubled = NO;
}

- (void)show:(NSDictionary *)found {
    self.found = found;
    [self send];
    BOOL following = [found[@"state"] isEqual:@"timed"];
    if (following == self.following) return;
    self.following = following;
    if (self.onFollowing) self.onFollowing(following);
}

- (void)send {
    id value = self.shown && self.found ? self.found : NSNull.null;
    if (!self.page.ready || [value isEqual:self.sent]) return;
    self.sent = value;
    [self.page call:@"setLyrics" with:@[value]];
}

@end
