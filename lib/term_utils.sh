#!/usr/bin/env bash
# Toolkit version: 0.1.4
# ════════════════════════════════════════════════════════════════════════════
# lib/term_utils.sh — Terminal string utilities
#
# Utilities for measuring and constructing terminal strings that may contain
# ANSI escape sequences or multi-byte Unicode characters.  All three
# functions were originally developed for the prompt builder but are fully
# general — useful in any bash script that does terminal layout work.
#
# Usage:
#   source lib/term_utils.sh
#   clean=$(strip_ansi "$colored")        # remove ANSI codes
#   w=$(str_width "$line")                # visible column count
#   sep=$(str_repeat "─" 40)              # draw a separator
#
# Functions:
#   strip_ansi  <string>       — remove ANSI escapes and readline \001..\002
#   str_width   <string>       — visible column count (Unicode + locale safe)
#   str_repeat  <char> <N>     — repeat a character N times (Unicode safe)
#
# Notes:
#   • strip_ansi and str_repeat are pure bash (regex loop / parameter
#     expansion) — no subprocess, as of v0.1.2. A prompt with a full row of
#     colored segments calls these dozens of times per render; each used to
#     be a sed or awk fork, which is real, measurable latency on every
#     keystroke, not just a style concern.
#   • str_width still forks `wc` for non-ASCII input (ASCII input is free —
#     ${#s} is exact in any locale). A locale-independent UTF-8 codepoint
#     count is possible in pure bash but needs a byte-scanning loop tricky
#     enough to be a net loss for maintainability against one fork per
#     colored segment; left as-is deliberately, not an oversight.
#     LC_ALL=C.UTF-8 forces correct multi-byte counting (─ ═ ╭ etc. as 1
#     column) even in a POSIX/C locale, which is common on HPC login nodes.
# ════════════════════════════════════════════════════════════════════════════

[[ -n "${_TERM_UTILS_SH_LOADED-}" ]] && return 0
readonly _TERM_UTILS_SH_LOADED=1

# Remove readline \001..\002 markers and ANSI escape sequences from a string:
# CSI sequences (color, cursor movement, erase — any letter terminator, not
# just SGR/erase-line) and OSC sequences (e.g. terminal title, BEL-terminated).
# Pure bash: repeatedly finds the leftmost match with the builtin regex
# engine and splices it out — same three patterns the old sed script used,
# no subprocess.
strip_ansi() {
    local s="$1" out=""
    local re=$'\001[^\002]*\002|\033\\[[0-9;]*[A-Za-z]|\033\\][^\007]*\007'
    while [[ "$s" =~ $re ]]; do
        out+="${s%%"${BASH_REMATCH[0]}"*}"
        s="${s#*"${BASH_REMATCH[0]}"}"
    done
    printf '%s' "${out}${s}"
}

# Count the visible Unicode columns (code points) in a string.
#
# Fast path: pure-ASCII strings have ${#} == visible width in any locale,
# so we skip the subprocess entirely.  Non-ASCII strings (containing
# box-drawing chars, arrows, checkmarks, etc.) are piped through
# LC_ALL=C.UTF-8 wc -m which counts code points independent of locale.
# Precondition: input must already be ANSI-free (run strip_ansi first) —
# escape bytes are not code points and would inflate the count.
str_width() {
    case "$1" in
        *[![:ascii:]]*) printf '%s' "$1" | LC_ALL=C.UTF-8 wc -m | tr -d ' \t' ;;
        *)              echo "${#1}" ;;
    esac
}

# Repeat character $1 exactly $2 times.
# Pads a string of $2 spaces, then substitutes every space for $1. $1 is
# escaped as a LITERAL replacement first: bash's ${//pat/repl} treats an
# unescaped & in repl as "the matched text" (i.e. a space) — str_repeat '&'
# would silently produce spaces instead of ampersands without this. A
# multi-byte char like ─ (U+2500, 3 bytes in UTF-8) still inserts whole,
# once per space, same as the old awk version's per-character iteration.
str_repeat() {
    local n="${2:-0}"
    (( n < 1 )) && return
    local pad; printf -v pad '%*s' "$n" ''
    local esc="${1//&/\\&}"
    printf '%s' "${pad// /$esc}"
}
