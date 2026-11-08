// Agent: the coding agent that runs the sessions the panel lists (Claude Code), and what the panel asks of it. An agent
// is a module that adopts Agent; what more it does, it says by the protocols it adopts beside it, one for each part of
// the panel that uses it, so none of them reaches into the whole agent: AgentWork (what a session did: its edits and
// its PRs), AgentBetweenSteps (words handed to a working session by its hooks), AgentAside (a question a copy of a
// session's conversation answers on the side), AgentCommands (its menus' choices, the commands that make them, and
// whether one took), AgentPrompt (a command put into a session's prompt while keeping your draft), AgentUsage (your
// plan's usage), AgentStarts (a new session, an ended one carried on, and whether it may work in a folder),
// AgentInstall (Whozmove's hooks in it, added and kept up to date), AgentVoice (its sessions' own voice input),
// AgentRecords (where it keeps what its sessions were told and read, for Keys) and AgentConversations (every
// conversation it keeps, for Sessions on the panel's back). The core finds the agent that runs a row's session (Core's
// agentOf:).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row, Reason;
@protocol TypingHost;

@protocol Agent <NSObject>
// Its name, as the panel says it ("Claude Code").
@property (readonly) NSString *name;
// As the rows are read, on their queue (Rows, the list part's): the sessions it runs now, as rows, leaving out its own
// (its usage check); then, once the hosts have added theirs (Claude Desktop's conversations, running or not), the
// sessions it ran in a terminal lately that have ended, and that no row in `listed` has, as rows with status "closed"
// and no process (a press on one opens it again: AgentStarts' resumeCommand:wordsFile:); then what its hooks recorded
// of each, which goes on the row after the host's own record (where both say when the session last moved, the later
// time stands); and last, the requests waiting for your answer.
- (NSArray<Row *> *)readSessions;
- (NSArray<Row *> *)readEndedSessions:(NSArray<Row *> *)listed;
- (void)addRecordTo:(Row *)row;
- (void)addRequestsTo:(NSArray<Row *> *)rows;
// The title it gives a session, which it also puts in the session's terminal tab (Claude Code's topic), or nil: as the
// last read of the rows found it, or, `now`, read again. A terminal finds a session's tab by it.
- (NSString *)titleOf:(Row *)row now:(BOOL)now;
// Whether a terminal tab's whole title, as the agent put it there, says it's at work in that tab (Claude Code turns a
// mark before its topic while it works). Two tabs with the same title, the same conversation open twice, are told
// apart by it.
- (BOOL)titleShowsWork:(NSString *)title;
// The marks it puts on the commands its sessions run, as the names of environment variables. A command you set off from
// the panel (making a worktree, say) is yours, so they're taken off it.
@property (readonly) NSArray<NSString *> *environmentMarks;
// The session a process is, by its id, when it's one of this agent's own running processes (not one of its tools: the
// core walks up to it from them); nil otherwise. Asked on the main thread, now and then: as a session asks the panel
// something (SessionAsks).
- (NSString *)sessionOfProcess:(pid_t)pid;
// Why a process sessionOfProcess: names a session for can't ask the panel things in that session's name (a program
// not the agent's own wrote its record, say), saying what to do; nil when it can. Asked only as a session asks.
- (NSString *)whyNotAsker:(pid_t)pid;
// Why `process`, found as that session's own, can't ask for something that only shows you something in the session's
// name, read fresh at the ask (another copy of it running now, say); nil when it can. Each says what to do.
- (NSString *)whyNot:(Row *)row speakFrom:(pid_t)process;
@end

