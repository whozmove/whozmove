// Printing: the print runs' JSON.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Printing.h"
#import "Core.h"
#import "Modules.h"
#import "Rows.h"
#import "Files.h"

int PrintJSON(id object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (!json) return 1;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    return 0;
}

NSArray<Row *> *ReadRows(Core *core) {
    __block NSArray *rows = nil;
    [core.rows read:^(NSArray<Row *> *read) {
        rows = read ?: @[];
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!rows && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return rows ?: @[];
}

// Read three times: what the first starts (the transcripts' reads, the checkouts' git) shows in the second, and whose
// each change is can be worked out only once the transcripts have said what each session edited, for the third.
NSArray<Row *> *SettledRows(Core *core) {
    MachineFilesInHome = YES;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    for (int read = 0; read < 2; read++) {
        ReadRows(core);
        while (deadline.timeIntervalSinceNow > 0 && core.modules.working)
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return ReadRows(core);
}
