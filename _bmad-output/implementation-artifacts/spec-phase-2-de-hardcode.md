---
title: 'Phase 2: de-hardcode call sites'
type: 'refactor'
created: '2026-04-15'
status: 'done'
baseline_commit: '7ae4310'
context:
  - '{project-root}/PORTABILITY_PROMPT.md'
  - '{project-root}/_bmad-output/implementation-artifacts/spec-phase-1-config-loader.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Phase 1 shipped `lib/wtx-config.sh` but no caller uses it yet. Acme-specific strings (`acme`, `web`/`mobile`/`backend`, `PROJ`/`APP`, `settings.gradle`, `PROJ-1234`, `example-feature-screen`, unconditional `android-worktree-setup.sh`) are still hard-coded in six libs, three scripts, and one hook.

**Approach:** Wire `wtx_config_get` / `wtx_config_get_list` into every call site called out by Phase 2 of `PORTABILITY_PROMPT.md`. Every hard-coded Acme fallback becomes empty-or-config-driven. Add a single `wtx_detect_project` helper in `lib/wtx-config.sh` that reads `detection.markers` and defaults to `.git`-only, and call it from the four duplicate `detect_project` sites. Replace the unconditional `android-worktree-setup.sh` invocation with a `worktree.setup_hook` lookup, and move the Android script to `plugins/android-setup.sh` as the opt-in example. Add forge-aware PR URL construction in `worktree-done.sh` (bitbucket / github / gitlab). No behavior change when a `wtx.toml` with the current Acme values is present — that reproduces today's behavior byte-for-byte.

## Boundaries & Constraints

**Always:**
- bash 3.2 compatible. No `declare -A`, `readarray`, `mapfile`, or `[[ =~ ]]` beyond what already exists.
- Every hard-coded Acme string listed in the I/O Matrix must be gone from the files listed in the Code Map.
- Preserve dual-path API, eval safety, graceful degradation, and inline stub fallbacks. Stubs must remain present; only their *contents* change (to empty / generic values).
- Libs in `lib/` source `wtx-config.sh` via `"$(dirname "${BASH_SOURCE[0]}")/wtx-config.sh"` guarded by `2>/dev/null || true`, so failure to source never breaks the lib.
- Config lookups use these keys only: `forge.type`, `forge.org`, `projects.list`, `jira.projects.<repo>`, `detection.markers`, `worktree.setup_hook`, `worktree.registry_path`, `worktree.builtin_path`, `defaults.base_branch`.
- PR URL builder supports `bitbucket` (default when unset, for backward compat), `github`, `gitlab`. Unknown forge type → print a warning and omit the PR offer (do not crash).
- `wtx_detect_project` defaults to `.git` alone when `detection.markers` is empty. When markers are configured, a directory qualifies if it contains `.git` **and** any one of the configured markers.
- Backward compat with legacy `.worktree-projects`: unchanged — continues to work via the Phase 1 fallback.
- A `wtx.toml` with `forge.org="acme"`, `forge.type="bitbucket"`, `projects.list=["web","mobile","backend"]`, `jira.projects.web="PROJ"`, `jira.projects.mobile="APP"`, `detection.markers=["settings.gradle","settings.gradle.kts"]`, `worktree.setup_hook="plugins/android-setup.sh"` reproduces current Acme behavior exactly.
- `git mv scripts/android-worktree-setup.sh plugins/android-setup.sh` — preserve history.

**Ask First:**
- Any change to `bin/wtx`, `install.sh`, or `wtx.example.toml` beyond what this spec covers (those are Phase 3 / 4).
- Touching `scripts/worktree-start.sh`'s SCRIPT_DIR/WORKSPACE_ROOT path math. It is broken for the standalone layout; Phase 3 dispatcher owns that fix.
- Adding any new config key beyond the allowlist above.

