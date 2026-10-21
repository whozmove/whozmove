// Spotify: the song the Spotify app on this Mac is playing, for the now-playing strip, what its token at the panel's
// corner shows, and its controls.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// Spotify tells the whole Mac each time the song or its state changes, and hearing that needs no permission. The
// cover's address, the position later on and the controls are asked of it with Apple events, which macOS lets Whozmove
// send only once you've allowed it ("Whozmove wants to control Spotify"); the cover is asked for as soon as a song
// plays, so that question comes then. They're sent one at a time on a queue of their own, as plain Apple events rather
// than AppleScript, which may run only on the main thread (Ghostty's runs there). Each goes to the Spotify process
// that's running, never to the app by name: telling a closed app anything would start it, and a Spotify that quits
// while one waits just doesn't answer. Whozmove starts Spotify only when you press the token's Play.
//
// The page gets the song as {track, title, artist, album, durationMs, positionMs, at, playing, pausedSince, artUrl,
// allowed}: positionMs was right at `at` (ms since 1970: when Spotify said it, or was asked it) and moves on from there
// while it plays, which the lyrics follow line by line; pausedSince is when a paused song was paused (0 for one found
// paused, as when Whozmove starts); artUrl is the cover once known; allowed is NO once macOS has refused Whozmove
// control of Spotify, YES once it has allowed it. Nothing (null) while Spotify plays nothing, isn't running, or Spotify
// is turned off in Whozmove (Show the song, on its page on the panel's back).
#import "Spotify.h"
#import "Page.h"
#import "Files.h"
#import "Log.h"
#import "SpotifyFacts.h"
#import "AppleEvents.h"
#import "Links.h"

static double NowMs(void) { return NSDate.date.timeIntervalSince1970 * 1000; }

// errAEEventNotPermitted: macOS's answer when you haven't allowed Whozmove to control the app.
static const OSStatus kNotPermitted = -1743;
// So a Spotify that has stopped answering holds nothing up for long. macOS's question about allowing Whozmove isn't
// timed: Spotify is asked nothing until it's answered.
static const NSTimeInterval kTimeout = 3;
// While a song plays, its position is read again this often, so a jump made in Spotify itself, or a song starting
// over, puts the strip's line right.
static const NSTimeInterval kRecheck = 15;
// A read that failed (Spotify busy, say) is tried again after this, a few times.
static const NSTimeInterval kRetry = 5;
static const NSUInteger kRetries = 3;
// While the song's lyrics follow it, its position alone is asked this often; and a position further than this (ms)
// from where the song should be by then is a jump, which the page is told.
static const NSTimeInterval kFollowEvery = 5;
static const double kDriftMs = 400;
// A song paused stays in the strip this long (ms), then folds into the token; page/now-playing.js's
// PAUSED_IN_STRIP_MS is the same.
static const double kPausedInStripMs = 15 * 60 * 1000;
// Play on a Spotify just opened: it's asked whether it's ready this often, for this long; and as it may say it's
// stopped a moment before it has loaded the song it last had, it's given this long to.
static const NSTimeInterval kReadyEvery = 0.5, kReadyFor = 20, kLoadFor = 6;
// Play with nothing to play (signed out, say) plays by itself if a song turns up within this, read this often.
static const NSTimeInterval kPendingFor = 300, kPendingEvery = 3;
// While Spotify isn't installed, whether it is now is looked at this often; and the token is looked at again this
// often anyway (a song paused long enough leaves the strip; a folded panel's token shows how far in it is).
static const NSTimeInterval kInstallEvery = 5;

BOOL SpotifyInstalled(void) {
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kSpotifyAppId];
    return app && ![app.path containsString:@"/.Trash/"];
}

static NSRunningApplication *RunningSpotify(void) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:kSpotifyAppId].firstObject;
}

