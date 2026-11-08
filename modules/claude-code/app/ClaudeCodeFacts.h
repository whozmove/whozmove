// ClaudeCodeFacts: what Whozmove relies on about Claude Code that it could change. When one changes, the fix belongs
// here.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The version these were last checked with is in docs/using/install.md ("What it's tested with").
//
// What isn't here, and why: the layout of a file is known only to the code that reads it (transcripts, the settings
// files), so it is still in one place each. The hooks know Claude Code's tool names and events (the permission hook
// also what a PreModelSwitch hook is told and how it answers, that a plan's request carries the plan read again from
// its file, that the registry says idle only while no prompt of its is up, and that a plan's approval is taken from a
// hook only as an allow with an empty input, a bare one being ignored, the session then going back to the mode it
// planned from: checked with 2.1.304). The words hook knows that a PostToolBatch or Stop hook's additional context
// reaches Claude in the very next request, a Stop's carrying the turn on, that neither runs when you stop a step with
// Esc, and that a sub-agent's hook input carries its agent_id; and Transcripts.m that the transcript records it as a
// hook_additional_context attachment (AfterHandedWords): checked with 2.1.304. ClaudeSessions.m knows how a message
// from another session comes in as a prompt (its cross-session-message wrapper, whose sender's address is that
// process's messagingSocketPath in the registry). build.sh knows the mark
// Claude Code puts on the commands an agent runs (CLAUDECODE; the app's own copy is kClaudeCodeAgentMarks), plugin.sh
// how it keeps an installed plugin (a copy per version, made again for a new one), PluginInstall.m what `claude plugin
// list --json` prints, Prompt.m how its prompt keeps a draft through Ctrl+S, and Results.m how it words a command's
// result. The module's page part keeps the few facts it needs itself: each model's context window, in page/agent.js;
// and in page/request-words.js, Claude Code's tools a request can be for and what each one's input holds (Bash, Edit,
// MultiEdit, NotebookEdit, Write, Read, WebFetch, WebSearch, KillShell, AskUserQuestion, ExitPlanMode, and a connected
// app's mcp__<server>__<action>, a server from claude.ai's account named claude_ai_<app> and a plugin's
// plugin_<plugin>_<app>: checked with 2.1.304).
#import <Foundation/Foundation.h>

