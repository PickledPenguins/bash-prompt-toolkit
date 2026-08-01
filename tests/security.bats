# SECURITY: PS1 command-injection via promptvars (bash re-parses $PS1 for
# command substitution on every prompt render, by default). A directory
# name, git branch, VIRTUAL_ENV path, tmux session name, $USER, or
# $HOSTNAME containing $(...) reaches PS1 verbatim through the relevant
# segment function, and bash executes it on the very next prompt render —
# and every render after that, for as long as it stays the active PS1.
#
# STATUS: FIXED as of v0.1.1 — `shopt -u promptvars` is applied at
# library-init time in prompt.sh. These tests now PASS and stand as
# regression guards: if that line is ever removed or the mechanism
# regresses, the first test below fails immediately rather than the
# vulnerability silently reopening.

load test_helper

setup() {
    load_prompt_lib
}

@test "[SECURITY] promptvars is disabled by the library (primary fix)" {
    [[ "$(shopt -p promptvars)" == "shopt -u promptvars" ]]
}

@test "[SECURITY] a malicious directory name does not execute when the real prompt is rendered (end-to-end, requires 'script')" {
    command -v script >/dev/null || skip "'script' (util-linux) not available for a real PTY"

    marker="$BATS_TEST_TMPDIR/PWNED"
    evil_dir="$BATS_TEST_TMPDIR/proj_\$(touch\$IFS${marker})_x"
    mkdir -p "$evil_dir"

    probe="$BATS_TEST_TMPDIR/probe.sh"
    cat > "$probe" << PROBE
cd '$DOTFILES_ROOT'
source ./lib/colors.sh; source ./lib/term_utils.sh
source ./lib/git_info.sh; source ./prompt.sh
source ./prompt_example.sh
cd '$evil_dir'
PROMPT_COMMAND=prompt_build
PROBE

    typescript="$BATS_TEST_TMPDIR/typescript.log"
    script -qec "bash --rcfile '$probe' -i" "$typescript" << 'INPUT'
echo hi
exit
INPUT

    # poll briefly instead of a fixed sleep -- PTY teardown timing varies
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [[ -f "$marker" ]] && break
        sleep 0.2
    done

    [[ ! -f "$marker" ]]
}

@test "[SECURITY] a malicious VIRTUAL_ENV path does not execute via the venv segment (mechanism-level check)" {
    cd "$BATS_TEST_TMPDIR"   # so a slash-free marker filename resolves predictably
    export VIRTUAL_ENV='/tmp/venv_$(touch$IFSPWNED_VENV)_x'
    out="$(_ps_seg_venv)"
    # with promptvars still on (pre-fix), this segment's OUTPUT correctly
    # contains the literal text unexecuted -- it's PS1's *later re-render*
    # that executes it, not the segment call itself. This test documents
    # that expectation and re-confirms the payload reaches the output
    # verbatim (i.e. nothing here quietly neutralizes it at the segment
    # level -- the fix has to be the promptvars mechanism, not this call).
    [[ "$out" == *'$(touch'* ]]
    [[ ! -f "PWNED_VENV" ]]
}
