#!/usr/bin/env bash
#
# secret-scan.sh — fast pre-commit secret gate for wtx.
#
# Scans for high-signal credential shapes. When a commit is pending it scans the
# STAGED files; otherwise it scans all tracked files. Prints `path:line:match`
# for anything suspicious.
#
#   exit 0  — clean (or not a git repo)
#   exit 1  — likely secret found (commit should be blocked)
#
# wtx conventions: bash 3.2 compatible, `set -u` only (never `set -e`), graceful
# degradation, no eval. Run standalone or from a pre-commit / automator gate.
#
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "secret-scan: not a git repo — skipping"; exit 0; }
cd "$ROOT" 2>/dev/null || exit 0

# --- high-signal secret patterns (single ERE alternation) -------------------
# telegram bot token | AWS access key id | GitHub token | sk- api key |
# Slack token | PEM private-key header | <name>=<long value> for sensitive keys
COMBINED='[0-9]{8,10}:[A-Za-z0-9_-]{35}|AKIA[0-9A-Z]{16}|gh[posru]_[A-Za-z0-9]{36,}|sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(api[_-]?key|secret|passwd|password|access[_-]?token|auth[_-]?token|bot[_-]?token)[[:space:]]*[:=].{0,4}[A-Za-z0-9_/+=:.-]{20,}'

# lines containing any of these (case-insensitive) are treated as placeholders
ALLOW_RE='REVOKED|REDACTED|PLACEHOLDER|EXAMPLE|CHANGE[_-]?ME|DUMMY|FAKE|YOUR[_-]|XXXX|<[A-Za-z_/.]'

# paths skipped entirely (templates, the scanner itself, binaries, generated)
skip_path() {
  case "$1" in
    scripts/secret-scan.sh|.gitignore) return 0 ;;
    *.example|*.example.*|*.lock) return 0 ;;
    *.png|*.jpg|*.jpeg|*.gif|*.pdf|*.zip|*.gz|*.tgz|*.ico|*.woff*|*.ttf) return 0 ;;
    graphify-out/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- mode: staged if a commit is pending, else whole working tree -----------
if git diff --cached --quiet 2>/dev/null; then
  MODE="worktree"
  list() { git ls-files; }
  read_file() { cat -- "$1" 2>/dev/null; }
else
  MODE="staged"
  list() { git diff --cached --name-only --diff-filter=ACM; }
  read_file() { git show ":$1" 2>/dev/null; }
fi

found=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  skip_path "$f" && continue
  hits="$(read_file "$f" | grep -nIE "$COMBINED" 2>/dev/null | grep -viE "$ALLOW_RE" 2>/dev/null)"
  [ -n "$hits" ] || continue
  while IFS= read -r h; do
    [ -n "$h" ] && echo "  $f:$h"
  done <<EOF
$hits
EOF
  found=1
done < <(list)

if [ "$found" -ne 0 ]; then
  echo "secret-scan: ✗ potential secret(s) found above ($MODE scan) — commit blocked." >&2
  exit 1
fi
echo "secret-scan: ✓ clean ($MODE scan)"
exit 0