// Claude Code's own folder in the home folder, a path in it, and what Whozmove reads there.
extern NSString *const kClaudeCodeFolder;
NSString *ClaudeDir(NSString *sub);
// The folder that holds each version's copy of Whozmove's plugin, as Claude Code keeps it: kClaudeCodePluginCache in
// ClaudeDir, then the marketplace's folder and the plugin's.
NSString *WhozmovePluginCopies(void);
extern NSString *const kClaudeCodeRegistry;      // one file per running session
extern NSString *const kClaudeCodeTranscripts;   // one folder per project, one transcript per session
extern NSString *const kClaudeCodeSettings;
// A project's own settings that stay on this Mac, in its kClaudeCodeFolder beside the shared kClaudeCodeSettings.
extern NSString *const kClaudeCodeLocalSettings;
// Settings an organisation sets for the whole machine.
extern NSString *const kClaudeCodeManagedSettings;
// Whether Claude Code records the lines a shell command changed in its checkout (a result's bashEditDiff) for a
// command run in `mode`: in auto and bypassPermissions modes unless the setting (kClaudeCodeShellDiffSetting, from the
// machine's settings, the project's or yours, `setting` being its value or nil) turns it off, and in any mode it turns
// on.
BOOL ClaudeRecordsShellChanges(NSString *mode, id setting);
extern NSString *const kClaudeCodeShellDiffSetting;
// How the result of a shell command that failed starts, which then records nothing of what the command changed.
extern NSString *const kClaudeCodeShellFailure;
// The folder beside a session's transcript where Claude Code keeps its sub-agents' records, one file each.
extern NSString *const kClaudeCodeSubagents;
// What else Claude Code keeps of what its sessions were told and read, in its folder (checked with 2.1.304): the long
// outputs of a session's tools, in a folder beside its transcript (as its sub-agents' are); the prompts you typed, a
// JSON record a line, each with its project's folder and session; long pastes, a file each; and copies of the files a session
// edited, as they were before, in a folder per session. It clears them away after cleanupPeriodDays (30 by default),
// but for the prompts, kept until you delete them.
extern NSString *const kClaudeCodeToolResults;
extern NSString *const kClaudeCodePromptHistory;
extern NSString *const kClaudeCodePastes;
extern NSString *const kClaudeCodeEditCopies;
// A transcript's line for what came in while Claude worked (`type` attachment, the rest under `attachment`), kept
// until it goes with the next turn: one of type queued_command is a message queued for it, with where it came from
// (`origin.kind`: human, or none, for one you typed; peer, task-notification, plugin and others) and isMeta for one
// Claude Code added (checked with 2.1.304).
extern NSString *const kClaudeCodeAttachmentLine;
extern NSString *const kClaudeCodeQueuedAttachment;
extern NSString *const kClaudeCodeTypedOrigin;
// The parts of a transcript's message that are a picture or a document (a PDF), as Anthropic's API names them: in what
// you sent, or in a tool's result.
extern NSArray<NSString *> *const kClaudeCodePictureParts;
// A transcript's line naming the copies kept of the files its session edited (checked with 2.1.304): `type`
// file-history-snapshot, and under `snapshot`, `trackedFileBackups`: each file's path (absolute, or from the folder the
// session ran in) with its copy's name in kClaudeCodeEditCopies/<session>/ (`backupFileName`, null before one's made).
extern NSString *const kClaudeCodeSnapshotLine;
// What Claude Code reads into a session as its instructions, with no tool's read of it recorded (its memory page,
// code.claude.com/docs/en/memory): kClaudeCodeInstructions in the session's folder and each one above it, up to but not
// /, and kClaudeCodeAgentsInstructions there only where none of those is in the folder or above it; the folders of more
// in each folder's kClaudeCodeProjectFolder (kClaudeCodeInstructionFolders), and in ClaudeDir; your own instructions
// (kClaudeCodeUserInstructions, in ClaudeDir); your organisation's (kClaudeCodeManagedInstructions); each project's
// memory, kClaudeCodeMemory in its folder of kClaudeCodeTranscripts; and its plugins' skills, agents and commands, in
// kClaudeCodePluginCache. An instruction file's `@path` imports (from its own folder, absolute, or ~) are read with it,
// kClaudeCodeImportHops deep. A subfolder's own instructions are read only once Claude reads a file there, which a
// checkout's own files cover.
extern NSArray<NSString *> *const kClaudeCodeInstructions;
extern NSArray<NSString *> *const kClaudeCodeAgentsInstructions;
extern NSArray<NSString *> *const kClaudeCodeInstructionFolders;
extern NSString *const kClaudeCodeUserInstructions, *const kClaudeCodeManagedInstructions;
extern NSString *const kClaudeCodeMemory, *const kClaudeCodePluginCache, *const kClaudeCodeProjectFolder;
extern const NSInteger kClaudeCodeImportHops;
// In a transcript, what Claude Code marks as yours though it isn't a message (checked with 2.1.304): a line you ran
// with `!` (kClaudeCodeShellInput) and what it printed, and a slash command's output (kClaudeCodeShellOutputs).
extern NSString *const kClaudeCodeShellInput;
extern NSArray<NSString *> *const kClaudeCodeShellOutputs;
// A conversation's titles, as records in its transcript (checked with 2.1.304): the one Claude Code gives it as it goes
// ({"type": "ai-title", "aiTitle": …}), and the name you give it with /rename ({"type": "custom-title", "customTitle":
// …}), which counts over it. The ai-title record comes again as the conversation goes on; the custom-title one may be
// written only when you /rename it (not checked), so it's found only in the part of the transcript that's read.
extern NSString *const kClaudeCodeAITitle;
extern NSString *const kClaudeCodeCustomTitle;
// What one conversation is made of, by its id (checked with 2.1.304): its transcript, <id>.jsonl in its project's
// folder of kClaudeCodeTranscripts; the folder beside it, <id>/, with its sub-agents' records and its tools' long
// outputs; and its copies of the files it edited, kClaudeCodeEditCopies/<id>/. Your typed prompts are one file shared
// by every session (kClaudeCodePromptHistory), and long pastes aren't tied to one. A session ends on SIGTERM as when
// its terminal's tab is closed, saving what it has. How long a session takes at most to end once sent SIGTERM, in
// seconds, before Sessions says it didn't.
extern const int kClaudeCodeEndWait;
// What clears all it keeps of a project's folder, its transcripts, copies and prompts among them, run as
// `claude purge <folder>` (checked with 2.1.304; `claude project purge` before 2.1.288). It asks before it deletes.
extern NSString *const kClaudeCodeClearCommand;
// The marks Claude Code puts on the commands an agent runs, as environment variables, separated by spaces. A command
// you set off from the panel (Deploy, making a worktree) is yours, so they're taken off it.
extern NSString *const kClaudeCodeAgentMarks;
// The marks a session's terminal tab title starts with while Claude works, one or the other, turned about once a second
// (checked with 2.1.302); the rest of the time it starts with ✳. One conversation can run in two tabs at once (a plain
// `claude --resume` of it while it still runs elsewhere, which its newer ways in refuse or make a copy), each
// registered with the same id, and with the same title but for this mark.
extern NSString *const kClaudeCodeTitleWorking;
// What a session's status in the registry means, as the rest of Whozmove takes it: idle (at its prompt), busy (Claude
// is working) or waiting (it asks you something); anything else as it is. Claude Code also says shell for a session at
// its prompt while a shell command Claude ran in the background still runs (checked with 2.1.304), which takes keys as
// idle does, so it's idle here. Closing a copy of a conversation still tells the two apart, as closing it would stop
// that command.
extern NSString *const kClaudeCodeStatusBackground;
NSString *ClaudeStatus(id status);
// A session's context window, in tokens: 1M for Opus and Fable 5.x and "[1m]" models, else 200k. A session using more
// than 200k can only have the larger window, so it gets 1M too. It's on the row (agent.window), which the page and
// the commands module read, so it's worked out here alone.
NSInteger ClaudeContextWindow(NSString *model, NSInteger tokens);
// When a session last edited files where its edits last landed, from its hook's record: when the hook noted it
// (`editedAt`), or, from an older hook that notes where but not when, the end of its last turn that changed something
// (`outcomeAt`, for an outcome the hook gives such a turn); else 0. It's on the row (workEditedAt), which the page and
// the commands module read, so it's worked out here alone. The row's own `editedAt` stays as the hook noted it, as
// the steps and Deploy go by whether it noted one.
double ClaudeEditedAt(NSNumber *editedAt, NSString *outcome, NSNumber *outcomeAt);
// The jobs a session runs in the background after its turn, as its Stop hook lists them (`background_tasks`, checked
// with 2.1.304 and 2.1.308), each with a type: Claude Code's own label for what kind of job it is. The ones that can
// change files in the session's folder (its agents, workflows and teammates) hold its next steps and Deploy, as an
// agent at work does; a shell command (kClaudeCodeJobShell) may run all day, as a dev server does, a monitor only
// watches and a cloud session works elsewhere, so they don't. A kind it adds later, or a job with no type, holds them
// until it's known, so nothing goes in while a job that may be changing files runs. Its own housekeeping (dream,
// auto-mode scan, memory import) isn't the session's work, so it isn't shown at all.
BOOL ClaudeJobHolds(NSString *type);
BOOL ClaudeJobShown(NSString *type);
extern NSString *const kClaudeCodeJobShell, *const kClaudeCodeJobAgent;
// Whozmove's own waits in a session's background are its ask-panel.sh asking the panel, not the session's work, so
// they aren't shown as its jobs. A session names the script as its skills give it, under the plugin's root as Claude
// Code writes it in them (kClaudePluginRootWord, checked with 2.1.304), or by the real path of the plugin's copy
// Claude Code runs: kClaudeCodePluginCache/<marketplace>/<plugin>/<version>/kWhozmoveAskScript. The words that may
// follow it are each module's own (BackgroundWaits, contracts/Module.h).
extern NSString *const kClaudePluginRootWord, *const kWhozmoveAskScript;
// What you type in a session to see its jobs in the background and stop one (checked with 2.1.304).
extern NSString *const kClaudeCodeStopJob;
// Each of a session's agents (kClaudeCodeJobAgent, by the id its job has) keeps a record of its own beside the
// session's transcript, in kClaudeCodeSubagents, which says once it has finished (Claude Code takes that off again when
// it carries the agent on).
NSString *ClaudeAgentRecordPath(NSString *transcript, NSString *agentId);
BOOL ClaudeAgentFinished(NSDictionary *record);
// Its voice mode (/voice, checked with 2.1.304): while you hold space, or between two taps, the session's own process
// records from the microphone (never whenever its terminal is in front: its prompt doesn't use voice's "focus" way),
// else a SoX recorder it starts, one of these programs (separated by spaces). It records nothing else anyone can read:
// no hook, no file.
extern NSString *const kClaudeCodeVoiceRecorders;
// How the registry marks a session started from a terminal (its `entrypoint`); Claude Desktop's are claude-desktop, and
// the SDK's sdk-cli.
extern NSString *const kClaudeCodeTerminalEntrypoint;
// Claude Code's command. A new session takes the id it's given (--session-id <uuid>, checked with 2.1.300), which is
// how the panel knows its row before it's listed, and its first message as its last argument.
extern NSString *const kClaudeCodeCommand;
// What carries an ended session on, under its own id (--resume <id>, checked with 2.1.302): only in the folder it ran
// in, as its transcript is kept with that folder's (elsewhere it says the conversation is from a different directory),
// and only while Claude Code still has its transcript, which it clears away after cleanupPeriodDays (30 by default). A
// session still running elsewhere gets a second process. A process's registry file follows it: rewritten in place with
// the new id when it goes on to another conversation (/clear, /resume of another), and with the new folder when the
// folder its conversation is kept with changes; and gone when it exits. `claude -p` registers as sdk-cli, never as a
// terminal's.
extern NSString *const kClaudeCodeResumeFlag;
// Claude Code's state file in the home folder. Among much else, it records each folder you've trusted Claude to work
// in, as projects[<folder>].<kClaudeCodeTrustKey>: Claude Code and Claude Desktop both read and write it there, and
// both ask once before working in a folder that neither it, its repo nor any folder above it has. While either writes
// the file, it holds a lock: a folder beside it (kClaudeCodeStateLock), which only one can make, waited for up to 15s
// and taken as abandoned once it's 10s old. A project they add starts from ClaudeCodeProjectDefaults().
extern NSString *const kClaudeCodeState;
extern NSString *const kClaudeCodeStateLock;
extern NSString *const kClaudeCodeTrustKey;
NSDictionary *ClaudeCodeProjectDefaults(void);