// What a session did, as the agent records it (Claude Code's transcripts, read a little at a time).
@protocol AgentWork <Agent>
// The PRs a session made or worked on, by their address: {url, number, repo, at}. `onPRLinks` is called when new ones
// turn up.
- (NSDictionary<NSString *, NSDictionary *> *)prLinksOf:(NSString *)sessionId;
@property (copy) void (^onPRLinks)(void);
// What a session edited: {files: {path: {path, edits, at, created, added, removed}}, count (the edits counted, which
// changes whenever they do), version (moves on whenever anything in files may have changed, a later result included;
// missing when the agent can't tell), known (whether everything it changed is known: a shell command whose changes
// the agent didn't record could have changed anything), failed (its shell commands that failed, which record nothing
// of what they may have changed first), doubts (the files a command changed whose lines its record leaves out)}.
// `added` and `removed` are the lines' keys (LineKey, shared/Text.h).
- (NSDictionary *)editsOf:(Row *)row;
// What the agent answered words put into a session's prompt: its last reply in the turn whose prompt is exactly
// `prompt`, sent after `since` (ms since 1970), read off the main thread and kept nowhere. `done` gets it on the main
// thread (16,384 characters at most), or nil while that turn has none yet: asked again once the session has stopped.
- (void)replyTo:(NSString *)prompt of:(NSString *)sessionId since:(double)since done:(void (^)(NSString *reply))done;
@end

// Words for a session at work, handed in by its own hooks (a side chat's): its hook asks the panel for them as its
// current tool calls finish, or as its turn ends, which then carries on, and hands them in once, after the line that
// says they're from you. Nothing is typed.
@protocol AgentBetweenSteps <Agent>
// Whether a session runs that hook (one started before it went in doesn't), and whether it would, but started before.
- (BOOL)takesWordsBetweenSteps:(Row *)row;
- (BOOL)startedBeforeBetweenSteps:(Row *)row;
// The line that opens your words as the hook hands them in.
@property (readonly) NSString *betweenStepsLine;
// Words (one line, as Send makes them) held for a session's hook, which takes them once: `wordsId` names them.
- (void)holdWords:(NSString *)words for:(Row *)row id:(NSString *)wordsId;
// Held words taken back: YES if its hook hadn't taken them yet.
- (BOOL)takeBackWords:(NSString *)wordsId;
// How far held words have got, on the main thread: nil while its hook hasn't taken them; once it has, `done` gets
// {state: handed}, then {state: read, how (step or turnEnd), at} once its transcript shows them taken in, with `reply`,
// what Claude wrote after them, and `turnEnded`, once that turn has ended.
- (void)wordsState:(NSString *)wordsId row:(Row *)row done:(void (^)(NSDictionary *state))done;
// Held words let go of: read, taken back, or their session ended.
- (void)forgetWords:(NSString *)wordsId;
@end

// A question asked on the side: a throwaway copy of a session's conversation answers it, using no tools and saving
// nothing, while the session itself works on and never sees it.
@protocol AgentAside <Agent>
// Why a session can't be asked on the side now, found without running anything, or nil: {why}, `why` noCommand (its
// command isn't on this Mac), notStarted (nothing said in it yet) or noConversation (its conversation's file isn't
// where it keeps them). Signed out is found by asking (its answer's signedOut).
- (NSDictionary *)asideWhyNot:(Row *)row;
// Asks it, at once and off the main thread: the ask's id, or nil when it couldn't start (and `done` is never called).
// `done` is called once, on the main thread, with {state, text, resetsAt, signIn, status, cacheRead, fresh, written,
// output}: `state` answered, tooSlow, noAnswer, wantedTool (it reached for a tool, which it can't use), limit (your
// plan's, until `resetsAt`, ms since 1970), signedOut (`signIn`, the command that signs it in), tooLong (its
// conversation is too long to read again), apiError (its provider sent back an error), noCommand (no command found to
// run) or stopped; `text`, its answer (16,384 characters at most) once answered; and, when it said, the error status
// its provider sent back (a number, never words), and the tokens it read from the cache, read fresh, wrote to the cache
// and wrote out.
- (NSString *)ask:(NSString *)question aside:(Row *)row done:(void (^)(NSDictionary *answer))done;
// An ask stopped: ended by its own checked process, its `done` then given `stopped`. Nothing if it has ended.
- (void)stopAside:(NSString *)askId;
@end

