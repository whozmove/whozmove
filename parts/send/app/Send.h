// Send: words into a session, through the app it runs in (its host) and the agent that runs it: typed into its terminal
// tab while keeping your draft, or written in its conversation's message box; and why they can't go in now, as the
// panel says it. What the panel's menus, cards and steps share.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Host.h"
#import "Agent.h"

@class Core, Row, Reason, Send;

// Where words for a session would go, as a menu, a card or a step words why they can't go in now. Each answer is found
// only when the wording first asks for it, in the order it asks (a terminal's tab is looked for only once it's needed).
@protocol Reach <NSObject>
// The session is a conversation an app keeps as its own (Claude Desktop's), and Whozmove may control that app.
@property (readonly) BOOL desktop;
@property (readonly) BOOL mayControl;
// Its first message is sent: it has a transcript.
@property (readonly) BOOL started;
// It ran in a terminal and has ended: nothing goes in until it's opened again from its row.
@property (readonly) BOOL ended;
// Its conversation runs in another process as well, not paused (the row's alsoOpen); and one of those runs in a
// terminal while this one does too, where a key for one could land in the other's tab, so nothing goes in.
@property (readonly) BOOL openElsewhere;
@property (readonly) BOOL openTwice;
// Else the terminal it runs in, by name, if the panel can type into it (nil when it can't), and the terminals it can
// type into, by name; whether the session's tab there is found, and whether it's certainly its.
@property (readonly, copy) NSString *terminal;
@property (readonly, copy) NSString *terminals;
@property (readonly) BOOL hasTab;
@property (readonly) BOOL unique;
// The terminal's own reason keys can't go into that tab now, or why it found none, as the panel says it, or nil
// (TypingHost's whyNotTypeIn:).
@property (readonly, copy) NSString *tabWhyNot;
// What a button for the terminal's way past that reason says, when it has one the panel can take (TypingHost's
// wayPastIn:), or nil.
@property (readonly, copy) NSString *wayPast;
// A change from the panel is still going into it (the row's goingIn, its switchAsk, or words or a command of the
// agent's Send is typing): nothing more goes in until it's done, as a key meant for the next command could answer what
// Claude asks about that one.
@property (readonly) BOOL changing;
// Why keys can't go into it now, or nil.
@property (readonly) Reason *whyNotType;
@end

// A row's reach as the app finds it: from the hosts and the session's agent, each once, when the wording first asks for
// it. What it found is kept for the words that then go in.
@interface SessionReach : NSObject <Reach>
- (instancetype)initWithRow:(Row *)row send:(Send *)send;
@property (readonly) id<ConversationHost> conversations;  // the app that keeps the session as a conversation, or nil
@property (readonly) id<TypingHost> typing;               // else the terminal it runs in, if the panel can type into it
@property (readonly) NSString *tab;                       // and its tab there, or nil
@end

@interface Send : NSObject
- (instancetype)initWithCore:(Core *)core;
// A session's reach, found as it's asked.
- (SessionReach *)reachOf:(Row *)row;
// The agent that runs a session, if words can be put into its prompt; the terminal it runs in, if it's one the panel
// can type into; the app that keeps it as a conversation of its own (Claude Desktop), or nil; and the terminals the
// panel can type into, by name ("Ghostty or iTerm2").
- (id<AgentPrompt>)agentOf:(Row *)row;
- (id<TypingHost>)terminalOf:(Row *)row;
- (id<ConversationHost>)conversationHostOf:(Row *)row;
@property (readonly) NSString *terminalNames;
// Whether words or one of the agent's commands are going into a session from here now (ask:, run:), until the filler is
// out: a change from the panel still going in, for the reach's `changing`.
- (BOOL)typingInto:(NSString *)sessionId;
// Whether a session ran in a terminal and has ended (the core's hasEnded:, which a press on its row goes by too).
- (BOOL)hasEnded:(Row *)row;
// The session's agent asked in words, as you'd type them, while it's idle: one of a row's next steps. The row says
// it's asking, or why they can't go in (stepNote).
- (void)ask:(NSString *)words row:(Row *)row;
// Words put into the session as a message you'd type and send, on one line (600 characters at most), while it's idle,
// as ask: puts them in but with no note on its row and nothing of the words in panel.log: control, invisible and
// turning characters go. `done` gets nil once they're in, or why they can't go in or stopped part-way (`here` and
// `there` end its sentences, as WhyNoWords takes them), with what a button past the terminal's own reason says, if
// there's one (WayPast). A Claude Desktop conversation is shown first, as only the one Claude shows takes words. Words
// that would run a command (WordsRunACommand) are refused, never typed.
- (void)say:(NSString *)words row:(Row *)row here:(NSString *)here there:(NSString *)there
       done:(void (^)(NSString *why, NSString *way))done;
// The same with the session's reach as already found, and `also`, when given, asked before each key too, as the
// terminal and the agent are, stopping the words as they do (stillAway:, for words going in by themselves).
- (void)say:(NSString *)words row:(Row *)row reach:(SessionReach *)reach here:(NSString *)here there:(NSString *)there
       also:(Reason *(^)(void))also done:(void (^)(NSString *why, NSString *way))done;
