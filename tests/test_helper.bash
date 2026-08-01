#!/usr/bin/env bash
# Toolkit version: 0.1.4
# ════════════════════════════════════════════════════════════════════════════
# tests/test_helper.bash — shared setup for the bats suite
#
# Loaded by every .bats file via `load test_helper`. Provides the toolkit
# root path plus the three helpers the suite builds on.
#
# Provides:
#   $DOTFILES_ROOT      — absolute path to the toolkit root (parent of tests/)
#   load_prompt_lib     — source all library modules + prompt.sh, prompt-mode colors
#   make_git_repo       — create and cd into a throwaway git repo; sets $REPO_DIR
#   plain <string>      — strip ANSI/readline markers for output comparison
# ════════════════════════════════════════════════════════════════════════════

# Toolkit root is the parent of the directory holding this helper.
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_ROOT

# bats-core installs its own DEBUG trap for internal test tracking and
# does call-stack introspection with hardcoded frame-depth assumptions;
# cmd_timer.sh chaining onto DEBUG corrupts that. This is the documented
# opt-out (see lib/cmd_timer.sh). Only @cmd_time is affected, and no test
# in this suite covers it.
#
# Set at file scope rather than inside load_prompt_lib: nounset.bats and
# the subshell-based tests in colors.bats / prompt_segments.bats source
# prompt.sh directly without going through load_prompt_lib, and would
# otherwise claim the DEBUG trap. PS_SKIP_DEBUG_TRAP is equivalent —
# prompt.sh forwards it to this variable — but this is the canonical name
# as of v0.1.2.
export CMD_TIMER_SKIP_TRAP=1

# Source every library module plus the prompt engine, with colors in
# prompt mode (readline-safe \001..\002 markers) — the state a real
# interactive shell would be in after sourcing prompt.sh.
#
# Call from a test's own setup() so every test gets an unpolluted copy of
# all globals (git cache state, color vars, row/segment registries).
load_prompt_lib() {
    # shellcheck source=/dev/null
    source "$DOTFILES_ROOT/lib/colors.sh"
    # shellcheck source=/dev/null
    source "$DOTFILES_ROOT/lib/term_utils.sh"
    # shellcheck source=/dev/null
    source "$DOTFILES_ROOT/lib/cache.sh"
    # shellcheck source=/dev/null
    source "$DOTFILES_ROOT/lib/git_info.sh"
    # shellcheck source=/dev/null
    source "$DOTFILES_ROOT/prompt.sh"
    colors_init prompt
}

# Fresh, isolated git repo under a throwaway temp dir. Sets $REPO_DIR and
# cd's into it. No teardown needed — bats removes $BATS_TEST_TMPDIR after
# each test automatically.
#
# Identity, default branch, and signing are pinned so the suite doesn't
# depend on (or get broken by) the running user's global git config —
# a global commit.gpgsign=true otherwise fails every commit here.
make_git_repo() {
    REPO_DIR="${BATS_TEST_TMPDIR}/repo"
    mkdir -p "$REPO_DIR"
    cd "$REPO_DIR" || return 1
    git init -q -b main 2>/dev/null || git init -q
    git config user.email "test@example.invalid"
    git config user.name  "Test User"
    git config commit.gpgsign false
    export REPO_DIR
}

# Strip readline \001..\002 markers and ANSI color codes so assertions can
# compare plain text regardless of colors_init's active mode.
#
# Deliberately does NOT call the library's own strip_ansi: a helper that
# uses the code under test to check the code under test can mask a
# regression in that very function. term_utils.bats covers strip_ansi
# directly; this stays independent of it.
plain() {
    printf '%s' "$1" | sed $'s/\x01//g; s/\x02//g; s/\x1b\\[[0-9;]*[A-Za-z]//g'
}