**Never:**
- Do not fix broken lib sourcing paths in scripts (`$SCRIPT_DIR/lib/...`). Those remain for Phase 3.
- Do not depend on `python3`, `jq`, `yq`, `tomlq` for config parsing — Phase 1 loader only.
- Do not add nested-table support or new TOML features. Loader is frozen.
- Do not remove or rewrite inline stubs. Only edit their *bodies* per the Code Map.
- Do not introduce new files outside the Code Map.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected | Error |
|---|---|---|---|
| Fresh clone, no `wtx.toml` | nothing configured | `BITBUCKET_ORG` empty; `get_known_projects` empty; `jira_project_for_repo web` empty; `detect_project` matches any `.git` dir | N/A |
| Acme-shaped `wtx.toml` | all keys set as listed in "Always" | behavior matches pre-Phase-2 exactly | N/A |
| PR URL, `forge.type=bitbucket`, org=`acme`, repo=`foo`, branch=`feat/x` | `worktree-done.sh` builds URL | `https://bitbucket.org/acme/foo/pull-requests/new?source=feat/x` | N/A |
| PR URL, `forge.type=github`, same inputs | `worktree-done.sh` builds URL | `https://github.com/acme/foo/compare/feat/x?expand=1` | N/A |
| PR URL, `forge.type=gitlab`, same inputs | `worktree-done.sh` builds URL | `https://gitlab.com/acme/foo/-/merge_requests/new?merge_request[source_branch]=feat/x` | N/A |
| PR URL, unknown forge type `svn` | same inputs | warning to stderr, PR offer skipped, rest of cleanup proceeds | warn-and-continue |
| PR URL, `forge.org` empty | no config | warning to stderr, PR offer skipped | warn-and-continue |
| `detect_project` with markers configured to `Cargo.toml` | cwd inside a Rust workspace | returns workspace root | N/A |
| `detect_project` no markers, cwd inside any git repo | fresh repo, no wtx.toml | returns the git repo root | N/A |
| `setup_hook` unset | worktree creation | no setup hook runs; no warning | N/A |
| `setup_hook = "plugins/android-setup.sh"`, file present | worktree creation | script runs with `(worktree_path, project_dir)` | N/A |
| `setup_hook` set but file missing | worktree creation | warning to stderr, creation still succeeds | warn-and-continue |
| Inline stubs (lib source fails) | libs unreachable | `get_known_projects` empty; `jira_project_for_repo` empty; `detect_project` matches any `.git` dir | N/A |
| Placeholder text in TUI prompts | interactive mode | prompts read `PROJ-1234`, example slug `user-login-screen` | N/A |

</frozen-after-approval>

## Code Map