// The settings a session's menus change (model, effort and permission mode), the commands that change them and that
// compact a session, and reading what such a command did.
@protocol AgentCommands <Agent>
// A field's choices (model, effort or mode), as [the value it takes, the name shown].
- (NSArray<NSArray<NSString *> *> *)choicesFor:(NSString *)field;
// The command that sets a field to a value, as typed in a session's prompt ("/model claude-opus-5-5"), or nil when no
// command does (a mode other than plan); and the one that compacts a session, with what to focus on, or none.
- (NSString *)commandSetting:(NSString *)field to:(NSString *)value;
- (NSString *)compactCommand:(NSString *)focus;
// The Shift+Tab cycles a session in a terminal could have, and how many presses take it from one mode to another in all
// of them (-1 when that isn't certain: a key too many or too few would land it in another mode).
- (NSArray<NSArray<NSString *> *> *)modeCyclesFor:(Row *)row;
- (NSInteger)shiftTabsFrom:(NSString *)from to:(NSString *)to cycles:(NSArray<NSArray<NSString *> *> *)cycles;
// Where a command's result will be written, marked as the command goes in, or nil while the session has nowhere yet;
// then the result written since that mark (nil while there's none), and what it says: the value that now applies for
// the field the command changed (nil: nothing changed, declined or failed), whether it saved the pick as the default
// for new sessions, and after a compaction, nil once it compacted, else what to say about it, in plain text ("" when
// there's nothing to say).
- (id)markResultsOf:(NSString *)sessionId;
- (NSString *)resultOf:(NSString *)command since:(id)mark;
- (NSString *)resultApplies:(NSString *)field value:(NSString *)value result:(NSString *)result;
- (BOOL)resultSavedDefault:(NSString *)result;
- (NSString *)compactNote:(NSString *)result;
// A command that sets the model or effort also saves the pick as the default for new sessions, while a pick in the
// panel is for one session: before one goes in, the defaults it may overwrite are kept, and once it has run (or won't),
// put back if it saved its own. One release for each hold.
- (void)holdDefaults:(NSString *)field;
- (void)releaseDefaults:(NSString *)field saved:(BOOL)saved;
// "Switch model?" for a session in a terminal, asked in the panel through the agent's hooks when the agent would ask
// it: a note, right before the command that switches a session's model goes in, that the switch is the panel's (nil
// for the model takes it back, once the command is over, so a switch typed in the terminal is never taken for it); what's
// asked of the panel for it now ({from, to, tokens}: the models, and how much the conversation holds, or NSNull), else
// nil; and the panel's answer.
- (void)noteSwitchOf:(NSString *)sessionId to:(NSString *)model;
// Whether the session's hooks would ask its "Switch model?" in the panel (a session started before they could has
// Claude ask in the terminal).
- (BOOL)asksSwitchInPanel:(Row *)row;
- (NSDictionary *)switchAskedIn:(NSString *)sessionId;
- (void)answerSwitchIn:(NSString *)sessionId allow:(BOOL)allow;
@end

// Words put into a session's prompt, in a terminal keeping any draft there.
@protocol AgentPrompt <Agent>
// Whether a session's first message has been sent (it has a transcript): before that, a command would start one.
- (BOOL)hasStarted:(NSString *)sessionId;
// Why keys can't go into a session's prompt now, or nil when it's safe: only while it sits idle at its prompt with no
// request waiting, where a stray Return would answer it. And why the one key that may go in while it works can't now:
// the Backspace that takes out the filler typing a command left.
- (Reason *)whyNotTypeInto:(NSString *)sessionId pid:(pid_t)pid;
- (Reason *)whyNotEditDraft:(NSString *)sessionId pid:(pid_t)pid;
// Types a command into a session's prompt through its terminal, keeping any draft there, a key at a time and each only
// while `whyNot` returns nil. `done` gets nil once every key is in, or why typing stopped, after how many of how many.
// The filler it leaves at the end of the draft is taken out once the draft is back.
- (void)type:(NSString *)command into:(id<TypingHost>)terminal tab:(NSString *)tab whyNot:(Reason *(^)(void))whyNot
        done:(void (^)(Reason *why, NSUInteger typed, NSUInteger steps))done;
- (void)deleteFillerIn:(id<TypingHost>)terminal tab:(NSString *)tab;
@end

