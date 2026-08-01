#!/usr/bin/env bats
# Regression tests for the v0.1.2 pass: lib/cache.sh, lib/cmd_timer.sh, the
# fork-free term_utils.sh functions, and the _ps_expand token-collision fix.
#
# These cover what changed in this pass. They do not replace the existing
# suite in this directory — run both:
#   bats tests/

setup() {
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    # bats-core has its own DEBUG trap; see lib/cmd_timer.sh's header for
    # why this is an explicit opt-out rather than automatic detection.
    export CMD_TIMER_SKIP_TRAP=1
}

# ── lib/cache.sh ─────────────────────────────────────────────────────────

@test "cache_stale: a never-touched key is stale" {
    source "$ROOT/lib/cache.sh"
    run cache_stale never_touched_key 5
    [ "$status" -eq 0 ]
}

@test "cache_stale: fresh immediately after cache_touch" {
    source "$ROOT/lib/cache.sh"
    cache_touch mykey
    run cache_stale mykey 5
    [ "$status" -eq 1 ]
}

@test "cache_stale: stale once TTL has elapsed" {
    source "$ROOT/lib/cache.sh"
    cache_touch mykey
    sleep 1.2   # TTL below is 1s — real elapsed time, not $SECONDS: cache.sh
                # prefers EPOCHSECONDS on bash 5+, which manipulating
                # $SECONDS directly would not have affected.
    run cache_stale mykey 1
    [ "$status" -eq 0 ]
}

@test "cache_age: -1 for a never-touched key, 0 immediately after touch" {
    source "$ROOT/lib/cache.sh"
    [ "$(cache_age untouched)" = "-1" ]
    cache_touch justnow
    [ "$(cache_age justnow)" = "0" ]
}

# ── lib/cmd_timer.sh ─────────────────────────────────────────────────────

@test "cmd_timer: elapsed is 0 when never armed" {
    source "$ROOT/lib/cmd_timer.sh"
    cmd_timer_elapsed
    [ "$_CMD_TIMER_ELAPSED" -eq 0 ]
}

@test "cmd_timer: arm records a start time on the next DEBUG fire" {
    source "$ROOT/lib/cmd_timer.sh"
    cmd_timer_arm
    _cmd_timer_preexec        # simulate the DEBUG trap firing once
    [ "$_CMD_TIMER_START" -ge 0 ]
    [ "$_CMD_TIMER_ARMED" -eq 0 ]
}

@test "cmd_timer: CMD_TIMER_SKIP_TRAP skips installing the DEBUG trap" {
    run bash -c "
        export CMD_TIMER_SKIP_TRAP=1
        source '$ROOT/lib/cmd_timer.sh'
        trap -p DEBUG
    "
    [ -z "$output" ]
}

@test "cmd_timer: PS_SKIP_DEBUG_TRAP is honored via prompt.sh's compat shim" {
    run bash -c "
        export PS_SKIP_DEBUG_TRAP=1 TMUX='' COLUMNS=80
        source '$ROOT/prompt.sh'
        trap -p DEBUG
    "
    [ -z "$output" ]
}

# ── lib/term_utils.sh: fork-free strip_ansi / str_repeat ────────────────

@test "strip_ansi: removes SGR, OSC, and readline markers, keeps plain text" {
    source "$ROOT/lib/term_utils.sh"
    input=$'\001\033[1;31m\002Hi\001\033[0m\002 \033]0;title\007there'
    [ "$(strip_ansi "$input")" = "Hi there" ]
}

@test "strip_ansi: plain text with no codes passes through unchanged" {
    source "$ROOT/lib/term_utils.sh"
    [ "$(strip_ansi "plain text, no codes")" = "plain text, no codes" ]
}

@test "str_repeat: repeats a multi-byte character the requested count" {
    source "$ROOT/lib/term_utils.sh"
    [ "$(str_repeat "─" 5)" = "─────" ]
}

@test "str_repeat: zero or negative count produces no output" {
    source "$ROOT/lib/term_utils.sh"
    [ -z "$(str_repeat "x" 0)" ]
    [ -z "$(str_repeat "x" -3)" ]
}

@test "term_utils: strip_ansi/str_repeat no longer fork sed or awk" {
    # A PATH with no sed/awk on it — the old implementations would fail
    # outright; the fork-free versions don't touch PATH at all.
    run bash -c "
        source '$ROOT/lib/term_utils.sh'
        export PATH=/nonexistent
        strip_ansi \$'\033[31mred\033[0m' && str_repeat '=' 3
    "
    [ "$status" -eq 0 ]
    [ "$output" = "red===" ]
}

