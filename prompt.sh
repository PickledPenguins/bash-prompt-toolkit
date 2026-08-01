#!/usr/bin/env bash
# Toolkit version: 0.1.4
# ════════════════════════════════════════════════════════════════════════════
# prompt.sh — Composable bash prompt builder
# Architecture: Segment → Row → Layout → PS1
#
#   Segment  Named function writing content to stdout. Knows nothing about
#            layout or box style. Use C_* / PS_* vars for color.
#
#   Row      Named template string. Tokens:
#              @segname   expands to segment output (one @fill per row max)
#              @fill      fills remaining line width with the border char
#            Tokens have no end delimiter — avoid a segment name that is a
#            literal prefix of adjacent template text.
#
#   Layout   Ordered row list with optional box decoration.
#            Default (open):  last row is  ╰─content — cursor follows.
#            Closed (--closed): last row gets ╯, cursor drops to new line.
#
# Library modules sourced automatically from lib/ next to this file:
#   lib/git_info.sh    — git state + mtime/TTL cache (GIT_* globals)
#   lib/term_utils.sh  — strip_ansi  str_width  str_repeat
#   lib/colors.sh      — C_* and PS_* color variables, c_fg/c_bg helpers
#   lib/cache.sh       — generic TTL bookkeeping (used by git_info.sh + @gpu)
#   lib/cmd_timer.sh   — command-duration tracking behind @cmd_time
#
# Setup — add to .bashrc:
#   source ~/dotfiles/prompt.sh
#   source ~/dotfiles/prompt.example.sh
#
# Built-in segment functions (register with prompt_segment <name> <func>):
#   _ps_seg_user  _ps_seg_host  _ps_seg_user_host  _ps_seg_root  _ps_seg_pwd
#   _ps_seg_git_branch  _ps_seg_git_remote  _ps_seg_git_ahead_behind
#   _ps_seg_git_status  _ps_seg_git_stash  _ps_seg_git_conflicts
#   _ps_seg_tmux  _ps_seg_display  _ps_seg_ssh  _ps_seg_venv
#   _ps_seg_jobs  _ps_seg_exit  _ps_seg_time
#   _ps_seg_cmd_time  _ps_seg_conda  _ps_seg_shlvl  _ps_seg_modules
#   _ps_seg_load  _ps_seg_disk  _ps_seg_gpu
#   _ps_seg_pbs_job  _ps_seg_pbs_queue  _ps_seg_pbs_nodes
#   _ps_seg_slurm_job  _ps_seg_slurm_queue  _ps_seg_slurm_nodes
# ════════════════════════════════════════════════════════════════════════════

[[ -n "${_PROMPT_SH_LOADED-}" ]] && return 0
readonly _PROMPT_SH_LOADED=1

# SECURITY: disable bash's promptvars expansion. By default bash re-parses
# PS1's stored value for command substitution ($(...), backticks, ${...},
# $((...))) on every single prompt render. Directory names, git branch
# names, $VIRTUAL_ENV, $USER, and $HOSTNAME can all legally contain $(...)
# text, and it would otherwise execute repeatedly for as long as it stays
# part of the active prompt. Backslash prompt-escapes (\$, \n, \u, \h, \w)
# are a separate, always-on bash mechanism and are unaffected by this.
shopt -u promptvars

# Source library modules relative to this file's location
_PROMPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_PROMPT_DIR}/lib/cache.sh"
source "${_PROMPT_DIR}/lib/git_info.sh"
source "${_PROMPT_DIR}/lib/term_utils.sh"
source "${_PROMPT_DIR}/lib/colors.sh"
colors_init prompt   # switch C_* / PS_* to readline-safe \001..\002 format

# cmd_timer.sh is standalone and doesn't know it's being used by a prompt,
# so its own DEBUG-trap opt-out is CMD_TIMER_SKIP_TRAP. PS_SKIP_DEBUG_TRAP
# is kept working as an alias so existing configs don't silently break.
[[ -n "${PS_SKIP_DEBUG_TRAP-}" && -z "${CMD_TIMER_SKIP_TRAP-}" ]] && CMD_TIMER_SKIP_TRAP=1
source "${_PROMPT_DIR}/lib/cmd_timer.sh"
unset _PROMPT_DIR

# Core count for the load segment's busy threshold — invariant for the
# life of the shell, so this forks nproc once here instead of once per
# render (as _ps_seg_load used to).
declare -gi _PS_CORES=1
_PS_CORES=$(nproc 2>/dev/null) || _PS_CORES=1

# ps_fg/ps_bg — thin wrappers kept for any existing code using the old names
ps_fg() { c_fg "$@"; }
# Background-color escape — wrapper kept for code using the old name.
ps_bg() { c_bg "$@"; }

