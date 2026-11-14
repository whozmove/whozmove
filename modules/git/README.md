# Git

Each row's next steps: the state of the checkout its session runs in (git status, its base branch, its pull request),
the steps its work has to take as git sees it (Commit, Push, Publish, Create PR), their icons on the row's work line,
Create PR's details with the branch it goes into, how the checkout's last code review went, where the branch stands while
commits wait to go, and the PRs a session made or worked on.

## Its pieces

- `app/GitModule.m`: its face for the core (contracts/Module.h): each row's checkout, read first, as what's counted
  of its changes goes by it; its PRs; and the page's messages. As the app launches it starts telling which checkouts
  changed (`CheckoutWatch`, in app/shared), and its print mode, `--print-watched`, shows what that tells. It lists Git
  for the panel's back, with Show Next Steps (`appEntries`), which waits, dimmed, until Apple's developer tools are in,
  as git does (the install module's card on that page says how they stand, with Install).
- `app/Checkouts.m`: each listed checkout's git status, base branch, new files, staged files and when its last commit
  was made, read on a queue of its own once something in the checkout has changed since its last read, as macOS's file
  system events tell it (`CheckoutWatch`), and those changes have settled: 2s after the latest, or 10s after the first
  while an agent keeps writing (`CheckoutSettled`), and 20s on while no session is at work there; and every half hour
  or so anyway (30 to 40 minutes, different for each checkout), in case an event was missed (`CheckoutReadDue`,
  `CheckoutQuietEvery`). A checkout macOS can't watch (on a network share) is read every 20s and 2s after activity, as
  are all of them in a print run. The repo's remotes and base branch are kept until GitHub's copies of its branches,
  its base branch, its packed refs or its config change. The branch's PR is asked of gh every 60s, only once the branch
  is on GitHub (`BranchOnRemote`), and never for its base branch (`BranchPRDue`).
- `app/NextSteps.m`: the steps, Commit and its ways (the changes view's ⌄ menu), Push, Publish and Create PR into a
  branch, each asked of the session's agent in its fixed words (`StepRequest`), through `Send` (parts/send), only when
  the checkout has it to take; a commit takes only what's staged when something is. And the branches GitHub's copy
  has, read for Create PR's details.
- `app/PullRequests.m` and `app/GitHub.m`: the PRs each session's agent recorded, and their state, from gh.
- `app/PRWakes.m`: a waiting session's pull request, for the waits module (contracts/Wake.h's `WakeSource`, which
  GitModule adopts): its branch's while open, else the newest open one it linked (the default branch has no looked-up
  pull request of its own, so there it's always one the session linked). While a session waits on it, it's
  asked of gh once a minute with its comments and reviews (`FetchPRActivity` in GitHub.m), Show Next Steps on or not;
  what came after the wait began wakes it: an approval, a review asking for changes, a merge or a close always (and a
  merge or close from a moment before the wait, as it's first read so), a comment or a commenting review only for a
  wait that asked for comments (`--comments`). A wait read back after a restart is watched on the address it began on.
  What it can't read says what puts it right ("gh may need you to sign in (gh auth login)"). Only each event's kind, who
  and when are kept (`PRActivityEvents`), never a word of a comment.
- `page/steps.js` (which steps a checkout has to take, `stepsOf`, what each says, how the checkout's last code review
  went, `reviewOf` and `reviewWords`, and where a branch stands while commits wait, `outgoingWords`: plain functions),
  `page/git-steps.js` (their icons on the work line, their words as they're pointed at, Create PR and its details,
  which a press on it opens at once, and
  the review, else where the branch stands, which opens the changes view on Outgoing through the reader, parts/pane) and
  `page/prs.js` (the pull requests and their details, and "+N more open"'s, listing the rest, which a press on it
  opens at once). `page/git.css` is those details' own styles, in a row's details
  ([parts/details](../../parts/details/README.md)). `module.json` lists them for tools/page.sh.

tests/rows.sh checks the rows' checkouts and PRs in its sample home, and tests/panel.sh the steps, the review and their
words. modules/git/tests/test.sh checks whether a branch keeps a PR of its own and when its look-up is due, never on the
base branch (`--print-pr-due`, pr-due.expected.txt); which checkouts each kind of change is told for (an edit, a new
file, staging, a commit, a submodule's, a remote's branch, the config), in a throwaway repo with a worktree, a submodule
and a link, whether branches are on a remote, and when a read is due; and what wakes a session waiting on a pull request
(`--print-pr-wakes`, from a made-up answer of gh's, pr-activity.json).

## Between the page and the app

- The page sends `gitStep` (`{sessionId, step, into}`: commit, push, publish, pr or draftPR pressed on a row, on Create
  PR's details or in the changes view; `into`, the branch a pull request goes into), `gitWays` (`{sessionId, x, y}`: the
  ways to commit, in a menu under the changes view's ⌄), `prBranches` (`{sessionId}`: the branches on GitHub, for
  Create PR's details) and `openPR` (`{url}`).
- The app calls `setPRBranches(sid, {base, branches})`.

## Rules

- A step never runs while the row's agent works or asks, or another session's agent works in the same checkout
  (`WhyStepsWait`, in parts/work): while the row's own agent is at work, the work line isn't there (the row
  part's `workHTML`), and while another is, the row says why when it's pressed.
- A step's words are fixed (`StepRequest`): the page only names the step, and a pull request's branch, which goes in its
  words only if it's the repo's default or one of its branches on GitHub as last read for its details.
- Git runs only for a checkout something may have changed in (`CheckoutWatch`), once those changes settle
  (`CheckoutSettled`), never more often than every 2s after a session's activity there, else 20s, and Whozmove's own
  reads never count as a change: each runs without optional locks and without a repo's file monitor (`GitReading`), so
  it writes nothing there.
- **Only someone who can change the repo wakes a session:** a comment or review counts only from an account GitHub
  marks `OWNER`, `MEMBER` or `COLLABORATOR`, so a stranger's comment never starts an unattended turn; and never from one
  gh's answer shows is a bot (a login ending in "[bot]", or an author whose type is Bot). A bot account added to the
  repo as a collaborator, with neither mark, still passes. The login reaches the session as the JSON's `by`, which its
  skill reads as someone else's words, and never the page.
- No git or `gh` runs before Apple's developer tools are installed (`RunGit`, `GhPath`): until then, git offers to
  install them each time it's run, and `gh` runs git.
- A review shows on the row only while it still speaks for the work there (`reviewOf`): the newest among the sessions
  in that checkout, on the branch it's on now. Once the checkout is edited after its last report, it says "Changed
  since the review"; it goes once anything is edited after a review with nothing left to fix, or after a commit that
  came since its last report. Its findings count as fixed only when the review reports them again, each with what
  became of it: Claude Code's /code-review does that only for the fixes it makes itself, so ones made later in the
  chat leave it saying what it found.
