// Text: small helpers for text the panel is given: a word for your shell, a terminal's colour codes taken out, a hash
// of bytes, a line's key, and words made one line.
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