// Claude Code's command, `claude`: where its installers put it (folders in the home folder, then elsewhere), and where
// Claude Desktop keeps copies of its own, one folder per version, then one per build, each with the command at
// kClaudeDesktopCommandInBuild. A Mac with only Claude Desktop has only those.
NSArray<NSString *> *ClaudeCommandFolders(void);
extern NSString *const kClaudeDesktopCommands;
extern NSString *const kClaudeDesktopCommandInBuild;
// Asking it for your plan's usage: run with ClaudeUsageArguments it answers requests sent to its input, a JSON line
// each, and nothing else starts (no hooks, plugins or MCP servers) or is saved. kClaudeUsageRequest is the request.
NSArray<NSString *> *ClaudeUsageArguments(void);
extern NSString *const kClaudeUsageRequest;
// A question asked on the side of a session (checked with 2.1.304 against a stand-in API, on a virtual Mac): run with
// ClaudeAsideArguments in the session's own folder, it answers from a copy of its conversation (--resume with
// --fork-session, never saved), reading the question on its input as a stream-json user message, and writes stream-json
// lines, the last a `result`. Its request starts as the session's last one did, byte for byte up to the session's last
// cache mark, but for the billing line at the system prompt's start (it says sdk-cli where the session's says cli) and
// a few beta flags. It runs no tool: no settings files are read (so no allow rules, plugins, their hooks or MCP
// servers), and the one hook it has, passed on its command line, refuses every tool; one turn at most, so a tool it
// reaches for ends the run (error_max_turns). It doesn't compact (DISABLE_AUTO_COMPACT) and registers as an sdk-cli
// session in the session's folder while it runs. `model` is the session's, with "[1m]" where its context is the long
// one; `effort`, the session's, or nil. None (nil) for a session ClaudeAsideResumable refuses, however it's reached.
NSArray<NSString *> *ClaudeAsideArguments(NSString *sessionId, NSString *model, NSString *effort);
// Whether a session may be asked on the side: only one whose id is a UUID, as Claude Code's own are. It reads a word
// after --resume that looks like a flag ("--mcp-config=…") as that flag, so an id planted where sessions are recorded
// could otherwise start a program you never agreed to.
BOOL ClaudeAsideResumable(NSString *sessionId);
// The words that open a side question, so the copy answers it and doesn't carry the session's task on.
extern NSString *const kClaudeAsideLine;
// Whether it's signed in (it prints JSON with loggedIn), and signing it in.
NSArray<NSString *> *ClaudeAuthStatusArguments(void);
NSArray<NSString *> *ClaudeSignInArguments(void);
// The environment variables that point it at an API key or another provider instead of a Claude plan.
NSArray<NSString *> *ClaudeOtherAuthVariables(void);
// Where Claude Code is installed from, for the line's Get Claude Code.
extern NSString *const kClaudeCodeInstallPage;

