# op-keepalive — 1Password session keepalive for Codespaces

Keeps the 1Password CLI (`op`) session alive in a Codespace so the Copilot dev
stack (specifically **copilot-api**) always boots and runs with valid secrets.

## Why this exists

`copilot-api` resolves its secrets **once at startup** via `op run --env-file=.env`,
including the GitHub token it uses to fetch PR data. The `op` session expires after
~30 min of inactivity and whenever the Codespace suspends/resumes. If `copilot-api`
(re)starts while the session is expired, it comes up with no valid token — PR
fetches return **401** and streamed PR reviews get **garbled** (a 401 mid-stream
makes the agent retry and splice two generations together).

This daemon refreshes the `op` session on a cadence under the idle timeout and,
when it recovers a lapsed session, restarts `copilot-api` so the new process
re-resolves its secrets.

## Files

- `script/op-keepalive` — the daemon (and `--status` / `--once` helpers).
- `script/codespaces-post-start` — launcher invoked by the github devcontainer's
  post-start hook on every container start/resume. Idempotent (won't double-start).

## How it runs automatically

GitHub Codespaces clones this dotfiles repo to
`/workspaces/.codespaces/.persistedshare/dotfiles/`. The "Base Dotcom Development"
(github) devcontainer's `post-start-command.sh` looks for and runs
`dotfiles/script/codespaces-post-start` on every start — which launches the daemon.

So to get this in **every future Codespace**, just commit these files to this repo:

```sh
cd /workspaces/.codespaces/.persistedshare/dotfiles
git add script/op-keepalive script/codespaces-post-start script/README-op-keepalive.md
git commit -m "Add op-keepalive: keep 1Password session alive for Copilot dev"
git push
```

It needs the `ONEP_PASSWORD` and `ONEP_SECRET_KEY` Codespace secrets (the same ones
the Copilot dev setup uses) to be set at https://github.com/settings/codespaces.

## Recreating it manually (a Codespace not using these dotfiles)

1. Copy `script/op-keepalive` somewhere persistent and make it executable
   (`chmod +x op-keepalive`).
2. Launch it once (it self-guards against duplicates):
   `nohup /path/to/op-keepalive >/dev/null 2>&1 &`
3. To make it survive restarts, invoke it from any hook that runs on container
   start — e.g. your dotfiles `codespaces-post-start`, or append the `nohup` line
   to a startup script.

## Operating it

```sh
script/op-keepalive --status   # is the daemon running? is op valid in THIS shell?
script/op-keepalive --once      # one ensure-signed-in pass, then exit
tail -f /tmp/op-keepalive.log   # daemon activity / recovery log
```

Env knobs:

- `OP_KEEPALIVE_INTERVAL` — seconds between refreshes (default `1200` = 20 min).
- `OP_KEEPALIVE_LOG` — log file path (default `/tmp/op-keepalive.log`).
- `OP_KEEPALIVE_NO_RESTART=1` — keep the session warm but never restart copilot-api.

## Notes / gotchas

- **Per-process `op` sessions:** `op signin` sets a session token in the calling
  process's env, so `--status` from a fresh shell may report the session INVALID
  even while the long-running daemon holds a valid one. What matters is that
  `copilot-api` re-auths itself when the daemon restarts it.
- **copilot-api restart is dotcom-specific:** it only fires when `/workspaces/github`
  exists and `overmind` is available; in other Codespaces that step is skipped, and
  the daemon just keeps the `op` session warm.
- **Do not add `set -u`** to these scripts — oh-my-bash's prompt startup leaks an
  unbound `SCM` variable that would abort `-u` scripts. (A stray
  `bash: SCM: unbound variable` line on the prompt is oh-my-bash, not this tool.)
