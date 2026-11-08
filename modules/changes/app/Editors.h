// Editors: the editor a file opens in, at a line, chosen once (from the changes view, or Settings' Open Files With)
// and kept: the changes view's changed files open in it, and other modules' files, through FilesAtLines
// (contracts/Module.h), as Keys' do.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The editors on this Mac that Whozmove offers (KnownEditors), each {id, name}, and the chosen one's id
// (nil until one is chosen, or once it's gone): {choice, apps}, as the page gets it; with none of them on this Mac,
// `get`, the name of the one to get (GetEditor). Which are on this Mac is kept for half a minute, as it's asked for
// every second while Settings shows; main thread only.
NSDictionary *EditorChoices(void);
// With none of the editors on this Mac, opens the download page of the one EditorChoices names to get, in your web
// browser; NO, doing nothing, once one is there.
BOOL GetEditor(void);
// The names of every editor Whozmove offers, installed or not, in its order.
NSArray<NSString *> *KnownEditorNames(void);
// Keeps an editor as the one to open files in; nil forgets the choice.
void ChooseEditor(NSString *editorId);
// Opens a file in the chosen editor, at a line where the editor has a link for that. NO if none is chosen or it fails.
BOOL OpenInEditor(NSString *path, NSInteger line);