# ── Prompt engine state ────────────────────────────────────────────────────
declare -gA _PS_SEGS=()          # segment name → function name
declare -gA _PS_ROWS=()          # row name → template string
declare -ga _PS_ORDER=()         # row names in display order
declare -ga _PS_SEGS_SORTED=()   # segment names, longest-first (expansion order)
declare -g    _PS_BOX=0            # 1 = wrap rows in a unicode box
declare -g    _PS_CLOSED=0         # 1 = close box (╯) on last row; 0 = open
declare -g    _PS_STYLE="rounded"
declare -g    _PS_HAS_GIT=0        # 1 = at least one git-dependent segment registered
declare -g    _PS_HAS_GPU=0        # 1 = a gpu-dependent segment is registered
declare -g    _PS_HAS_DISK=0       # 1 = a disk-dependent segment is registered
declare -g    _PS_HAS_LOAD=0       # 1 = a load-dependent segment is registered

# Which collected data each built-in segment FUNCTION depends on.
#
# [v0.1.4] Keyed on the function, not on the name it's registered under.
# Previously these flags were set by string-matching the registered name
# (`git_*`, `gpu`, `disk`, `load`), which silently broke any alias: a user
# writing `prompt_segment gpu_util _ps_seg_gpu` or `prompt_segment branch
# _ps_seg_git_branch` got a permanently blank segment, because the
# corresponding refresh never ran and nothing reported a problem. Aliasing
# is exactly what the row-template system invites, so it must not be a
# trap. Custom segments needing their own cached data declare it with
# prompt_segment_needs (below) rather than being guessed at by name.
declare -gA _PS_SEG_NEEDS=(
    [_ps_seg_git_branch]=git       [_ps_seg_git_remote]=git
    [_ps_seg_git_ahead_behind]=git [_ps_seg_git_status]=git
    [_ps_seg_git_stash]=git        [_ps_seg_git_conflicts]=git
    [_ps_seg_gpu]=gpu
    [_ps_seg_disk]=disk
    [_ps_seg_load]=load
)

# ── Box character sets ────────────────────────────────────────────────────
declare -gA _PS_CHARS=(
    [rounded_tl]="╭"  [rounded_tr]="╮"  [rounded_bl]="╰"  [rounded_br]="╯"
    [rounded_h]="─"   [rounded_v]="│"
    [sharp_tl]="┌"    [sharp_tr]="┐"    [sharp_bl]="└"    [sharp_br]="┘"
    [sharp_h]="─"     [sharp_v]="│"
    [double_tl]="╔"   [double_tr]="╗"   [double_bl]="╚"   [double_br]="╝"
    [double_h]="═"    [double_v]="║"
    [ascii_tl]="+"    [ascii_tr]="+"    [ascii_bl]="+"    [ascii_br]="+"
    [ascii_h]="-"     [ascii_v]="|"
)

# ── Command timer + gpu/disk/load cache values ──────────────────────────────
# Command-duration tracking (the DEBUG trap, arm/elapsed logic) now lives in
# lib/cmd_timer.sh, sourced above — nothing prompt-specific about it.
# cache.sh tracks *when* each value was last refreshed; the values
# themselves still live here since cache.sh deliberately doesn't store
# values (see lib/cache.sh's header — different segments cache different
# shapes of data). Populated by _ps_refresh_gpu/_disk/_load, called from
# prompt_build — never write these from inside a *_seg_* function; those
# run via command substitution (a subshell) and any assignment made there
# is silently lost when it exits. See prompt_build's comment for why.
declare -g _PS_GPU_CACHE_VAL=""    # nvidia-smi utilization.gpu, or "" if unavailable
declare -g _PS_DISK_CACHE_VAL=""   # usage percent, or "" if unavailable/not near capacity
declare -g _PS_LOAD_CACHE_VAL=""   # 1-min load average, or "" if unavailable/not busy

# ── Row template expansion ─────────────────────────────────────────────────

