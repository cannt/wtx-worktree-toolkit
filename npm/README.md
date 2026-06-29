# wtx-toolkit

One-command installer for [**wtx**](https://github.com/cannt/wtx-worktree-toolkit) —
a portable, pure-bash git **worktree management** toolkit.

This npm package is a thin wrapper. It does no install logic of its own; it runs
the project's `bootstrap.sh`, which clones the toolkit to a stable home, links the
`wtx` command onto your `PATH`, and (optionally) runs the per-project setup wizard.

## Usage

```bash
# Install (from anywhere; if inside a git repo it offers per-project setup)
npx wtx-toolkit install

# Just install the binary, skip per-project setup
npx wtx-toolkit --no-project

# Preview without changing anything
npx wtx-toolkit --dry-run
```

Equivalent pure-bash one-liner (no Node required):

```bash
curl -fsSL https://raw.githubusercontent.com/cannt/wtx-worktree-toolkit/main/bootstrap.sh | bash
```

## Requirements

- `bash`, `git`, `curl` (wtx is a bash toolkit; Node is only used to launch the bootstrap)

## Configuration

The wrapper forwards all flags to `bootstrap.sh`. Environment overrides:
`WTX_HOME`, `WTX_REPO_URL`, `WTX_REF`, `WTX_PREFIX`. See `bootstrap.sh --help`.

## Updating

Re-run the installer, or use the built-in updater once installed:

```bash
wtx update
```

## License

MIT
