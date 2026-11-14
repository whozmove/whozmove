// What a side chat keeps for one session, as plain functions over its record: {pid, processStart, says}, `says` being
// your words, oldest first, each {at, words, line, opening, state, how, doneAt, late, repliedAt, why, way, permission,
// where}. The page draws each state (side-chat-words.js); the module keeps the record and moves it on
// (SideChatModule.m).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The most you may send at once, the words that open yours included, as Send takes them.
extern const NSUInteger SideChatMost;
// The states words are back in your box in: taken back, refused, their session ended first, Whozmove restarted
// first, or not sent at all (notSent: the words that open them where the chat is drawn weren't one plain line). The
// page puts them back once, and says so (sideChatPutBack), and then they go from the record.
extern NSArray<NSString *> *const SideChatBackStates;

// The most the words that open yours may have, when the chat is drawn in another view that names what they're about
// (One Task's task, its step).
extern const NSUInteger SideChatMostOpening;
// Words that open yours, as the view the chat is drawn in gives them: "" for none, the same words when they're one
// plain line of at most SideChatMostOpening, starting with a letter and ending in one space, else nil (refused whole).
NSString *SideChatOpening(NSString *opening);
// The line words said go in as (`line`, kept whole as they were said: the words that open them, `opening`, then your
// own, `words`, which are what the chat shows and what comes back to your box). What's sent, sent again, copied, and
// what their reply is found by, never the words alone; words kept before the line was, by their words.
NSString *SideChatLine(NSDictionary *said);
// What words sent from a place go as (`words`, your own, with `opening`, the words that open them there; or a side
// question sent with Send's words, `aside`, as the app kept it, with its own opening): {words, opening, line} to go,
// {words, why} to put back in your box when they can't (not one plain line, or too long with them), or nil with no
// words at all.
NSDictionary *SideChatToGo(NSString *words, NSString *opening, NSDictionary *aside);
// What Copy and Go puts on the clipboard: words said (`said`) as they went in, or words from the box with the words
// that open them there, on one line; nil when those aren't one plain line.
NSString *SideChatCopyLine(NSDictionary *said, NSString *words, NSString *opening);
// Send's progress for words (`change`), with the way past a refusal Send can't give itself: for Claude Desktop without
// the Accessibility permission (`desktop`, `mayControl`), its pane (SideChatAccessibilityWay, `permission`).
extern NSString *const SideChatAccessibilityWay;
NSDictionary *SideChatRefusedWay(NSDictionary *change, BOOL desktop, BOOL mayControl);
// The record with your words added at `at` (ms since 1970), held, for the process `pid` that started at `started`,
// with the words that open them (`opening`, from SideChatOpening, "" or nil for none).
NSDictionary *SideChatRecordSaid(NSDictionary *record, NSString *words, NSString *opening, double at, pid_t pid,
                                 long long started);
// How far the words said at `at` have got, from Send's progress (sayBetweenSteps:): their state, when (`doneAt`) and
// how they were read, or why they didn't go in (`permission` when the way past is Accessibility's pane). Words read
// stay read, words you copied stay copied, and words back in your box stay there.
NSDictionary *SideChatRecordProgress(NSDictionary *record, double at, NSDictionary *change);
// Words taken back: out of it (takenBack, back in your box) when `late` is nil, else how far they'd got, which the
// page says.
NSDictionary *SideChatRecordTakeBack(NSDictionary *record, double at, NSString *late);
// Held words you copied to paste yourself (Copy and Go), at `now`: copied, as Send no longer holds them, so they go in
// only as you paste them. Only held words are copied this way.
NSDictionary *SideChatRecordCopied(NSDictionary *record, double at, double now);
// Words read, answered (replied, `repliedAt`) or not (noReply, its turn ended with no words for you).
NSDictionary *SideChatRecordReplied(NSDictionary *record, double at, BOOL replied, double repliedAt);
// After Whozmove restarted: words that hadn't gone in (held, typing or handed to its hook) are back in your box.
NSDictionary *SideChatRecordRestarted(NSDictionary *record);
// Words the page has put back in your box, gone from the record.
NSDictionary *SideChatRecordPutBack(NSDictionary *record, double at);
// The words said at `at`, as kept, or nil.
NSDictionary *SideChatRecordAt(NSDictionary *record, double at);

// What you asked a session on the side, kept in memory only: its asides, oldest first, each {at, question, state,
// text, answer, answeredAt, remembered, resetsAt, signIn, sentAt, step, opening}, `state` asking until its agent
// answers (AgentAside's states), `step` what its agent last said the answer is doing while it's asked (AgentAside's
// `step`), `opening` the words that opened it where it was asked, `text` the answer as the app read it, `answer` the
// same cut into prose and code,
// `remembered` how many of the answered ones before it the side conversation knew, `sentAt` when one it couldn't
// answer was sent to the session the normal way. One question at a time.
// The asides with a question asked at `at`, kept with the words that opened it where it was asked (`opening`, "" or nil
// for none), or nil while one is still being answered.
NSArray<NSDictionary *> *SideChatAsideAsked(NSArray<NSDictionary *> *asides, NSString *question, NSString *opening,
                                            double at);
// A side question as its agent was asked it, and as Ask Again, Send's words and Copy the Question take it: the words
// that opened it, then the question.
NSString *SideChatAsideLine(NSDictionary *aside);
// The asides with the one asked at `at`, while it's still being asked, on its new step (`step`, kept to one line of
// SideChatStepMost characters); as they were for any other, or for no words.
extern const NSUInteger SideChatStepMost;
NSArray<NSDictionary *> *SideChatAsideToStep(NSArray<NSDictionary *> *asides, double at, NSString *step);
// The asides with a question that couldn't be asked once you'd pressed (notAsked), so it isn't lost.
NSArray<NSDictionary *> *SideChatAsideNotAsked(NSArray<NSDictionary *> *asides, NSString *question, NSString *opening,
                                               double at);
// The asides with the one asked at `at` answered, as its agent's `answer` says, at `now`; a state it doesn't know is
// noAnswer, and so is answered with no words. Only a question still being asked takes an answer, and its step goes. Its words are as
// the agent cut them (AgentAside: 16,384 characters at most).
NSArray<NSDictionary *> *SideChatAsideAnswered(NSArray<NSDictionary *> *asides, double at, NSDictionary *answer,
                                               double now);
// The aside asked at `at` while it may still be sent the normal way (Send's words), or nil: never one still being
// asked, nor one answered, nor one already sent.
NSDictionary *SideChatAsideSendable(NSArray<NSDictionary *> *asides, double at);
// The asides with the one asked at `at` marked sent the normal way at `sentAt`, if it may be (SideChatAsideSendable).
NSArray<NSDictionary *> *SideChatAsideSent(NSArray<NSDictionary *> *asides, double at, double sentAt);
// The asides with the one asked at `at` no longer sent: the words it went as were taken back, or are back in your box.
NSArray<NSDictionary *> *SideChatAsideUnsent(NSArray<NSDictionary *> *asides, double at);
// The asides as the page is told them: without the answer's text as read and the sign-in command, which only the app
// copies.
NSArray<NSDictionary *> *SideChatAsidesShown(NSArray<NSDictionary *> *asides);
// The side questions answered before the one asked at `at`, as the agent is told them (AgentAside's `earlier`):
// oldest first, each {question, text, at}, only those answered with words.
NSArray<NSDictionary *> *SideChatAsidesEarlier(NSArray<NSDictionary *> *asides, double at);
// The aside asked at `at`, or nil.
NSDictionary *SideChatAsideAt(NSArray<NSDictionary *> *asides, double at);
