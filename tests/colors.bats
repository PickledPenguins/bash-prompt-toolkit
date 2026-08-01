load test_helper

setup() {
    source "$DOTFILES_ROOT/lib/colors.sh"
}

@test "raw mode produces plain ANSI codes when stdout is a real tty" {
    command -v script >/dev/null || skip "'script' not available to simulate a real tty"
    result=$(script -qec "bash -c \"source '$DOTFILES_ROOT/lib/colors.sh'; colors_init raw; echo -n \\\$C_RED\"" /dev/null)
    [[ "$result" == *$'\033[31m'* ]]
}

@test "prompt mode wraps codes in readline \\001..\\002 markers" {
    colors_init prompt
    [[ "$C_RED" == $'\001\033[31m\002' ]]
}

@test "C_R resets and is non-empty in prompt mode" {
    colors_init prompt
    [[ -n "$C_R" ]]
}

@test "all 16 documented color variables are set in prompt mode" {
    colors_init prompt
    for v in C_R C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA C_CYAN \
             C_WHITE C_BRED C_BGREEN C_BYELLOW C_BBLUE C_BCYAN C_BWHITE; do
        [[ -n "${!v}" ]]
    done
}

@test "PS_* mirrors match C_* in prompt mode" {
    colors_init prompt
    [[ "$PS_RED" == "$C_RED" ]]
    [[ "$PS_BGREEN" == "$C_BGREEN" ]]
}

@test "NO_COLOR disables color in raw mode" {
    NO_COLOR=1 bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; colors_init raw; [[ -z \"\$C_RED\" ]]"
}

@test "NO_COLOR disables color in prompt mode too" {
    NO_COLOR=1 bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; colors_init prompt; [[ -z \"\$C_RED\" ]]"
}

@test "raw mode with non-tty stdout disables color automatically" {
    # bats itself redirects stdout, so this sandbox's stdout is never a tty
    colors_init raw
    [[ -z "$C_RED" ]]
}

@test "prompt mode is exempt from the tty check (PS1 is inherently interactive)" {
    colors_init prompt
    [[ -n "$C_RED" ]]
}

@test "c_fg respects NO_COLOR" {
    run env NO_COLOR=1 bash -c "source '$DOTFILES_ROOT/lib/colors.sh'; colors_init raw; c_fg 196"
    [[ -z "$output" ]]
}

@test "_e helper function is cleaned up after colors_init (no leaked internal function)" {
    colors_init prompt
    ! declare -f _e >/dev/null
}
