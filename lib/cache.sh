#!/usr/bin/env bash
# Toolkit version: 0.1.4
# ════════════════════════════════════════════════════════════════════════════
# lib/cache.sh — Generic TTL bookkeeping for bash scripts
#
# Tracks "when was <key> last refreshed" and answers whether that's still
# within a caller-supplied TTL. Deliberately does not store the cached
# *value* itself — different callers cache different shapes of data (a
# single percentage, a dozen git fields) — only the refresh timestamp.
# Callers keep their own state; this just tells them when to update it.
#
# Usage:
#   if cache_stale mykey 10; then
#       … expensive work, update your own state …
#       cache_touch mykey
#   fi
#
# A caller with its own smarter invalidation (e.g. a file's mtime) composes
# it directly rather than through a callback — this stays a plain TTL clock:
#   if my_mtime_changed || cache_stale mykey 10; then … ; fi
#
# IMPORTANT — call cache_touch from the SAME shell process that will later
# read the cache, never from inside a subshell (a segment invoked as
# val=$(segfunc), a pipeline, a background job). Assignments made inside a
# subshell vanish when it exits; the write silently no-ops from the
# caller's point of view — every value gets recomputed on every call, with
# no error to signal it. If you cache something inside a function that
# gets invoked via command substitution, cache_touch there does nothing.
#
# Functions:
#   cache_stale <key> [ttl_seconds]   — 0 (stale/never touched) or 1 (fresh)
#   cache_touch <key>                 — record key as refreshed now
#   cache_age   <key>                 — seconds since last touch, or -1
#
# [v0.1.3] Clock source: EPOCHSECONDS (bash 5.0+) when available — a real
# wall-clock counter no script would plausibly reassign. Bash before 5.0
# falls back to $SECONDS, which IS commonly reassigned (`SECONDS=0` to
# time an operation is a very ordinary idiom) — cache_stale treats any
# negative elapsed time on that fallback path as stale rather than
# trusting a clock that just appeared to run backwards.
# ════════════════════════════════════════════════════════════════════════════

[[ -n "${_CACHE_SH_LOADED-}" ]] && return 0
readonly _CACHE_SH_LOADED=1

declare -gA _CACHE_TOUCHED=()   # key → clock reading at last cache_touch

# Clock selection, decided once at load time. EPOCHSECONDS (bash 5.0+) is
# preferred: unlike $SECONDS, no ordinary script has a reason to reassign
# it, so it can't be silently clobbered by an unrelated `SECONDS=0`
# elsewhere in the same shell.
declare -gi _CACHE_USE_EPOCH=0
(( BASH_VERSINFO[0] >= 5 )) && _CACHE_USE_EPOCH=1

# Has <key> not been refreshed within <ttl_seconds> (default 5)?
cache_stale() {
    local key="$1" ttl="${2:-5}"
    local last="${_CACHE_TOUCHED[$key]-}"
    [[ -z "$last" ]] && return 0             # never touched: stale

    local now delta
    (( _CACHE_USE_EPOCH )) && now=$EPOCHSECONDS || now=$SECONDS
    delta=$(( now - last ))

    # On the $SECONDS fallback, a negative delta means something reset the
    # clock out from under us (SECONDS=0 is the common case) — treat that
    # as stale rather than as "fresh forever until real time catches up".
    (( delta < 0 )) && return 0
    (( delta < ttl )) && return 1            # within TTL: fresh
    return 0
}

# Record <key> as freshly refreshed, timestamped now.
cache_touch() {
    (( _CACHE_USE_EPOCH )) && _CACHE_TOUCHED["$1"]=$EPOCHSECONDS || _CACHE_TOUCHED["$1"]=$SECONDS
}

# Seconds since <key> was last touched, or -1 if it never has been.
# Useful for prompt_debug-style diagnostics. Reports the raw delta,
# negative included, since a negative reading is itself a useful signal
# to a human debugging a stuck cache — cache_stale is what treats it as
# "gate the expensive work", cache_age just reports the number honestly.
cache_age() {
    local last="${_CACHE_TOUCHED[$1]-}"
    [[ -z "$last" ]] && { printf -- '-1'; return; }
    local now
    (( _CACHE_USE_EPOCH )) && now=$EPOCHSECONDS || now=$SECONDS
    printf '%d' "$(( now - last ))"
}