// Whozmove's hooks as Claude Code's plugin (modules/claude-code/plugin/): the plugin and its marketplace are both
// kWhozmoveMarketplace, so `claude plugin` names it kWhozmovePlugin. Claude Code's own commands keep it, each checked
// with 2.1.302: one lists the plugins (PluginListArguments); the marketplace is added from a folder (adding it again
// when it's there already is fine: "already on disk") and the plugin installed from it; a new version in the folder
// is taken with a marketplace update, then a plugin update; and a plugin turned off is turned on again. A plugin added
// or changed reaches only the sessions that start after it: Claude Code loads its plugins as a session starts, and
// again when kReloadPluginsCommand is typed into it, which a running session takes, in a terminal or Claude Desktop,
// without restarting and without losing its cache (hooks don't change what Claude is sent). Its result starts with
// kReloadedResult ("Reloaded: 2 plugins · … · 5 hooks"); checked with 2.1.304. A reload that would change Claude's
// tools is held back ("Run /reload-plugins --force to apply."), as its next message would re-read the whole
// conversation; kForcedReloadCommand takes it anyway.
extern NSString *const kReloadPluginsCommand;
extern NSString *const kForcedReloadCommand;
extern NSString *const kReloadedResult;
extern NSString *const kWhozmovePlugin;
extern NSString *const kWhozmoveMarketplace;
// What Claude Code keeps of its plugins, as 2.1.304 keeps it, in ClaudeDir(kClaudeCodePlugins): the plugins put in and
// their versions (kClaudeCodeInstalledPlugins), and the marketplaces (kClaudeCodeKnownMarketplaces), neither written
// by listing them; whether each is on is in the settings files. None is documented, so when they were written only
// says when to list the plugins again, never how they stand.
extern NSString *const kClaudeCodePlugins;
extern NSString *const kClaudeCodeInstalledPlugins;
extern NSString *const kClaudeCodeKnownMarketplaces;
NSArray<NSString *> *PluginListArguments(void);
NSArray<NSString *> *PluginMarketplaceAddArguments(NSString *folder);
NSArray<NSString *> *PluginInstallArguments(void);
NSArray<NSString *> *PluginMarketplaceUpdateArguments(void);
NSArray<NSString *> *PluginUpdateArguments(void);
NSArray<NSString *> *PluginEnableArguments(void);


