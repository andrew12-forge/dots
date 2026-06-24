#!/usr/bin/env bash
# pr-dev-merge-cron.sh
# Keep non-WIP, open PRs (base: dev) merged up-to-date with dev, across one or
# more repos.
#
# Per PR:
#   * Pick a worktree:
#       - if a registered git worktree is already checked out to the PR branch
#         AND it is clean AND not ahead of origin -> use it in place
#       - otherwise lease a treehouse worktree (detached, isolated) and hard-reset
#   * Merge origin/dev:
#       - clean merge, or conflicts only in generated/+_build/ -> sand build,
#         commit ALL output, push
#       - conflict in a source file or .sand/summaries -> abort, comment on PR
#       - already up to date -> skip
#
# Safety: an existing user worktree is NEVER hard-reset and is skipped if dirty
# or ahead of origin. Set DRY_RUN=1 to preview without commit/push/comment.

set -uo pipefail
export PATH="/Users/andrew/go/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

# Repos to keep merged up with dev. Each must be a sand repo with a treehouse
# pool (treehouse.toml). Conflict flags are namespaced per repo, so PR numbers
# never collide across repos.
REPO_DIRS=(
  "/Users/andrew/_dev/chime-disputes"
  "/Users/andrew/_dev/chime_non_reg"
)
LEASE_HOLDER="pr-dev-merge-cron"
SAND_BIN="/Users/andrew/Library/Application Support/sand/sand"
# Paths sand build fully regenerates — conflicts here are safely auto-resolvable
# by taking dev's side and letting the rebuild overwrite. (.sand/summaries are
# generated too, but `sand build` does NOT rewrite them, so they need a human.)
REGEN_REGEX='^(generated/|_build/)'
MARKER="<!-- pr-dev-merge-cron -->"
DRY_RUN="${DRY_RUN:-0}"
# Per-PR conflict flags persist across runs/sessions. A flag means "I already
# commented about an unresolvable merge and nothing has merged since." It is
# cleared the moment a merge succeeds or the PR is found up to date with dev, so
# a fresh conflict after real progress can be flagged again. Flags are keyed
# "<repo-slug>_<num>.conflict" so the same PR number in two repos can't clash.
STATE_DIR="$HOME/.local/state/pr-dev-merge-cron"
mkdir -p "$STATE_DIR" 2>/dev/null || true

# --- self-contained log rotation -------------------------------------------
# launchd writes its own stdout to cron.boot.log (catches only catastrophic
# pre-exec errors); this script owns cron.log and exec's its output there. Since
# nothing holds cron.log open between the short-lived runs, rotating it at
# startup is safe and needs no root (unlike newsyslog in /etc/newsyslog.d).
LOG="$STATE_DIR/cron.log"
LOG_MAX_BYTES=$((1024 * 1024))   # rotate at ~1 MB
LOG_KEEP=5                       # cron.log.1.gz .. cron.log.5.gz

rotate_log() {
  [ -f "$LOG" ] || return 0
  local size; size=$(stat -f%z "$LOG" 2>/dev/null || echo 0)
  [ "$size" -lt "$LOG_MAX_BYTES" ] && return 0
  rm -f "$LOG.$LOG_KEEP.gz" 2>/dev/null || true
  local i=$((LOG_KEEP - 1))
  while [ "$i" -ge 1 ]; do
    [ -f "$LOG.$i.gz" ] && mv -f "$LOG.$i.gz" "$LOG.$((i + 1)).gz"
    i=$((i - 1))
  done
  mv -f "$LOG" "$LOG.1" && gzip -f "$LOG.1"
  : > "$LOG"
}

rotate_log
# Direct all output to the managed log under launchd (no TTY). Set
# PRCRON_STDOUT=1 to keep output on the terminal for manual/debug runs.
if [ -z "${PRCRON_STDOUT:-}" ] && [ ! -t 1 ]; then
  exec >>"$LOG" 2>&1
fi

# Set per repo by run_repo: the repo path and a filesystem-safe slug used to
# namespace conflict flags.
REPO_DIR=""
REPO_SLUG=""
WT_LEASED=""   # path of a leased treehouse worktree, returned per repo + on exit

say() { printf '%s\n' "$*"; }

# Return any leased worktree and forget it. Called at the end of each repo and
# from the EXIT trap as a safety net.
release_lease() {
  [ -n "$WT_LEASED" ] && treehouse return "$WT_LEASED" --force >/dev/null 2>&1 || true
  WT_LEASED=""
}
trap release_lease EXIT