NSDictionary *SongFromAnnouncement(NSDictionary *info, double now) {
    NSString *state = AsText(info[kSpotifyStateKey]), *track = AsText(info[kSpotifyTrackKey]);
    if (!state || [state isEqual:kSpotifyStopped] || !track.length) return nil;
    double position = AsNumber(info[kSpotifyPositionKey]).doubleValue;
    return @{@"track": track, @"title": AsText(info[kSpotifyNameKey]) ?: @"",
             @"artist": AsText(info[kSpotifyArtistKey]) ?: @"", @"album": AsText(info[kSpotifyAlbumKey]) ?: @"",
             @"durationMs": @(AsNumber(info[kSpotifyDurationKey]).doubleValue), @"positionMs": @(round(position * 1000)),
             @"at": @(now), @"playing": @([state isEqual:kSpotifyPlaying])};
}

NSDictionary *SongFromReply(NSArray *fields, double now) {
    if (fields.count != 8 || !AsText(fields[0]).length) return nil;
    BOOL playing = [AsText(fields[6]) caseInsensitiveCompare:kSpotifyPlaying] == NSOrderedSame;
    NSMutableDictionary *song = [@{@"track": fields[0], @"title": AsText(fields[1]) ?: @"",
                                   @"artist": AsText(fields[2]) ?: @"", @"album": AsText(fields[3]) ?: @"",
                                   @"durationMs": @(AsNumber(fields[4]).doubleValue),
                                   @"positionMs": @(round(AsNumber(fields[5]).doubleValue * 1000)), @"at": @(now),
                                   @"playing": @(playing)} mutableCopy];
    if (AsText(fields[7]).length) song[@"artUrl"] = fields[7];
    return song;
}

BOOL ControlRefused(OSStatus status) {
    return status == kNotPermitted;
}

BOOL SongInStrip(NSDictionary *song, double now) {
    if (!song) return NO;
    return [song[@"playing"] boolValue] || now - [song[@"pausedSince"] doubleValue] < kPausedInStripMs;
}

BOOL PositionMoved(NSDictionary *song, double positionMs, double at) {
    if (![song[@"playing"] boolValue]) return NO;
    double expected = [song[@"positionMs"] doubleValue] + MAX(0, at - [song[@"at"] doubleValue]);
    return fabs(expected - positionMs) > kDriftMs;
}

NSDictionary *TokenFor(BOOL installed, NSDictionary *song, BOOL starting, NSNumber *allowed, BOOL collapsed,
                       double now) {
    // Folded, the panel is the cat alone in its corner: nothing of Spotify's beside it.
    if (collapsed) return @{@"state": @"hidden"};
    if (!installed) return @{@"state": @"missing"};
    if (starting) return @{@"state": @"hidden"};
    if (SongInStrip(song, now)) return @{@"state": @"hidden", @"strip": @YES};
    if (allowed && !allowed.boolValue) return @{@"state": @"refused"};
    if (!song) return @{@"state": @"ready"};
    // A song playing is in the strip, so one here is paused.
    double duration = [song[@"durationMs"] doubleValue];
    return @{@"state": @"paused", @"title": song[@"title"] ?: @"",
             @"artist": song[@"artist"] ?: @"", @"artUrl": song[@"artUrl"] ?: @"",
             @"progress": @(duration > 0 ? MIN(1, [song[@"positionMs"] doubleValue] / duration) : 0)};
}

#pragma mark Apple events

// One Apple event to the Spotify process `pid`, waiting kTimeout at most (AppleEvents.m): its answer, or nil with why in
// `status`.
static NSAppleEventDescriptor *Send(pid_t pid, AEEventClass eventClass, AEEventID eventId,
                                    NSAppleEventDescriptor *object, NSAppleEventDescriptor *data, OSStatus *status) {
    return SendAppleEvent(pid, eventClass, eventId, object, data, kTimeout, status);
}

static NSAppleEventDescriptor *Get(pid_t pid, NSAppleEventDescriptor *property, OSStatus *status) {
    return Send(pid, kAECoreSuite, kAEGetData, property, nil, status);
}

