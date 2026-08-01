# nounset (set -u) safety. A prompt snippet sourced into an interactive
# .bashrc never runs under `set -u` in practice, so these gaps are
# invisible there -- but a REUSABLE LIBRARY (this toolkit's stated goal)
# is much more likely to be sourced into a caller's own script that does
# use `set -u`. STATUS: the three previously FAIL-marked gaps
# (PROMPT_COMMAND, $USER, PROMPT_LAST_EXIT) all have their ${VAR:-...}
# guards applied as of v0.1.1 — every test in this file now passes and
# serves as a regression guard.

load test_helper

@test "[nounset] sourcing all 4 files does not itself error" {
    run bash -uc "
        source '$DOTFILES_ROOT/lib/colors.sh'
        source '$DOTFILES_ROOT/lib/term_utils.sh'
        source '$DOTFILES_ROOT/lib/git_info.sh'
        source '$DOTFILES_ROOT/prompt.sh'
    "
    [[ "$status" -eq 0 ]]
}

@test "[nounset] colors_init runs cleanly" {
    run bash -uc "source '$DOTFILES_ROOT/lib/colors.sh'; colors_init prompt"
    [[ "$status" -eq 0 ]]
}

@test "[nounset] git_info_refresh and cache_valid run cleanly" {
    run bash -uc "
        source '$DOTFILES_ROOT/lib/git_info.sh'
        cd '$BATS_TEST_TMPDIR'
        git_info_refresh
        git_info_cache_valid
    "
    [[ "$status" -ne 127 ]]  # 127 would mean a real crash, not just cache-miss's expected rc=1
    [[ "$output" != *"unbound variable"* ]]
}

@test "[nounset] prompt_layout does not crash on a fresh shell with no PROMPT_COMMAND set" {
    run bash -uc "
        source '$DOTFILES_ROOT/prompt.sh'
        _solo() { printf 'X'; }
        prompt_segment solo _solo
        prompt_row r1 '@solo'
        prompt_layout --box rounded r1
    "
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"PROMPT_COMMAND: unbound variable"* ]]
}

@test "[nounset] user_host segment does not crash when \$USER is unset" {
    run bash -uc "
        unset USER
        source '$DOTFILES_ROOT/lib/colors.sh'
        source '$DOTFILES_ROOT/prompt.sh'
        colors_init prompt
        _ps_seg_user_host
    "
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"USER: unbound variable"* ]]
}

@test "[nounset] exit segment does not crash before any command has run yet" {
    run bash -uc "
        source '$DOTFILES_ROOT/lib/colors.sh'
        source '$DOTFILES_ROOT/prompt.sh'
        colors_init prompt
        _ps_seg_exit
    "
    [[ "$status" -eq 0 ]]
    [[ "$output" != *"PROMPT_LAST_EXIT: unbound variable"* ]]
}