# Comment about an unresolvable merge, but at most once until something actually
# merges. The per-PR flag file is the gate: set here, cleared on any successful
# merge / up-to-date result. So a still-conflicting PR with no merge in between
# is left alone; a conflict that reappears after real progress is flagged again.
maybe_comment() {
  local num="$1" dev_sha="$2" detail="$3"
  local flag="$STATE_DIR/${REPO_SLUG}_${num}.conflict"
  if [ -f "$flag" ]; then
    say "    (already flagged; no merge since — not re-commenting)"
    return
  fi
  if [ "$DRY_RUN" = "1" ]; then
    say "    [dry-run] would comment on #$num (and set conflict flag):"
    printf '%s\n' "$detail" | sed 's/^/        /'
    return
  fi
  local body="$MARKER
🤖 **Auto dev-merge needs a hand**

I tried to merge \`dev\` (\`dev@$dev_sha\`) into this PR via the PR cron and couldn't finish automatically:

\`\`\`
$detail
\`\`\`

Please merge \`dev\` and resolve manually. I won't comment again until a merge into this PR succeeds."
  if gh pr comment "$num" --body "$body" >/dev/null 2>&1; then
    touch "$flag" 2>/dev/null || true
    say "    commented on #$num"
  else
    say "    comment FAILED on #$num"
  fi
}

# Clear the conflict flag: a merge happened (or none was needed), so a future
# conflict is allowed to comment again.
clear_conflict_flag() { rm -f "$STATE_DIR/${REPO_SLUG}_${1}.conflict" 2>/dev/null || true; }

# Find a registered worktree checked out to refs/heads/<branch>, if any.
find_existing_worktree() {
  git -C "$REPO_DIR" worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree /{p=substr($0,10)}
    /^branch /{ if (substr($0,8)==b) { print p; exit } }'
}

# Process every non-WIP open PR (base dev) in $REPO_DIR.
run_repo() {
  cd "$REPO_DIR" || { say "ERROR: repo dir missing: $REPO_DIR" >&2; return 1; }

  local prs_json count
  prs_json=$(gh pr list --author "@me" --state open --base dev \
    --json number,title,headRefName \
    --jq '[.[] | select(.title|startswith("WIP:")|not)]' 2>/dev/null || echo '[]')
  count=$(printf '%s' "$prs_json" | jq 'length' 2>/dev/null || echo 0)

  say ""
  say "##### $REPO_SLUG — targeting $count non-WIP PR(s)."
  [ "$count" -eq 0 ] && return 0
  printf '%s' "$prs_json" | jq -r '.[] | "  - #\(.number) \(.headRefName)  (\(.title))"'

  # One fetch updates origin/* for every worktree (shared object store).
  git fetch origin --prune -q || { say "ERROR: git fetch failed in $REPO_SLUG" >&2; return 1; }

  local pr num head wt mode existing ahead dev_sha unmerged blocking f
  while IFS= read -r pr; do
    num=$(printf '%s' "$pr" | jq -r '.number')
    head=$(printf '%s' "$pr" | jq -r '.headRefName')
    say ""
    say "=== PR #$num ($head) ==="

    # --- choose a worktree ---------------------------------------------------
    # Prefer an existing on-branch worktree, but only when it's safe to operate
    # in place: clean and not ahead of origin. Otherwise fall back to a leased
    # one so the PR still advances without touching the user's uncommitted work.
    wt=""; mode=""
    existing=$(find_existing_worktree "$head")
    if [ -n "$existing" ] && [ -d "$existing" ]; then
      ahead=$(git -C "$existing" rev-list --count "origin/$head..HEAD" 2>/dev/null || echo 0)
      if [ -n "$(git -C "$existing" status --porcelain)" ]; then
        say "    existing worktree is dirty — falling back to a leased worktree: $existing"
      elif [ "${ahead:-0}" != "0" ]; then
        say "    existing worktree has $ahead unpushed commit(s) — falling back to a leased worktree"
      else
        wt="$existing"; mode="existing"
        say "    using existing worktree: $wt"
        # Fast-forward to origin if it moved ahead (clean + not-ahead guarantees ff).
        git -C "$wt" merge --ff-only -q "origin/$head" >/dev/null 2>&1 || true
      fi
    fi
    if [ -z "$wt" ]; then
      if [ -z "$WT_LEASED" ]; then
        WT_LEASED=$(treehouse get --lease --lease-holder "$LEASE_HOLDER" 2>/dev/null)
        if [ -z "${WT_LEASED:-}" ] || [ ! -d "$WT_LEASED" ]; then
          say "    ERROR: failed to lease a worktree — skipping"; WT_LEASED=""; continue
        fi
        say "    leased worktree: $WT_LEASED"
      fi
      wt="$WT_LEASED"; mode="leased"
      git -C "$wt" merge --abort >/dev/null 2>&1 || true
      if ! git -C "$wt" checkout -q --detach "origin/$head" 2>/dev/null; then
        say "    skip: cannot checkout origin/$head"; continue
      fi
      git -C "$wt" reset --hard -q "origin/$head"
      git -C "$wt" clean -fdq -e node_modules >/dev/null 2>&1 || true
    fi

    g() { git -C "$wt" "$@"; }
    dev_sha=$(g rev-parse --short origin/dev)

    # --- merge dev -----------------------------------------------------------
    if g merge --no-ff --no-commit origin/dev >/tmp/prcron_merge 2>&1; then
      if ! g rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && g diff --cached --quiet; then
        say "    already up to date with dev@$dev_sha"
        clear_conflict_flag "$num"
        continue
      fi
      say "    clean merge of dev@$dev_sha"
    else
      unmerged=$(g diff --name-only --diff-filter=U)
      blocking=$(printf '%s\n' "$unmerged" | grep -vE "$REGEN_REGEX" || true)
      if [ -n "$blocking" ]; then
        say "    conflict needs a human — leaving for manual merge:"
        printf '%s\n' "$blocking" | sed 's/^/      /'
        g merge --abort >/dev/null 2>&1 || true
        maybe_comment "$num" "$dev_sha" "Merge conflict in file(s) the cron won't auto-resolve:
$blocking"
        continue
      fi
      # All conflicts are in fully-regenerated paths: take dev's side, rebuild over it.
      say "    regenerated-file conflict(s) — taking dev's side + rebuilding"
      printf '%s\n' "$unmerged" | while IFS= read -r f; do
        [ -n "$f" ] && g checkout --theirs -- "$f" && g add -- "$f"
      done
    fi

    # --- rebuild + stage everything sand build emits -------------------------
    if ! ( cd "$wt" && "$SAND_BIN" build ) >/tmp/prcron_build 2>&1; then
      say "    BUILD FAILED:"; tail -5 /tmp/prcron_build | sed 's/^/      /'
      g merge --abort >/dev/null 2>&1 || true
      maybe_comment "$num" "$dev_sha" "sand build failed during auto dev-merge:
$(tail -5 /tmp/prcron_build)"
      continue
    fi
    g add -A

    # Safety net: never commit unresolved conflict markers.
    if [ -n "$(g ls-files -u)" ] || g diff --cached -U0 | grep -qE '^\+(<{7}|={7}|>{7})'; then
      say "    unresolved conflict after build — leaving for manual merge"
      g merge --abort >/dev/null 2>&1 || true
      maybe_comment "$num" "$dev_sha" "Conflict could not be auto-resolved by sand build."
      continue
    fi

    if g diff --cached --quiet; then
      say "    nothing to commit after build — skipping"
      g merge --abort >/dev/null 2>&1 || true
      clear_conflict_flag "$num"
      continue
    fi

    say "    staged changes:"
    g diff --cached --name-only | sed 's/^/      /'

    if [ "$DRY_RUN" = "1" ]; then
      say "    [dry-run] would commit merge of dev@$dev_sha + build output and push to $head ($mode worktree)"
      g merge --abort >/dev/null 2>&1 || true
      [ "$mode" = "existing" ] && g reset --hard -q "origin/$head"
      continue
    fi

    g -c user.name="$LEASE_HOLDER" -c user.email="andrew@withforge.com" \
      commit -q -m "chore: merge dev + sand build [auto-cron]

Auto-merged origin/dev ($dev_sha) and rebuilt sand artifacts."
    if g push origin HEAD:"$head" >/tmp/prcron_push 2>&1; then
      say "    pushed merge+build to $head ($mode worktree)"
      clear_conflict_flag "$num"
    else
      say "    PUSH FAILED:"; tail -5 /tmp/prcron_push | sed 's/^/      /'
      # Roll the local branch back so a push failure doesn't leave a divergent worktree.
      [ "$mode" = "existing" ] && g reset --hard -q "origin/$head"
    fi
  done < <(printf '%s' "$prs_json" | jq -c '.[]')

  # Return this repo's leased worktree before moving to the next repo (each
  # repo has its own treehouse pool).
  release_lease
}

say "[$(date '+%Y-%m-%d %H:%M')] DRY_RUN=$DRY_RUN — repos: ${#REPO_DIRS[@]}"
for REPO_DIR in "${REPO_DIRS[@]}"; do
  REPO_SLUG=$(basename "$REPO_DIR")
  run_repo
done

say ""
say "Done."
