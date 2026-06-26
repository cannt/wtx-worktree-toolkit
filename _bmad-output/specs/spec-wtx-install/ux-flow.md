# wtx install — UX Flow

Step-by-step wizard screens. Consumed by CAP-1 (wizard flow) and CAP-2 (templating engine) in SPEC.md. Each step shows the gum-styled rendering and its pure-bash fallback.

---

## Notation

```
┌─ gum rendering ─────────────────────────────────┐
│  What the user sees when gum is present          │
└──────────────────────────────────────────────────┘

  fallback (no gum): plain read prompt equivalents
```

`[dry-run]` is prepended to action lines when `--dry-run` is active. No files are written in that mode; the console output is otherwise identical.

---

## Step 0 — Preflight

Before any prompt, the wizard performs silent checks:

1. Verify the current directory is inside a git repo (`git rev-parse --git-dir`). If not, print an error and exit non-zero.
2. Detect `gum` on PATH; set a flag that governs every subsequent prompt.
3. Detect `--dry-run` flag; set a flag that governs every write operation.

No user interaction. If gum is absent, a one-line notice is printed:

```
  note: gum not found — using plain prompts (install with: brew install gum)
```

---

## Step 1 — Welcome banner

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   wtx  ·  interactive project installer                 │
│                                                         │
│   workspace : /path/to/your/workspace                   │
│   wtx root  : /path/to/wtx                             │
│                                                         │
│   Press Ctrl-C at any time to abort without changes.   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

*fallback (no gum):* same text, printed with plain `echo`/`printf`. No border.

---

## Step 2 — Binary install

**Context check:** The wizard checks whether a `wtx` command is already on PATH and resolves to the current `WTX_ROOT`.

*If already installed and pointing at this install:*

```
┌─────────────────────────────────────────────────────────┐
│   [✓] wtx already on PATH  →  ~/.local/bin/wtx          │
│       pointing at this install. Skipping symlink step.  │
└─────────────────────────────────────────────────────────┘
```

*If not installed (or pointing elsewhere):*

```
┌─────────────────────────────────────────────────────────┐
│   Install wtx on PATH                                   │
│                                                         │
│   Install prefix  [~/.local]  ▏                        │
│   (symlink will be created at <prefix>/bin/wtx)        │
└─────────────────────────────────────────────────────────┘
```

User confirms or edits the prefix. The wizard delegates to `install.sh --prefix <value>` (or `install.sh --prefix <value> --dry-run` in dry-run mode).

*fallback (no gum):*

```
Install wtx symlink.
Install prefix [~/.local]:
```

---

## Step 3 — Forge configuration

Shown as a two-part block: select, then input.

```
┌─────────────────────────────────────────────────────────┐
│   Forge type                                            │
│                                                         │
│   > github                                              │
│     gitlab                                              │
│     bitbucket                                           │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│   Forge org / owner slug                                │
│                                                         │
│   ▏                                                     │
└─────────────────────────────────────────────────────────┘
```

`base_url` is offered only if the user signals they use a self-hosted instance (a checkbox or yes/no confirm before the URL prompt).

```
┌─────────────────────────────────────────────────────────┐
│   Self-hosted instance? (leave blank for SaaS)          │
│   Base URL  []:  ▏                                      │
└─────────────────────────────────────────────────────────┘
```

*fallback (no gum):*

```
Forge type [bitbucket|github|gitlab] (github):
Forge org/owner:
Self-hosted base URL (leave blank for SaaS default):
```

---

## Step 4 — Project directories

```
┌─────────────────────────────────────────────────────────┐
│   Known project directories                             │
│   (comma-separated, relative to workspace root)         │
│   Leave blank to skip — you can add them later.        │
│                                                         │
│   ▏                                                     │
└─────────────────────────────────────────────────────────┘
```

*fallback (no gum):*

```
Known project dirs, comma-separated (optional):
```

---

## Step 5 — Detection markers

Select a preset or enter custom.

```
┌─────────────────────────────────────────────────────────┐
│   Project root detection markers                        │
│                                                         │
│   > .git (any git repo — default)                       │
│     Gradle / Android  (settings.gradle, settings.gradle.kts)
│     Rust              (Cargo.toml)                      │
│     Node.js           (package.json)                    │
│     Custom…                                             │
└─────────────────────────────────────────────────────────┘
```

If "Custom…" is selected, a text input appears:

```
┌─────────────────────────────────────────────────────────┐
│   Custom markers, comma-separated                       │
│   ▏                                                     │
└─────────────────────────────────────────────────────────┘
```

*fallback (no gum):*

```
Detection markers preset:
  1) .git (default)
  2) Gradle / Android
  3) Rust
  4) Node.js
  5) Custom
Choice [1]:
```

---

## Step 6 — Branch defaults

```
┌─────────────────────────────────────────────────────────┐
│   Branch defaults                                       │
│                                                         │
│   Base branch   [main]   ▏                              │
│   Branch prefix [feature] ▏                             │
└─────────────────────────────────────────────────────────┘
```

*fallback (no gum):*

```
Default base branch [main]:
Default branch prefix [feature]:
```

---

## Step 7 — Jira project key mapping

Iterative loop. Jira integration is optional; the user may skip by pressing Enter with no input.

```
┌─────────────────────────────────────────────────────────┐
│   Jira project keys                 (optional — skip ↵) │
│                                                         │
│   Repo name  ▏                                          │
└─────────────────────────────────────────────────────────┘
```

