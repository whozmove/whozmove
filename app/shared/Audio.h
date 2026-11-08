// Audio: what the Mac's sound is doing, as CoreAudio says, which needs no permission to read (not even the
// microphone's): whether a microphone is in use, which processes are recording from one, and whether a process is
// playing sound. Plain functions, any app's.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Whether any input device (a microphone, built in or not) is running for some app now: on a device that's one for
// sound in and out (a headset, an audio interface), that's its sound playing too.
BOOL MicrophoneInUse(void);
// The processes recording from an input device now, by pid; nil before macOS 14, which can't tell who.
NSArray<NSNumber *> *MicrophoneRecorders(void);
// Whether the process `pid` is playing sound on this Mac now; NO before macOS 14, which can't tell.
BOOL ProcessPlaysSound(pid_t pid);
// Calls `changed` on `queue` whenever an input device starts or stops running for some app, or devices come or go,
// and from macOS 14 whenever a process starts or stops recording, or processes come or go, until the block it returns
// is called.
dispatch_block_t ListenToMicrophones(dispatch_queue_t queue, dispatch_block_t changed);
