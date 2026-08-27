# Global tooling notes (Forge / sand)

Cross-cutting rules for my custom tools, loaded in **every** session. Project-specific
facts (repo structure, repo-local lint false-positives) stay in each project's `memory/`.

## Tools & where they live
- Personal scripts — `forge-ui-checks`, `forge-ui-shot`, `forge-ui-pr-report`,
  `forge-report-dump`, `forge-report-shot` — are tracked in `~/dots/forge-tools/.local/bin`
  and stowed onto PATH via `just stow`. Edit the source in `~/dots`, never the
  `~/.local/bin` symlink.
- `chime-cases` is the EXCEPTION: it lives in its own repo `~/_dev/chime-dev-tools`
  (github Forge-FDE/chime-dev-tools, private), and the dots entry is a symlink into it —
  edit `~/_dev/chime-dev-tools/cli/chime-cases`. It fills `run_test_cases_dev` from past
  Forge runs (non-reg + UT), clears it, builds, and cloud-runs the suite. Driven from
  Claude by the `chime-test-cases` SKILL (auto-triggers on intent; no slash needed) and
  from Cursor by the "Chime Dev Tools" extension (`just install-chime-dev-tools`).
- Go tools (`no-mistakes`, `treehouse`) live in `~/go/bin` via `go install`.
- `sand` is at `~/Library/Application Support/sand/sand`.
- treehouse worktrees go in `~/_dev/.treehouse`; interactive shell is fish (config in `~/dots`).

## Canonical workflow on a sand project
Not the monorepo (`~/_dev/monorepo`): there its `AGENTS.md` wins — Graphite `gt submit`
through the `submit-pr` skill, and the Context/Summary/Motivation/Design/Changes body
instead of the terse house style below.

1. `treehouse` — new worktree off `dev` for the task (isolated).
2. Open a shell in that worktree and STAY in it for the whole task.
3. Edit → `sand build` + `sand lint` (focused; leave global `sand format` to the gate — it
   rewrites ~8 unrelated files). Commit regenerated `_build/` artifacts with the change.
4. Interface/report change? Validate headlessly with `forge-report-probe` / `forge-ui-checks`
   (+ screenshots for the PR).
5. Commit on the feature branch.
6. `/no-mistakes --intent "<tight intent>"` → drive the gates → `checks-passed`.
7. Terse-ify the PR body to house style (below).
8. Ask a human to review/merge; the auto-dev-merger handles the dev merge.

## no-mistakes gotchas
- `axi abort`/`respond`/`rerun` act on the run for the **shell cwd's branch**, not a run id.
  Never `cd` for side errands (use `git -C <path>`); before any mutating command run
  `no-mistakes axi` and confirm the target is under `active_run`, NOT `other_branch_active_run`.
- Runs are created by pushing through the `no-mistakes` proxy remote; `axi run` errors
  "no previous run" if none exists.
- PR bodies are auto-generated and verbose (Intent / Risk / Testing / Pipeline are hardcoded,
  not configurable). House style is terse: `## Summary` + `## Test plan` (~300–1800 chars).
  After each run rewrite via `gh pr edit`, and keep `--intent` tight (it's dumped verbatim into `## Intent`).

## General
- No code comments unless explicitly asked.

@~/.claude/codealmanac.md
