// Editors: the editor a changed file opens in, chosen once (from the changes view, or the pawn menu's Open With) and
// kept.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The editors on this Mac that Whozmove offers (KnownEditors), each {id, name}, and the chosen one's id
// (nil until one is chosen, or once it's gone): {choice, apps}, as the page gets it.
NSDictionary *EditorChoices(void);
// Keeps an editor as the one to open files in; nil forgets the choice.
void ChooseEditor(NSString *editorId);
// Opens a file in the chosen editor, at a line where the editor has a link for that. NO if none is chosen or it fails.
BOOL OpenInEditor(NSString *path, NSInteger line);
