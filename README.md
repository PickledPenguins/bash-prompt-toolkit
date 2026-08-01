# Bash Prompt Toolkit

**Version:** 0.1.4

A composable bash `PS1` builder for terminal-centric HPC workflows — cached
git state, PBS/Slurm awareness, and a segment/row/layout system for
building your own prompt without touching string-concatenation spaghetti.

## Contents

**Using it**
- [What it looks like](#what-it-looks-like)
- [Installation](#installation)
- [Requirements](#requirements)
- [Segment reference](#segment-reference)
- [Customization](#customization)
- [Configuration and API reference](#configuration-and-api-reference)
- [Environment variables](#environment-variables)
- [Assumptions and limitations](#assumptions-and-limitations)

**Developing it**
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Testing](#testing)
- [Future work](#future-work)
- [Known issues](#known-issues)
- [Version history](#version-history)

## What it looks like

The default layout from `prompt_example.sh`, rendered in a git repo
inside a tmux session over SSH:

```
╭─[ chris@devbox ]────────────────────────────────[ ~/projects/myapp ]─╮
│  ⬇2  ⇄ ssh  ⧉ proj:2.1  :0  (py311)  ⚙ 2                              │
│  ⎇  feature/auth  →  origin/feature/auth  ↑3 ↓1                       │
│     +2 ~5 ?3  ⚑1                                                       │
╰─[✓] 5s $
```

Every field is optional and every one is silent when it doesn't apply —
on a plain workstation outside a repo, the same configuration collapses
to just the identity row and the prompt character.

### Row 1 — identity and location

| Field | Token | Meaning | Shown when |
|---|---|---|---|
| `⚡` | `@root` | Running as root | `$EUID` is 0 |
| `chris@devbox` | `@user_host` | User and short hostname | Always |
| `~/projects/myapp` | `@pwd` | Working directory, `$HOME` collapsed to `~`, truncated to 35 columns with a leading `…` | Always |

### Row 2 — environment

| Field | Token | Meaning | Shown when |
|---|---|---|---|
| `⬇2` | `@shlvl` | Nested shell depth | `$SHLVL` > 1 |
| `⚖1.42` | `@load` | 1-minute load average | Load exceeds core count |
| `⛁92%` | `@disk` | Filesystem usage for `$PWD` | Usage ≥ 90% |
| `⇄ ssh` | `@ssh` | Shell arrived over SSH | `$SSH_CLIENT`/`$SSH_TTY` set |
| `⧉ proj:2.1` | `@tmux` | tmux session:window.pane | Inside tmux |
| `:0` | `@display` | X11 display | `$DISPLAY` set |
| `(py311)` | `@venv` | Python virtualenv name | `$VIRTUAL_ENV` set |
| `(myenv)` | `@conda` | Conda environment name | Set and not `base` |
| `⚙ 2` | `@jobs` | Background job count | At least one job |

### Row 3 — git branch and tracking

| Field | Token | Meaning | Shown when |
|---|---|---|---|
| `feature/auth` | `@git_branch` | Branch name, or short SHA when detached | Inside a repo |
| `origin/feature/auth` | `@git_remote` | Upstream tracking branch | Branch has an upstream |
| `↑3` / `↓1` / `✓` | `@git_ahead_behind` | Commits ahead (green), behind (yellow), or in sync | Branch has an upstream |

### Row 4 — git working tree

| Field | Token | Meaning | Shown when |
|---|---|---|---|
| `+2` | `@git_status` | Staged files (green) | Any staged |
| `~5` | `@git_status` | Modified files (yellow) | Any unstaged modifications |
| `?3` | `@git_status` | Untracked files (dim) | Any untracked |
| `⚑1` | `@git_stash` | Stash entry count | Stash is non-empty |
| `⚠1` | `@git_conflicts` | Unmerged/conflicted paths (bold red) | Mid-merge or mid-rebase |

### Row 5 — status line

| Field | Token | Meaning | Shown when |
|---|---|---|---|
| `✓` / `✗ 127` | `@exit` | Last command's exit status | Always |
| `5s` | `@cmd_time` | Duration of the last command | Ran ≥ 2s (configurable) |
| `14:32` | `@time` | Wall clock, `HH:MM` | Only in layouts that use it |

### HPC row (not shown above — silent off-cluster)

| Field | Token | Meaning | Shown when |
|---|---|---|---|
| `PBS 819234` | `@pbs_job` | PBS job ID, suffix stripped | `$PBS_JOBID` set |
| `normal` | `@pbs_queue` | PBS queue name | `$PBS_QUEUE` set |
| `64 nodes` | `@pbs_nodes` | Unique nodes in `$PBS_NODEFILE` | Nodefile readable |
| `SLURM 4471` | `@slurm_job` | Slurm job ID | `$SLURM_JOB_ID` set |
| `gpu-a100` | `@slurm_queue` | Slurm partition | `$SLURM_JOB_PARTITION` set |
| `8 nodes` | `@slurm_nodes` | Slurm node count | `$SLURM_NNODES` set |
| `⊞ 6` | `@modules` | Loaded environment-module count | `$LOADEDMODULES` non-empty |
| `GPU 47%` | `@gpu` | GPU utilization, TTL-cached | `nvidia-smi` available |
## Installation

**Automated:**

```bash
./install.sh ~/dotfiles          # copies lib/, prompt.sh, prompt_example.sh there
                                  # and prints the two .bashrc lines below
```

`install.sh` also checks your bash version against the requirements
below and warns (doesn't block) if it's older than recommended.

**Manual:** copy `lib/`, `prompt.sh`, and `prompt_example.sh` to a
directory of your choice, then add to `.bashrc`, in this order:

```bash
source ~/dotfiles/prompt.sh
source ~/dotfiles/prompt_example.sh
```

`prompt.sh` auto-sources `lib/cache.sh`, `lib/git_info.sh`,
`lib/term_utils.sh`, `lib/colors.sh`, and `lib/cmd_timer.sh` relative to
its own location — keep the `lib/` directory alongside it.
`prompt_example.sh` is a working configuration you edit directly
(register segments, define rows, pick a layout) — it's meant to be
copied and customized, not left as a black box.

## Requirements

- **bash 4.0+** — associative arrays (`declare -A`), used throughout.
- **bash 5.0+ recommended** — `lib/cache.sh` and `lib/cmd_timer.sh` use
  `EPOCHSECONDS` when available for TTL bookkeeping that can't be
  disrupted by an unrelated `SECONDS=0` elsewhere in the shell. Bash
  4.x still works via a `$SECONDS`-based fallback with its own (weaker)
  defense against that specific case — see the [version history](#version-history).
- **GNU coreutils** (`stat -c`, specifically) — this targets Linux. It
  has not been tested against BSD/macOS coreutils, which use different
  `stat` flags, and no portability shim is planned; if that matters to
  you, `git_info.sh`'s two `stat -c '%Y'` calls are the only place to
  look.
- **Runtime dependencies** (all optional except `git`; every segment
  that needs one degrades to silent/empty if it's missing): `git`,
  `tmux`, `nvidia-smi`, `df`, `nproc`, `stat`, `tput`, `date`, `awk`,
  `sort`, `cut`, `tr`, `timeout`. None of these are external to a
  typical Linux install except `nvidia-smi` (GPU nodes only) and `tmux`
  (only if you use it).

## Segment reference

All segments are silent (empty output, zero visual footprint) when
not applicable — an `@venv` segment outside a virtualenv costs one
cheap function call, not a blank space.

| Segment | Shows | Silent when |
|---|---|---|
| `_ps_seg_user` / `_ps_seg_host` / `_ps_seg_user_host` | `user@host` | never |
| `_ps_seg_root` | `⚡` privileged-shell indicator | not running as root |
| `_ps_seg_pwd` | Working directory, `$HOME`→`~`, truncated past 35 visible chars | never |
| `_ps_seg_git_branch` | Branch name, or short SHA if detached | outside a git repo |
| `_ps_seg_git_remote` | Upstream tracking branch | no upstream configured |
| `_ps_seg_git_ahead_behind` | `↑N ↓N` | no divergence from upstream |
| `_ps_seg_git_status` | `+staged ~modified ?untracked` | working tree is clean |
| `_ps_seg_git_stash` | `⚑N` stash count | no stashes |
| `_ps_seg_git_conflicts` | `⚠N` unmerged paths | no active conflict |
| `_ps_seg_tmux` | `⧉ session:win.pane` | not inside tmux |
| `_ps_seg_display` | `$DISPLAY` value | unset |
| `_ps_seg_ssh` | `⇄ ssh` | local session |
| `_ps_seg_venv` | Active virtualenv name | not activated |
| `_ps_seg_conda` | Active conda env (unless `base`) | not activated |
| `_ps_seg_jobs` | `⚙ N` background jobs | none |
| `_ps_seg_exit` | `✓` or `✗ N` | never (always shows last exit state) |
| `_ps_seg_time` | `HH:MM` | never |
| `_ps_seg_cmd_time` | Last command's duration | faster than the threshold (default 2s) |
| `_ps_seg_shlvl` | `⬇N` nesting depth | top-level shell |
| `_ps_seg_modules` | `⊞N` loaded HPC modules | `$LOADEDMODULES` unset |
| `_ps_seg_load` | `⚖N.NN` 1-min load average | load ≤ core count |
| `_ps_seg_disk` | `⛁N%` filesystem usage | below 90% |
| `_ps_seg_gpu` | `GPU N%` utilization (TTL-cached) | no `nvidia-smi`, or off-GPU node |
| `_ps_seg_pbs_job` / `_ps_seg_pbs_queue` / `_ps_seg_pbs_nodes` | PBS job context | outside a PBS job |
| `_ps_seg_slurm_job` / `_ps_seg_slurm_queue` / `_ps_seg_slurm_nodes` | Slurm job context | outside a Slurm allocation |

## Customization

Write a segment, register it, reference it in a row:

```bash
_my_seg() { printf '%s' "some text"; }   # use $PS_* vars for color
prompt_segment myname _my_seg
prompt_row myrow '@myname  @pwd'
prompt_layout --box rounded myrow
```

**The one rule for segment authors: a segment formats, it does not
collect.** Segments run inside a command substitution — a subshell — so
any variable a segment sets, including any caching bookkeeping, is
discarded the moment it returns. A segment that caches its own data
silently re-does the expensive work on every keystroke.

```bash
# WRONG — cache_touch runs in a subshell; the TTL never takes effect,
# and `expensive_thing` runs on every single render with no error shown.
_my_thing() {
    if cache_stale mything 10; then
        MY_VALUE=$(expensive_thing)
        cache_touch mything
    fi
    printf '%s' "$MY_VALUE"
}

# RIGHT — collect in a refresh function, format in the segment.
_my_refresh() { MY_VALUE=$(expensive_thing); cache_touch mything; }
_my_thing()   { [[ -n "$MY_VALUE" ]] && printf '%s' "$MY_VALUE"; }
```

If the data you need is one of the four the toolkit already collects,
just declare the dependency and read the globals — no refresh function
needed:

```bash
_my_branch() { printf '⎇ %s' "$GIT_BRANCH"; }
prompt_segment_needs _my_branch git      # must come before prompt_segment
prompt_segment mybranch _my_branch
```

Valid dependencies are `git`, `gpu`, `disk`, and `load`. Skipping this
step means the refresh never runs and the segment renders blank forever.

**Tuning:**

```bash
prompt_cache_ttl 5             # seconds before forcing a git refresh (default 5)
prompt_cmd_time_threshold 2    # minimum seconds before @cmd_time appears (default 2)
```

**Row templates** use single quotes so `\$` survives as the literal
bash prompt-escape sequence (rendered as `$`, or `#` for root) rather
than being shell-expanded at registration time. Tokens have no end
delimiter — avoid a segment name that's a literal prefix of adjacent
template text.

**Box styles:** `rounded` (╭╮╰╯), `sharp` (┌┐└┘), `double` (╔╗╚╝),
`ascii` (++++) — pass as `prompt_layout --box <style> ...`.

## Configuration and API reference

All configuration happens by calling these functions from a config file
sourced after `prompt.sh` (see `prompt_example.sh`). There are no
command-line arguments to the library itself; `install.sh` is the only
executable, and takes one optional positional argument.

### Public functions

| Function | Arguments | Purpose |
|---|---|---|
| `prompt_segment` | `<name> <function>` | Register `<function>` as the `@name` token usable in row templates. |
| `prompt_segment_needs` | `<function> <git\|gpu\|disk\|load>` | Declare that a custom segment function depends on collected data, so `prompt_build` refreshes it. Call before `prompt_segment`. Built-in segments are pre-declared. |
| `prompt_row` | `<name> <template>` | Define a named row template: literal text, `@segment` tokens, and at most one `@fill`. |
| `prompt_layout` | `[--box [style]] [--closed] [--no-box] <row>…` | Set the ordered row list and box decoration, and wire `prompt_build` into `PROMPT_COMMAND`. Idempotent. |
| `prompt_build` | none | Rebuild `PS1`. Called automatically via `PROMPT_COMMAND`; rarely called directly. |
| `prompt_debug` | none | Print the active layout, rows, segments, and cache ages to stderr. |
| `prompt_cache_ttl` | `<seconds>` | Set the git-state staleness window (default 5). |
| `prompt_cmd_time_threshold` | `<seconds>` | Set the minimum command duration before `@cmd_time` displays (default 2). |

### Library functions (usable standalone)

| Function | Arguments | Purpose |
|---|---|---|
| `strip_ansi` | `<string>` | Remove ANSI escapes and readline `\001..\002` markers. |
| `str_width` | `<string>` | Visible column count, locale- and Unicode-safe. |
| `str_repeat` | `<char> <n>` | Repeat a character `n` times, multi-byte safe. |
| `colors_init` | `[prompt\|raw]` | (Re)initialize `C_*`/`PS_*` color variables in the given mode. |
| `c_fg` / `c_bg` | `<0-255>` | 256-color foreground/background escape, mode-aware. |
| `cache_stale` | `<key> [ttl]` | Whether `<key>` has gone stale (returns 0 if stale). |
| `cache_touch` | `<key>` | Record `<key>` as refreshed now. |
| `cache_age` | `<key>` | Seconds since last touch, or `-1`. |
| `git_info_refresh` | none | Populate the `GIT_*` globals. |
| `git_info_cache_valid` | none | Whether the cached git state is still fresh. |
| `git_info_cache_ttl` | `<seconds>` | Set the git TTL. |
| `cmd_timer_arm` | none | Arm the command timer (call after displaying a prompt). |
| `cmd_timer_elapsed` | none | Compute `$_CMD_TIMER_ELAPSED` for the last command. |

### install.sh

```
./install.sh [target_dir]      # default: ~/.local/share/bash-prompt-toolkit
```

Copies `lib/`, `prompt.sh`, `prompt_example.sh`, and `README.md` to
`target_dir` and prints the two lines to add to `.bashrc`. Refuses to
overwrite an existing target. Warns (does not block) on bash older than
recommended. It does not modify `.bashrc` — shell startup files are left
under the user's own control.

## Assumptions and limitations

**Assumptions:**

- Linux with GNU coreutils. `git_info.sh` uses `stat -c '%Y'`, which is
  GNU-specific; BSD/macOS `stat` takes different flags. Untested there
  and no portability shim is planned.
- A UTF-8-capable terminal for the default box-drawing characters. The
  `ascii` box style exists for terminals that can't render them.
- One prompt configuration per shell. Sourcing two configs that both
  call `prompt_layout` means the last one wins.

**Limitations:**

- **Segments must not collect their own cached data.** `_ps_expand`
  invokes each segment via command substitution — a subshell — so any
  variable a segment assigns, including `cache_touch`, is discarded when
  it exits. Collection belongs in `prompt_build`; segments format
  already-collected globals. See [Customization](#customization).
- **Git state is per-process.** Each shell maintains its own cache; ten
  panes in the same repo each run their own `git status` on a cache miss.
- **`@cmd_time` requires the `DEBUG` trap.** If another tool owns it, set
  `PS_SKIP_DEBUG_TRAP=1` and lose only that segment.
- **Disk usage uses `df`, not real quotas.** Quota semantics vary too
  much across NFS/Lustre/GPFS to handle generically.
- **`str_width` forks `wc` for non-ASCII input.** A pure-bash codepoint
  counter was judged a net maintainability loss against one fork per
  colored segment.
- **Row templates have no token end-delimiter.** Avoid a segment name
  that is a literal prefix of adjacent template text.

## Future work

- Build real line/branch coverage into the test workflow (needs `kcov`;
  see [Testing](#testing)).
- Optional shared cross-shell git cache, so panes in the same repo don't
  each pay their own cache miss.
- Verify or explicitly drop BSD/macOS support — currently untested.
- A `prompt_layout --preview` mode to render a layout once without
  installing it into `PROMPT_COMMAND`, for faster iteration.
- Reduce the remaining per-render forks, mostly `tr` in `_ps_seg_pwd`'s
  control-byte sanitizer and `wc` in `str_width`.
## Environment variables

| Variable | Effect |
|---|---|
| `NO_COLOR` | Disables all color output (both raw and prompt mode) — [no-color.org](https://no-color.org) convention |
| `PS_SKIP_DEBUG_TRAP` | Set to `1` before sourcing to skip claiming the `DEBUG` trap — use when combining with another DEBUG-trap tool (bats, direnv). Sacrifices `@cmd_time`; nothing else is affected. As of v0.1.2 this is a compatibility alias for `lib/cmd_timer.sh`'s own `CMD_TIMER_SKIP_TRAP`; either works. See the [version history](#version-history) for why automatic detection was abandoned in favor of this. |
| `PS_DEBUG_SEGMENTS` | Set to `1` to surface a failing segment's stderr and a `segment "<name>" exited <code>` message instead of silently rendering it as empty. Off by default — one broken custom segment still can't take down the whole prompt. |

Raw-mode color also auto-disables when stdout isn't a terminal (e.g.
piped to a log file) — no environment variable needed for that case.

## Architecture

```
Segment → Row → Layout → PS1
```

- **Segment** — a function that writes one piece of prompt content to
  stdout (branch name, exit code, working directory, …). Segments know
  nothing about layout; they use `C_*`/`PS_*` color variables and stay
  silent (empty output) when not applicable.
- **Row** — a named template string referencing segments by `@name`
  token, plus an optional `@fill` token that pads to the row's width.
- **Layout** — an ordered list of rows, optionally wrapped in a Unicode
  box (`--box <style>`), open or `--closed`.

```
╭─[ chris@devbox ]────────────────────────────────[ ~/projects/myapp ]─╮
│  ⬇2  ⇄ ssh  ⧉ proj:2.1  :0  (py311)  ⚙ 2                              │
│  ⎇  feature/auth  →  origin/feature/auth  ↑3 ↓1                       │
│     +2 ~5 ?3  ⚑1                                                       │
╰─[✓] 5s $
```
(see [What it looks like](#what-it-looks-like) for a field-by-field
breakdown of that render)

### Where data collection happens

`prompt_build` runs in the shell's own process. It collects everything
expensive — git state, GPU, disk, load — into globals, honoring each
one's TTL, and only then expands the rows.

Row expansion invokes each segment as `val=$(segfunc)`, which is a
**subshell**. That's the single most important fact about this
architecture:

- Anything a segment *assigns* — a variable, a `cache_touch` — is
  discarded when that subshell exits. The parent never sees it.
- So a segment that tries to cache its own data will re-do the expensive
  work on every render, forever, with no error to indicate it.

Hence the rule enforced throughout: **collect in `prompt_build`, format
in the segment.** Built-in segments needing collected data are declared
in `_PS_SEG_NEEDS`; custom ones declare it with `prompt_segment_needs`.

Git state is cached per-process with an mtime+TTL check
(`git_info.sh`) — a cache hit costs two `stat(2)` calls, not a `git`
subprocess.

## Project structure

| File | Purpose |
|---|---|
| `lib/colors.sh` | `C_*`/`PS_*` ANSI color variables; raw mode (scripts) and readline-safe `\001..\002`-wrapped prompt mode |
| `lib/term_utils.sh` | `strip_ansi`, `str_width` (locale-safe code-point count), `str_repeat` — fork-free as of v0.1.2 except `str_width` on non-ASCII input |
| `lib/cache.sh` | Generic TTL bookkeeping (`cache_stale`/`cache_touch`/`cache_age`) — shared by `git_info.sh` and the `@gpu` segment |
| `lib/git_info.sh` | Cached git branch/status/ahead-behind/conflicts/stash state |
| `lib/cmd_timer.sh` | Command-duration tracking via the `DEBUG` trap, behind `@cmd_time` — general-purpose, not prompt-specific |
| `prompt.sh` | The segment/row/layout engine itself |
| `prompt_example.sh` | Working configuration — segments registered, rows defined, one active layout |
| `tests/` | Bats test suite — 8 `.bats` files plus `test_helper.bash` (see [Testing](#testing)) |
| `install.sh` | Copies the toolkit to a target directory and prints the `.bashrc` lines to add — see [Installation](#installation) |

## Testing

```bash
bats tests/                    # requires bats-core; apt install bats
shellcheck lib/*.sh prompt.sh prompt_example.sh install.sh
```

**92 tests across 8 files**, all passing against v0.1.4:

| File | Tests | Covers |
|---|---|---|
| `colors.bats` | 11 | raw/prompt modes, `NO_COLOR`, tty detection, `PS_*` mirrors |
| `git_info.bats` | 11 | counts, conflicts, detached HEAD, ahead/behind, stash, cache validity |
| `nounset.bats` | 6 | `set -u` safety across all modules |
| `prompt_box.bats` | 7 | open/closed boxes, single- and multi-row, `@fill`, layout idempotence |
| `prompt_segments.bats` | 14 | pwd truncation/sanitizing, module counting, exit and conflict segments |
| `security.bats` | 3 | promptvars command-injection regression guards |
| `term_utils.bats` | 9 | ANSI stripping, width, repeat |
| `test_v012_changes.bats` | 31 | everything added or fixed in v0.1.2 – v0.1.4 |

`tests/test_helper.bash` provides `$DOTFILES_ROOT`, `load_prompt_lib`,
`make_git_repo`, and `plain`, and sets `CMD_TIMER_SKIP_TRAP=1` so the
toolkit's `DEBUG` trap doesn't collide with bats-core's own.

Tests carrying `[SECURITY]` or `[nounset]` labels document
previously-open vulnerabilities and gaps that are now **fixed** — they
pass today and exist to catch a regression, not to signal pending work.

### Coverage

`kcov` isn't in this sandbox's apt repositories and wasn't built from
source for this pass — building it needs `cmake` plus several dev
libraries, which felt like too much for a supporting metric on top of
everything else in this round. If it's available in your environment:

```bash
kcov --include-path=lib,prompt.sh,prompt_example.sh coverage/ bats tests/
```

In its place, an executed (not aspirational) function-level audit —
which functions in `lib/*.sh` and `prompt.sh` are referenced by name
anywhere in `tests/`:

**33 / 62 functions (53%)** referenced by at least one test. The
uncovered half is almost entirely trivial single-line environment-
variable formatters (`_ps_seg_host`, `_ps_seg_ssh`, `_ps_seg_time`,
the Slurm segments) plus the `_ps_refresh_*` collectors, which are
exercised indirectly through `prompt_build` but not called by name.

This is a real measured number, not an estimate — but function-name
reference is a weaker signal than line or branch execution. Treat it
as a floor, and use `kcov` above for real numbers.

## Known issues

No code-level issues currently open — everything found in the v0.1.1,
v0.1.2, and v0.1.3 production-readiness audits is fixed, each captured
as a permanent regression test in `tests/`.

One measurement gap remains open:

- **Coverage is a function-name audit, not real line/branch coverage.**
  `kcov` wasn't available in the environment this was assembled in. See
  [Coverage](#coverage) for the command to run and
  [Future work](#future-work).

## Version history

### v0.1.4

**Fixed:**

- **Refresh gating was keyed on the segment's registered NAME, not its
  function**, so any alias silently broke it. `prompt_segment gpu_util
  _ps_seg_gpu` or `prompt_segment branch _ps_seg_git_branch` left the
  corresponding refresh disarmed, and the segment rendered blank
  forever with no error — the worst failure mode, in exactly the
  situation the row-template system invites. Dependencies are now
  declared per-function in `_PS_SEG_NEEDS`, so a built-in segment works
  under any name.
- **`_ps_seg_pbs_nodes` mis-declared its locals.** `local -A seen=()
  line n=0` applies `-A` to all three names, making `line` and `n`
  associative arrays. It produced correct output only because bash
  routes the bare read and increment through index `[0]` — accident,
  not rule. Each variable is now declared with its intended type.
- Corrected the README's test claims, which cited a suite size and file
  count the package did not contain.

**Added:**

- `prompt_segment_needs <function> <git|gpu|disk|load>` — lets a custom
  segment declare a dependency on collected data, the supported
  replacement for the name-matching that used to be inferred.
- `tests/test_helper.bash` — the seven original `.bats` files all
  `load test_helper`, which was missing from the tree, so none of them
  could run. Provides `$DOTFILES_ROOT`, `load_prompt_lib`,
  `make_git_repo`, and `plain`, plus the `CMD_TIMER_SKIP_TRAP=1` opt-out
  that keeps the toolkit's `DEBUG` trap from colliding with bats-core's.
  Reconciled against the original: the trap opt-out moved to file scope
  (several `.bats` files source `prompt.sh` directly without going
  through `load_prompt_lib`, and would otherwise claim the trap);
  `make_git_repo` now pins the default branch and disables commit
  signing, so a global `commit.gpgsign=true` can't break the suite; and
  `plain` no longer delegates to the library's own `strip_ansi`, since a
  helper built on the code under test can mask a regression in exactly
  that function. Both versions pass all 92 tests against v0.1.4.
- Six regression tests for the two fixes above.

**Changed:**

- README restructured user-facing-first, opening with a rendered prompt
  mockup and a field-by-field table for every row. Added
  [Configuration and API reference](#configuration-and-api-reference),
  [Assumptions and limitations](#assumptions-and-limitations), and
  [Future work](#future-work); renamed "File layout" to
  "Project structure" and "Changelog" to "Version history".
- The segment-authoring contract — collect in `prompt_build`, format in
  the segment — is now documented in
  [Customization](#customization) with correct and incorrect examples,
  and in [Architecture](#architecture). It previously appeared only
  inside a changelog bug narrative, despite being the rule whose
  violation caused the v0.1.3 GPU cache bug.
- Every function in `lib/*.sh` and `prompt.sh` now carries a brief
  descriptive comment (21 were missing, including `prompt_segment`).
- Obsolete `[FAIL pending fix]` and "EXPECTED TO FAIL" labels removed
  from `security.bats` and `nounset.bats` — those fixes landed in
  v0.1.1 and the tests have been passing since.

### v0.1.3

**Fixed — all found during a production-readiness review, each with a
permanent regression test in `tests/test_v012_changes.bats`:**

- **[CRITICAL] The `@gpu` segment's TTL cache never worked — verified
  via a mocked `nvidia-smi`, every render re-forked it regardless of
  the 10s TTL.** Root cause: `_ps_seg_gpu` ran the actual collection
  and called `cache_touch` from *inside itself* — but `_ps_expand`
  invokes every segment as `val=$(segfunc)`, a command-substitution
  subshell. Any variable a segment assigns is discarded the instant
  that subshell exits, so the cache state never reached the parent
  shell. This generalizes past the one segment it was found in: **data
  collection now happens in `prompt_build` (the parent shell); `_seg_*`
  functions only format already-collected globals** — the same
  separation the git segments always had, by construction. Applied
  consistently to `@disk` and `@load` too, which had the identical
  latent bug (unverified until this pass, since neither had been
  checked the way `@gpu` was).
- **[CRITICAL] `str_repeat '&' N` silently produced spaces instead of
  ampersands** — a regression from v0.1.2's fork-free rewrite. `&` is
  special in bash's `${var//pat/repl}` replacement text (it means "the
  matched text"); the old awk-based version didn't have this quirk.
  Fixed by escaping the replacement character first. Caught because a
  broader input sweep was run against the fork-free rewrite this time,
  not just the handful of characters exercised in v0.1.2's tests.
- **[CRITICAL] `PS_DEBUG_SEGMENTS` changed rendered output, not just
  diagnostic visibility.** A segment that printed partial output before
  failing rendered that partial text in debug mode and correctly
  rendered nothing in normal mode — the debug branch was missing the
  `|| val=""` fallback the normal branch already had. A diagnostic flag
  must be observation-only; fixed to clear `val` on failure in both
  branches, same as before.
- **[HIGH] `SECONDS=0` — an extremely ordinary "time this operation"
  idiom — silently disabled all TTL caching**, making `cache_stale`
  report "fresh" indefinitely once the clock appeared to run backwards.
  `lib/cache.sh` and `lib/cmd_timer.sh` now prefer `EPOCHSECONDS`
  (bash 5.0+), which no ordinary script has a reason to reassign; the
  `$SECONDS` fallback on older bash now treats a negative elapsed time
  as stale rather than trusting it.
- **[HIGH] `_ps_seg_load` and `_ps_seg_disk` forked `nproc`/`df`/`awk`
  on every render even though they render nothing the vast majority of
  the time** — the fork happened before the "should I show anything"
  check could skip it. `nproc`'s result is invariant for the life of
  the shell and is now read once at source time instead of once per
  render. `df`'s result is now collected the same way `@gpu` is — TTL
  cached (30s) via `prompt_build`, not re-forked every render.
- **[HIGH] Shell startup cost of ~175–215ms** from `prompt_segment`
  re-sorting the entire segment-name list via `awk | sort | cut` on
  *every* registration call — a typical config registering ~30
  segments paid for ~30 re-sorts of a list only the final state of
  which mattered. The sort is now deferred to a lazy rebuild
  (`_ps_resort_segments`), a no-op unless something registered since
  the last render. Verified: startup dropped to ~9ms.
  - *A regression introduced by this exact fix, caught by re-running
    the full test suite rather than trusting the isolated checks*:
    deferring the sort meant `_ps_expand` implicitly depended on
    `prompt_build` having run first — called directly (as several
    tests and the collision-bug regression test do), the segment list
    was empty and nothing expanded. `_ps_expand` now also calls the
    (cheap, idempotent) resort itself, so it's self-sufficient again
    regardless of caller.

**Changed:**
- `_ps_seg_jobs`, `git_info.sh`'s `GIT_STASH` count, and
  `_ps_seg_pbs_nodes` no longer fork `wc`/`tr`/`sort` for line-counting
  and deduplication — replaced with `mapfile` or a plain bash read loop.
  `pbs_nodes` in particular had no TTL cache and PBS_NODEFILE doesn't
  change during a job, so this one forked all three, every render, for
  the entire life of any PBS job.
- `git_info.sh` now gives an immediate, clear error if `lib/cache.sh`
  is missing, instead of a confusing `command not found: cache_stale`
  the next time the git cache is actually checked.
- Fork count per render (default layout, in a git repo, in tmux):
  measured ~29 in v0.1.1, ~25 in v0.1.2, **~13 in v0.1.3**. The
  remainder is almost entirely `tr` (control-byte stripping — a
  security-relevant sanitizer, deliberately not touched) and `wc`
  (`str_width`'s non-ASCII fallback, deliberately left as-is per the
  v0.1.2 changelog's own reasoning — still stands).

**Not changed on purpose, considered and rejected:**
- A fork-free bash-native replacement for `_ps_seg_load`'s remaining
  `awk` float comparison. Prototyping it required parsing a load
  average's fractional digits into bash arithmetic, which hits bash's
  octal-literal gotcha (a fractional part like `"08"` is invalid octal
  and errors `(( ))` outright) unless every value is forced through a
  `10#` base prefix. One awk fork on an already TTL-gated,
  already-guarded path is a better trade than a hand-rolled numeric
  parser with its own footgun, freshly discovered while trying to
  avoid it.

### v0.1.2

**Added:**
- `lib/cache.sh` — generic TTL bookkeeping (`cache_stale`/`cache_touch`/
  `cache_age`). Tracks *when* a key was last refreshed, not the cached
  value itself, so it composes with a caller's own smarter invalidation
  (like `git_info.sh`'s mtime checks) instead of replacing it.
- `lib/cmd_timer.sh` — command-duration tracking split out of `prompt.sh`
  (the `DEBUG`-trap arm/elapsed logic behind `@cmd_time`). Nothing about
  it is prompt-specific; it's a standalone "how long did that take"
  utility now, like `colors.sh`, `term_utils.sh`, and `git_info.sh`
  already were.
- `PS_DEBUG_SEGMENTS` — opt-in diagnostic mode. A failing or misnamed
  segment normally renders as silent empty output (by design — one
  broken custom segment shouldn't take down the whole prompt); this
  surfaces its stderr and exit code instead, for when "why is `@foo`
  blank" needs an answer.

**Fixed:**
- **`_ps_expand` token-collision bug.** Segment expansion worked by
  repeatedly substituting `@name` across the *entire accumulated row
  string*, one registered name at a time. If an earlier segment's own
  output happened to contain literal text shaped like `@othername` — a
  branch called `feature/@venv-fix`, a path, a hostname — a later pass
  could match that accidental text and overwrite it with a completely
  unrelated segment's value, even when that segment was never referenced
  in the row's template. Rewritten as a single left-to-right scan over
  the original template that never revisits already-emitted segment
  output, which closes the whole bug class rather than the one instance
  found. Covered by a permanent regression test that reproduces it
  directly (`tests/test_v012_changes.bats`).
- `term_utils.sh`'s `strip_ansi` and `str_repeat` no longer fork
  `sed`/`awk` — rewritten as pure bash (a builtin regex loop, and
  parameter-expansion substitution on a `printf`-padded string).
  Verified to produce byte-identical output to the old implementations
  across representative and edge-case input. One less external-tool
  dependency per colored segment and per padded row, which is a
  robustness property (nothing to be absent, wrong version, or behave
  differently across systems) as much as a speed one.

**Changed:**
- `git_info.sh`'s TTL bookkeeping and the `@gpu` segment's cache now
  both sit on `lib/cache.sh` instead of each independently reinventing
  `$SECONDS`-based TTL tracking. A future cached segment (a live
  Slurm/PBS queue poll, say) gets correct TTL handling by using
  `cache.sh` directly instead of writing a third version of the same
  logic.
- `PS_SKIP_DEBUG_TRAP` is now a compatibility alias: `prompt.sh` forwards
  it to `lib/cmd_timer.sh`'s own `CMD_TIMER_SKIP_TRAP` if the latter
  isn't already set, so existing configs keep working unchanged.

### v0.1.1

**Added:**
- `_ps_seg_root` (`⚡`), `_ps_seg_load` (`⚖`), `_ps_seg_disk` (`⛁`),
  `_ps_seg_gpu` (`GPU N%`, TTL-cached) — wired into the top/env/hpc
  rows in `prompt_example.sh`.

**Fixed (critical):**
- **PS1 command injection via `promptvars`.** Bash re-executes literal
  `$(...)` sitting in `$PS1`'s stored value on every prompt render. A
  directory name, git branch, `$VIRTUAL_ENV` path, `$USER`, or
  `$HOSTNAME` containing `$(...)` reached PS1 unmodified and executed
  repeatedly. Fixed with `shopt -u promptvars` at load time — confirmed
  to fully close this with zero effect on `\$`/`\n` prompt-escape
  handling (a separate, always-on bash mechanism).

**Fixed (high):**
- **DEBUG trap coexistence.** The v0.1.0 chaining fix broke bats-core's
  own DEBUG trap (which does call-stack introspection with hardcoded
  frame-depth assumptions). Automatic detection proved unreliable
  across execution contexts more broadly. Replaced with an explicit
  `PS_SKIP_DEBUG_TRAP=1` opt-out; default behavior is unchanged.
- **Function-scoped `declare` bug.** Every top-level `declare` across
  all four files needed `-g` added. Without it, sourcing this toolkit
  from *within* a bash function — exactly what a test-helper wrapper
  does, and a legitimate pattern for a reusable library — silently
  scopes all of prompt.sh's own state as local to that function,
  vanishing the instant it returns.
- **`set -u` (nounset) safety.** Bare references to `$PROMPT_COMMAND`,
  `$USER`, and `$PROMPT_LAST_EXIT` failed under `set -u`. Invisible in
  an interactive `.bashrc`, relevant when sourced as a library into a
  script that uses nounset. The `$USER` fix also closes a real gap
  independent of nounset: it's a plain env var, not bash-guaranteed
  like `$HOSTNAME`, and can be legitimately unset (confirmed in a
  minimal/containerized context).
- `git_info_refresh` returned git's raw internal exit code (128) via a
  bare `return` rather than a clean, predictable status.

**Fixed (lint hygiene, no behavior change):** quoted git's `@{u}`
syntax and made the space-padding `printf '%*s'` call explicit rather
than relying on implicit argument-exhaustion behavior.

### v0.1.0 — first tagged release

Baseline audit and fix pass across all four files.

**Fixed:**
- Git status counters (`GIT_STAGED`/`MODIFIED`/`UNTRACKED`) threw a
  bash arithmetic error on nearly every refresh — `grep -c` exits 1 on
  zero matches, which tripped an `|| echo 0` fallback and left each
  counter holding two lines instead of one.
- Merge conflicts were invisible — unmerged paths (`UU`/`AA`/etc.)
  matched none of the staged/modified/untracked patterns and read as
  a clean working tree. Added `GIT_CONFLICTS` and the `@git_conflicts`
  segment.
- A single-row box (open *or* closed) rendered as a bare top border
  with no prompt escape at all — `i == 0` was checked before
  `is_last`, so a row that's simultaneously first and last always hit
  the "top of a multi-row box" branch.
- `_ps_seg_pwd`/`_ps_seg_tmux` didn't sanitize control bytes or ANSI
  escapes from directory/session names, which can legally contain
  either.
- `_ps_seg_modules` overcounted on a leading, trailing, or doubled
  colon in `$LOADEDMODULES`.
- The DEBUG trap was silently overwritten if another tool had already
  claimed it.
- Redundant `git rev-parse --git-dir` call (ran twice; one discarded).
- Three `grep -c` forks per refresh consolidated into one `awk` pass.
- `colors_init` forked a subshell per color variable (16 total) —
  switched to `printf -v` for direct assignment.
- Added `NO_COLOR` and non-tty support to `colors.sh`.
- Broadened `strip_ansi` to cover cursor-movement and OSC/BEL
  sequences, not just SGR/erase-line — matching its documented scope.
- Tightened `prompt_layout`'s dedup guard from a bare substring match
  to the exact call token.

**Added:** `GIT_CONFLICTS` global and `@git_conflicts` segment;
version tags across all four files.