// The song now, in the order SongFromReply takes (none while Spotify is stopped), or nil with why in `status`; and in
// `positionAt`, when its position was right: halfway through asking it, so the cover asked for after it (which can be
// slow) doesn't make the lyrics late.
static NSArray *ReadSong(pid_t pid, OSStatus *status, double *positionAt) {
    NSAppleEventDescriptor *state = Get(pid, AppleEventProperty(kSpotifyPlayerState, nil), status);
    if (!state) return nil;
    FourCharCode code = state.enumCodeValue;
    if (code == kSpotifyStateStopped) return @[];
    NSAppleEventDescriptor *track = AppleEventProperty(kSpotifyCurrentTrack, nil);
    NSMutableArray *fields = [NSMutableArray array];
    for (NSNumber *property in @[@(kSpotifyTrackId), @(kSpotifyTrackName), @(kSpotifyTrackArtist),
                                 @(kSpotifyTrackAlbum), @(kSpotifyTrackDuration)]) {
        NSAppleEventDescriptor *value = Get(pid, AppleEventProperty(property.unsignedIntValue, track), status);
        if (!value) return nil;
        BOOL number = property.unsignedIntValue == kSpotifyTrackDuration;
        [fields addObject:number ? @(value.doubleValue) : value.stringValue ?: @""];
    }
    double before = NowMs();
    NSAppleEventDescriptor *position = Get(pid, AppleEventProperty(kSpotifyPlayerPosition, nil), status);
    if (!position) return nil;
    if (positionAt) *positionAt = (before + NowMs()) / 2;
    [fields addObject:@(position.doubleValue)];
    [fields addObject:code == kSpotifyStatePlaying ? @"playing" : @"paused"];
    // A track without a cover answers "missing value", which isn't text.
    [fields addObject:Get(pid, AppleEventProperty(kSpotifyTrackArtwork, track), status).stringValue ?: NSNull.null];
    return fields;
}

#pragma mark Spotify

@interface Spotify ()
@property (strong) Page *page;
@property (strong) dispatch_queue_t queue;  // where Spotify is asked, one thing at a time
@property (strong) NSTimer *recheck;
@property (copy) NSDictionary *song;        // what's playing, as the page has it or gets it
@property (copy) NSString *sent;            // as last sent, as JSON, so the page is called only on a change
@property (copy) NSString *askedAbout;      // the track the cover was last asked for
@property (strong) NSNumber *allowed;       // macOS's answer about controlling Spotify, once known
@property (assign) BOOL reading;
@property (assign) NSUInteger heardCount;   // announcements so far: did one come while Spotify was being asked?
@property (assign) NSUInteger retries;      // reads tried again since the last that worked
@property (assign) BOOL starting;           // Play pressed: Spotify opening, or being asked to play
@property (strong) NSDate *pendingUntil;    // Play found nothing to play: a song turning up before this plays
@property (strong) NSTimer *pendingTimer;
@property (strong) NSTimer *installTimer;
@property (assign) BOOL installed;          // as last looked for: asking LaunchServices can be slow
@property (copy) NSDictionary *tokenSent;   // what the token was last told
@property (strong) NSTimer *followTimer;    // while the lyrics follow the song: its position, asked every few seconds
@property (assign) BOOL checking;           // its position being asked
@end

@implementation Spotify