- `lib/wtx-config.sh` -- ADD `wtx_detect_project` (walks up from $1, requires `.git` plus ANY configured marker, or just `.git` if markers empty). Keep loader guard intact.
- `lib/worktree-api.sh:12` -- Replace hardcoded `acme`. Source `wtx-config.sh`; `BITBUCKET_ORG="${BITBUCKET_ORG:-$(wtx_config_get forge.org)}"`.
- `lib/worktree-jira.sh:15` -- Same treatment as api.sh.
- `lib/worktree-jira.sh:230,328` -- Replace example slug `example-feature-screen` with `user-login-screen` inside the two prompt heredocs.
- `lib/worktree-jira.sh:441-466` -- `jira_project_for_repo`: source `wtx-config.sh`; first try `wtx_config_get "jira.projects.$repo"`; empty else. Delete the two hardcoded `case` blocks.
- `lib/worktree-tui.sh:53-69` -- `get_known_projects`: source `wtx-config.sh`; return `wtx_config_get_list projects.list`. Delete hardcoded echoes.
- `lib/worktree-interactive.sh:85,95` -- Replace `PROJ-1234` with `PROJ-1234` in `tui_input` prompts.
- `scripts/worktree-start.sh:36` -- Inline stub `get_known_projects() { :; }` (returns empty).
- `scripts/worktree-start.sh:73` -- Inline stub `jira_project_for_repo() { echo ""; }`.
- `scripts/worktree-start.sh:99-109` -- Replace body of `detect_project` with: try sourcing `lib/wtx-config.sh` via `"$(dirname "$SCRIPT_DIR")/lib/wtx-config.sh"`; if `wtx_detect_project` defined, delegate; else walk up looking for `.git` only.
- `scripts/worktree-start.sh:10,12,129,131` -- Replace `PROJ-1234` / `web` example text with `PROJ-1234` / generic placeholders in usage comments and echoed help.
- `scripts/worktree-start.sh:238-244` -- Replace Android setup block: read `setup_hook=$(wtx_config_get worktree.setup_hook)`; if non-empty and file exists (resolved relative to the wtx repo root), run it with `(worktree_path, project_dir)`; missing-file → stderr warning; unset → silent skip.
- `scripts/worktree-done.sh:32` -- Empty inline stub.
- `scripts/worktree-done.sh:59-67` -- Same `detect_project` replacement as worktree-start.sh.
- `scripts/worktree-done.sh:418-431` -- Build PR URL using `forge.type` / `forge.org`. Helper function `_wtx_build_pr_url forge_type org repo branch` printed stdout; unknown / empty → warn+skip.
- `scripts/worktree-status.sh:28` -- Empty inline stub.
- `scripts/worktree-status.sh:60-68` -- Same `detect_project` replacement.
- `hooks/worktree-create.sh:27-37` -- Same `detect_project` replacement (anchor via `$WORKSPACE_ROOT/lib/wtx-config.sh`).
- `hooks/worktree-create.sh:98-101` -- Replace Android setup with same `setup_hook` config lookup as `worktree-start.sh`.
- `scripts/android-worktree-setup.sh` → `plugins/android-setup.sh` -- `git mv`. No content changes.
- `wtx.example.toml` -- Append `setup_hook = "plugins/android-setup.sh"` commented example under `[worktree]`, and a `forge.type` / `forge.org` stanza with all three forge values documented. Do not touch existing lines.
- `tests/test-wtx-config.sh` -- ADD assertions for `wtx_detect_project` (with and without markers) and for a new `_wtx_build_pr_url` helper if that helper lives in `wtx-config.sh` (decide during impl; default: put it in a new tiny helper `lib/wtx-forge.sh` if it complicates config loader — Ask First before adding new file). **Decision:** put `_wtx_build_pr_url` inline in `scripts/worktree-done.sh` to avoid a new lib file.

## Tasks & Acceptance

**Execution:**
- [x] `lib/wtx-config.sh` -- add `wtx_detect_project` walker reading `detection.markers`, default `.git`-only
- [x] `lib/worktree-api.sh` -- source wtx-config, `BITBUCKET_ORG` from `forge.org`
- [x] `lib/worktree-jira.sh` -- source wtx-config; `BITBUCKET_ORG`; `jira_project_for_repo` via config; swap example slug
- [x] `lib/worktree-tui.sh` -- `get_known_projects` via `wtx_config_get_list projects.list`
- [x] `lib/worktree-interactive.sh` -- prompts use `PROJ-1234`
- [x] `scripts/worktree-start.sh` -- empty stubs, delegating `detect_project`, setup-hook lookup, generic placeholder text
- [x] `scripts/worktree-done.sh` -- empty stubs, delegating `detect_project`, forge-aware PR URL builder
- [x] `scripts/worktree-status.sh` -- empty stubs, delegating `detect_project`
- [x] `hooks/worktree-create.sh` -- delegating `detect_project`, setup-hook lookup
- [x] `git mv scripts/android-worktree-setup.sh plugins/android-setup.sh`
- [x] `wtx.example.toml` -- already documents `forge.type`, `forge.org`, `worktree.setup_hook` (no change needed)
- [x] `tests/test-wtx-config.sh` -- assertions for `wtx_detect_project` (4 new cases, 23/23 passing)
- [x] `scripts/builtin-worktree-enhance.sh` -- in-scope nudge: same setup_hook pattern (the `git mv` would have left it invoking a now-missing file)

