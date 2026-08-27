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

## Step 2c: Case-signal criteria

Criteria about what a run CONCLUDED are answered by the signal path, not run
tags. BOTH projects have one, live and current to the minute:

- non-reg -> `non_reg_prod_v2` (~55 cols, booleans, soft-deleted)
- UT -> `ut_disputes` (56 cols, "Yes"/"No" TEXT, no soft delete)

The CLI routes these automatically; pass the phrase through.

```
chime-cases find "5 cases with partial merchant credit"
chime-cases find "3 ssd cnp cases with a transcript"
chime-cases find "3 cases" --signal cb_eligibility_outcome=WAIT_15_DAYS --signal 'dispute_amount>200'
```

`--signal` forms: `col=v`, `col!=v`, `col=a,b,c` (IN), `col>10`, `col~text`
(substring), `col=null`, `col` (set/true), `!col` (unset/false). Repeatable,
ANDed. Shortcuts: `--merchant-credit`, `--intake phone|ssd`, `--cb-eligible`,
`--scenario N`. `--where "<raw sql>"` is the escape hatch.

**Discover before guessing.** `chime-cases signals` lists every column with the
row count and freshness; `chime-cases signals --column X` shows X's distinct
values and counts. Use these instead of inventing a column or a value — an
unknown column is rejected with suggestions, but an unknown *value* silently
returns nothing.

The data is LIVE (queried on the shared/prod SandSQL lane, current to the
minute). Do not repeat the old claim that signals are frozen at 2026-08-16 —
that was true only of the retired SandDB table.

On non-reg, "phone-filed" / "SSD" are REAL `intake_type` filters. UT HAS the
column but it is NULL on every row, so UT degrades to the transcript proxy —
the CLI says so; relay it.

The --merchant-credit / --cb-eligible / --scenario shortcuts name non-reg
columns. On UT use `--signal` over ut_disputes instead, and prefer the value
form for its text columns: `--signal potential_scam_victim=Yes`, NOT the bare
`--signal potential_scam_victim` (bare means "set and not false", and "No"
satisfies that).

## Step 3: Pass the criteria through

Give the user's phrasing to the CLI **verbatim** as a single quoted argument.
Since v2.0.0 a free-text phrase is mapped by Claude against the live table
schema, so it reaches every column — pre-translating into flags throws that
away and is strictly worse. Requires ANTHROPIC_API_KEY.

Read the CLI's `note:` lines back to the user. "not expressible as a filter — …"
means part of their request was NOT applied; never present such a result as if
the whole request was honoured.

Add explicit flags only for things the phrase cannot express, or to override it:
`-n`, `--since`, `--until`, `--reason-code`, `--dispute-type`, `--status`,
`--any-status`, `--transcript`, `--no-transcript`, `--case-id`, `--dispute-id`.

Notes that matter:
- Default status filter is `finished`. If the user wants failures, the phrase
  "errored" handles it.
- Intake: real on non-reg (via the signal table's `intake_type`), a transcript
  proxy on UT. See Step 2c.
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
