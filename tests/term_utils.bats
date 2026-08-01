load test_helper

setup() {
    source "$DOTFILES_ROOT/lib/term_utils.sh"
}

@test "strip_ansi removes SGR color codes" {
    [[ "$(strip_ansi $'\033[31mred\033[0m')" == "red" ]]
}

@test "strip_ansi removes readline \\001..\\002 markers" {
    [[ "$(strip_ansi $'\001\033[31m\002red\001\033[0m\002')" == "red" ]]
}

@test "strip_ansi removes cursor-movement CSI sequences (not just SGR/erase-line)" {
    [[ "$(strip_ansi $'a\033[10;20Hb')" == "ab" ]]
}

@test "strip_ansi removes OSC/BEL sequences (e.g. terminal title)" {
    [[ "$(strip_ansi $'before\033]0;title\007after')" == "beforeafter" ]]
}

@test "str_width counts ASCII length correctly" {
    [[ "$(str_width 'hello')" == "5" ]]
}

@test "str_width counts multi-byte UTF-8 as code points, not bytes" {
    [[ "$(str_width 'café')" == "4" ]]
}

@test "str_repeat produces the requested count" {
    [[ "$(str_repeat '-' 5)" == "-----" ]]
}

@test "str_repeat with a multi-byte character repeats the character, not its bytes" {
    result="$(str_repeat '─' 3)"
    [[ "$(str_width "$result")" == "3" ]]
}

@test "str_repeat with count 0 produces empty output" {
    [[ "$(str_repeat '-' 0)" == "" ]]
}
