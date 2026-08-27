---
name: chime-test-cases
description: Fill, inspect, clear, or cloud-run the `run_test_cases_dev` test suite in the Chime sand projects (Chime Non Reg and Chime Disputes / UT) using the `chime-cases` CLI. Use when the user wants past dispute runs pulled in as test cases ("give me 5 cases from the last 2 weeks with reason code gsc that had a transcript"), wants to run a specific case or the whole suite on cloud ("run case 22632810 on cloud"), wants to know or clear what test cases are currently staged, or mentions run_test_cases_dev, main_dev.sand, chime-cases, or the Chime Dev Tools extension.
user-invocable: true
---

Populate, inspect, clear, or cloud-run `run_test_cases_dev` in a chime sand project, using the `chime-cases` CLI.

Arguments: $ARGUMENTS — free-text criteria and/or a verb, e.g.
- "5 cases in the last 2 weeks with reason code gsc which had a transcript"
- "3 errored cnp debit cases from the last week"
- "clear"
- "run" / "run it on cloud"
- "add 2 more mwr cases"
- "what's in there right now?"

## Step 1: Pick the project

`chime-cases` auto-detects the project from the working directory (it walks up
for `sand.mod.json` and matches the workflow id). Do NOT pass `-p` when the
user is already inside a worktree.

Pass `-p non-reg` or `-p ut` only when the user names a project explicitly and
the cwd is somewhere else. `ut` means `~/_dev/chime-disputes`.

If the user names a worktree/bug that is neither default checkout, pass
`--dir <path>` instead.

## Step 2: Pick the verb

| user intent | command |
|---|---|
| show me / preview / which cases match | `chime-cases find "<criteria>"` |
| use these / replace what's there | `chime-cases populate "<criteria>"` (REPLACES the whole list) |
| add / also include / more | `chime-cases add "<criteria>"` (APPENDS, skipping disputes already present) |
| clear / empty / wipe | `chime-cases clear` |
| what's in the file | `chime-cases list` |
| rebuild | `chime-cases build` |
| run them / run on cloud | `chime-cases run` |

`populate`, `add`, and `clear` run `sand build --shared` themselves — do not run
a separate build afterwards. Pass `--no-build` only if the user asks you to skip it.

Default to `find` first when the criteria are vague or the user sounds like they
are exploring; go straight to `populate` when they clearly want the cases in place.

## Step 2b: "Run case X on cloud" (a single named case)

When the user names one or more case ids (or dispute ids) AND wants them run,
it is a two-step, because the cloud run always executes whatever is currently
in `run_test_cases_dev`:

```
chime-cases list --json            # capture what is there now, so it can be restored
chime-cases populate --case-id <ID>   # REPLACES the list with just that case, then builds
chime-cases run                       # cloud-runs, prints the run id, opens Forge Desktop
```

Naming ids explicitly switches the search to a lookup: the limit becomes the
number of ids given and the status filter opens to any, so an errored case is
still found (re-running a failed case is the usual reason to ask by id).

**Tell the user their existing case list was replaced, and how many cases it
had.** Offer to restore it afterwards — you captured the run ids in step one, so
`chime-cases populate --run-id <id> --run-id <id> …` puts the old set back
exactly. Do not restore automatically: the cloud run reads the file as it is,
so restoring before the run finishes would be wrong.

If the user only wants to *stage* the case without running it, stop after
`populate` and say so.

## Step 3: Pass the criteria through

Give the user's phrasing to the CLI verbatim as a single quoted argument. It
parses counts, relative windows, reason codes (full names and the gsc / nrogs /
mwr / gsnad / pbom / cnp aliases), dispute types, statuses, and transcript
presence. Do not pre-translate it into flags.

Add explicit flags only for things the phrase cannot express, or to override it:
`-n`, `--since`, `--until`, `--reason-code`, `--dispute-type`, `--status`,
`--any-status`, `--transcript`, `--no-transcript`, `--case-id`, `--dispute-id`.

Notes that matter:
- Default status filter is `finished`. If the user wants failures, the phrase
  "errored" handles it.
- Intake wording is a PROXY, not a real filter. Phone-filed vs SSD is decided by
  `intake_type` (`src/utils.sand:93`), which is extracted during the run and is NOT
  on the invocation, so the CLI cannot filter on it. "phone-filed" / "SSD" map to
  transcript presence and the CLI prints a note saying so. Repeat that caveat to the
  user rather than presenting the result as an intake filter.
- UT runs carry no `reason_code` tag, so a reason-code criterion cannot work
  there. Say so rather than silently returning unfiltered cases.

## Step 4: Report

Show the CLI's table as-is. Then state, in one line each:
- how many cases landed and in which file,
- whether the build passed,
- if fewer cases matched than asked for, say so plainly and suggest the
  loosest criterion to relax (usually the time window or the transcript filter).

Do not paste transcript bodies into the conversation — they are long and contain
member PII. Refer to them by case id.

## Step 5: Running on cloud

`chime-cases run` builds, uploads the local branch definition, enqueues a cloud
run of `run_test_cases_dev`, prints the run id, and opens it in the Forge desktop
app. Use `--no-open` if the user does not want focus stolen.

It refuses to launch with an empty case list unless given `--force`.

Report the run id and the `forge://<run_id>` deep link.

## Troubleshooting

- Auth failures ("run `sand auth`") mean the Forge session expired. Tell the
  user to run `sand auth`; do not try to work around it.
- `chime-cases doctor` checks credentials, the API, `sand`, and both projects.
