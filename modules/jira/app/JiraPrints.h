// JiraPrints: Jira's print run, for its tests (modules/jira/tests): Whozmove --print-jira facts prints the plain
// functions (keys and links, the search's JQL, the kinds, the sign-in's PKCE, the card for each state); --print-jira
// answers <folder> reads recorded answers into tickets; and --print-jira talk runs a whole sign-in and every call
// against a stand-in for Atlassian on 127.0.0.1 (WHOZMOVE_JIRA_SERVER, in a throwaway home only), the run itself
// acting as the browser, so nothing reaches Atlassian and nothing opens.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

int PrintJira(NSArray<NSString *> *arguments);
// For the tests, in a throwaway home: marks the Keychain's stand-in entry under `service` as one other apps can read.
void JiraStandInOpenAccess(NSString *service);
// For the tests, in a throwaway home: marks it as one macOS would ask about, with the build that kept it set to an
// older one (`newBuild`, as a new build finds it), or left as it was (as a look-alike's quiet rewrite would leave it).
void JiraStandInAsks(NSString *service, BOOL newBuild);