// For words going in by themselves: asked before each key, it stops them once they no longer would
// (ReachGoesByItself, with the session as it's listed now and the app in front then), as you've come to it.
- (Reason *(^)(void))stillAway:(Row *)row;
// Words for a session that may be at work (a side chat's), and how far they've got, told to `progress` on the main
// thread each time that changes, as {state, …}:
// - held, with `until`: step (its agent's hook hands them in once its current step ends), turnEnd (its agent has no
//   such hook for it: once its turn ends), or press (its turn has ended, and they wait for your Send Now, as they never
//   go in by themselves where you might be typing: WordsGoByThemselves);
// - handed (its agent's hook has them), typing, typed;
// - read, with `how` (step, turnEnd or typed) and `at`: the session's own record shows them;
// - stopped (it stopped before reading them), refused (`why` and `way`: they couldn't be typed in), or ended (its
//   session ended first).
// Words for a session that's idle go in at once, as say: puts them in. Returns their id, or nil when they're refused at
// once (`progress` says why). Only how they went is logged, never the words.
- (NSString *)sayBetweenSteps:(NSString *)words row:(Row *)row progress:(void (^)(NSDictionary *change))progress;
// Takes held words back before they go in: nil once they're out, else how far they'd got (handed, or read).
- (NSString *)takeBack:(NSString *)wordsId;
// Held words sent now, by your press: typed in as say: does, if the session can take them.
- (void)sendNow:(NSString *)wordsId;
// One of the agent's own commands, typed in as ask: puts words in, only while the session is idle; `done` gets the
// result the agent wrote for it (AgentCommands' resultOf:since:), or why it didn't go in or no result came, as a row's
// note says it. `here` and `there` end the sentences on why it can't go in now, as WhyNoWords takes them.
- (void)run:(NSString *)command row:(Row *)row here:(NSString *)here there:(NSString *)there
       done:(void (^)(NSString *result, NSString *why))done;
// A press on the button past a terminal's reason (WayPast), on a menu, a card or a step's note, `{sessionId}`: the
// terminal takes it, if it's still that reason, and the row says how it went, or what's left to do.
- (void)takeWayPast:(NSDictionary *)msg;
@end

// Why no words can be typed into the session's tab: it has ended, there's no terminal the panel can type into, its tab
// isn't found, its conversation is open in another terminal too, another tab fits as well, or the terminal has a reason
// of its own. `here` and `there` end the sentences ("can be changed here", "change it there").
NSString *WhyNoTab(id<Reach> reach, NSString *here, NSString *there);
// The terminal's own reason keys can't go into a tab now, or nil: what the last check before a key goes in asks, and
// each key typed after it, as a terminal that refused one refuses the rest.
Reason *WhyTerminalRefuses(id<TypingHost> terminal, NSString *tab);
// What a button beside `why` says, when `why` is the terminal's own reason and it has a way past it the panel can take
// (the reach's wayPast), else nil: what a menu, a card or a step's note offers, so you're never left with only a reason.
NSString *WayPast(id<Reach> reach, NSString *why);
// Why nothing more goes into a session while a change from the panel is still going in, as the panel says it.
extern NSString *const kStillChanging;
// Why no words can go into it now, as the row's note says it, or nil: `here` and `there` end the sentences, as
// WhyNoTab's do. And why its agent can't be asked in words now, in those words.
NSString *WhyNoWords(id<Reach> reach, NSString *here, NSString *there);
// Whether words, as say: sends them (PlainOneLine), start with what Claude Code's prompt or Claude Desktop's message box
// takes as a command rather than a message: "/" (a slash command, /exit among them), "!" (a shell line), "#" (a
// memory) or "&". say: refuses them, so words passed through from anyone can never run one.
BOOL WordsRunACommand(NSString *words);
// Whether words held for a session go in by themselves once it's idle: only into a terminal that isn't the app in front
// at all (the tab it shows may have changed since it last said), never into the session you're on, and never into a
// Claude Desktop conversation, which comes forward only for your press. `hostApp` is the app the session runs in and
// `frontApp` the one in front, by bundle id.
BOOL WordsGoByThemselves(BOOL focused, BOOL desktop, NSString *hostApp, NSString *frontApp);
// The same for a session as its reach finds it: its terminal is the one the panel would type into (`typing`, the
// terminal its process runs in), never only an app that keeps it as a conversation of its own, so a session in a
// terminal counts as one.
BOOL ReachGoesByItself(SessionReach *reach, BOOL focused, NSString *frontApp);
// The name of a session's terminal when it's the app in front (`frontApp`, by bundle id), where words held for it wait
// for your press, or nil.
NSString *ReachTerminalInFront(SessionReach *reach, NSString *frontApp);
// What held words do now, from what's known of their session: wait for its turn to end (turnEnd), for your press
// (press), or for the words before them or another change from the panel to finish going in (later), or go in
// (type). `pressed` is your press (Send, or Send Now) and `byThemselves` WordsGoByThemselves. A press counts only for
// going in at once: words that wait for anything wait under WordsGoByThemselves from then on (`stillPressed`).
NSString *HeldWordsStep(BOOL works, BOOL first, BOOL pressed, BOOL byThemselves, BOOL changing, BOOL *stillPressed);
NSString *WhyNoAsk(id<Reach> reach);
// Why a command can't go into a Claude Desktop conversation now, or nil: one that runs takes it only while it sits
// idle, by what its agent says, and one that doesn't run can take one at any time (it's opened first).
Reason *WhyNotSendTo(id<AgentPrompt> agent, Row *row);