// The choices the details line offers, as [the value Claude Code takes, the name shown]. Models are the current
// family, by the id /model takes; efforts are Claude Code's levels; modes are in Claude's own order.
NSArray<NSArray<NSString *> *> *ModelChoices(void);
NSArray<NSArray<NSString *> *> *EffortChoices(void);
NSArray<NSArray<NSString *> *> *ModeChoices(void);

// How Claude Code's own program is told from any other, for what only one of its sessions may do (asking the panel in
// its own name, and holding AnswerFor's switches kept for a folder). Its native build is signed by Anthropic:
// kClaudeCodeSigningIdentifier, with Apple's Developer ID under kClaudeCodeTeam, as 2.1.316 is, whether from its own
// installer, Homebrew's cask, Claude Desktop's copy or npm, which installs that build as kClaudeCodeNpmProgram from
// kClaudeCodeNpmSignedSince on. Before that, npm's ran as Node (kClaudeCodeNodeProgram) with its kClaudeCodeNodeEntry
// among Node's arguments, until it set its title over them as it started (2.1.112 and those before it do), so only that
// path, or the session's own record in the registry, tells it. The system's short name for its process is
// kClaudeCodeProgram, kClaudeCodeNpmProgram, its installer's file named for its version (kClaudeCodeVersionName,
// "2.1.316"), or Node's.
extern NSString *const kClaudeCodeSigningIdentifier;
extern NSString *const kClaudeCodeTeam;
extern NSString *const kClaudeCodeNodeEntry;
extern NSString *const kClaudeCodeProgram;
extern NSString *const kClaudeCodeNpmProgram;
extern NSString *const kClaudeCodeNpmSignedSince;
extern NSString *const kClaudeCodeNodeProgram;
extern NSString *const kClaudeCodeVersionName;