// Your plan's usage, as the agent knows it.
@protocol AgentUsage <Agent>
// On a queue of the caller's, as it can take a few seconds: {state, plan, session, week, limits, extraUsage} as the
// usage strip takes them (the usage module's Usage.m says what each is), with `signIn`, the command that signs the
// agent in as typed in a terminal, once one answered; nil in a print run, where it's never asked. `state` is "ok" (a
// plan's numbers), "signedOut", "other" (signed in or set up, with no plan's numbers), "none" (nothing to ask) or
// "failed"; with "other" or "none", `noPlan` says why, as read: "signedIn", "shell" (your shell sets a key the agent
// uses) or "unknown" (its sign-in can't be read) with "other", and "notFound" or "notReady" (this Mac isn't set up
// for it yet) with "none".
- (NSDictionary *)askUsage;
@end

// A new session started from the panel, an ended one carried on, and whether the agent may work in a folder.
@protocol AgentStarts <Agent>
// The command a terminal runs for a new session with this id, its first message read from `wordsFile` (nil: none).
- (NSString *)startCommand:(NSString *)sessionId wordsFile:(NSString *)wordsFile;
// The command a terminal runs, in the session's own folder, to carry on an ended session under its own id, its first
// message read from `wordsFile` (nil: none), or nil when that isn't one of its sessions' ids.
- (NSString *)resumeCommand:(NSString *)sessionId wordsFile:(NSString *)wordsFile;
// Whether it may work in a folder (it, its checkout, its repo or a folder above it is trusted), and recording your yes
// to that: nil once done, else why it couldn't be, as the panel says it. Both block: call them off the main thread.
- (BOOL)folderTrusted:(NSString *)folder;
- (NSString *)trustFolder:(NSString *)folder;
@end

// What lets the panel follow the agent's sessions, put into the agent as Whozmove opens: for Claude Code, its hooks,
// as a plugin.
@protocol AgentInstall <Agent>
// Puts the hooks in the folder `hooks` (the ones this app carries) into the agent, or brings them up to date there:
// {state, detail}. `state` is ready (as they were), added (the first time, or back after your press), updated (a new
// version), noCommand (the agent isn't on this Mac), removed (taken out of the agent since they were put in, so they're
// left out), turnedOff (turned off in it) or failed, with what went wrong as `detail` (the agent's own last line, when
// it said one). `answer` is your press on the line (addBack, turnOn, or retry, which puts them in again from the
// start), else nil; `before` says whether they were ever put in on this Mac, as the install module records it, so the
// agent keeps nothing. It blocks: call it off the main thread. Nil in a print run, where it's never asked.
- (NSDictionary *)connect:(NSString *)answer before:(BOOL)before from:(NSString *)hooks;
// Something quick to find, without running anything, that changes whenever how the hooks stand in the agent may have
// changed (its own record of what's put in, whether they're turned on), so they're looked at again then rather than
// on a timer. Nil when it can't tell, and then they're looked at every few minutes.
@property (readonly) NSString *hooksStamp;
// Whether the agent is on this Mac, found without running anything, not even your shell, whose startup files may run
// git before Apple's developer tools are in: asked before the tools, which only its sessions need.
@property (readonly) BOOL onThisMac;
// Where to get the agent, for the line's Get Claude Code.
@property (readonly) NSURL *installPage;
// The page on the panel's back its settings go on (an AppEntry's id: Claude Code's are on Claude's), where the install
// module adds how its hooks stand; nil for none.
@property (readonly) NSString *appId;
// A session that was running before the hooks went in runs without them until it takes them: whether a running
// session started before `since` (when they last went in, in seconds since 1970) and nothing it did has been recorded
// since it started. Then the command that has it take them without restarting, typed as the panel's commands are,
// whether its result says it did, and the command that takes them anyway when the agent holds that back (as it would
// re-read the whole conversation), which is left for you to type.
- (BOOL)runsWithoutHooks:(Row *)row since:(NSTimeInterval)since;
@property (readonly) NSString *reloadCommand;
@property (readonly) NSString *forcedReloadCommand;
- (BOOL)reloaded:(NSString *)result;
@end