# ── prompt.sh: _ps_expand token-collision fix ────────────────────────────

@test "_ps_expand: a segment's own output is never re-scanned for other tokens" {
    source "$ROOT/prompt.sh"
    _test_emitter() { printf 'value@victimTAIL'; }
    _test_victim()  { printf 'SHOULD_NOT_APPEAR'; }
    prompt_segment emitter_longname _test_emitter
    prompt_segment victim           _test_victim

    out="$(_ps_expand '@emitter_longname' 100)"
    [ "$out" = 'value@victimTAIL' ]
}

@test "_ps_expand: an unmatched bare @ passes through literally" {
    source "$ROOT/prompt.sh"
    [ "$(_ps_expand 'email@example.com' 100)" = "email@example.com" ]
}

@test "_ps_expand: longest-match-first still resolves a real prefix collision" {
    source "$ROOT/prompt.sh"
    _test_git() { printf 'SHORT'; }
    _test_git_branch() { printf 'LONG'; }
    prompt_segment git         _test_git
    prompt_segment git_branch  _test_git_branch
    [ "$(_ps_expand '@git_branch' 100)" = "LONG" ]
}

@test "PS_DEBUG_SEGMENTS: a failing segment's stderr is surfaced, not swallowed" {
    source "$ROOT/prompt.sh"
    _test_broken() { echo "boom" >&2; return 1; }
    prompt_segment broken _test_broken

    run bash -c "
        source '$ROOT/prompt.sh'
        _test_broken() { echo boom >&2; return 1; }
        prompt_segment broken _test_broken
        PS_DEBUG_SEGMENTS=1 _ps_expand '@broken' 100
    "
    [[ "$output" == *boom* ]]
    [[ "$output" == *'segment "broken"'* ]]
}

