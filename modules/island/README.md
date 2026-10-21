# Island

Each row's island: the state of the checkout its session runs in (its changed files, the extra stage, its commits not
on GitHub yet, its pull request), the menu behind each stage with the ways to take its next step, the commits stage's
card, the extra stage's question, and the PRs a session made or worked on.

## Its pieces

- `app/IslandModule.m`: its face for the core (contracts/Module.h): each row's checkout, read first, as what's counted
  of its changes goes by it; its PRs; the checkouts' file lists, sent only when they change; and the page's messages. It
  lists Git for the panel's back, with Show Next Steps (`appEntries`).
- `app/Checkouts.m`: each listed checkout's git status, base branch, new files and staged files, and its extra stage,
  read on a queue of its own: every 20s, and within 2s of any activity by a session working there. The file lists and
  commit subjects its menus show are kept here, not sent with the rows.
- `app/Stages.m`: the extra stage (docs/reference/stages.md): the command a repo's git config names, run only once you've allowed
  it, your answers, and its own steps.
- `app/NextSteps.m`: the menu behind each stage, and the commits stage's card. A step asks the session's agent in its
  fixed words (`StepRequest`), through the core's `Send`.
- `app/PullRequests.m` and `app/GitHub.m`: the PRs each session's agent recorded, and their state, from gh.
- `page/stages.js` (its stages, `stagesOf`: plain functions), `page/island.js` (the capsule, its gauge and how it
  moves), `page/island-files.js` (the gauge's file lists), `page/island-steps.js` (the commits stage's card),
  `page/stage-trust.js` (the extra stage's question) and `page/prs.js` (the pull requests and their card). `module.json`
  lists them for tools/page.sh. Its styles are the core's (panel/styles).

tests/rows.sh checks the rows' checkouts, extra stages and PRs in its sample home, and tests/panel.sh the stages and
their labels.

## Between the page and the app

- The page sends `stageMenu` (`{stage, step, count, pr, sessionId, x, y}`: a stage pressed, whose menu opens there),
  `stageCard` (`{stage, step, count, sessionId}`: the commits stage pointed at, asked with `quiet` with every update),
  `stageStep` (`{sessionId, from, step}`: a step pressed on that card), `stageTrust` (`{sessionId, command, allow}`:
  your answer about an extra stage's command) and `openPR` (`{url}`).
- The app calls `setCheckoutFiles(files)` (each checkout's files by kind, the first 100 of each, sent only when they
  change) and `showStageCard(sid, card, step)`.

## Rules

- The extra stage runs only what you allowed, and only that exact command; a changed command is asked about again
  (CONTRIBUTING's rules, and docs/reference/stages.md).
- A step never runs while the row's agent works or asks, or another session's agent works in the same checkout
  (`WhyStepsWait`, in the core's Work.m); its menus still open, to show what each stage holds.
- A step's words are fixed (`StepRequest`), or come from an extra stage you allowed (its `ask` steps): the page only
  names the step.