# Expand a row template into its final display string: a single
# left-to-right scan over the ORIGINAL template text, consuming one @token
# or one literal character at a time.
#   1. @segname expands to segment output, longest names first so
#      @git_branch is matched before a shorter @git prefix could shadow it.
#   2. @fill is left as a placeholder, resolved in a second pass below once
#      the full line's width is known.
#
# [v0.1.2] Rewritten from repeated whole-string substitution, which had a
# real bug: replacing @name globally across the *entire accumulated result*
# meant a later pass could match "@othername"-shaped text that came from an
# EARLIER segment's actual output (a branch like feature/@venv-fix, a path,
# a hostname) — not from the template — and wrongly re-expand it. Scanning
# the template once, left to right, and never revisiting already-emitted
# output makes that class of bug structurally impossible rather than
# patching around specific cases.
#
# $1  template string
# $2  effective terminal width (caller reduces by box border char count)
_ps_expand() {
    local tmpl="$1" tw="${2:-${COLUMNS:-80}}"
    local result="" plain="" rest="$tmpl"
    local name val matched

    # [v0.1.3 fix] _ps_resort_segments is a no-op unless something
    # registered since the last call, so this is cheap in the normal
    # (prompt_build already called it) case — but without it here,
    # _ps_expand silently produced nothing for every token whenever
    # called before prompt_build had run once, e.g. directly from a
    # test or from prompt_debug-style tooling. Found by my own
    # regression test for the OTHER bug this file fixes, which calls
    # _ps_expand directly and stopped working.
    _ps_resort_segments

    while [[ -n "$rest" ]]; do
        if [[ "${rest:0:1}" != "@" ]]; then
            # Fast path: most characters are literal (spaces, borders,
            # icons) — one comparison, no token-list scan.
            result+="${rest:0:1}"; plain+="${rest:0:1}"
            rest="${rest:1}"
            continue
        fi

        if [[ "$rest" == '@fill'* ]]; then
            result+='@fill'; plain+='@fill'
            rest="${rest#@fill}"
            continue
        fi

        matched=0
        for name in "${_PS_SEGS_SORTED[@]}"; do
            [[ "$rest" == "@${name}"* ]] || continue
            if [[ -n "${PS_DEBUG_SEGMENTS-}" ]]; then
                val=$("${_PS_SEGS[$name]}")
                local seg_rc=$?
                if (( seg_rc != 0 )); then
                    printf 'prompt: segment "%s" (%s) exited %d\n' \
                        "$name" "${_PS_SEGS[$name]}" "$seg_rc" >&2
                    val=""   # a diagnostic must not change what renders
                fi
            else
                val=$("${_PS_SEGS[$name]}" 2>/dev/null) || val=""
            fi
            result+="$val"
            # Skip the strip_ansi call when the segment returned plain text.
            # Readline markers start with \001; their absence means no ANSI.
            [[ "$val" == *$'\001'* ]] && plain+="$(strip_ansi "$val")" || plain+="$val"
            rest="${rest#"@${name}"}"
            matched=1
            break
        done
        if (( ! matched )); then
            # Bare '@' matching no known token — pass it through literally,
            # same as the old code did for unmatched text.
            result+="@"; plain+="@"
            rest="${rest:1}"
        fi
    done

    if [[ "$result" == *"@fill"* ]]; then
        # Measure text flanking @fill in the stripped copy.
        # str_width gives code-point count so ─ counts as 1, not 3 bytes.
        local pre="${plain%%@fill*}" post="${plain##*@fill}"
        local fill_len=$(( tw - $(str_width "$pre") - $(str_width "$post") ))
        result="${result//@fill/$(str_repeat "${_PS_CHARS[${_PS_STYLE}_h]:-─}" "$fill_len")}"
    fi

    printf '%s' "$result"
}

# ── Public API ─────────────────────────────────────────────────────────────

declare -g _PS_SEGS_DIRTY=0   # 1 = _PS_SEGS_SORTED needs rebuilding before next use

# Register a named segment.
# $1  name       Token used in row templates as @name.
# $2  function   Bash function that writes display text to stdout.
#                May use C_* / PS_* color variables.
prompt_segment() {
    local name="$1" func="$2"
    [[ -z "$name" || -z "$func" ]] && {
        printf 'prompt_segment: usage: <name> <function>\n' >&2
        return 1
    }
    _PS_SEGS["$name"]="$func"
    # Arm whichever refresh this segment's FUNCTION depends on, regardless
    # of the name it was registered under.
    case "${_PS_SEG_NEEDS[$func]-}" in
        git)  _PS_HAS_GIT=1  ;;
        gpu)  _PS_HAS_GPU=1  ;;
        disk) _PS_HAS_DISK=1 ;;
        load) _PS_HAS_LOAD=1 ;;
    esac
    _PS_SEGS_DIRTY=1
}

# Declare that a segment function depends on collected data, so
# prompt_build refreshes it. For custom segments wrapping built-in data:
#   _my_branch() { printf '⎇ %s' "$GIT_BRANCH"; }
#   prompt_segment_needs _my_branch git      # before prompt_segment
#   prompt_segment mybranch _my_branch
# $1  function name   $2  one of: git | gpu | disk | load
prompt_segment_needs() {
    local func="$1" need="$2"
    case "$need" in
        git|gpu|disk|load) _PS_SEG_NEEDS["$func"]="$need" ;;
        *) printf 'prompt_segment_needs: unknown dependency "%s" (expected git, gpu, disk, or load)\n' "$need" >&2
           return 1 ;;
    esac
}