@test "PS_DEBUG_SEGMENTS unset: a failing segment stays silent (default behavior unchanged)" {
    source "$ROOT/prompt.sh"
    _test_broken() { echo "boom" >&2; return 1; }
    prompt_segment broken _test_broken
    run _ps_expand '@broken' 100
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ── lib/git_info.sh: still works after routing its TTL through cache.sh ──

@test "git_info: refresh then cache_valid reports fresh immediately after" {
    source "$ROOT/lib/git_info.sh"
    tmpdir="$(mktemp -d)"
    git -C "$tmpdir" init -q
    git -C "$tmpdir" config user.email a@b.com
    git -C "$tmpdir" config user.name test
    (cd "$tmpdir" && echo x > f && git add f && git commit -qm x)

    cd "$tmpdir"
    git_info_refresh
    [ "$GIT_IN_REPO" -eq 1 ]
    run git_info_cache_valid
    [ "$status" -eq 0 ]
    rm -rf "$tmpdir"
}

@test "git_info: cache_valid goes stale once the TTL elapses" {
    source "$ROOT/lib/git_info.sh"
    tmpdir="$(mktemp -d)"
    git -C "$tmpdir" init -q
    git -C "$tmpdir" config user.email a@b.com
    git -C "$tmpdir" config user.name test
    (cd "$tmpdir" && echo x > f && git add f && git commit -qm x)

    cd "$tmpdir"
    git_info_cache_ttl 1
    git_info_refresh
    sleep 1.2   # real elapsed time — see the cache.sh test above for why
    run git_info_cache_valid
    [ "$status" -eq 1 ]
    rm -rf "$tmpdir"
}

# ── v0.1.3: regression tests for bugs found in the production-readiness review ──

@test "cache_stale: SECONDS going backwards ($SECONDS=0 idiom) is treated as stale, not fresh forever" {
    source "$ROOT/lib/cache.sh"
    _CACHE_USE_EPOCH=0   # force the $SECONDS fallback path deliberately
    SECONDS=500
    cache_touch k
    SECONDS=0             # simulates an unrelated `SECONDS=0; time_something` elsewhere
    run cache_stale k 5
    [ "$status" -eq 0 ]   # must be STALE, not incorrectly fresh
}

@test "str_repeat: ampersand repeats literally, not as spaces" {
    source "$ROOT/lib/term_utils.sh"
    [ "$(str_repeat '&' 4)" = "&&&&" ]
}

@test "_ps_expand: works when called directly, without prompt_build having run first" {
    source "$ROOT/prompt.sh"
    _test_direct() { printf 'DIRECT'; }
    prompt_segment direct _test_direct
    # No prompt_build call before this — _ps_expand must not depend on it.
    [ "$(_ps_expand '@direct' 100)" = "DIRECT" ]
}

@test "gpu/disk/load: data collection survives into the parent shell (not lost to the segment's subshell)" {
    fakebin="$(mktemp -d)"
    cat > "$fakebin/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
echo "$$" >> "$NVIDIA_SMI_CALL_LOG"
echo "55"
EOF
    chmod +x "$fakebin/nvidia-smi"
    calllog="$(mktemp)"
    script="$(mktemp)"
    cat > "$script" <<'EOF'
root="$1"; fakebin="$2"; calllog="$3"
export PATH="$fakebin:$PATH" NVIDIA_SMI_CALL_LOG="$calllog"
export TMUX="" COLUMNS=100
source "$root/prompt.sh"
prompt_segment gpu _ps_seg_gpu
prompt_row r '@gpu'
prompt_layout r      # prompt_build returns immediately with no rows configured
for i in 1 2 3 4 5; do prompt_build; done
echo "val=$_PS_GPU_CACHE_VAL age=$(cache_age gpu)"
EOF

    run bash "$script" "$ROOT" "$fakebin" "$calllog"
    [[ "$output" == *"val=55"* ]]
    [[ "$output" == *"age=0"* ]]
    [ "$(wc -l < "$calllog")" -eq 1 ]   # the expensive call ran exactly once across 5 renders
    rm -rf "$fakebin" "$calllog" "$script"
}

@test "prompt_segment: registering N segments forks the sort at most once, not N times" {
    run bash -c "
        source '$ROOT/prompt.sh'
        _t() { :; }
        for i in \$(seq 1 10); do prompt_segment \"seg\$i\" _t; done
        echo \"dirty_after_registering=\$_PS_SEGS_DIRTY\"
        _ps_resort_segments
        echo \"dirty_after_one_resort=\$_PS_SEGS_DIRTY\"
        echo \"sorted_count=\${#_PS_SEGS_SORTED[@]}\"
    "
    [[ "$output" == *"dirty_after_registering=1"* ]]
    [[ "$output" == *"dirty_after_one_resort=0"* ]]
    # >=10: includes whatever built-in-adjacent state exists in a fresh source
    [[ "$output" =~ sorted_count=([0-9]+) ]]
    [ "${BASH_REMATCH[1]}" -ge 10 ]
}

# ── v0.1.4: regression tests for the production-readiness review ────────

@test "pbs_nodes: counts unique nodes, and its locals are correctly typed" {
    source "$ROOT/prompt.sh"
    nodefile="$BATS_TEST_TMPDIR/nodes"
    printf 'n1\nn1\nn2\nn3\nn3\nn3\n' > "$nodefile"
    PBS_NODEFILE="$nodefile"
    [ "$(_ps_seg_pbs_nodes)" = "3 nodes" ]
}

@test "pbs_nodes: does not declare its scalar locals as associative arrays" {
    # `local -A seen=() line n=0` would apply -A to all three names.
    run grep -A6 '^_ps_seg_pbs_nodes()' "$ROOT/prompt.sh"
    [[ "$output" != *'local -A seen=() line'* ]]
}

@test "refresh gating: a built-in segment registered under a CUSTOM alias still arms its refresh" {
    source "$ROOT/prompt.sh"
    prompt_segment gpu_util   _ps_seg_gpu          # not named "gpu"
    prompt_segment branchname _ps_seg_git_branch   # not prefixed "git_"
    prompt_segment freespace  _ps_seg_disk         # not named "disk"
    prompt_segment busy       _ps_seg_load         # not named "load"
    [ "$_PS_HAS_GPU"  -eq 1 ]
    [ "$_PS_HAS_GIT"  -eq 1 ]
    [ "$_PS_HAS_DISK" -eq 1 ]
    [ "$_PS_HAS_LOAD" -eq 1 ]
}

@test "prompt_segment_needs: a custom segment can declare its own data dependency" {
    source "$ROOT/prompt.sh"
    _my_custom_branch() { printf '%s' "$GIT_BRANCH"; }
    prompt_segment_needs _my_custom_branch git
    prompt_segment mine _my_custom_branch
    [ "$_PS_HAS_GIT" -eq 1 ]
}

@test "prompt_segment_needs: rejects an unknown dependency name" {
    source "$ROOT/prompt.sh"
    _x() { :; }
    run prompt_segment_needs _x notathing
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown dependency"* ]]
}

@test "registering an unrelated segment does not arm any refresh" {
    source "$ROOT/prompt.sh"
    _plain() { printf 'hi'; }
    prompt_segment plain _plain
    [ "$_PS_HAS_GIT"  -eq 0 ]
    [ "$_PS_HAS_GPU"  -eq 0 ]
    [ "$_PS_HAS_DISK" -eq 0 ]
    [ "$_PS_HAS_LOAD" -eq 0 ]
}
