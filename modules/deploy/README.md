# Deploy

Deploy, a next step for any project: the command you've set for each project, the one Whozmove suggests before you
have, running it on this Mac, and how each folder's last run went; its round button on a row, its set-up card and its
menu.

## Its pieces

- `app/DeployModule.m`: its face for the core (contracts/Module.h): the round button's presses, the set-up card's
  messages, each row's project and folder kept fresh, and the print modes the tests check. It adds Show Deploy to Git's
  page on the panel's back (`appEntries`). Its round button sits among a row's next steps, so the switch is on only
  while they show, and turning it on turns Show Next Steps on too; Show Next Steps turned off leaves Deploy's own choice
  for when it's back on. Like Show Next Steps, it waits for Apple's developer tools.
- `app/Deploys.m`: the commands you've saved, by project, in Whozmove's own folder (`deploy.json`), never in the
  project; the one it suggests, from the project's own files; running one detached with a log; each folder's last run.
- `app/DeployMenu.m`: the menu behind the round button: what it runs, changing or forgetting that, passing on it,
  stopping a run, and the last run's log.
- `page/deploys.js` (whether a row has the round button, how it looks, and the set-up card: plain functions) and
  `page/deploy-row.js` (the button, the line and the card on a row). `module.json` lists them for tools/page.sh.

tests/rows.sh checks what it suggests for sample projects and how their last runs read (`--print-deploys`), and what
the set-up card is told sample commands really run (`--print-deploy-checks`).

## Between the page and the app

- The page sends `deploy` (`{sessionId}`), `saveDeployCommand` (`{sessionId, command, deployNow}`), `checkDeployCommand`
  (`{sessionId, command}`: a command on the set-up card, about to be confirmed) and `stepMenu` (`{step: "deploy",
  sessionId, x, y}`: its menu).
- The app calls `setDeploys({projects, folders})`, `openDeploySetup(sid, then)` and `deployChecked(sid, {command,
  production, runs, more})`.

## Rules

- Deploy runs only what you confirmed, through the set-up card's two steps, and only when you press it; a suggestion
  never runs by itself, and none is made that looks as if it could reach production (CONTRIBUTING's rules).
- It never starts while the row's agent works or asks, or another session's agent works in the same folder
  (`WhyStepsWait`, in the core's Work.m).
