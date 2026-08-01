#!/usr/bin/env bash
# install.sh — copy the toolkit to a target directory and print the
# .bashrc lines to add. Toolkit version: 0.1.4
#
# Usage: ./install.sh [target_dir]
#   target_dir defaults to ~/.local/share/bash-prompt-toolkit
#
# This script only copies files and prints instructions — it does not
# edit your .bashrc for you. Deliberate: your shell startup files are
# yours to control, and a script silently appending to them is exactly
# the kind of thing that's hard to debug later ("why does my prompt
# look different, I don't remember adding this").
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$HOME/.local/share/bash-prompt-toolkit}"

# Warn (don't block) on an old bash — see README.md's Requirements
# section for what each version threshold buys you.
if (( BASH_VERSINFO[0] < 4 )); then
    printf 'WARNING: bash %d.%d detected. This toolkit needs bash 4.0+\n' \
        "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" >&2
    printf '(associative arrays, used throughout). Installing anyway,\n' >&2
    printf 'but it will not run correctly until you source it under a newer bash.\n' >&2
elif (( BASH_VERSINFO[0] < 5 )); then
    printf 'Note: bash %d.%d detected. bash 5.0+ is recommended (not required)\n' \
        "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" >&2
    printf 'for stronger TTL-cache correctness — see README.md Requirements.\n' >&2
fi

if [[ -e "$TARGET" ]]; then
    printf 'install.sh: %s already exists.\n' "$TARGET" >&2
    printf 'Remove it first, or choose a different target directory.\n' >&2
    exit 1
fi

mkdir -p "$TARGET"
cp -r "$SRC_DIR/lib" "$TARGET/"
cp "$SRC_DIR/prompt.sh" "$SRC_DIR/prompt_example.sh" "$TARGET/"
[[ -f "$SRC_DIR/README.md" ]] && cp "$SRC_DIR/README.md" "$TARGET/"

printf 'Installed to: %s\n\n' "$TARGET"
printf 'Add these two lines to your .bashrc, in this order:\n\n'
printf '    source %s/prompt.sh\n' "$TARGET"
printf '    source %s/prompt_example.sh\n\n' "$TARGET"
printf 'prompt_example.sh is a starting configuration, meant to be\n'
printf 'edited directly — open %s/prompt_example.sh\n' "$TARGET"
printf 'and adjust the segments, rows, and active layout to taste.\n'
