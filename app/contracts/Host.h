// Host: an app sessions run in (Claude Desktop, Ghostty, iTerm2, Terminal), and what the panel can do there. A host is
// a module that adopts Host; what more it can do, it says by the protocols it adopts beside it: TypingHost (a session's
// tab found, and keys typed into it), CommandHost (a command run in a new tab) and ConversationHost (an app that keeps
// sessions as conversations of its own, Claude Desktop's). The core finds the host a row runs in (Core's hostOf:).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

@protocol Host <NSObject>
// Its app id, and its name as the panel says it.
@property (readonly) NSString *appId;
@property (readonly) NSString *name;
@optional
// Whether a session is one it holds as its own, whatever process runs it (a conversation of Claude Desktop's). A host
// without this holds the sessions whose process its app owns.
- (BOOL)holds:(Row *)row;
// Whether a process with no ordinary app up its tree runs in it: a terminal that keeps its sessions under a server of
// its own, which can outlive the app, or one kept out of the Dock, which isn't an ordinary app. It's asked only when
// there's no ordinary app above the process, so an ordinary terminal started from another's shell keeps its own
// sessions; one kept out of the Dock and started that way has its sessions taken for the other's. A host without this
// runs the processes its app owns.
- (BOOL)runsProcess:(pid_t)pid;
// Brings a session forward in it. YES once it shows the session, or is bringing it forward; NO when it can't find it
// (then only the app comes forward).
- (BOOL)open:(Row *)row;
// Which of these sessions (each running in it) it shows: `done` gets the one in its front window's selected tab, or nil
// when that's certainly none of them. It isn't called when it can't tell (no answer, or tabs it can't tell apart), nor
// while an answer to an earlier ask is still on its way. Asked off the main thread, as it can take a while to answer;
// `done` runs on the main thread.
- (void)whichShows:(NSArray<Row *> *)rows done:(void (^)(Row *row))done;
@end

// The keys the panel presses in a session's prompt.
typedef NS_ENUM(NSInteger, TerminalKey) {
    TerminalKeyReturn,
    TerminalKeyBackspace,
    TerminalKeyShiftTab,
    TerminalKeyControlS,
};

// A terminal the panel can type into. Whether it's safe to type is the session's own state, the same in every terminal
// (WhyNotTypeInto).
@protocol TypingHost <Host>
// Brings a session's tab forward (Host's open:, which a terminal the panel types into always has).
- (BOOL)open:(Row *)row;
// The tab a session runs in, or nil. *unique says whether nothing else in its folder fits as well: keys go only into a
// tab that's certainly the session's.
- (NSString *)tabFor:(Row *)row unique:(BOOL *)unique;
// Puts text into a tab, or presses a key there `times` times.
- (void)type:(NSString *)text inTab:(NSString *)tab;
- (void)press:(TerminalKey)key times:(NSInteger)times inTab:(NSString *)tab;
@end

// A terminal that can run a command in a new tab, in a folder (a new conversation, or the usage card's Sign in:
// `claude auth login`), so it runs in your shell as you'd type it, with your PATH. `name` says what it runs ("Sign in
// to Claude Code"), or nil, for a terminal that shows that (macOS's Terminal names its window so). The terminal comes
// forward with it, or, not `forward`, opens it behind the app you're in. `done` gets, on the main thread, nil once the
// tab has opened, or why it couldn't, as the panel says it, which may take a while (macOS may ask you first).
@protocol CommandHost <Host>
- (void)newTabIn:(NSString *)folder running:(NSString *)command named:(NSString *)name forward:(BOOL)forward
            done:(void (^)(NSString *why))done;
@end

// An app that keeps sessions as conversations of its own, which it lists, shows and sends messages in.
@protocol ConversationHost <Host>
// On the sessions' queue, as the rows are read: what it knows of the running sessions it holds that the agent doesn't
// (its own record of each, which goes on the row before the agent's hooks', and the setup it shows, `hostDetails`),
// rows for the conversations it keeps that aren't running, and which of them all it shows now (`focused`). Returns the
// rows it adds.
- (NSArray<Row *> *)readRows:(NSArray<Row *> *)running;
// Makes sure it shows a conversation, in front: opened if it shows another one, else brought forward.
- (void)show:(Row *)row;
// Whether Whozmove may control it; when it may not, macOS is asked to offer the Accessibility permission.
- (BOOL)mayControl;
// Writes a command in a conversation's message box and sends it. `done` gets nil once it's sent, or why it wasn't, as
// the panel says it.
- (void)send:(NSString *)command toConversation:(NSString *)hostId done:(void (^)(NSString *why))done;
// "Switch model?": whether it would ask that for this conversation; never again, once "Don't ask again" is chosen;
// whether its own box is up; and answering that box (NO if it isn't up).
- (BOOL)mayAskToSwitch:(Row *)row;
- (void)stopAskingToSwitch;
- (BOOL)showsSwitchBox;
- (BOOL)answerSwitchBox:(BOOL)switchModel dontAskAgain:(BOOL)dontAskAgain;
// A new conversation in a folder, with your words as its first message, sent once it's ready. `trusted`: Claude Code's
// record trusts the folder, so if it asks to trust the folder anyway, it's answered yes, as you've said yes already.
// `done` gets nil once it's sent (or at once with no words, for you to write them there), or why it couldn't be.
- (void)startConversationIn:(NSString *)folder words:(NSString *)words trusted:(BOOL)trusted
                       done:(void (^)(NSString *why))done;
// The new conversations it says it started lately, oldest first, as {id, folder, at}: its own id, the folder it started
// in (which needn't be the one it was asked for), and when, in ms since 1970, to the second.
- (NSArray<NSDictionary *> *)startedConversations;
// Whether a session id is one of its own (a conversation it started, before Claude Code's id for it is known).
- (BOOL)isOwnId:(NSString *)sessionId;
// When `folder` is one it made for a conversation started with no folder of yours, how the conversation's row says so
// ("Claude started it with "No folder", not in <asked>"); else nil.
- (NSString *)startedWithoutFolder:(NSString *)folder asked:(NSString *)asked;
// The link it would be opened with for a new conversation with these words (the tests print it), and the most words
// that link carries.
- (NSURL *)newConversationLink:(NSString *)words;
@property (readonly) NSUInteger linkWordsMax;
@end
