// Log: the panel's log file, panel.log in Whozmove's own folder.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Log.h"
#import "Files.h"

// Lines come from the main thread and from the queues that read alongside it, so they're written one at a time.
static NSObject *Turn(void) {
    static NSObject *turn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        turn = [NSObject new];
    });
    return turn;
}

// Appends to ~/Library/Application Support/Whozmove/panel.log (unified-log NSLog output isn't retained
// for this app). A write that fails is let go: the log never stops the panel.
static void Append(NSString *text) {
    NSString *path = AppDir(@"panel.log");
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (attrs.fileSize > 256 * 1024) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    if (![NSFileManager.defaultManager fileExistsAtPath:path])
        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    [fh seekToEndReturningOffset:nil error:nil];
    [fh writeData:[[NSString stringWithFormat:@"%@  %@\n", NSDate.date, text] dataUsingEncoding:NSUTF8StringEncoding]
            error:nil];
    [fh closeAndReturnError:nil];
}

void PanelLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    @synchronized (Turn()) {
        Append(text);
    }
}

// For something that can go wrong every second: logged when it starts, not every time.
void LogProblem(NSString *text) {
    static NSString *last;
    @synchronized (Turn()) {
        if ([text isEqualToString:last]) return;
        last = text;
        Append(text);
    }
}
