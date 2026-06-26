#!/bin/bash
# Android Worktree Setup Script
# Configures a newly created worktree with Android-specific files and directories.
# Called by worktree-start.sh and worktree-create.sh after git worktree add.
#
# Usage: ./plugins/android-setup.sh <worktree-path> <source-project-path>
#
# ERROR HANDLING: No set -e. Each operation has its own check. Script prints
# warnings but continues — a missing local.properties should not block worktree use.

WORKTREE_PATH="$1"
SOURCE_PROJECT="$2"

if [[ -z "$WORKTREE_PATH" ]] || [[ -z "$SOURCE_PROJECT" ]]; then
    echo "Usage: $0 <worktree-path> <source-project-path>" >&2
    exit 1
fi

if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree path does not exist: $WORKTREE_PATH" >&2
    exit 1
fi

if [[ ! -d "$SOURCE_PROJECT" ]]; then
    echo "Error: Source project path does not exist: $SOURCE_PROJECT" >&2
    exit 1
fi

# Resolve workspace root: walk up from script location to find .worktreeinclude
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="${CLAUDE_PROJECT_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

INCLUDE_FILE="$WORKSPACE_ROOT/.worktreeinclude"

# Copy files listed in .worktreeinclude
if [[ -f "$INCLUDE_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue

        # Trim whitespace and strip carriage return
        line="$(echo "$line" | xargs)"
        line="${line%$'\r'}"

        # Block path traversal
        if [[ "$line" == *".."* ]]; then
            echo "  Warning: Skipping path with '..': $line" >&2
            continue
        fi

        SOURCE_FILE="$SOURCE_PROJECT/$line"
        DEST_FILE="$WORKTREE_PATH/$line"

        if [[ -f "$SOURCE_FILE" ]]; then
            # Create parent directory if needed
            DEST_DIR="$(dirname "$DEST_FILE")"
            mkdir -p "$DEST_DIR" 2>/dev/null

            cp "$SOURCE_FILE" "$DEST_FILE" 2>/dev/null
            if [[ $? -eq 0 ]]; then
                echo "  Copied: $line" >/dev/tty 2>/dev/null || true
            else
                echo "  Warning: Failed to copy $line" >&2
            fi
        else
            echo "  Warning: Source file not found, skipping: $line" >&2
        fi
    done < "$INCLUDE_FILE"
else
    echo "  Warning: .worktreeinclude not found at $INCLUDE_FILE" >&2
fi

# Create .build-cache directory
mkdir -p "$WORKTREE_PATH/.build-cache" 2>/dev/null
if [[ $? -eq 0 ]]; then
    echo "  Created: .build-cache/" >/dev/tty 2>/dev/null || true
else
    echo "  Warning: Could not create .build-cache directory" >&2
fi

# Verify ANDROID_HOME or sdk.dir
SDK_OK=false
if [[ -n "$ANDROID_HOME" ]]; then
    SDK_OK=true
elif [[ -f "$WORKTREE_PATH/local.properties" ]]; then
    if grep -q "sdk.dir" "$WORKTREE_PATH/local.properties" 2>/dev/null; then
        SDK_OK=true
    fi
fi

if [[ "$SDK_OK" != "true" ]]; then
    echo "  Warning: Neither ANDROID_HOME nor sdk.dir in local.properties is set" >&2
fi

# Add worktree entries to .git/info/exclude (local-only, not tracked)
# Worktrees share the main repo's .git, so we add to the source project's info/exclude.
# This covers both the main repo and all its worktrees.
EXCLUDE_FILE="$SOURCE_PROJECT/.git/info/exclude"
if [[ -f "$EXCLUDE_FILE" ]]; then
    if ! grep -q "\.build-cache/" "$EXCLUDE_FILE" 2>/dev/null; then
        printf "\n# Worktree artifacts\n.build-cache/\nWORKTREE_CONTEXT.md\n" >> "$EXCLUDE_FILE"
        echo "  Updated: .git/info/exclude" >/dev/tty 2>/dev/null || true
    fi
elif [[ -d "$SOURCE_PROJECT/.git/info" ]]; then
    printf "# Worktree artifacts\n.build-cache/\nWORKTREE_CONTEXT.md\n" >> "$EXCLUDE_FILE"
    echo "  Created: .git/info/exclude entries" >/dev/tty 2>/dev/null || true
else
    echo "  Warning: Could not find .git/info/exclude at $SOURCE_PROJECT" >&2
fi

echo "  Setup complete." >/dev/tty 2>/dev/null || true
