// Signature: who signed a running program, from the copy of its signature the system keeps while it runs.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// What the system says of a running process's code signature, never what the process says of itself:
// {valid, identifier, team, developerID, why}. `valid`: the system checked the code as it was loaded and keeps checking
// it as it runs. `identifier` and `team` are what the signature names. `developerID`: the signature is a developer's,
// certified by Apple: its certificates lead, each signed by the next, to Apple's own root (kept here by its
// fingerprint, so nothing is looked up), its leaf is a Developer ID Application certificate whose team is `team`, both
// were in date when it signed, and what it signed is the code the system runs. `why` says what failed. Nil for a process
// that has ended or isn't yours. It reads only the system's copy, so it holds for a program whose file has gone since it
// started (an update deletes the version that was running).
NSDictionary *RunningSignature(pid_t pid);