- (instancetype)initWithPage:(Page *)page {
    if (!(self = [super init])) return nil;
    self.page = page;
    self.queue = dispatch_queue_create("whozmove.spotify", DISPATCH_QUEUE_SERIAL);
    __weak typeof(self) weakSelf = self;
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:kSpotifyAnnouncement object:nil
                                                                queue:NSOperationQueue.mainQueue
                                                           usingBlock:^(NSNotification *note) {
        [weakSelf heard:note.userInfo];
    }];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidTerminateApplicationNotification
                                                                object:nil queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if ([app.bundleIdentifier isEqual:kSpotifyAppId]) [weakSelf forget];
    }];
    // Spotify's installer opens it once it's done, so its token can turn into Play at once.
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                                                                object:nil queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if ([app.bundleIdentifier isEqual:kSpotifyAppId]) [weakSelf lookForSpotify];
    }];
    self.installed = SpotifyInstalled();
    self.installTimer = [NSTimer scheduledTimerWithTimeInterval:kInstallEvery repeats:YES block:^(NSTimer *timer) {
        if (!weakSelf.installed) [weakSelf lookForSpotify];
        else [weakSelf tokenChanged];
    }];
    self.installTimer.tolerance = 1;
    self.recheck = [NSTimer scheduledTimerWithTimeInterval:kRecheck repeats:YES block:^(NSTimer *timer) {
        Spotify *spotify = weakSelf;
        if ([spotify.song[@"playing"] boolValue] && [spotify.allowed boolValue]) [spotify read:YES];
    }];
    self.recheck.tolerance = 2;
    return self;
}

// What's already playing, or paused, is read only if you've already allowed Whozmove to control Spotify; otherwise
// macOS asks when a song next plays, or when you press Play.
- (void)setShown:(BOOL)shown {
    if (shown == _shown) return;
    _shown = shown;
    if (!shown) [self forget];
    else [self read:NO];
    [self tokenChanged];
}

- (void)resend {
    self.sent = nil;
    [self send];
}

#pragma mark What's playing

- (void)heard:(NSDictionary *)info {
    if (!self.shown) return;
    self.heardCount++;
    NSDictionary *song = SongFromAnnouncement(info, NowMs());
    if (!song) {
        [self take:nil];
        return;
    }
    // The announcement has no cover: the one already found stays while the song does, and a new song's is asked for.
    NSMutableDictionary *kept = [song mutableCopy];
    if ([self.song[@"track"] isEqual:song[@"track"]] && self.song[@"artUrl"]) kept[@"artUrl"] = self.song[@"artUrl"];
    if (![song[@"track"] isEqual:self.song[@"track"]]) self.retries = 0;
    [self take:kept];
    [self playIfPending];
    if (![song[@"track"] isEqual:self.askedAbout]) [self read:YES];
}

// Asks Spotify for the song now, with its cover and position: `ask`, whether macOS may ask you first.
- (void)read:(BOOL)ask {
    NSRunningApplication *spotify = RunningSpotify();
    if (!self.shown || self.reading || !spotify) return;
    self.reading = YES;
    self.askedAbout = self.song[@"track"];
    NSUInteger since = self.heardCount;
    pid_t pid = spotify.processIdentifier;
    dispatch_async(self.queue, ^{
        OSStatus status = AutomationPermission(pid, ask);
        double at = 0;
        NSArray *fields = status == noErr ? ReadSong(pid, &status, &at) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.reading = NO;
            [self answered:fields status:status since:since at:at];
        });
    });
}

// On the main thread: what Spotify answered, or why it didn't, with when its position was right (`at`). An answer
// overtaken by an announcement (the song changed while Spotify was being asked) gives only the cover, if it's still the
// same song, and the new song is asked about in turn.
- (void)answered:(NSArray *)fields status:(OSStatus)status since:(NSUInteger)since at:(double)at {
    if (!self.shown || !RunningSpotify()) return;
    if (!fields) {
        [self failed:status];
        return;
    }
    [self allow:YES];
    self.retries = 0;
    NSDictionary *song = SongFromReply(fields, at > 0 ? at : NowMs());
    if (since == self.heardCount) {
        self.askedAbout = song[@"track"];
        [self take:song];
    } else if (song[@"artUrl"] && [song[@"track"] isEqual:self.song[@"track"]] && !self.song[@"artUrl"]) {
        NSMutableDictionary *kept = [self.song mutableCopy];
        kept[@"artUrl"] = song[@"artUrl"];
        [self take:kept];
    }
    [self playIfPending];
    if (self.song && ![self.song[@"track"] isEqual:self.askedAbout]) [self read:YES];
}

