# Git

Each row's next steps: the state of the checkout its session runs in (git status, its base branch, its pull request),
the steps its work has to take as git sees it (Commit, Push, Publish, Create PR), their icons on the row's work line,
Create PR's card with the branch it goes into, how the checkout's last code review went, where the branch stands while
commits wait to go, and the PRs a session made or worked on.

## Its pieces

- `app/GitModule.m`: its face for the core (contracts/Module.h): each row's checkout, read first, as what's counted
  of its changes goes by it; its PRs; and the page's messages. It lists Git for the panel's back, with Show Next Steps
  (`appEntries`).
- `app/Checkouts.m`: each listed checkout's git status, base branch, new files, staged files and when its last commit
  was made, read on a queue of its own: every 20s, and within 2s of any activity by a session working there.
- `app/NextSteps.m`: the steps, Commit and its ways (the changes view's ⌄ menu), Push, Publish and Create PR into a
  branch, each asked of the session's agent in its fixed words (`StepRequest`), through the core's `Send`, only when
  the checkout has it to take; a commit takes only what's staged when something is. And the branches GitHub's copy
  has, read for Create PR's card.
- `app/PullRequests.m` and `app/GitHub.m`: the PRs each session's agent recorded, and their state, from gh.
- `page/steps.js` (which steps a checkout has to take, `stepsOf`, what each says, how the checkout's last code review
  went, `reviewOf` and `reviewWords`, and where a branch stands while commits wait, `outgoingWords`: plain functions),
  `page/git-steps.js` (their icons on the work line, their words as they're pointed at, Create PR and its card, and
  the review, else where the branch stands, which opens the changes view on Outgoing through the core's reader) and
  `page/prs.js` (the pull requests and their card). `module.json` lists them for tools/page.sh. Its styles are the
  core's (panel/styles).

tests/rows.sh checks the rows' checkouts and PRs in its sample home, and tests/panel.sh the steps, the review and their
words.

## Between the page and the app

- The page sends `gitStep` (`{sessionId, step, into}`: commit, push, publish, pr or draftPR pressed on a row, on Create
  PR's card or in the changes view; `into`, the branch a pull request goes into), `gitWays` (`{sessionId, x, y}`: the
  ways to commit, in a menu under the changes view's ⌄), `prBranches` (`{sessionId}`: the branches on GitHub, for
  Create PR's card) and `openPR` (`{url}`).
- The app calls `setPRBranches(sid, {base, branches})`.

## Rules

- A step never runs while the row's agent works or asks, or another session's agent works in the same checkout
  (`WhyStepsWait`, in the core's Work.m): while the row's own agent is at work, the work line isn't there (the core's
  `workHTML`), and while another is, the row says why when it's pressed.
- A step's words are fixed (`StepRequest`): the page only names the step, and a pull request's branch, which goes in its
  words only if it's the repo's default or one of its branches on GitHub as last read for the card.
