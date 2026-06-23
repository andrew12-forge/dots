if status is-interactive
    # Commands to run in interactive sessions can go here
end

# ── PATH ──────────────────────────────────────────────
fish_add_path "$HOME/.local/bin"
fish_add_path "$HOME/Library/Application Support/sand"
fish_add_path "$HOME/go/bin"
fish_add_path /opt/homebrew/bin
fish_add_path /opt/homebrew/opt/postgresql@18/bin

# ── Environment ───────────────────────────────────────
# API keys intentionally omitted — use a secrets manager or
# set them in a file not checked into version control, e.g.
#   ~/.config/fish/conf.d/secrets.fish
set -gx SAND_RIZA_PATH ~/tools/riza

# ── NVM (via nvm.fish or fnm) ─────────────────────────
set -gx NVM_DIR "$HOME/.nvm"
# If you use nvm.fish: https://github.com/jorgebucaran/nvm.fish
# Or fnm (already in conf.d/fnm.fish)

# ── Git aliases ───────────────────────────────────────
alias g git
alias gs 'git status'
alias gc 'git checkout'

# ── mm: stash local changes, update dev, switch back, merge dev in (then restore stash) ──
function mm -d "Stash, update dev, switch back to prior branch, merge dev, restore stash"
    set -l cur (git rev-parse --abbrev-ref HEAD); or return 1
    set -l stashed 0
    if not git diff --quiet; or not git diff --cached --quiet
        git stash push -m "mm autostash"; and set stashed 1; or return 1
    end
    git checkout dev; and git pull; and git checkout $cur; and git merge dev; or return 1
    test $stashed -eq 1; and git stash pop
end

# ── mp: update dev without leaving the current branch ──
function mp -d "Update dev without leaving the current branch"
    set -l cur (git rev-parse --abbrev-ref HEAD); or return 1
    git checkout dev; and git pull; and git checkout $cur
end

# ── gall {message} [-y]: git add/commit, optionally push ──
function gall -d "git add . && commit, with optional -y to push"
    set -l args $argv
    set -l do_push 0

    if test (count $args) -gt 0; and test "$args[-1]" = -y
        set do_push 1
        set -e args[-1]
    end

    if test (count $args) -eq 0
        echo "usage: gall {message} [-y]" >&2
        return 2
    end

    set -l msg (string join " " $args)

    git add .
    and git commit -m "$msg"
    and if test $do_push -eq 1
        git push
    end
end

# ── Forge / Sand ──────────────────────────────────────
alias cdforge 'pushd "$HOME/Library/Application Support/Forge/sand/userfolders"'
alias sa sand
alias sb 'sand build'

# ── monoprs: copy my open PRs to clipboard ────────────
function monoprs -d "Copy my open PRs to clipboard"
    gh pr list --author @me --state open --json number,title,url \
        --jq '[.[] | "PR \(.number) - \(.title) \(.url)"] | to_entries[] | "\(.key+1). \(.value)"' \
        | pbcopy
    and echo "Copied to clipboard"
end

# ── Claude ────────────────────────────────────────────
alias cld claude

# ── Chime / Non-reg ──────────────────────────────────
alias nrrelease 'gh workflow run create_release_pr.yaml --repo Forge-FDE/chime-non-reg --ref dev'
alias nr 'pushd ~/_dev/chime_non_reg'
alias mono 'pushd ~/_dev/monorepo'
alias ut 'pushd ~/_dev/chime-disputes'

# ── Snapshot automator ────────────────────────────────
function snap -d "Run snapshot-automator"
    pushd "$HOME/_dev/snapshot-automator"
    npx tsx src/index.ts $argv
    popd
end

function snap-test -d "Run snapshot-automator tests"
    pushd "$HOME/_dev/snapshot-automator"
    npx tsx src/scenario_test.ts $argv
    popd
end

zoxide init fish | source
# Set up fzf key bindings
fzf --fish | source