**Acceptance Criteria:**
- Given `grep -RInE 'acme|mobile|example-feature|PROJ-1234' lib/ scripts/ hooks/ bin/`, when run after Phase 2, then only PORTABILITY_PROMPT.md, spec files, and `_bmad-output/` show hits — no runtime file.
- Given no `wtx.toml`, when `lib/worktree-tui.sh` is sourced and `get_known_projects` called, then output is empty (not `web\nmobile\nbackend`).
- Given `wtx.toml` with the Acme-shaped values, when any of the three scripts run, then observable behavior matches the pre-Phase-2 baseline.
- Given `forge.type=github`, when `worktree-done.sh` reaches the PR offer, then the printed URL matches the github pattern in the I/O Matrix.
- Given `bash -n` on every modified `.sh` file, then exit 0 with no output.
- Given `bash tests/test-wtx-config.sh`, then exit 0 with all assertions passing (existing + new).
- Given `git diff --stat`, then only the files in the Code Map are touched.

## Spec Change Log

- **2026-04-15 — Review patch.** Finding: `wtx_detect_project` infinite-loops on relative-path input (`dirname "."` == `"."`). Patch: normalise relative inputs to absolute via `cd && pwd`, and add `prev` sentinel as a belt-and-braces terminator. Added test case 14 (`detect: relative '.' normalised, no infinite loop`). 24/24 passing. No frozen section modified. KEEP: absolute-path precondition — do not revert to bare `dirname` walk.

## Design Notes

**Sourcing wtx-config from libs:**
```bash
# inside lib/worktree-api.sh, lib/worktree-jira.sh, lib/worktree-tui.sh
_wtx_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_wtx_self_dir/wtx-config.sh" 2>/dev/null || true
```

**Forge URL builder (inline in `worktree-done.sh`):**
```bash
_wtx_build_pr_url() {
    local forge_type="$1" org="$2" repo="$3" branch="$4"
    case "$forge_type" in
        bitbucket|"") printf 'https://bitbucket.org/%s/%s/pull-requests/new?source=%s\n' "$org" "$repo" "$branch" ;;
        github)       printf 'https://github.com/%s/%s/compare/%s?expand=1\n' "$org" "$repo" "$branch" ;;
        gitlab)       printf 'https://gitlab.com/%s/%s/-/merge_requests/new?merge_request[source_branch]=%s\n' "$org" "$repo" "$branch" ;;
        *)            return 1 ;;
    esac
}
```

**`wtx_detect_project` sketch:**
```bash
wtx_detect_project() {
    local dir="$1"
    local markers
    markers="$(wtx_config_get_list detection.markers)"
    while [[ -n "$dir" && "$dir" != "/" ]]; do
        if [[ -e "$dir/.git" ]]; then
            if [[ -z "$markers" ]]; then
                printf '%s\n' "$dir"; return 0
            fi
            local m
            while IFS= read -r m; do
                [[ -n "$m" ]] || continue
                if [[ -e "$dir/$m" ]]; then printf '%s\n' "$dir"; return 0; fi
            done <<< "$markers"
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}
```

**Why keep broken `$SCRIPT_DIR/lib` sourcing:** scripts today fall through to inline stubs. Fixing that is Phase 3's dispatcher work (it sets `WTX_ROOT` correctly). Here we just make the stubs and libs both honor config.

## Verification

**Commands:**
- `bash -n lib/*.sh scripts/*.sh hooks/*.sh tests/*.sh` -- exit 0
- `bash tests/test-wtx-config.sh` -- exit 0, all assertions pass
- `grep -RInE 'acme|mobile|example-feature|PROJ-1234' lib scripts hooks bin` -- no hits
- `git diff --stat` -- only Code Map files touched
- `git log --oneline -1 plugins/android-setup.sh` -- history preserved via `git mv`

**Manual checks:**
- Source `lib/worktree-tui.sh` in a throwaway shell with no `wtx.toml`; confirm `get_known_projects` prints nothing.
- Create a scratch `wtx.toml` with `forge.type=github`, `forge.org=acme`; trace `worktree-done.sh` PR URL line via `set -x` on a dummy branch.