// Its sessions' own voice input (Claude Code's voice mode), so the panel can tell you're talking to one.
@protocol AgentVoice <Agent>
// Whether a process recording from the microphone is one of its sessions taking your voice, from what's known of it:
// its pid, its parent's, and its program's path, among the sessions listed.
- (BOOL)takesVoice:(pid_t)pid parent:(pid_t)parent path:(NSString *)path among:(NSArray<Row *> *)rows;
@end

// Where it keeps what its sessions were told and read, which can hold a key you sent or a tool read, for Keys (the
// storage module) to look through. Keys never changes them: the agent's own command clears them, for you to run. Each
// of these only works out what it's given, so Keys calls them on its own queue.
@protocol AgentRecords <Agent>
// Its records, each {path, kind, format, deep, within}: `kind` is conversation (a session's messages, and what its
// tools read and returned), prompts (what you typed), pastes (long pastes), edits (copies of files it edited, as they
// were) or instructions (what it reads into its sessions as their instructions, with no read of it recorded: a file you
// keep); `format` is jsonl (a JSON record a line) or text; `deep` is a folder whose files are looked through at any
// depth; and `within`, for a deep folder, the name of the folder its files must be under.
@property (readonly) NSArray<NSDictionary *> *records;
// What part of a record is about, as far as it says: {session, folder, how, summary, toAgent, picture, copyOf}, each
// left out when it doesn't say: its session's id, its project's folder, how it got there, sent (you sent it), read (a
// tool read or returned it) or wrote (the agent wrote it, its prompt to a sub-agent among it, `toAgent`), whether it's
// a summary of what came before, which is never where anything was first said, whether it holds a picture or a
// document (one you pasted, or a tool returned), which what the agent writes after it may have been read off, and, for
// a copy of a file it edited, the file it's a copy of (`copyOf`). `line` is one record of a jsonl file, or nil for the
// whole file.
- (NSDictionary *)about:(NSString *)path line:(NSDictionary *)line;
// The command that clears what it keeps of a project's folder, for you to run in a terminal, or nil.
- (NSString *)clearCommandFor:(NSString *)folder;
@end

// Every conversation it keeps on this Mac, for Sessions on the panel's back (the sessions module), which lists them
// and moves those you pick to the Trash: what each is made of, whether it's open where it can't be ended now, and
// ending it.
// Reading them takes a moment with hundreds, so none of these is called on the main thread but isPlaceOfConversation:
// and whatStaysOfConversations, which read no conversation.
@protocol AgentConversations <Agent>
// Each conversation, newest first, as {id, folder, title, movedAt, ranIn, linked}: its id, its project's folder, its
// title as you or it named it (nil for none), when it last moved (ms since 1970), the app it ran in, when that's known,
// and whether it's kept through a link to a folder somewhere else (which can't go to the Trash from here).
- (NSArray<NSDictionary *> *)conversations;
// The files a conversation is made of, each a path there now: its record, what it keeps beside it, and Whozmove's own
// note of it (the hook's record, and the one kept once it ended).
- (NSArray<NSString *> *)filesOfConversation:(NSString *)conversationId;
// What of a conversation stays once its files go to the Trash, in a sentence for the question that asks first ("Your
// typed prompts stay in Claude Code's history.").
@property (readonly) NSString *whatStaysOfConversations;
// Whether a path is a place one of a conversation's files would be, there now or not: named for its conversation, in
// one of the folders they're kept in, with only those resolved, so nothing reached through a link counts. Only such a
// file is moved to the Trash, and put back.
- (BOOL)isPlaceOfConversation:(NSString *)path;
// Whether it's open in a process now; and if so, why it can't be ended now, in a few words, with nil when it can.
- (BOOL)conversationIsOpen:(NSString *)conversationId;
- (NSString *)whyNotEnd:(NSString *)conversationId;
// Ends it wherever it's open, the way closing its terminal's tab would; `done` gets nil on the main thread once every
// process of it has gone (within a few seconds), or why not.
- (void)endConversation:(NSString *)conversationId done:(void (^)(NSString *why))done;
@end
