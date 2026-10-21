// Install: Whozmove setting itself up each time it opens, as an install from Homebrew only copies the app. From an
// Applications folder only, it notes where it runs from (the hooks record only while that app is there), looks for the
// agent, waits for Apple's developer tools, which only the agent's sessions need, and puts its hooks into the agent or
// brings them up to date there (AgentInstall), unless an agent built it. One thing at a time, on a queue of its own,
// your presses on the line included.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Puts the hooks in the folder `hooks` into the agent, as AgentInstall's connect:before:from: does.
typedef NSDictionary *(^ConnectHooks)(NSString *answer, BOOL before, NSString *hooks);

@interface Install : NSObject
// What it goes by, given as it is: where this app runs from, whether an agent built it, and the hooks this app carries.
- (instancetype)initWithApp:(NSString *)app builtByAgent:(BOOL)agentBuild hooks:(NSString *)hooks;
// What it asks, each answered by a stand-in in its print mode: whether the agent is on this Mac; whether Apple's
// developer tools are there, asked of macOS again `now`, or as last asked (at most every 5 minutes, DeveloperToolsGit);
// whether macOS's installer for them is open, and asking macOS to open it; and the agent's part.
@property (copy) BOOL (^agentHere)(void);
@property (copy) BOOL (^tools)(BOOL now);
@property (copy) BOOL (^installer)(void);
@property (copy) void (^askTools)(void);
@property (copy) ConnectHooks connect;
// Goes through it all, after any check still under way, with your press on the line or the panel's back as `answer`:
// tools (Install: macOS's installer opened), addBack, turnOn or retry; else nil.
- (void)check:(NSString *)answer;
// Each tick: while it waits for the agent or for the developer tools, it looks again every 10 seconds; once the agent
// has said how its hooks stand, every 5 minutes, as you may turn them off there meanwhile.
- (void)tick;
// Whether a check is queued or under way: its print mode waits until none is, and a press waits meanwhile.
@property (readonly) BOOL working;
// What the last check found, on the main thread: {state, detail, since, tools}. state is notInApplications, noTools,
// installing (macOS's installer for the developer tools is open), agentBuild, or the agent's (AgentInstall); since
// when it has been so, in ms since 1970, kept across launches (a × on the line holds until it changes); and tools how
// the developer tools stand: in, missing or installing. `onFound` hears of each.
@property (readonly) NSDictionary *found;
@property (copy) void (^onFound)(NSDictionary *found);
@end

// Whether an app at this path runs from an Applications folder, /Applications or ~/Applications, at any depth: never
// from a disk image, a download, a build's folder, or the copy of one macOS runs it from instead (App Translocation).
BOOL InApplications(NSString *app);
// What the panel's back says of it, on Git's page (the developer tools, as `tools` stands) and on the agent's (its
// hooks, as `found` stands, or nil before the first check has ended): {said, note, ok, button, action, busy}, where
// action is what its button's press asks, as the line's does (InstallModule). `busy` while a press is under way.
NSDictionary *ToolsCard(NSString *tools, BOOL busy);
NSDictionary *PluginCard(NSDictionary *found, BOOL busy);
// The print modes, for the module's tests: `--print-install <case>…`, and `--print-install-cards`, every card the
// panel's back can show.
int PrintInstall(NSArray<NSString *> *cases);
int PrintInstallCards(void);
