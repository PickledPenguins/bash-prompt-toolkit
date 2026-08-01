#!/usr/bin/env bash
# Toolkit version: 0.1.4
# ════════════════════════════════════════════════════════════════════════════
# lib/colors.sh — ANSI color variables for bash scripts and PS1 prompts
#
# Provides a single set of C_* color variables whose escape-sequence format
# switches between two modes:
#
#   raw     (default)  Plain ANSI codes — safe in printf/echo/tput contexts.
#   prompt             readline-safe codes wrapped in \001..\002 — required
#                      inside PS1 so readline correctly measures the visible
#                      line length for cursor positioning.
#
# NO_COLOR (https://no-color.org) always disables color. In raw mode, color
# is also disabled automatically when stdout is not a terminal (e.g. output
# redirected to a file) — prompt mode is exempt since PS1 is inherently
# interactive.
#
# Usage — scripts:
#   source lib/colors.sh           # raw mode is the default
#   printf '%sError:%s %s\n' "$C_RED" "$C_R" "$msg"
#
# Usage — PS1 prompts (prompt.sh calls this automatically):
#   source lib/colors.sh
#   colors_init prompt
#   PS1="${C_GREEN}\\u${C_R}@${C_CYAN}\\h${C_R} \\$ "
#
# In prompt mode, PS_* aliases are also defined for every C_* variable so
# that existing segment functions using PS_RED, PS_GREEN, etc. continue to
# work without any changes.
#
# Variables set by colors_init:
#   C_R                            — reset all attributes
#   C_BOLD    C_DIM                — intensity
#   C_RED     C_GREEN   C_YELLOW  — standard foreground colors
#   C_BLUE    C_MAGENTA C_CYAN    C_WHITE
#   C_BRED    C_BGREEN  C_BYELLOW — bold/bright variants
#   C_BBLUE   C_BCYAN   C_BWHITE
#   (PS_* mirrors of all the above, in prompt mode only)
#
# Functions:
#   colors_init [prompt|raw]   — (re)initialize variables in the given mode
#   c_fg <0-255>               — 256-color foreground escape (mode-aware)
#   c_bg <0-255>               — 256-color background escape (mode-aware)
# ════════════════════════════════════════════════════════════════════════════

[[ -n "${_COLORS_SH_LOADED-}" ]] && return 0
readonly _COLORS_SH_LOADED=1

declare -g _COLORS_MODE="raw"

# (Re)initialize all color variables in the requested mode.
# Safe to call multiple times; prompt.sh calls colors_init prompt at startup.
colors_init() {
    _COLORS_MODE="${1:-raw}"

    # _e VAR code: assign VAR directly via printf -v — no subshell fork
    # (previously $(_e code) x16, forking a subshell per color on every init).
    # Also picks the NO_COLOR / non-tty case once, up front, rather than
    # per variable.
    if [[ -n "${NO_COLOR-}" ]] || { [[ "$_COLORS_MODE" != "prompt" ]] && [[ ! -t 1 ]]; }; then
        _e() { printf -v "$1" ''; }
    elif [[ "$_COLORS_MODE" == "prompt" ]]; then
        _e() { printf -v "$1" '\001\033[%sm\002' "$2"; }
    else
        _e() { printf -v "$1" '\033[%sm' "$2"; }
    fi

    _e C_R 0
    _e C_BOLD 1;        _e C_DIM 2
    _e C_RED 31;        _e C_GREEN 32;    _e C_YELLOW 33
    _e C_BLUE 34;       _e C_MAGENTA 35;  _e C_CYAN 36
    _e C_WHITE 37
    _e C_BRED '1;31';   _e C_BGREEN '1;32';   _e C_BYELLOW '1;33'
    _e C_BBLUE '1;34';  _e C_BCYAN '1;36';    _e C_BWHITE '1;37'

    # In prompt mode, mirror every C_* as PS_* for backward compatibility
    # with segment functions and user configs that reference PS_RED, PS_GREEN…
    if [[ "$_COLORS_MODE" == "prompt" ]]; then
        PS_R=$C_R
        PS_BOLD=$C_BOLD       PS_DIM=$C_DIM
        PS_RED=$C_RED         PS_GREEN=$C_GREEN    PS_YELLOW=$C_YELLOW
        PS_BLUE=$C_BLUE       PS_MAGENTA=$C_MAGENTA PS_CYAN=$C_CYAN
        PS_WHITE=$C_WHITE
        PS_BRED=$C_BRED       PS_BGREEN=$C_BGREEN   PS_BYELLOW=$C_BYELLOW
        PS_BBLUE=$C_BBLUE     PS_BCYAN=$C_BCYAN     PS_BWHITE=$C_BWHITE
    fi

    unset -f _e
}

# 256-color foreground/background escape — mode-aware.
# Usage: printf '%s%s%s\n' "$(c_fg 214)" "text" "$C_R"
c_fg() {
    [[ -n "${NO_COLOR-}" ]] && return
    if [[ "$_COLORS_MODE" == "prompt" ]]; then printf '\001\033[38;5;%sm\002' "$1"
    elif [[ -t 1 ]]; then printf '\033[38;5;%sm' "$1"; fi
}

# 256-color background escape — mode-aware, mirrors c_fg.
c_bg() {
    [[ -n "${NO_COLOR-}" ]] && return
    if [[ "$_COLORS_MODE" == "prompt" ]]; then printf '\001\033[48;5;%sm\002' "$1"
    elif [[ -t 1 ]]; then printf '\033[48;5;%sm' "$1"; fi
}

# Initialize in raw mode by default (safe for scripts that just source this file)
colors_init raw