# Rebuild _PS_SEGS_SORTED (longest-name-first, so @git_branch matches
# before a shorter @git could shadow it) — but only when something has
# actually changed since the last rebuild.
#
# [v0.1.3] Previously this ran inline in prompt_segment, forking
# awk|sort|cut on every single registration call. A typical config
# registering ~30 segments paid for ~30 re-sorts at shell-startup time
# (measured ~175-215ms) to produce one final list — every intermediate
# sort was thrown away by the next registration. Deferred here instead:
# called once per render from prompt_build, a no-op unless something
# registered since the last call.
_ps_resort_segments() {
    (( _PS_SEGS_DIRTY )) || return
    _PS_SEGS_SORTED=()
    while IFS= read -r n; do _PS_SEGS_SORTED+=("$n"); done < <(
        printf '%s\n' "${!_PS_SEGS[@]}" |
            awk '{ print length" "$0 }' | sort -rn | cut -d' ' -f2-
    )
    _PS_SEGS_DIRTY=0
}

# Define a named row template.
# $1  name      Referenced by prompt_layout.
# $2  template  Literal text + @segname tokens + one optional @fill spacer.
prompt_row() {
    local name="$1" tmpl="$2"
    [[ -z "$name" ]] && {
        printf 'prompt_row: usage: <name> <template>\n' >&2
        return 1
    }
    _PS_ROWS["$name"]="$tmpl"
}

# Set the prompt layout: ordered rows + optional box decoration.
#
# Usage: prompt_layout [--box [style]] [--closed] <row1> [row2…]
#
#   --box [style]   Draw a unicode box.  Styles: rounded (default) | sharp |
#                   double | ascii
#   --closed        Close box with ╯ on last row; cursor on new line below.
#   --no-box        No box decoration (default).
#
# Prepends prompt_build to PROMPT_COMMAND so it always runs first and
# captures $? before any other handler can clobber it.
prompt_layout() {
    _PS_ORDER=(); _PS_BOX=0; _PS_CLOSED=0; _PS_STYLE="rounded"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --box)
                _PS_BOX=1
                [[ -n "${2-}" && "${2}" != --* ]] && { _PS_STYLE="$2"; shift; }
                ;;
            --closed) _PS_CLOSED=1 ;;
            --no-box) _PS_BOX=0    ;;
            *)        _PS_ORDER+=("$1") ;;
        esac
        shift
    done

    # Prepend once — checks the exact call token (start of string, or right
    # after a "; "), not a bare substring, so a differently-named function
    # that merely contains "prompt_build" can't cause a false-positive skip.
    if [[ "${PROMPT_COMMAND-}" != 'prompt_build'* && "${PROMPT_COMMAND-}" != *'; prompt_build'* ]]; then
        PROMPT_COMMAND="prompt_build${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
    fi
}

# Print current configuration to stderr — useful during layout development.
prompt_debug() {
    printf '=== prompt.sh  box=%d  closed=%d  style=%s ===\n' \
        "$_PS_BOX" "$_PS_CLOSED" "$_PS_STYLE" >&2
    printf 'rows:\n' >&2
    local r; for r in "${_PS_ORDER[@]}"; do
        printf '  %-16s %s\n' "$r" "${_PS_ROWS[$r]:-<undefined>}" >&2
    done
    printf 'segments:\n' >&2
    local s; for s in "${!_PS_SEGS[@]}"; do
        printf '  @%-20s → %s\n' "$s" "${_PS_SEGS[$s]}" >&2
    done
    printf 'git cache:  dir=%s  age=%ss  ttl=%ds\n' \
        "${_GIT_CACHE_DIR:-(none)}" \
        "$(cache_age git_info)" \
        "$_GIT_CACHE_TTL" >&2
    (( _PS_HAS_GPU  )) && printf 'gpu cache:  age=%ss  ttl=10s  val=%s\n'  "$(cache_age gpu)"  "${_PS_GPU_CACHE_VAL:-(none)}"  >&2
    (( _PS_HAS_DISK )) && printf 'disk cache: age=%ss  ttl=30s  val=%s\n' "$(cache_age disk)" "${_PS_DISK_CACHE_VAL:-(none)}" >&2
    (( _PS_HAS_LOAD )) && printf 'load cache: age=%ss  ttl=10s  val=%s\n' "$(cache_age load)" "${_PS_LOAD_CACHE_VAL:-(none)}" >&2
    printf 'raw PS1: '; printf '%s' "$PS1" | cat -v >&2; printf '\n' >&2
}

# Backward-compatible wrappers — delegate to the library functions
prompt_cache_ttl()          { git_info_cache_ttl "$@"; }
# Set the minimum seconds a command must run before @cmd_time displays it.
prompt_cmd_time_threshold() { _PS_CMD_TIME_MIN="${1:-2}"; }

