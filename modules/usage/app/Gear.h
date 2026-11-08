// Gear: how many sessions work at once on your plan, and how many it can carry to the week's end, worked out live from
// the usage card's percents and the time left, as a thermostat would: how much of the week a working session-hour took
// lately, measured between usage answers while Whozmove watched. Only your press on a seat of the card's sets your gear.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// The lowest gear and the highest.
extern const NSInteger GearLowest, GearHighest;

// What the reads of the rows have added up, as running totals: the hours of each session working (a session working
// for an hour is one), the hours Whozmove was reading, and the hours any session worked; and when it last read, in
// seconds since 1970. Each sample keeps them, so they carry on from the last after a restart.
typedef struct {
    double sessionHours, watchedHours, workHours;
    NSTimeInterval lastRead;
} GearTotals;

// The sessions among `rows` working now (SessionWorking), of those `ours` says use the plan the card shows, in the
// order of their ids.
NSArray<Row *> *GearCounted(NSArray<Row *> *rows, BOOL (^ours)(Row *row));
// A read at `now` with `working` sessions at work: the time since the last read added to the totals, or nothing when
// that's over 10 seconds (asleep, quit), as nobody was watching then.
void GearRead(GearTotals *totals, NSUInteger working, NSTimeInterval now);
// A gear as it's kept in the preferences, or as a press on a seat asks for it, or nil when it isn't a whole number from
// the lowest to the highest (JSON's true isn't one): a value edited by hand counts as no gear set, and a press that
// says no seat sets none.
NSNumber *GearOf(id value);
// The samples as read from usage-gear.json, only records kept, each field a number or 0, so a file edited by hand can't
// stop the measuring.
NSArray<NSDictionary *> *GearSamplesFrom(id samples);
// The totals the last sample kept, carried on from.
GearTotals GearTotalsFrom(NSArray<NSDictionary *> *samples);
// A usage answer in state "ok", with the totals as it came, as a sample: {at, week: {used, resetsAt}, session: {…},
// sessionHours, watchedHours, workHours}, numbers only (seconds since 1970, a reset in ms since 1970, as answered).
NSDictionary *GearSample(NSDictionary *usage, GearTotals totals, NSTimeInterval now);
// The samples kept: those before, with the new one, less those over 3 days old.
NSArray<NSDictionary *> *GearKeep(NSArray<NSDictionary *> *samples, NSDictionary *sample, NSTimeInterval now);
// Whether the session is at its limit, as the card's wait has it (usageView's in page/usage.js, its twin): at 100%,
// resetting later, and extra usage off.
BOOL GearAtLimit(NSDictionary *usage, NSTimeInterval now);
// What the samples measure, at the gear set (nil while unset), from the last "ok" answer: {recommended (nil while the
// week can't be measured), notYet (nil, or {reason: rise|hours|watched, rise, hours}), bound (week|session, which
// window sets the recommendation), forecast ({gear, ends, runsOutAt, sessionRunsOutAt, resetsAt}, at the gear set or
// else the recommended one), limit, checkedAt}. Worked out at each answer and each press, never on the clock alone.
NSDictionary *GearMeasured(NSArray<NSDictionary *> *samples, NSDictionary *usage, NSNumber *gear);
// The counts for the facts, from the sessions working: {atWork, counted (their ids), over (the ids beyond the gear,
// those whose turn began last first; none while no gear is set), room (how many more the gear lets work, never below
// 0; NSNull while no gear is set)}.
NSDictionary *GearCounts(NSArray<Row *> *counted, NSNumber *gear);
// What a lead session of yours may read, in gear.json: {gear, atWork, recommended, checkedAt, changedAt, updatedAt},
// no session's id or name.
NSDictionary *GearFileFor(NSDictionary *facts, NSNumber *changedAt, NSTimeInterval now);
// gear.json while Usage Gear is off: {off: true, updatedAt}, holding no gear, so a lead never takes a file not written
// yet for the gear turned off.
NSDictionary *GearOffFile(NSTimeInterval now);
// Whether gear.json, as read, is the off record: its `off` is JSON's true itself, never the number 1.
BOOL GearFileIsOff(NSDictionary *file);
// How many sessions a lead may have working at once by its gear.json, `file` as read (nil for none, or one that can't
// be read): NSNull for no limit (the off record), the gear for a whole number from the lowest to the highest, and 0 for
// anything else, so a missing file never means no limit. The app reads gear.json back only to see whether it holds
// the off record, never to take a gear from it: this is the lead's reading, which `--print-gear` checks.
id GearFileLimit(NSDictionary *file);
// Writes `json` to the file `name` in Whozmove's folder, readable only by you; a write that fails is logged.
void GearWrite(NSString *name, id json);
// Takes away what the gear keeps: the gear you set and when (`gear`, `gearChangedAt`) from `preferences`, and
// usage-gear.json and gear.json from Whozmove's folder, then writes gear.json's off record (GearOffFile at `now`): the
// gear turned off in Settings keeps nothing measured.
void GearForget(NSUserDefaults *preferences, NSTimeInterval now);
// `Whozmove --print-gear <cases.json>`: each case through the functions above; it refuses your own home, as it writes.
int PrintGear(NSArray<NSString *> *arguments);