// Spotify didn't answer. macOS refusing is shown on the strip; not having asked yet waits for a song; anything else
// (Spotify busy or starting up) is tried again shortly, while a song is on show.
- (void)failed:(OSStatus)status {
    if (ControlRefused(status)) return [self allow:NO];
    if (status == errAEEventWouldRequireUserConsent) return;
    PanelLog(@"Spotify didn't answer: %d", (int)status);
    self.askedAbout = nil;
    if (!self.song || self.retries >= kRetries) return;
    self.retries++;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (weakSelf.song && !weakSelf.askedAbout) [weakSelf read:YES];
    });
}

- (void)allow:(BOOL)allowed {
    if ([self.allowed isEqual:@(allowed)]) return;
    PanelLog(@"Spotify: Whozmove %@ to control it", allowed ? @"is allowed" : @"isn't allowed");
    self.allowed = @(allowed);
    if (self.song) [self take:self.song];
}

- (void)take:(NSDictionary *)song {
    NSMutableDictionary *kept = [song mutableCopy];
    if (kept && self.allowed) kept[@"allowed"] = self.allowed;
    // When it was paused: kept while it stays paused; now, if it was playing; long ago, if it's the first seen of it.
    if (kept && ![kept[@"playing"] boolValue]) {
        BOOL wasPaused = self.song && ![self.song[@"playing"] boolValue];
        kept[@"pausedSince"] = wasPaused ? self.song[@"pausedSince"] ?: @0 : self.song ? @(NowMs()) : @0;
    }
    self.song = kept;
    [self send];
    [self tokenChanged];
    if (self.onSong) self.onSong(self.shown ? self.song : nil);
}

// Spotify has quit, or is removed from Whozmove: the strip folds away, and the token shows Play.
- (void)forget {
    self.askedAbout = nil;
    self.song = nil;
    self.starting = NO;
    [self endPending];
    [self send];
    [self tokenChanged];
    if (self.onSong) self.onSong(nil);
}

#pragma mark Following the song, for its lyrics

- (void)setFollowing:(BOOL)following {
    if (following == _following) return;
    _following = following;
    [self.followTimer invalidate];
    self.followTimer = nil;
    if (!following) return;
    __weak typeof(self) weakSelf = self;
    self.followTimer = [NSTimer scheduledTimerWithTimeInterval:kFollowEvery repeats:YES block:^(NSTimer *timer) {
        [weakSelf checkPosition];
    }];
    self.followTimer.tolerance = 0.5;
}

// Where Spotify is in the song, asked alone (one Apple event), while a song plays and Whozmove is allowed to ask. The
// page is told only when it's further off than a jump's worth; and not at all when news of the song came meanwhile (an
// announcement, a read, another song, a pause), as that's newer.
- (void)checkPosition {
    NSRunningApplication *spotify = RunningSpotify();
    if (!self.shown || !spotify || self.reading || self.checking || ![self.song[@"playing"] boolValue] ||
        ![self.allowed boolValue]) return;
    self.checking = YES;
    NSUInteger since = self.heardCount;
    NSString *track = self.song[@"track"];
    pid_t pid = spotify.processIdentifier;
    dispatch_async(self.queue, ^{
        OSStatus status = AutomationPermission(pid, NO);
        double before = NowMs();
        NSAppleEventDescriptor *position =
            status == noErr ? Get(pid, AppleEventProperty(kSpotifyPlayerPosition, nil), &status) : nil;
        double at = (before + NowMs()) / 2;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checking = NO;
            if (!position || since != self.heardCount || self.reading || ![self.song[@"track"] isEqual:track] ||
                ![self.song[@"playing"] boolValue]) return;
            double positionMs = round(position.doubleValue * 1000);
            if (!PositionMoved(self.song, positionMs, at)) return;
            NSMutableDictionary *song = [self.song mutableCopy];
            song[@"positionMs"] = @(positionMs);
            song[@"at"] = @(at);
            [self take:song];
        });
    });
}

- (void)tokenChanged {
    if (!self.shown) return;
    NSDictionary *token = TokenFor(self.installed, self.song, self.starting, self.allowed, self.collapsed, NowMs());
    if ([token isEqual:self.tokenSent]) return;
    self.tokenSent = token;
    if (self.onToken) self.onToken(token);
}

