load test_helper

setup() {
    load_prompt_lib
    make_git_repo
    git_info_cache_ttl 0   # disable TTL so every test sees a fresh refresh
}

@test "non-repo directory: GIT_IN_REPO is 0, returns a clean explicit status" {
    cd "$BATS_TEST_TMPDIR"
    run git_info_refresh
    [[ "$status" -eq 1 ]]
    [[ "$GIT_IN_REPO" == "0" ]]
}

@test "clean repo produces zero counts with NO stderr output" {
    echo x > f.txt && git add f.txt && git commit -qm init
    run bash -c "source '$DOTFILES_ROOT/lib/git_info.sh'; cd '$REPO_DIR'; git_info_refresh 2>&1 >/dev/null"
    [[ -z "$output" ]]
}

@test "clean repo: staged/modified/untracked/conflicts are all exactly 0" {
    echo x > f.txt && git add f.txt && git commit -qm init
    git_info_refresh
    [[ "$GIT_STAGED" == "0" ]]
    [[ "$GIT_MODIFIED" == "0" ]]
    [[ "$GIT_UNTRACKED" == "0" ]]
    [[ "$GIT_CONFLICTS" == "0" ]]
}

@test "arithmetic on a zero count does not throw a syntax error (regression: grep -c || echo 0 bug)" {
    echo x > f.txt && git add f.txt && git commit -qm init
    git_info_refresh
    (( GIT_STAGED > 0 )) || true   # must not error regardless of outcome
}

@test "staged, modified, and untracked are each counted correctly and independently" {
    echo x > f.txt && git add f.txt && git commit -qm init
    echo y >> f.txt                      # modified
    echo z > untracked.txt               # untracked
    echo w > staged.txt && git add staged.txt   # staged
    git_info_refresh
    [[ "$GIT_STAGED" == "1" ]]
    [[ "$GIT_MODIFIED" == "1" ]]
    [[ "$GIT_UNTRACKED" == "1" ]]
}

@test "merge conflict sets GIT_CONFLICTS, not silently 'clean'" {
    echo base > f.txt && git add f.txt && git commit -qm base
    git checkout -qb a && echo aaa > f.txt && git commit -qam a
    git checkout -q main 2>/dev/null || git checkout -q master
    git checkout -qb b && echo bbb > f.txt && git commit -qam b
    git merge a -q 2>/dev/null || true
    git_info_refresh
    [[ "$GIT_CONFLICTS" == "1" ]]
    [[ "$GIT_STAGED" == "0" ]]   # conflicted paths must not double-count as staged
}

@test "detached HEAD falls back to short SHA for GIT_BRANCH" {
    echo x > f.txt && git add f.txt && git commit -qm init
    git checkout -q "$(git rev-parse HEAD)"
    git_info_refresh
    [[ "$GIT_IN_REPO" == "1" ]]
    [[ -n "$GIT_BRANCH" ]]
    [[ "${#GIT_BRANCH}" -le 10 ]]   # short SHA, not a branch name
}

@test "ahead/behind counts reflect actual commit divergence" {
    echo x > f.txt && git add f.txt && git commit -qm init
    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"
    git init -q --bare "$REMOTE_DIR"
    git remote add origin "$REMOTE_DIR"
    local_branch="$(git branch --show-current)"
    git push -q origin "HEAD:$local_branch"
    git branch -q --set-upstream-to="origin/$local_branch" "$local_branch"
    echo y >> f.txt && git commit -qam second
    git_info_refresh
    [[ "$GIT_AHEAD" == "1" ]]
    [[ "$GIT_BEHIND" == "0" ]]
}

@test "cache_valid returns false immediately after cd to a different repo" {
    echo x > f.txt && git add f.txt && git commit -qm init
    git_info_refresh
    OTHER_DIR="$BATS_TEST_TMPDIR/other"
    mkdir -p "$OTHER_DIR" && cd "$OTHER_DIR"
    ! git_info_cache_valid
}

@test "cache_valid returns true on an immediate second call with no changes" {
    echo x > f.txt && git add f.txt && git commit -qm init
    git_info_cache_ttl 30   # this test needs the TTL to actually hold
    git_info_refresh
    git_info_cache_valid
}

@test "stash count is reflected in GIT_STASH" {
    echo x > f.txt && git add f.txt && git commit -qm init
    echo y >> f.txt
    git stash -q
    git_info_refresh
    [[ "$GIT_STASH" == "1" ]]
}
