load test_helper

setup() {
    load_prompt_lib
    _solo() { printf 'X'; }
    prompt_segment solo _solo
    COLUMNS=40
}

@test "single-row OPEN box: cursor follows content, no stray top-right corner" {
    prompt_row r1 '@solo \$ '
    prompt_layout --box rounded r1
    prompt_build
    [[ "$PS1" == *'\$'* ]]
    [[ "$PS1" != *"╮"* ]]   # no top-right corner should leak in for an open single row
}

@test "single-row CLOSED box: seals with bottom-right corner and a real prompt escape" {
    prompt_row r1 '@solo'
    prompt_layout --box rounded --closed r1
    prompt_build
    [[ "$PS1" == *'\$'* ]]
    [[ "$PS1" == *"╯"* ]]
}

@test "multi-row OPEN box: last row still has no right corner (unchanged convention)" {
    prompt_row r1 '@solo'
    prompt_row r2 '@solo \$ '
    prompt_layout --box rounded r1 r2
    prompt_build
    [[ "$PS1" == *'\$'* ]]
}

@test "multi-row CLOSED box: still seals correctly (regression check)" {
    prompt_row r1 '@solo'
    prompt_row r2 '@solo'
    prompt_layout --box rounded --closed r1 r2
    prompt_build
    [[ "$PS1" == *"╯"* ]]
    [[ "$PS1" == *'\$'* ]]
}

@test "box with @fill correctly pads between two segments" {
    prompt_row r1 '[@solo]@fill[@solo]'
    prompt_layout --box rounded --closed r1
    prompt_build
    plain_ps1="$(strip_ansi "$PS1")"
    [[ "$plain_ps1" == *"[X]"*"[X]"* ]]
}

@test "prompt_layout is idempotent: calling it twice does not double-prepend prompt_build" {
    prompt_row r1 '@solo'
    prompt_layout --box rounded r1
    prompt_layout --box rounded r1
    count=$(grep -o "prompt_build" <<< "$PROMPT_COMMAND" | wc -l)
    [[ "$count" -eq 1 ]]
}

@test "no-box layout joins rows with real newlines, not box borders" {
    prompt_row r1 '@solo'
    prompt_row r2 '@solo'
    prompt_layout r1 r2
    prompt_build
    [[ "$PS1" != *"╭"* ]]
    [[ "$PS1" != *"│"* ]]
}
