# PR dev-merge cron

Keeps my **non-WIP open PRs** (base `dev`) across a configured set of repos
continuously merged up to date with `dev`, rebuilt, and pushed — fully
automatically, with no Claude session required. Runs as a macOS **launchd**
LaunchAgent.

Lives in this dotfiles repo (`forge-tools` stow package) and is stowed onto the
system via `just stow`. It has nothing to do with Claude — it just used to be
parked under `~/.claude/` before it moved here.

## Repos covered

Set in `REPO_DIRS` at the top of the script:

- `~/_dev/chime-disputes`
- `~/_dev/chime_non_reg`

Each must be a sand repo with a `treehouse.toml` pool. Add a repo by appending
its path to the array — nothing else to change.

## What it does, per PR (every run)

For each open PR I authored against `dev` whose title does **not** start with `WIP:`:

1. **Pick a worktree.** Prefer an existing git worktree already checked out to the
   PR branch *if it is clean and not ahead of origin* (operates in place). Otherwise
   lease an isolated `treehouse` worktree. A dirty/ahead existing worktree is never
   touched or reset — it falls back to a leased one. The leased worktree is returned
   at the end of each repo (each repo has its own treehouse pool).
2. **Merge `origin/dev`.**
   - **Clean merge, or conflicts only in `generated/` + `_build/`** → take dev's side
     on those, run `sand build`, commit **all** build output, and push a
     `chore: merge dev + sand build [auto-cron]` merge commit.
   - **Conflict in a source file or `.sand/summaries/`** (which `sand build` does not
     regenerate) → abort and post a PR comment. `sand build` failing also aborts +
     comments (so a structurally broken merge never gets pushed).
   - **Already up to date** → skip.

### Comment de-duplication
A per-PR flag file `~/.local/state/pr-dev-merge-cron/<repo-slug>_<num>.conflict` means
"I already commented and nothing has merged since." It is **set** when a conflict
comment is posted and **cleared** the moment a merge succeeds *or* the PR is found
already up to date with `dev`. So a still-conflicting PR is left alone until real
progress happens; a conflict that reappears *after* a successful merge is flagged
again. The flag is namespaced by repo slug, so the same PR number in two repos can't
collide.

## Files

| Path | Purpose |
|---|---|
| `forge-tools/.local/bin/pr-dev-merge-cron.sh` (repo) → `~/.local/bin/pr-dev-merge-cron.sh` (stowed) | The standalone script (all logic). |
| `forge-tools/Library/LaunchAgents/com.withforge.pr-dev-merge-cron.plist` (repo) → `~/Library/LaunchAgents/…` (stowed) | launchd schedule. |
| `~/.local/state/pr-dev-merge-cron/cron.log` | Run log (self-rotating; **not** in git). |
| `~/.local/state/pr-dev-merge-cron/cron.log.N.gz` | Rotated archives (up to 5). |
| `~/.local/state/pr-dev-merge-cron/cron.boot.log` | launchd's own stdout; only catches catastrophic pre-exec errors (normally empty). |
| `~/.local/state/pr-dev-merge-cron/<repo-slug>_<num>.conflict` | Per-PR "already flagged" markers. |

## Schedule

Fires every **2 min** (`StartInterval` 120s). Survives restarts/logout; no expiry.
Runs in the GUI session so `gh` can read its token from the login keychain.

## Managing it

```sh
UID_=$(id -u)   # 502 on this machine
PLIST=~/Library/LaunchAgents/com.withforge.pr-dev-merge-cron.plist

# watch activity
tail -f ~/.local/state/pr-dev-merge-cron/cron.log

# run on demand (writes to cron.log)
launchctl kickstart gui/$UID_/com.withforge.pr-dev-merge-cron

# run manually with output on the terminal (no launchd)
PRCRON_STDOUT=1 bash ~/.local/bin/pr-dev-merge-cron.sh
# ...or preview without committing/pushing/commenting:
DRY_RUN=1 PRCRON_STDOUT=1 bash ~/.local/bin/pr-dev-merge-cron.sh

# pause / resume
launchctl bootout   gui/$UID_ "$PLIST"
launchctl bootstrap gui/$UID_ "$PLIST"

# status
launchctl print gui/$UID_/com.withforge.pr-dev-merge-cron | grep -E 'state|program'

# stop permanently
launchctl bootout gui/$UID_/com.withforge.pr-dev-merge-cron && rm "$PLIST"

# clear a PR's "already flagged" marker so it can comment again
rm ~/.local/state/pr-dev-merge-cron/<repo-slug>_<num>.conflict
```

**After editing the script:** no reload needed (launchd re-reads the file each run).
The stowed symlink points at the repo copy, so editing the repo file takes effect live.
**After editing the plist:** re-stow if you added/removed it, then `bootout` then
`bootstrap` to apply.

## Config knobs (top of the script)

- `REPO_DIRS` — array of repos to keep merged. Add/remove paths here.
- `REGEN_REGEX` — paths `sand build` fully regenerates (safe to auto-resolve). Currently
  `^(generated/|_build/)`. `.sand/summaries/` is intentionally excluded (build doesn't
  rewrite it).
- `LOG_MAX_BYTES` (default 1 MB) / `LOG_KEEP` (default 5) — rotation thresholds.
- PR selection: `gh pr list --author "@me" --state open --base dev` minus `WIP:` titles.

## Caveats

- **`builtin_types.ts` drift**: the locally-installed `sand` CLI emits a newer
  `builtin_types.ts` than what's on `dev`, so every touched PR gains those lines until
  the regenerated file lands on `dev`. Pin the team's `sand` version to avoid ping-pong.
- **Keychain**: works while logged into the Mac. If the log shows `gh` auth failures,
  add `GH_TOKEN` to the plist's `EnvironmentVariables` (kept out by default to avoid a
  plaintext token).
- Originally set up as a Claude Code session cron, then moved to launchd because Claude
  session crons are session-only here (don't survive restart) and expire after 7 days.
