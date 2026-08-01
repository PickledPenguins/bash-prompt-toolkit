#!/usr/bin/env bash
# Toolkit version: 0.1.4
# ════════════════════════════════════════════════════════════════════════════
# prompt.example.sh — Prompt configuration using prompt.sh
#
# Add to .bashrc (in this order):
#   source ~/dotfiles/prompt.sh
#   source ~/dotfiles/prompt.example.sh
#
# Switch layouts by uncommenting one block in the "Active layout" section.
#
# To write a custom segment:
#   _my_seg() { printf '%s' "some text"; }   # use PS_* for color
#   prompt_segment myname _my_seg
#   # then reference it as @myname in any row template
# ════════════════════════════════════════════════════════════════════════════

# ── Custom segments ───────────────────────────────────────────────────────

# Colored user@host — override the plain _ps_seg_user_host built-in
_my_user_host() {
    printf '%s%s%s@%s%s%s' \
        "$PS_BGREEN" "$USER"           "$PS_R" \
        "$PS_BCYAN"  "${HOSTNAME%%.*}" "$PS_R"
}

# ── Register all segments ─────────────────────────────────────────────────
# Only registered segments incur a function call per prompt build.
# Comment out any you do not need.

prompt_segment user_host        _my_user_host              # colored user@host
prompt_segment root             _ps_seg_root               # ⚡ shown only in a root shell
prompt_segment pwd              _ps_seg_pwd                # working directory
prompt_segment git_branch       _ps_seg_git_branch         # branch / detached SHA
prompt_segment git_remote       _ps_seg_git_remote         # tracking remote
prompt_segment git_ahead_behind _ps_seg_git_ahead_behind   # ↑N ↓N or ✓
prompt_segment git_status       _ps_seg_git_status         # +staged ~modified ?untracked
prompt_segment git_stash        _ps_seg_git_stash          # ⚑N stash count
prompt_segment git_conflicts    _ps_seg_git_conflicts      # ⚠N unmerged/conflicted paths
prompt_segment tmux             _ps_seg_tmux               # ⧉ session:win.pane
prompt_segment display          _ps_seg_display            # $DISPLAY value
prompt_segment ssh              _ps_seg_ssh                # ⇄ ssh (when remote)
prompt_segment venv             _ps_seg_venv               # (virtualenv name)
prompt_segment jobs             _ps_seg_jobs               # ⚙ N background jobs
prompt_segment exit             _ps_seg_exit               # ✓ or ✗ N
prompt_segment time             _ps_seg_time               # HH:MM
prompt_segment pbs_job          _ps_seg_pbs_job            # PBS JOBID
prompt_segment pbs_queue        _ps_seg_pbs_queue          # PBS queue name
prompt_segment pbs_nodes        _ps_seg_pbs_nodes          # N nodes
prompt_segment slurm_job        _ps_seg_slurm_job          # SLURM JOBID
prompt_segment slurm_queue      _ps_seg_slurm_queue        # Slurm partition
prompt_segment slurm_nodes      _ps_seg_slurm_nodes        # N nodes
prompt_segment cmd_time         _ps_seg_cmd_time           # last command duration (≥2 s)
prompt_segment conda            _ps_seg_conda              # active conda env (not "base")
prompt_segment shlvl            _ps_seg_shlvl              # ⬇N when shell is nested
prompt_segment modules          _ps_seg_modules            # ⊞N HPC loaded-module count
prompt_segment load             _ps_seg_load               # ⚖N.NN — only shown when the node is genuinely busy
prompt_segment disk             _ps_seg_disk               # ⛁N% — only shown near capacity (>=90%)
prompt_segment gpu              _ps_seg_gpu                # GPU N% — TTL-cached, silent off GPU nodes

# ── Tune defaults (optional) ──────────────────────────────────────────────
# prompt_cache_ttl 5            # seconds before forcing a git refresh (default 5)
# prompt_cmd_time_threshold 2   # minimum seconds before duration appears (default 2)

# ── Row definitions ───────────────────────────────────────────────────────
# Rows are reused across layout definitions. Define once, reference anywhere.
# Use single quotes so \$ is preserved as the PS1 prompt-char escape.