#pragma mark Play, from the token

- (void)refreshToken {
    [self tokenChanged];
}

- (void)setCollapsed:(BOOL)collapsed {
    _collapsed = collapsed;
    [self tokenChanged];
}

// Whether Spotify is installed, looked for again: it's been opened (its installer opens it), Play was pressed, or it
// wasn't there last time.
- (void)lookForSpotify {
    self.installed = SpotifyInstalled();
    [self tokenChanged];
}

- (void)getSpotify {
    OpenLink(kSpotifyDownloadPage);
}

// As its Dock icon would: a Spotify with no window open shows one.
- (void)open {
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kSpotifyAppId];
    if (!self.shown || !app) return;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:app configuration:[NSWorkspaceOpenConfiguration configuration]
                                    completionHandler:^(NSRunningApplication *opened, NSError *error) {
        if (!opened) PanelLog(@"Spotify didn't open: %@", error.localizedDescription);
    }];
}

- (BOOL)play {
    [self lookForSpotify];
    if (!self.shown || self.starting || !self.installed) return NO;
    self.starting = YES;
    [self tokenChanged];
    NSRunningApplication *running = RunningSpotify();
    if (running) {
        [self playIn:running.processIdentifier launched:NO];
        return YES;
    }
    // In the background: the music is what you asked for, not Spotify's window.
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kSpotifyAppId];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:app configuration:configuration
                                    completionHandler:^(NSRunningApplication *opened, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (opened) return [self playIn:opened.processIdentifier launched:YES];
            PanelLog(@"Spotify didn't open: %@", error.localizedDescription);
            self.starting = NO;
            [self tokenChanged];
        });
    }];
    return YES;
}

// Waits for a Spotify just opened (`launched`) to answer and load what it last had, asks macOS (the first time, this
// is its question), then plays what Spotify has. With nothing loaded, Spotify comes forward, and a song that turns up
// soon plays by itself.
- (void)playIn:(pid_t)pid launched:(BOOL)launched {
    NSUInteger since = self.heardCount;
    dispatch_async(self.queue, ^{
        OSStatus status = noErr;
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:kReadyFor], *loadUntil = nil;
        NSAppleEventDescriptor *state = nil;
        do {
            status = AutomationPermission(pid, YES);
            state = status == noErr ? Get(pid, AppleEventProperty(kSpotifyPlayerState, nil), &status) : nil;
            if (ControlRefused(status)) break;
            if (state) {
                if (!launched || state.enumCodeValue != kSpotifyStateStopped) break;
                if (!loadUntil) loadUntil = [NSDate dateWithTimeIntervalSinceNow:kLoadFor];
                if (loadUntil.timeIntervalSinceNow <= 0) break;
            }
            [NSThread sleepForTimeInterval:kReadyEvery];
        } while (until.timeIntervalSinceNow > 0);
        BOOL loaded = state && state.enumCodeValue != kSpotifyStateStopped;
        BOOL played = loaded && Send(pid, kSpotifySuite, kSpotifyPlay, nil, nil, &status) != nil;
        double at = 0;
        NSMutableArray *fields = played ? [ReadSong(pid, &status, &at) mutableCopy] : nil;
        // Spotify may not say it's playing yet, a moment after it was told to: it is.
        if (fields.count == 8) fields[6] = @"playing";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.starting = NO;
            if (state && !loaded) {
                [[NSRunningApplication runningApplicationWithProcessIdentifier:pid]
                    activateWithOptions:NSApplicationActivateAllWindows];
                [self startPending];
            }
            if (state) [self allow:YES];
            if (fields) [self answered:fields status:status since:since at:at];
            else if (!state || loaded) [self failed:status];
            [self tokenChanged];
        });
    });
}

