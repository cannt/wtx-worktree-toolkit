---
title: 'Phase 1: wtx config loader'
type: 'feature'
created: '2026-04-15'
status: 'done'
baseline_commit: '355e4e2805b687702188547b4603dac5eea43821'
context:
  - '{project-root}/PORTABILITY_PROMPT.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `wtx` is a standalone tool but still hard-codes Acme-specific values (org, project list, Jira keys, detection markers) across six libs and scripts. Before any de-hardcoding (Phase 2) can happen, there must be a single, discoverable source of truth for per-repo configuration.

**Approach:** Add a new `lib/wtx-config.sh` loader that parses flat-keyed TOML via awk (no external parser), resolves a user-overridable config path, and exposes two scalar/list accessors. Ship a documented `wtx.example.toml` alongside. This phase introduces the loader and schema **only** — no existing script is modified, no existing behavior changes. Phase 2 will wire the loader into `api.sh`, `jira.sh`, `tui.sh`, etc.

## Boundaries & Constraints

**Always:**
- bash 3.2 compatible (no `declare -A`, no `readarray`, no `mapfile`).
- No external TOML parser. Parse flat keys only via `awk`/`sed`/`grep`.
- `wtx_config_get "section.key" [default]` returns value or default or empty string. Never errors.
- `wtx_config_get_list "section.key"` returns newline-separated values. Empty output when key missing.
- Config resolution order (first hit wins): `$WTX_CONFIG` → `$WORKSPACE_ROOT/wtx.toml` → `$HOME/.config/wtx/config.toml`.
- Loader is idempotent and safe to source multiple times (guard with `_WTX_CONFIG_LOADED`).
- Loader is safe to source when no config file exists — functions just return empty/default.
- Backward compat: if `wtx.toml` is absent but `.worktree-projects` exists, `wtx_config_get_list "projects.list"` and `wtx_config_get "jira.projects.<repo>"` must fall back to reading it (same parsing rules as the current `get_known_projects` / `jira_project_for_repo`).
- Preserve eval safety posture of the rest of the codebase: parser must never `eval` user-supplied strings.

