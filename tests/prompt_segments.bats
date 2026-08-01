load test_helper

setup() {
    load_prompt_lib
}

@test "pwd segment collapses \$HOME to ~" {
    HOME="$BATS_TEST_TMPDIR"
    cd "$HOME"
    [[ "$(_ps_seg_pwd)" == "~" ]]
}

@test "pwd segment truncates long paths with a leading ellipsis" {
    mkdir -p "$BATS_TEST_TMPDIR/a/very/long/nested/path/that/exceeds/the/visible/width/limit/for/sure"
    cd "$BATS_TEST_TMPDIR/a/very/long/nested/path/that/exceeds/the/visible/width/limit/for/sure"
    result="$(_ps_seg_pwd)"
    [[ "$result" == "…"* ]]
    [[ "$(str_width "$result")" -le 35 ]]
}

@test "pwd segment truncation does not mangle multi-byte UTF-8 characters" {
    mkdir -p "$BATS_TEST_TMPDIR/café/données/very/long/path/segment/for/testing/truncation/logic"
    cd "$BATS_TEST_TMPDIR/café/données/very/long/path/segment/for/testing/truncation/logic"
    result="$(_ps_seg_pwd)"
    # a mangled multi-byte sequence would produce invalid UTF-8; python's
    # strict decode raises on any invalid byte sequence
    printf '%s' "$result" | python3 -c "import sys; sys.stdin.buffer.read().decode('utf-8')"
}

@test "pwd segment strips ANSI escape sequences from directory names" {
    evil_dir="$BATS_TEST_TMPDIR/evil$(printf '\033[31m')colored"
    mkdir -p "$evil_dir" 2>/dev/null || skip "filesystem rejected ANSI bytes in a filename"
    cd "$evil_dir"
    result="$(_ps_seg_pwd)"
    [[ "$result" != *$'\033'* ]]
}

@test "pwd segment strips raw control bytes from directory names" {
    evil_dir="$BATS_TEST_TMPDIR/evil$(printf '\x07')bell"
    mkdir -p "$evil_dir" 2>/dev/null || skip "filesystem rejected control bytes in a filename"
    cd "$evil_dir"
    result="$(_ps_seg_pwd)"
    [[ "$result" != *$'\x07'* ]]
}

@test "modules segment: two modules, no stray colons" {
    result=$(LOADEDMODULES="gcc/11:python/3.9" bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; source '$DOTFILES_ROOT/lib/term_utils.sh'; source '$DOTFILES_ROOT/lib/git_info.sh'; source '$DOTFILES_ROOT/prompt.sh'; _ps_seg_modules")
    [[ "$result" == "⊞ 2" ]]
}

@test "modules segment: trailing colon does not overcount" {
    result=$(LOADEDMODULES="gcc/11:python/3.9:" bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; source '$DOTFILES_ROOT/lib/term_utils.sh'; source '$DOTFILES_ROOT/lib/git_info.sh'; source '$DOTFILES_ROOT/prompt.sh'; _ps_seg_modules")
    [[ "$result" == "⊞ 2" ]]
}

@test "modules segment: leading colon does not overcount" {
    result=$(LOADEDMODULES=":gcc/11:python/3.9" bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; source '$DOTFILES_ROOT/lib/term_utils.sh'; source '$DOTFILES_ROOT/lib/git_info.sh'; source '$DOTFILES_ROOT/prompt.sh'; _ps_seg_modules")
    [[ "$result" == "⊞ 2" ]]
}

@test "modules segment: doubled colon does not overcount" {
    result=$(LOADEDMODULES="gcc/11::python/3.9" bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; source '$DOTFILES_ROOT/lib/term_utils.sh'; source '$DOTFILES_ROOT/lib/git_info.sh'; source '$DOTFILES_ROOT/prompt.sh'; _ps_seg_modules")
    [[ "$result" == "⊞ 2" ]]
}

@test "modules segment: unset LOADEDMODULES produces no output" {
    result=$(unset LOADEDMODULES; bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; source '$DOTFILES_ROOT/lib/term_utils.sh'; source '$DOTFILES_ROOT/lib/git_info.sh'; source '$DOTFILES_ROOT/prompt.sh'; _ps_seg_modules")
    [[ -z "$result" ]]
}

@test "exit segment shows a checkmark for success" {
    PROMPT_LAST_EXIT=0
    [[ "$(plain "$(_ps_seg_exit)")" == "✓" ]]
}

@test "exit segment shows the code for failure" {
    PROMPT_LAST_EXIT=127
    [[ "$(plain "$(_ps_seg_exit)")" == "✗ 127" ]]
}

@test "git_conflicts segment is silent when there are no conflicts" {
    GIT_IN_REPO=1
    GIT_CONFLICTS=0
    [[ -z "$(_ps_seg_git_conflicts)" ]]
}

@test "git_conflicts segment shows the count when conflicts exist" {
    GIT_IN_REPO=1
    GIT_CONFLICTS=2
    [[ "$(plain "$(_ps_seg_git_conflicts)")" == "⚠2" ]]
}