- (void)startPending {
    self.pendingUntil = [NSDate dateWithTimeIntervalSinceNow:kPendingFor];
    [self.pendingTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.pendingTimer = [NSTimer scheduledTimerWithTimeInterval:kPendingEvery repeats:YES block:^(NSTimer *timer) {
        if (weakSelf.pendingUntil.timeIntervalSinceNow <= 0) return [weakSelf endPending];
        [weakSelf read:NO];
    }];
}

- (void)endPending {
    self.pendingUntil = nil;
    [self.pendingTimer invalidate];
    self.pendingTimer = nil;
}

// While Play waits for something to play: a song that has turned up (you've signed in, say) plays, once.
- (void)playIfPending {
    if (!self.pendingUntil || !self.song) return;
    BOOL playing = [self.song[@"playing"] boolValue];
    [self endPending];
    if (!playing) [self control:@"playpause" fraction:0];
}

- (void)send {
    NSDictionary *song = self.shown ? self.song : nil;
    NSData *json = song ? [NSJSONSerialization dataWithJSONObject:song options:NSJSONWritingSortedKeys error:nil] : nil;
    NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"null";
    if (!self.page.ready || [text isEqual:self.sent]) return;
    self.sent = text;
    [self.page call:@"setNowPlaying" arguments:text];
}

#pragma mark Controls

- (void)control:(NSString *)action fraction:(double)fraction {
    if ([action isEqual:@"settings"]) {
        OpenLink(@"x-apple.systempreferences:com.apple.preference.security?Privacy_Automation");
        // Once you've allowed it there, the next press finds out: the token offers Play again meanwhile.
        self.allowed = nil;
        NSMutableDictionary *song = [self.song mutableCopy];
        [song removeObjectForKey:@"allowed"];
        if (song) [self take:song];
        [self tokenChanged];
        return;
    }
    NSRunningApplication *spotify = RunningSpotify();
    if (!spotify || !self.shown) return;
    if ([action isEqual:@"open"]) {
        [spotify activateWithOptions:NSApplicationActivateAllWindows];
        return;
    }
    NSNumber *command = @{@"playpause": @(kSpotifyPlayPause), @"next": @(kSpotifyNext),
                          @"previous": @(kSpotifyPrevious)}[action];
    double durationMs = [self.song[@"durationMs"] doubleValue];
    BOOL seek = [action isEqual:@"seek"];
    // Something without a length (an ad, say) has nowhere to jump to.
    if (!command && !(seek && durationMs > 0)) return;
    double seconds = MAX(0, MIN(1, fraction)) * durationMs / 1000;
    // Then the song is read again: a jump or going back to the start of the same song isn't announced. Spotify may
    // answer that read before it has done what it was told, so for the same song the press is taken as done.
    NSUInteger since = self.heardCount;
    pid_t pid = spotify.processIdentifier;
    NSString *track = self.song[@"track"];
    BOOL wasPlaying = [self.song[@"playing"] boolValue], toggle = [action isEqual:@"playpause"];
    dispatch_async(self.queue, ^{
        OSStatus status = AutomationPermission(pid, YES);
        BOOL done = status == noErr &&
            (seek ? Send(pid, kAECoreSuite, kAESetData, AppleEventProperty(kSpotifyPlayerPosition, nil),
                         [NSAppleEventDescriptor descriptorWithDouble:seconds], &status)
                  : Send(pid, kSpotifySuite, command.unsignedIntValue, nil, nil, &status)) != nil;
        // A jump is where it was sent the moment Spotify took it.
        double jumped = NowMs(), at = 0;
        NSMutableArray *fields = done ? [ReadSong(pid, &status, &at) mutableCopy] : nil;
        if (fields.count == 8 && [fields[0] isEqual:track]) {
            if (toggle) fields[6] = wasPlaying ? @"paused" : @"playing";
            if (seek) {
                fields[5] = @(seconds);
                at = jumped;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            // The page showed a pause or a jump ahead of Spotify: if it didn't go through, it's told what's true.
            if (!done) self.sent = nil;
            [self answered:fields status:status since:since at:at];
            [self send];
        });
    });
}

@end
