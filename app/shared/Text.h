// Text: small helpers for text the panel is given: a word for your shell, a terminal's colour codes taken out, a hash
// of bytes, a line's key, words made one line (plain, for a session), a reason's first letter, whether an id is plain,
// whether text holds a secret, and a session's reply cut into prose and code.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Text as one word for your shell, whatever it holds: in single quotes, with any single quote in it closed, escaped
// and reopened.
NSString *ShellWord(NSString *text);
// Text without the colour codes a terminal program writes (ESC [ … m); nil for nil.
NSString *WithoutColours(NSString *text);
// FNV-1a over the bytes up to the first zero byte (none for NULL). NSString's own hash reads only parts of a long
// string, so two long ones that differ in the middle would look the same.
uint64_t HashBytes(const char *bytes);
// A line as the edits know it, to tell later whose a line is: its text without the spaces around it, as a number. Nil
// for a blank line. The agent's edits and the changes git sees are keyed the same way, so they can be matched.
NSNumber *LineKey(NSString *line);
// Words as one line, to go into a session as a message typed once: each line break a space, the ends trimmed, and cut
// at `most` characters.
NSString *OneLine(NSString *words, NSUInteger most);
// Words as one line that hides nothing and acts on nothing in a terminal: each run of line breaks becomes a space;
// control, invisible and turning characters (Unicode's format characters) go; the ends are trimmed, and it's cut at
// `most` characters. What goes into a session as words typed once.
NSString *PlainOneLine(NSString *words, NSUInteger most);
// A reason at the start of a sentence, its first letter a capital, and as the rest of one, after a colon: its first
// letter small, unless its first word is Whozmove or has a capital past its first letter (macOS, PAY-142). So a reason
// starts with a plain word wherever it may be said, never another name. Nil for nil.
NSString *AtSentenceStart(NSString *reason);
NSString *AfterColon(NSString *reason);
// Whether an id from outside (a session's, one the page made up, a key another app hands out) is only letters, digits
// and dashes, and at most `most` of them: so it can name a file in a folder and nothing else, or go in a header.
BOOL IsPlainId(NSString *text, NSUInteger most);
// Whether `text` holds something shaped like a key, a token or a private key: the common services' own shapes, each
// known by how it starts (sk-, ghp_, AKIA, xoxb-, sk_live_, AIza, GOCSPX-, glpat-, npm_, hf_, SG., Bearer, a private
// key's first line), so ordinary words never count. What the panel shows and keeps from outside is checked with it,
// as the panel never holds one.
BOOL LooksLikeSecret(NSString *text);
// A session's reply cut into what's read and what's copied: its prose, each {prose}, and each code fence (``` or ~~~, a
// fence left open running to the end), {code, lang}, exactly as written between its fences, in the order they came.
// Empty prose is left out. Nothing in it is ever run: a fence's words are only shown and copied.
NSArray<NSDictionary *> *ReplyParts(NSString *reply);