# ── Builder ────────────────────────────────────────────────────────────────

# Rebuilds PS1 before each prompt display. Wired in by prompt_layout via
# PROMPT_COMMAND. The $? capture MUST remain the very first statement.
prompt_build() {
    local last_exit=$?
    PROMPT_LAST_EXIT=$last_exit   # global — readable by all segment functions

    # Compute how long the last user command ran (sets $_CMD_TIMER_ELAPSED).
    cmd_timer_elapsed

    _ps_resort_segments   # also called inside _ps_expand itself; cheap either way, kept here for a predictable point in the render sequence

    # Refresh git data only when the cache is stale.
    # Cache hit: ~2 stat calls (<1 ms). Cache miss: full git_info_refresh.
    (( _PS_HAS_GIT )) && { git_info_cache_valid || git_info_refresh; }

    # [v0.1.3] gpu/disk/load data collection happens HERE, in the parent
    # shell — not inside the segment functions. Segments run via
    # val=$(segfunc), a subshell; any cache_touch or value assignment made
    # there is lost the instant the subshell exits. That was a real,
    # verified bug: the @gpu segment's TTL cache never once took effect —
    # every render re-forked nvidia-smi regardless of its 10s TTL. The
    # rule going forward: data collection happens in prompt_build,
    # segments only format already-collected globals — same pattern the
    # git segments have always used.
    (( _PS_HAS_GPU  )) && { cache_stale gpu  10 && _ps_refresh_gpu;  }
    (( _PS_HAS_DISK )) && { cache_stale disk 30 && _ps_refresh_disk; }
    (( _PS_HAS_LOAD )) && { cache_stale load 10 && _ps_refresh_load; }

    local tw=${COLUMNS:-0}
    (( tw > 0 )) || tw=$(tput cols 2>/dev/null || echo 80)

    local nrows=${#_PS_ORDER[@]}
    (( nrows == 0 )) && { PS1='\$ '; return; }

    local c_h="${_PS_CHARS[${_PS_STYLE}_h]:-─}"  c_v="${_PS_CHARS[${_PS_STYLE}_v]:-│}"
    local c_tl="${_PS_CHARS[${_PS_STYLE}_tl]:-┌}" c_tr="${_PS_CHARS[${_PS_STYLE}_tr]:-┐}"
    local c_bl="${_PS_CHARS[${_PS_STYLE}_bl]:-└}"  c_br="${_PS_CHARS[${_PS_STYLE}_br]:-┘}"

    local ps1="" i
    for (( i=0; i<nrows; i++ )); do
        local rname="${_PS_ORDER[$i]}"
        local tmpl="${_PS_ROWS[$rname]:-}"
        local has_fill=0; [[ "$tmpl" == *@fill* ]] && has_fill=1
        local is_last=0;  (( i == nrows-1 )) && is_last=1

        if (( ! _PS_BOX )); then
            local content; content=$(_ps_expand "$tmpl" "$tw")
            (( is_last )) && ps1+="$content" || ps1+="${content}\n"
            continue
        fi

        local budget=$(( tw - 2 ))
        local content; content=$(_ps_expand "$tmpl" "$budget")

        # Checks lead with is_last (not i==0) so a single-row box — where
        # i==0 and is_last are both true — gets last-row treatment instead
        # of always falling into the top-border/top-corner branch. That was
        # the bug: a single-row box previously always rendered as a bare top
        # border with no prompt escape at all, in either --closed or open
        # mode, since i==0 was checked first and unconditionally won.
        #
        # Auto-fill rows without @fill.
        # Closed last row (incl. single-row closed): pad with bar char.
        # Open last row (incl. single-row open): no padding — cursor follows.
        # Top border of a real multi-row box: pad with bar char.
        # Inner rows: pad with spaces.
        if (( ! has_fill )); then
            local plain; plain=$(strip_ansi "$content")
            local pad=$(( budget - $(str_width "$plain") ))
            if (( pad > 0 )); then
                if (( is_last && _PS_CLOSED )); then
                    content+=$(str_repeat "$c_h" "$pad")
                elif (( is_last )); then
                    :   # open last row: intentionally no pad, cursor follows
                elif (( i == 0 )); then
                    content+=$(str_repeat "$c_h" "$pad")
                else
                    content+=$(printf '%*s' "$pad" '')
                fi
            fi
        fi

        if (( is_last && _PS_CLOSED )); then
            # Closed: seal the box, cursor on new line with \$ prompt char.
            # A single row (i==0 too) opens with the top-left corner, since
            # nothing is drawn above it.
            local left=$c_bl; (( i == 0 )) && left=$c_tl
            ps1+="${left}${content}${c_br}"$'\n''\$ '
        elif (( is_last )); then
            # Open: no right corner — cursor follows content directly
            local left=$c_bl; (( i == 0 )) && left=$c_tl
            ps1+="${left}${content}"
        elif (( i == 0 )); then
            ps1+="${c_tl}${content}${c_tr}\n"
        else
            ps1+="${c_v}${content}${c_v}\n"
        fi
    done

    PS1="$ps1"
    cmd_timer_arm   # the next user command will record its start time
}

# ════════════════════════════════════════════════════════════════════════════
# Built-in segment functions
# Register any of these with:  prompt_segment <alias> <function_name>
# Git segments read GIT_* globals (populated by git_info_refresh in
# lib/git_info.sh) — no additional git subprocess cost.
# ════════════════════════════════════════════════════════════════════════════

# ── Identity ──────────────────────────────────────────────────────────────
_ps_seg_user()      { printf '%s'    "${USER:-$(id -un)}"; }
# Short hostname, domain stripped.
_ps_seg_host()      { printf '%s'    "${HOSTNAME%%.*}"; }
# Plain user@host, domain stripped. See prompt_example.sh for a colored variant.
_ps_seg_user_host() { printf '%s@%s' "${USER:-$(id -un)}" "${HOSTNAME%%.*}"; }

# Root/privileged-shell indicator — silent for normal users. $EUID is a
# bash-managed, read-only builtin; nothing in the environment can spoof it.
_ps_seg_root() {
    (( EUID == 0 )) || return
    printf '%s⚡%s' "$C_BRED" "$C_R"
}

# Working directory — $HOME collapsed to ~, capped at 35 visible chars.
# Directory names may legally contain control bytes and escape sequences;
# strip both before they can reach PS1. Truncation then uses str_width/cut
# (code-point aware) instead of ${#p}/${p: -N}, which count/slice by byte
# and can cut a multi-byte character in half outside a UTF-8 locale.
_ps_seg_pwd() {
    local p="${PWD/#$HOME/\~}"
    p=$(strip_ansi "$p")
    p=$(tr -d '\000-\037\177' <<< "$p")
    local w; w=$(str_width "$p")
    (( w > 35 )) && p="…$(LC_ALL=C.UTF-8 cut -c "$(( w - 31 ))-" <<< "$p")"
    printf '%s' "$p"
}

# ── Git (all read GIT_* from lib/git_info.sh; no extra git calls) ─────────

# Current branch name, or short SHA when HEAD is detached.
_ps_seg_git_branch() {
    (( GIT_IN_REPO )) || return
    printf '%s' "$GIT_BRANCH"
}

# Upstream tracking branch, silent when the branch has no remote.
_ps_seg_git_remote() {
    (( GIT_IN_REPO )) && [[ -n "$GIT_REMOTE" ]] || return
    printf '%s' "$GIT_REMOTE"
}

# ↑N ahead (green)  ↓N behind (yellow)  ✓ if up to date  — silent if no remote
_ps_seg_git_ahead_behind() {
    (( GIT_IN_REPO )) && [[ -n "$GIT_REMOTE" ]] || return
    if (( GIT_AHEAD == 0 && GIT_BEHIND == 0 )); then
        printf '%s✓%s' "$C_GREEN" "$C_R"
        return
    fi
    local r=""
    (( GIT_AHEAD  > 0 )) && r+="${C_GREEN}↑${GIT_AHEAD}${C_R} "
    (( GIT_BEHIND > 0 )) && r+="${C_YELLOW}↓${GIT_BEHIND}${C_R}"
    printf '%s' "${r% }"
}

# +N staged (green)  ~N modified (yellow)  ?N untracked (dim) — silent if clean
_ps_seg_git_status() {
    (( GIT_IN_REPO )) || return
    local r=""
    (( GIT_STAGED    > 0 )) && r+="${C_GREEN}+${GIT_STAGED}${C_R} "
    (( GIT_MODIFIED  > 0 )) && r+="${C_YELLOW}~${GIT_MODIFIED}${C_R} "
    (( GIT_UNTRACKED > 0 )) && r+="${C_DIM}?${GIT_UNTRACKED}${C_R}"
    [[ -n "$r" ]] && printf '%s' "${r% }"
}

# ⚑N stash count — silent when no stashes or not in a repo
_ps_seg_git_stash() {
    (( GIT_IN_REPO && GIT_STASH > 0 )) || return
    printf '⚑%d' "$GIT_STASH"
}

# ⚠N unmerged/conflicted paths (bold red) — silent when none or not in a repo
_ps_seg_git_conflicts() {
    (( GIT_IN_REPO && GIT_CONFLICTS > 0 )) || return
    printf '%s⚠%d%s' "$C_BRED" "$GIT_CONFLICTS" "$C_R"
}

# ── Environment ───────────────────────────────────────────────────────────

# tmux session:window.pane, sanitized (session names are user-settable).
_ps_seg_tmux() {
    [[ -z "${TMUX-}" ]] && return
    local info; info=$(tmux display-message -p '#S:#I.#P' 2>/dev/null) || return
    info=$(strip_ansi "$info")               # session names are user-settable
    info=$(tr -d '\000-\037\177' <<< "$info")
    printf '⧉ %s' "$info"
}

# $DISPLAY value, indicating X11 forwarding is active.
_ps_seg_display() { [[ -n "${DISPLAY-}" ]] && printf '%s' "$DISPLAY"; }

# Marker shown when this shell arrived over SSH.
_ps_seg_ssh()     { [[ -n "${SSH_CLIENT-}" || -n "${SSH_TTY-}" ]] && printf '⇄ ssh'; }

# Active Python virtualenv name in parentheses.
_ps_seg_venv()    { [[ -n "${VIRTUAL_ENV-}" ]] && printf '(%s)' "$(basename "$VIRTUAL_ENV")"; }

# Count of background jobs in this shell, silent when there are none.
_ps_seg_jobs() {
    local -a j; mapfile -t j < <(jobs 2>/dev/null)
    (( ${#j[@]} > 0 )) && printf '⚙ %d' "${#j[@]}"
}

# Last command's exit status: a checkmark, or a cross plus the code.
_ps_seg_exit() {
    if (( ${PROMPT_LAST_EXIT:-0} == 0 )); then
        printf '%s✓%s'    "$C_GREEN" "$C_R"
    else
        printf '%s✗ %d%s' "$C_RED" "${PROMPT_LAST_EXIT:-0}" "$C_R"
    fi
}

# Current wall-clock time, HH:MM.
_ps_seg_time() { date '+%H:%M'; }

# ── Command duration ──────────────────────────────────────────────────────
declare -gi _PS_CMD_TIME_MIN=2

# Duration of the last command, shown only past _PS_CMD_TIME_MIN seconds.
_ps_seg_cmd_time() {
    (( _CMD_TIMER_ELAPSED >= _PS_CMD_TIME_MIN )) || return
    local s=$_CMD_TIMER_ELAPSED
    (( s >= 3600 )) && { printf '%dh%dm%ds' $(( s/3600 )) $(( (s%3600)/60 )) $(( s%60 )); return; }
    (( s >=   60 )) && { printf '%dm%ds'    $(( s/60 ))   $(( s%60 ));         return; }
    printf '%ds' "$s"
}

# ── Conda environment ─────────────────────────────────────────────────────
_ps_seg_conda() {
    [[ -z "${CONDA_DEFAULT_ENV-}" || "$CONDA_DEFAULT_ENV" == "base" ]] && return
    printf '(%s)' "$CONDA_DEFAULT_ENV"
}

# ── Shell depth ───────────────────────────────────────────────────────────
_ps_seg_shlvl() {
    (( ${SHLVL:-1} > 1 )) && printf '%s⬇%d%s' "$C_YELLOW" "$SHLVL" "$C_R"
}

# 1-minute load average, shown only when the node is genuinely busy
# (load exceeds core count) — quiet on an idle shared login node.
# [v0.1.3] Collection (the /proc/loadavg read and the busy-threshold
# check) moved to _ps_refresh_load, called from prompt_build and
# TTL-cached (10s) via cache.sh. Previously this forked nproc AND awk on
# *every* render, even the vast majority where it prints nothing — and
# because it ran inside the segment (a command-substitution subshell),
# nothing it computed could have been cached here even if it had tried.
_ps_refresh_load() {
    _PS_LOAD_CACHE_VAL=""
    if [[ -r /proc/loadavg ]]; then
        local load1; read -r load1 _ < /proc/loadavg
        awk -v l="$load1" -v c="$_PS_CORES" 'BEGIN { exit !(l > c) }' &&
            _PS_LOAD_CACHE_VAL="$load1"
    fi
    cache_touch load
}
# Formats the cached load average (collected by _ps_refresh_load).
_ps_seg_load() {
    [[ -n "$_PS_LOAD_CACHE_VAL" ]] && printf '⚖%s' "$_PS_LOAD_CACHE_VAL"
}

# Filesystem usage percent for $PWD, shown only near capacity (>=90%).
# Uses df rather than true quota parsing -- quota semantics vary too much
# across NFS/Lustre/GPFS to get generically right.
# [v0.1.3] Same restructuring as load: collection is now
# _ps_refresh_disk, TTL-cached (30s — usage doesn't need per-render
# freshness) and run from prompt_build instead of inside the segment.
_ps_refresh_disk() {
    _PS_DISK_CACHE_VAL=""
    local pct; pct=$(df -P . 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    [[ -n "$pct" ]] && (( pct >= 90 )) && _PS_DISK_CACHE_VAL="$pct"
    cache_touch disk
}
# Formats the cached disk usage percent (collected by _ps_refresh_disk).
_ps_seg_disk() {
    [[ -n "$_PS_DISK_CACHE_VAL" ]] && printf '%s⛁%d%%%s' "$C_BYELLOW" "$_PS_DISK_CACHE_VAL" "$C_R"
}

# ── HPC module count ──────────────────────────────────────────────────────
_ps_seg_modules() {
    [[ -z "${LOADEDMODULES-}" ]] && return
    # Some module systems emit a leading/trailing/doubled colon; squeeze and
    # trim first or a bare colon-count overcounts entries that aren't there.
    local mods; mods=$(tr -s ':' <<< "$LOADEDMODULES")
    mods="${mods#:}"; mods="${mods%:}"
    [[ -z "$mods" ]] && return
    local colons="${mods//[^:]}"
    printf '⊞ %d' $(( ${#colons} + 1 ))
}

# GPU utilization -- nvidia-smi is slow (~100ms+), so this is TTL-cached
# (10s) with a timeout guard so a misbehaving driver can't stall every
# prompt render. Silent on non-GPU nodes or if nvidia-smi is unavailable.
#
# [v0.1.3, CRITICAL FIX] This TTL cache never actually worked before —
# collection ran inside _ps_seg_gpu, which _ps_expand calls as
# val=$(_ps_seg_gpu): a command-substitution SUBSHELL. cache_touch and
# the value assignment both happened in that subshell and were discarded
# the instant it exited; the parent shell never saw them. Every render
# re-forked nvidia-smi (with its 1s timeout) regardless of the 10s TTL —
# verified directly: cache_age stayed -1 (never recorded) after repeated
# renders. Collection now runs in _ps_refresh_gpu, called from
# prompt_build in the parent shell, same as git and (as of this version)
# load/disk. The rule generalizes: DATA COLLECTION HAPPENS IN
# prompt_build; *_seg_* functions only format already-collected globals.
# Never call cache_touch from inside a segment — it will silently no-op.
_ps_refresh_gpu() {
    _PS_GPU_CACHE_VAL=""
    if command -v nvidia-smi &>/dev/null; then
        _PS_GPU_CACHE_VAL=$(timeout 1 nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    fi
    cache_touch gpu
}
# Formats the cached GPU utilization (collected by _ps_refresh_gpu).
_ps_seg_gpu() {
    [[ -n "$_PS_GPU_CACHE_VAL" ]] && printf '%sGPU %s%%%s' "$C_BCYAN" "$_PS_GPU_CACHE_VAL" "$C_R"
}

# ── PBS / Torque ──────────────────────────────────────────────────────────
_ps_seg_pbs_job()   { [[ -n "${PBS_JOBID-}"   ]] && printf 'PBS %s'  "${PBS_JOBID%%.*}"; }
# PBS queue name for the current job.
_ps_seg_pbs_queue() { [[ -n "${PBS_QUEUE-}"   ]] && printf '%s'      "$PBS_QUEUE"; }
# Count unique nodes allocated to the current PBS job.
_ps_seg_pbs_nodes() {
    [[ -f "${PBS_NODEFILE:-}" ]] || return
    # sort -u | wc -l | tr -d ' ' replaced with a plain bash dedup: this
    # segment has no TTL cache of its own and PBS_NODEFILE doesn't change
    # during a job, so it forks all three, every render, for the entire
    # life of the job — worth the small bit of extra code.
    # Each variable is declared separately on purpose: `local -A seen=()
    # line n=0` would apply -A to ALL THREE names, making `line` and `n`
    # associative arrays too. That happened to still produce the right
    # answer (bash routes the bare reads and increments through index
    # [0]) but only by accident, not by any documented rule.
    local -A seen=()
    local line
    local -i n=0
    while IFS= read -r line; do
        [[ -n "${seen[$line]-}" ]] && continue
        seen["$line"]=1
        (( n++ ))
    done < "$PBS_NODEFILE"
    (( n > 0 )) && printf '%d nodes' "$n"
}

# ── Slurm ─────────────────────────────────────────────────────────────────
_ps_seg_slurm_job()   { [[ -n "${SLURM_JOB_ID-}"        ]] && printf 'SLURM %s' "$SLURM_JOB_ID"; }
# Slurm partition name for the current job.
_ps_seg_slurm_queue() { [[ -n "${SLURM_JOB_PARTITION-}" ]] && printf '%s'        "$SLURM_JOB_PARTITION"; }
# Node count allocated to the current Slurm job.
_ps_seg_slurm_nodes() { [[ -n "${SLURM_NNODES-}"        ]] && printf '%d nodes'  "$SLURM_NNODES"; }
