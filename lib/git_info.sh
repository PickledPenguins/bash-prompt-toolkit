#!/usr/bin/env bash
# Toolkit version: 0.1.4
# ════════════════════════════════════════════════════════════════════════════
# lib/git_info.sh — Cached git repository state for bash scripts
#
# Provides current branch, remote tracking, ahead/behind counts, and
# file-status counts in plain globals.  An mtime+TTL cache avoids
# re-running git on every call; only two stat(2) calls are needed on a hit.
#
# Depends on lib/cache.sh (sourced automatically, same directory) for the
# TTL half of cache validity — the mtime checks below are this file's own,
# since they catch changes cache.sh's flat clock alone would miss.
#
# Usage:
#   source lib/git_info.sh
#   git_info_cache_valid || git_info_refresh
#   echo "$GIT_BRANCH  ↑$GIT_AHEAD ↓$GIT_BEHIND  +$GIT_STAGED ~$GIT_MODIFIED"
#
# Public globals (populated by git_info_refresh):
#   GIT_IN_REPO   — 1 if the current directory is inside a git repo, else 0
#   GIT_BRANCH    — short branch name, or short SHA in detached-HEAD state
#   GIT_REMOTE    — upstream tracking branch (empty if none)
#   GIT_AHEAD     — commits ahead of remote
#   GIT_BEHIND    — commits behind remote
#   GIT_STAGED    — files with staged changes
#   GIT_MODIFIED  — files with unstaged modifications
#   GIT_UNTRACKED — untracked files
#   GIT_CONFLICTS — unmerged/conflicted paths (mid-merge or mid-rebase)
#   GIT_STASH     — stash entries
#
# Public functions:
#   git_info_refresh        — collect all git data (or use cache)
#   git_info_cache_valid    — returns 0 if cached data is still fresh
#   git_info_cache_ttl <N>  — set the worktree-staleness TTL (default 5 s)
#
# Cache invalidation triggers:
#   • Different directory                 (cd to another repo)
#   • .git/HEAD mtime changed             (commit, checkout, merge, rebase)
#   • .git/index mtime changed            (git add, git reset, git rm)
#   • _GIT_CACHE_TTL seconds elapsed      (catches unstaged edits, new files)
#
# Non-repo directories are cached by PWD alone: once confirmed as non-repo,
# the git rev-parse is skipped on every subsequent prompt in that directory.
# ════════════════════════════════════════════════════════════════════════════

[[ -n "${_GIT_INFO_SH_LOADED-}" ]] && return 0
readonly _GIT_INFO_SH_LOADED=1

_GIT_INFO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_GIT_INFO_DIR}/cache.sh"
unset _GIT_INFO_DIR

# [v0.1.3] Fail loudly and immediately if cache.sh didn't load, rather
# than leaving cache_stale/cache_touch undefined and only surfacing that
# as a cryptic "command not found" the next time git_info_cache_valid or
# git_info_refresh actually runs.
if ! declare -F cache_stale >/dev/null; then
    printf 'git_info.sh: lib/cache.sh not found or failed to load — keep it in the same directory as this file\n' >&2
    return 1
fi

# ── Public state ──────────────────────────────────────────────────────────
declare -g    GIT_IN_REPO=0
declare -g    GIT_BRANCH=""   GIT_REMOTE=""
declare -gi GIT_AHEAD=0     GIT_BEHIND=0
declare -gi GIT_STAGED=0    GIT_MODIFIED=0
declare -gi GIT_UNTRACKED=0 GIT_STASH=0     GIT_CONFLICTS=0

# ── Cache keys (private) ──────────────────────────────────────────────────
declare -g    _GIT_CACHE_DIR=""       # $PWD when cache was last populated
declare -g    _GIT_CACHE_GIT_DIR=""   # absolute path to the .git directory
declare -g    _GIT_CACHE_HEAD_MT=""   # stat mtime of .git/HEAD
declare -g    _GIT_CACHE_IDX_MT=""    # stat mtime of .git/index
declare -gi _GIT_CACHE_TTL=5       # max seconds between forced full refreshes

# Adjust the worktree-staleness window.
git_info_cache_ttl() { _GIT_CACHE_TTL="${1:-5}"; }

# ── Cache validity ────────────────────────────────────────────────────────

