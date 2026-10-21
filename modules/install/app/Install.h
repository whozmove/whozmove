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
// What it goes by, given as they are: where this app runs from, whether an agent built it, whether the agent is on this
// Mac and Apple's developer tools are there now, the agent's part, and the hooks this app carries.
- (instancetype)initWithApp:(NSString *)app builtByAgent:(BOOL)agentBuild agentHere:(BOOL (^)(void))agentHere
                      tools:(BOOL (^)(void))tools connect:(ConnectHooks)connect hooks:(NSString *)hooks;
// Goes through it all, after any check still under way, with your press on the line (addBack, turnOn, retry) as
// `answer`, or nil.
- (void)check:(NSString *)answer;
// Each tick: while it waits for the agent or for the developer tools, it looks again every 10 seconds (macOS is asked
// about the tools at most every 5 minutes, DeveloperToolsGit).
- (void)tick;
// Whether a check is queued or under way: its print mode waits until none is.
@property (readonly) BOOL working;
// What the last check found, {state, detail}, on the main thread: state is notInApplications, noTools, agentBuild, or
// the agent's (AgentInstall). `onFound` hears of each.
@property (readonly) NSDictionary *found;
@property (copy) void (^onFound)(NSDictionary *found);
@end

// Whether an app at this path runs from an Applications folder, /Applications or ~/Applications, at any depth: never
// from a disk image, a download, a build's folder, or the copy of one macOS runs it from instead (App Translocation).
BOOL InApplications(NSString *app);
// The print mode, `--print-install <case>…`, for the module's tests.
int PrintInstall(NSArray<NSString *> *cases);