When the user enters a repo name:

```
┌─────────────────────────────────────────────────────────┐
│   Jira key for "my-repo"                                │
│   ▏                                                     │
└─────────────────────────────────────────────────────────┘
```

After each pair, a confirmation/continue prompt:

```
  Added: my-repo = "PROJ"
  Add another? [y/N]
```

Accumulated pairs are shown as a table if gum is available. When the user declines to add more (or skipped the whole step), the wizard moves on. The `[jira.projects]` section is written with accumulated pairs (zero pairs → section is written with only a comment).

*fallback (no gum):*

```
Jira integration (optional).
Repo name (blank to skip):
Jira key for "my-repo":
Add another? [y/N]:
```

---

## Step 8 — Setup hook

The wizard lists available plugins from `$WTX_ROOT/plugins/` plus a "none" option.

```
┌─────────────────────────────────────────────────────────┐
│   Post-create setup hook                   (optional)   │
│                                                         │
│   > None                                                │
│     android-setup.sh  (Gradle/Android workspace setup)  │
│     Custom path…                                        │
└─────────────────────────────────────────────────────────┘
```

If "Custom path…" is selected, a text input appears for a path relative to `$WTX_ROOT`.

*fallback (no gum):*

```
Post-create setup hook (optional):
  1) None
  2) android-setup.sh
  3) Custom path
Choice [1]:
```

---

## Step 9 — Claude Code hooks

```
┌─────────────────────────────────────────────────────────┐
│   Claude Code lifecycle hooks                           │
│                                                         │
│   Installs three hook scripts into .claude/hooks/:      │
│     worktree-create.sh  — sets up a new worktree       │
│     worktree-detect.sh  — shows worktree context       │
│     worktree-remove.sh  — tears down a worktree        │
│                                                         │
│   Install Claude Code hooks? [Y/n]                      │
└─────────────────────────────────────────────────────────┘
```

If confirmed, the wizard delegates to `install.sh --hooks` (or `--hooks --dry-run`). If declined, step is skipped cleanly.

*fallback (no gum):*

```
Install Claude Code lifecycle hooks into .claude/hooks/? [Y/n]:
```

---

## Step 10 — Extras menu

Shown sequentially, each as a yes/no. Skipped items produce no output or filesystem change.

```
┌─────────────────────────────────────────────────────────┐
│   Optional extras                                       │
│                                                         │
│   [?] Gradle worktree-cache init script                 │
│       Isolates Gradle build caches per worktree.        │
│       Install to ~/.gradle/init.d/?  [y/N]              │
└─────────────────────────────────────────────────────────┘
```

If confirmed, delegates to `install.sh --gradle` (or `--gradle --dry-run`).

```
┌─────────────────────────────────────────────────────────┐
│   [?] PATH hint                                         │
│       ~/.local/bin is not on your PATH.                 │
│       Show how to add it?  [Y/n]                        │
└─────────────────────────────────────────────────────────┘
```

If confirmed (or PATH not detected — see Open Question in SPEC.md), the wizard prints:

```
  Add to your shell startup file:
    export PATH="$HOME/.local/bin:$PATH"
  then restart your shell (or: source ~/.zshrc)
```

*fallback (no gum):* plain yes/no prompts for each extra.

---

## Step 11 — Completion summary

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   wtx install complete                                          │
│                                                                 │
│   [✓] symlink    ~/.local/bin/wtx → /path/to/wtx/bin/wtx       │
│   [✓] config     /path/to/workspace/wtx.toml                   │
│   [✓] hooks      .claude/hooks/worktree-{create,detect,remove} │
│   [-] gradle     skipped                                        │
│   [-] path hint  already on PATH                               │
│                                                                 │
│   Verify your install:                                          │
│                                                                 │
│       wtx doctor                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

Each line is `[✓]` (done), `[-]` (skipped by user), or `[!]` (completed with a warning) followed by a one-line description. In dry-run mode, a header note appears:

```
  [dry-run] No files were written. Remove --dry-run to apply.
```

*fallback (no gum):* same content, plain text without borders.

---

## Wizard ordering rationale

| Order | Step | Why here |
|-------|------|----------|
| 0 | Preflight | Gate — must pass before any user input |
| 1 | Banner | Orient the user before any prompts |
| 2 | Binary install | PATH first so `wtx doctor` can run at the end |
| 3 | Forge config | Core identity of the workspace |
| 4 | Projects | Defines the project picker scope |
| 5 | Detection | Depends on project list being known |
| 6 | Branch defaults | Quick, low-cognitive-load step mid-flow |
| 7 | Jira keys | Optional, per-project detail — placed after project list |
| 8 | Setup hook | Advanced optional — later in flow reduces abandonment |
| 9 | Hooks | Optional integration — after core config complete |
| 10 | Extras | Lowest priority — placed last before summary |
| 11 | Summary | Closing confirmation and handoff to `wtx doctor` |

---

## Dry-run visual difference

In dry-run mode, every step that would write or modify a file instead prints:

```
  [dry-run] would write: /path/to/workspace/wtx.toml
  [dry-run] would create: ~/.local/bin/wtx -> /path/to/wtx/bin/wtx
  [dry-run] would copy:  hooks/worktree-create.sh -> .claude/hooks/worktree-create.sh
```

All prompts still appear and accept input so the user sees what the real run would produce. The completion summary shows `[dry-run]` next to each item.