# Top border — identity on the left, working directory on the right
prompt_row top      '─[ @root@user_host ]@fill[ @pwd ]─'

# Environment: ⬇N nested shell, connectivity, active envs, bg jobs.
# @shlvl @conda @modules are all silent when not applicable — zero overhead
# on a plain workstation or outside a PBS/Slurm job.
prompt_row env      '  @shlvl  @load  @disk  @ssh  @tmux  @display  @conda  @venv  @jobs'

# Git — branch + remote tracking line
prompt_row git      '  ⎇  @git_branch  →  @git_remote  @git_ahead_behind'

# Git — working-tree file status, stash count, and unmerged conflicts
prompt_row status   '     @git_status  @git_stash  @git_conflicts'

# HPC — PBS/Slurm job context + loaded module count (all silent off-cluster)
prompt_row hpc      '  @pbs_job  @pbs_queue  @pbs_nodes  @slurm_job  @slurm_queue  @slurm_nodes  @modules  @gpu'

# Bottom rows — pick one per layout.
# @cmd_time is silent for fast commands (threshold tunable via prompt_cmd_time_threshold).
prompt_row cmd       '─[@exit] @cmd_time \$ '         # open: ╰─[✓] 5s $
prompt_row cmd_clock '─[@exit]@fill[ @time ]─\$ '     # open with right-aligned wall clock
prompt_row footer    '─[@exit]@fill[ @time ]─'        # closed box bottom (use with --closed)

# ════════════════════════════════════════════════════════════════════════════
# Active layout — uncomment exactly one block
# ════════════════════════════════════════════════════════════════════════════

# ── Layout A: env header, git below (DEFAULT) ─────────────────────────────
#
# ╭─[ chris@devbox ]────────────────────────────────[ ~/projects/myapp ]─╮
# │  ⬇2  ⇄ ssh  ⧉ proj:2.1  :0  (py311)  ⚙ 2                           │
# │  ⎇  feature/auth  →  origin/feature/auth  ↑3 ↓1                     │
# │     +2 ~5 ?3  ⚑1                                                     │
# ╰─[✓] 5s $

prompt_layout --box rounded  top  env  git  status  cmd

# ── Layout B: git header, env footer ─────────────────────────────────────
#
# prompt_layout --box rounded  top  git  status  env  cmd

# ── Layout C: right-aligned env on the same rows as git ──────────────────
#
# prompt_row git_r    '  ⎇  @git_branch  →  @git_remote@fill@tmux  @display  '
# prompt_row status_r '     @git_ahead_behind  @git_status@fill@venv  @jobs  '
# prompt_layout --box rounded  top  git_r  status_r  cmd

# ── Layout D: full verbose, closed box, cursor below ─────────────────────
#
# ╭─[ chris@devbox ]────────────────────────────────[ ~/projects/myapp ]─╮
# │  ⬇2  ⇄ ssh  ⧉ proj:2.1  :0  (py311)  ⚙ 2                           │
# │  ⎇  feature/auth  →  origin/feature/auth  ↑3 ↓1                     │
# │     +2 ~5 ?3  ⚑1                                                     │
# │  PBS 819234  normal  64 nodes  ⊞ 6                                   │
# ╰─[✓]──────────────────────────────────────────────────────[ 14:32 ]─╯
# $
#
# prompt_layout --box rounded --closed  top  env  git  status  hpc  footer

# ── Layout E: HPC / SSH focused ───────────────────────────────────────────
#
# prompt_row top_hpc  '─[ @user_host ]─[ @ssh ]@fill[ @pwd ]─'
# prompt_row env_hpc  '  @tmux  @display  @conda  @venv  @modules'
# prompt_layout --box rounded  top_hpc  env_hpc  hpc  git  cmd

# ── Layout F: minimal, no box ─────────────────────────────────────────────
#
# prompt_row line1  '[ @user_host ] ⎇ @git_branch @git_ahead_behind @pwd'
# prompt_row line2  '[@exit] @cmd_time \$ '
# prompt_layout  line1  line2