# Returns 0 (cache is fresh) or 1 (must call git_info_refresh).
# Cost on a hit: two stat calls + string comparisons — well under 1 ms.
git_info_cache_valid() {
    # Different directory always stale
    [[ "$PWD" == "$_GIT_CACHE_DIR" ]] || return 1

    # Non-repo: valid as long as the directory hasn't changed
    (( GIT_IN_REPO )) || return 0

    # Verify the .git directory still exists (e.g. repo not deleted under us)
    [[ -d "$_GIT_CACHE_GIT_DIR" ]] || return 1

    # Check mtime of HEAD (commits, checkouts, merges, rebases)
    local mt
    mt=$(stat -c '%Y' "${_GIT_CACHE_GIT_DIR}/HEAD" 2>/dev/null) || return 1
    [[ "$mt" == "$_GIT_CACHE_HEAD_MT" ]] || return 1

    # Check mtime of index (git add, git reset, git rm)
    mt=$(stat -c '%Y' "${_GIT_CACHE_GIT_DIR}/index" 2>/dev/null) || return 1
    [[ "$mt" == "$_GIT_CACHE_IDX_MT" ]] || return 1

    # TTL: catch unstaged edits and new untracked files
    cache_stale git_info "$_GIT_CACHE_TTL" && return 1

    return 0
}

# ── Refresh ───────────────────────────────────────────────────────────────

# Collect all git state in one pass.  Call via:
#   git_info_cache_valid || git_info_refresh
git_info_refresh() {
    GIT_IN_REPO=0; GIT_BRANCH=""; GIT_REMOTE=""
    GIT_AHEAD=0;   GIT_BEHIND=0
    GIT_STAGED=0;  GIT_MODIFIED=0; GIT_UNTRACKED=0; GIT_STASH=0; GIT_CONFLICTS=0

    # Always record current dir so non-repo directories are cached too
    _GIT_CACHE_DIR="$PWD"

    # Single call serves both the in-repo check and the cache key below
    # (previously two calls: one discarded, one captured).
    local git_dir; git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 1
    GIT_IN_REPO=1

    # Branch name; falls back to short SHA in detached-HEAD state
    GIT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null) ||
    GIT_BRANCH=$(git rev-parse --short HEAD 2>/dev/null) || {
        GIT_IN_REPO=0; return 1  # corrupted/unreadable HEAD, or bare-repo edge case
    }

    # Remote tracking branch (absent for local-only branches)
    GIT_REMOTE=$(
        git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null
    ) || true

    # Ahead/behind in a single rev-list call — "behind<TAB>ahead"
    if [[ -n "$GIT_REMOTE" ]]; then
        local counts
        counts=$(git rev-list --count --left-right '@{u}...HEAD' 2>/dev/null) || true
        if [[ "$counts" =~ ^([0-9]+)$'\t'([0-9]+)$ ]]; then
            GIT_BEHIND=${BASH_REMATCH[1]}
            GIT_AHEAD=${BASH_REMATCH[2]}
        fi
    fi

    # File-status counts from a single --porcelain call, classified in one
    # awk pass (previously 3 grep forks; `grep -c` also exits 1 on zero
    # matches, which tripped the old `|| echo 0` fallback and left each
    # GIT_* var holding two lines instead of one — a bash arithmetic error
    # on nearly every clean-file-status refresh). Unmerged paths get their
    # own category so a conflicted repo doesn't read as "clean".
    local porcelain; porcelain=$(git status --porcelain 2>/dev/null) || true
    if [[ -n "$porcelain" ]]; then
        local counts; counts=$(awk '
            { xy = substr($0,1,2) }
            xy == "??" { untracked++; next }
            xy=="DD"||xy=="AU"||xy=="UD"||xy=="UA"||xy=="DU"||xy=="AA"||xy=="UU" { conflicts++; next }
            substr(xy,1,1) ~ /[MADRCT]/ { staged++ }
            substr(xy,2,1) ~ /[MD]/     { modified++ }
            END { printf "%d %d %d %d", staged+0, modified+0, untracked+0, conflicts+0 }
        ' <<< "$porcelain")
        read -r GIT_STAGED GIT_MODIFIED GIT_UNTRACKED GIT_CONFLICTS <<< "$counts"
    fi
    local -a _stash_lines; mapfile -t _stash_lines < <(git stash list 2>/dev/null)
    GIT_STASH=${#_stash_lines[@]}

    # Save cache keys for the next git_info_cache_valid check
    _GIT_CACHE_GIT_DIR="$git_dir"
    _GIT_CACHE_HEAD_MT=$(stat -c '%Y' "${git_dir}/HEAD"  2>/dev/null) || true
    _GIT_CACHE_IDX_MT=$( stat -c '%Y' "${git_dir}/index" 2>/dev/null) || true
    cache_touch git_info
}