**Ask First:**
- Any change that touches a file outside `lib/wtx-config.sh`, `wtx.example.toml`, or a new test script. (Existing scripts stay untouched this phase — that's Phase 2.)
- Adopting a different config format (JSON/YAML/INI) instead of flat TOML.
- Moving the default config path.

**Never:**
- Do not modify `worktree-api.sh`, `worktree-jira.sh`, `worktree-tui.sh`, `worktree-start.sh`, `worktree-done.sh`, `worktree-status.sh`, or any hook. Those belong to Phase 2.
- Do not depend on `python3`, `jq`, `yq`, `tomlq`, or any non-core tool for parsing.
- Do not support nested tables beyond one level of section (`[jira.projects]` is the deepest — key becomes `jira.projects.<name>`). No arrays of tables, no inline tables, no multiline strings.
- Do not break if `wtx.toml` has CRLF line endings or trailing whitespace.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Scalar lookup, key present | `wtx.toml` has `[forge]\norg = "acme"`; call `wtx_config_get forge.org` | prints `acme` | N/A |
| Scalar lookup, key absent, default given | call `wtx_config_get forge.org mydefault` | prints `mydefault` | N/A |
| Scalar lookup, key absent, no default | call `wtx_config_get missing.key` | prints empty, exit 0 | N/A |
| List lookup | `projects.list = ["web", "mobile", "backend"]` | three lines: `web`, `mobile`, `backend` | N/A |
| Dotted nested section | `[jira.projects]\nweb = "PROJ"`; call `wtx_config_get jira.projects.web` | prints `PROJ` | N/A |
| No config file at all | `$WTX_CONFIG` unset, no `wtx.toml`, no user global | all gets return empty/default, exit 0 | N/A |
| Backward compat — projects list | no `wtx.toml`, `$WORKSPACE_ROOT/.worktree-projects` has `web=PROJ\nbackend=CORE` | `wtx_config_get_list projects.list` → `web\nbackend` | N/A |
| Backward compat — jira key | same file as above; `wtx_config_get jira.projects.web` | `PROJ` | N/A |
| `$WTX_CONFIG` points to missing file | env var set to nonexistent path | fall through to next source in resolution chain | silent |
| Commented line | `# org = "ignored"` | key treated as absent | N/A |
| Quoted vs unquoted scalar | `org = "acme"` and `org = acme` | both yield `acme` (strip surrounding `"` only) | N/A |
| Key with inline comment | `org = "acme"  # forge org` | yields `acme` | N/A |

</frozen-after-approval>

## Code Map

- `lib/wtx-config.sh` -- NEW. Config loader. Exposes `wtx_config_get`, `wtx_config_get_list`, and internal `_wtx_config_resolve_path`, `_wtx_config_parse_scalar`, `_wtx_config_parse_list`, `_wtx_config_fallback_worktree_projects`.
- `wtx.example.toml` -- REWRITE. Currently a 1-line stub. Replace with fully commented example covering every documented field (`[forge]`, `[jira.projects]`, `[projects]`, `[detection]`, `[worktree]`, `[defaults]`).
- `tests/test-wtx-config.sh` -- NEW. Executable bash test script sourcing the loader against fixture tomls and asserting every row of the I/O Matrix. Runnable via `bash tests/test-wtx-config.sh`.
- `tests/fixtures/config-full.toml` -- NEW. Valid example covering all documented sections.
- `tests/fixtures/config-partial.toml` -- NEW. Only `[forge]` present — exercises missing-key paths.
- `tests/fixtures/worktree-projects-legacy` -- NEW. Legacy `.worktree-projects` fixture for backward-compat test.
- `lib/worktree-tui.sh:53` -- READ ONLY (reference). Current `get_known_projects` — the parser's fallback must match its semantics exactly.
- `lib/worktree-jira.sh:441` -- READ ONLY (reference). Current `jira_project_for_repo` — same note.

## Tasks & Acceptance

**Execution:**
- [x] `lib/wtx-config.sh` -- Loader with `_WTX_CONFIG_LOADED` guard, path resolver, awk-based scalar + list parsers, `.worktree-projects` fallback helper.
- [x] `wtx.example.toml` -- Rewritten as fully commented example covering every schema field.
- [x] `tests/fixtures/config-full.toml` -- Full fixture covering every section.
- [x] `tests/fixtures/config-partial.toml` -- Partial fixture for missing-key + default paths.
- [x] `tests/fixtures/worktree-projects-legacy` -- Legacy `.worktree-projects` fixture for compat tests.
- [x] `tests/test-wtx-config.sh` -- 19 assertions, all passing.

**Acceptance Criteria:**
- Given a valid `wtx.toml` at `$WORKSPACE_ROOT`, when any script sources `lib/wtx-config.sh` and calls `wtx_config_get "forge.org"`, then it prints the configured org.
- Given `$WTX_CONFIG` is set to an absolute path, when the loader resolves, then that file wins over `$WORKSPACE_ROOT/wtx.toml` and the user global.
- Given no config file exists anywhere, when any getter is called, then it returns empty (or the provided default) and exit code 0.
- Given only a legacy `.worktree-projects` file, when `wtx_config_get_list "projects.list"` is called, then it returns exactly the repo names (field 1) the existing `get_known_projects` would return.
- Given only a legacy `.worktree-projects` file, when `wtx_config_get "jira.projects.web"` is called with that file containing `web=PROJ`, then it prints `PROJ`.
- Given `bash -n lib/wtx-config.sh tests/test-wtx-config.sh`, then both parse without syntax errors.
- Given `bash tests/test-wtx-config.sh`, then it exits 0 with every I/O Matrix row passing.
- Given `git diff --stat`, then only the six files in the Code Map are touched — no other file in the repo is modified.

## Design Notes

**Parser sketch (awk, one pass per lookup — simple beats clever):**

```awk
# Input: KEY="forge.org"  → target_section="forge" target_key="org"
# Track current section; on match, strip quotes + trailing comment, print, exit.
BEGIN { FS="="; in_section="" }
/^\s*\[[^]]+\]\s*$/ { gsub(/[][[:space:]]/,"",$0); in_section=$0; next }
/^\s*#/ || /^\s*$/ { next }
{
  k=$1; sub(/^[[:space:]]+/,"",k); sub(/[[:space:]]+$/,"",k)
  $1=""; sub(/^=/,"",$0); v=$0
  sub(/^[[:space:]]+/,"",v); sub(/[[:space:]]+#.*$/,"",v); sub(/[[:space:]]+$/,"",v)
  gsub(/^"|"$/,"",v)
  full = (in_section=="" ? k : in_section"."k)
  if (full==target) { print v; exit }
}
```

List parser is similar but matches `key = [...]`, strips brackets, splits on `,`, trims quotes per element.

**Why no global associative array:** bash 3.2 lacks `declare -A`. Each getter does a fresh awk pass over the resolved file. `wtx.toml` is small (tens of lines), so this is cheap and keeps the loader stateless.

**Backward-compat fallback path:** inside `wtx_config_get_list` and `wtx_config_get`, if the resolved file is empty and the requested key is `projects.list` or `jira.projects.*`, read `$WORKSPACE_ROOT/.worktree-projects` using the exact same awk rules as the current `get_known_projects` / `jira_project_for_repo`. This mirrors existing behavior byte-for-byte so Phase 2 can swap call sites without regression.

## Verification

**Commands:**
- `bash -n lib/wtx-config.sh` -- expected: exit 0, no output
- `bash -n tests/test-wtx-config.sh` -- expected: exit 0, no output
- `bash tests/test-wtx-config.sh` -- expected: exit 0, every I/O Matrix row prints `PASS`
- `git diff --stat` -- expected: only the six Code Map files appear
