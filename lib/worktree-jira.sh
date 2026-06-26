#!/bin/bash
# Worktree Jira Library
# Jira and Bitbucket integration for worktree scripts.
# Uses curl-first approach for data fetching, with claude -p MCP fallback.
# AI reasoning (branch suggestion, AC analysis) still uses claude -p.
#
# Usage: source "$SCRIPT_DIR/lib/worktree-jira.sh"
#
# Requires: worktree-api.sh must be sourced before this file (provides api_* functions).
#   worktree-tui.sh must be sourced first (provides run_with_timeout, has_claude).
#   WORKSPACE_ROOT must be set by the caller.
# All functions degrade gracefully if claude CLI is unavailable.

# Load wtx config loader (same directory); safe if missing.
_wtx_jira_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_wtx_jira_self_dir/wtx-config.sh" 2>/dev/null || true

# Logging stub — real implementation provided when worktree-tui.sh is sourced first.
type -t wtx_log >/dev/null 2>&1 || wtx_log() { :; }

# Bitbucket organization slug — from config or env override, empty if unset.
if command -v wtx_config_get >/dev/null 2>&1; then
    BITBUCKET_ORG="${BITBUCKET_ORG:-$(wtx_config_get "forge.org")}"
else
    BITBUCKET_ORG="${BITBUCKET_ORG:-}"
fi

# AI model for all claude -p operations — Haiku is sufficient for structured-output tasks
# Override per-user via environment variable: WORKTREE_AI_MODEL=claude-sonnet-4-5-20250514
WORKTREE_AI_MODEL="${WORKTREE_AI_MODEL:-claude-haiku-4-5-20251001}"

# Speed optimization env vars for reasoning-only claude -p calls (no MCP, no tools)
# These disable CLAUDE.md scanning, file checkpointing, and telemetry to reduce startup from ~6s to ~3s
CLAUDE_FAST_ENV="CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING=1 DISABLE_TELEMETRY=1"

# Validate an eval payload against a whitelist regex (defense-in-depth)
# Returns 0 if valid, 1 if invalid
_jira_validate_eval() {
    local payload="$1"
    local result
    result=$(python3 -c "
import sys, re
line = sys.argv[1].strip() if len(sys.argv) > 1 else ''
if line and re.fullmatch(r\"([A-Z_]+='[^'\\n\\r]*';\\s*)+\", line + ' '):
    print('valid')
else:
    print('invalid')
" "$payload" 2>/dev/null) || result="invalid"
    [[ "$result" == "valid" ]]
}

# Fetch current user's Jira tickets
# Usage: TICKETS=$(jira_fetch_my_tickets "PROJ")
# Returns: newline-separated "KEY | Title | Status" lines, empty on failure
jira_fetch_my_tickets() {
    local jira_project_key="$1"
    if [[ -z "$jira_project_key" ]]; then
        return 0
    fi
    wtx_log INFO "project=$jira_project_key"
    # F11: Validate project key to prevent JQL injection
    if [[ ! "$jira_project_key" =~ ^[A-Z][A-Z0-9_]+$ ]]; then
        wtx_log WARN "invalid project key format: $jira_project_key"
        echo "Invalid Jira project key: $jira_project_key — entering manual mode" >&2
        return 0
    fi

    # Try curl-first approach
    if type -t api_jira_my_tickets >/dev/null 2>&1; then
        local api_result
        api_result=$(api_jira_my_tickets "$jira_project_key" 2>/dev/null)
        local _api_rc=$?
        if [[ $_api_rc -eq 0 ]] && [[ -n "$api_result" ]]; then
            wtx_log INFO "curl path ok: $(echo "$api_result" | wc -l | tr -d ' ') tickets"
            echo "$api_result"
            return 0
        fi
        wtx_log WARN "curl path failed (rc=$_api_rc output_len=${#api_result})"
    else
        wtx_log WARN "api_jira_my_tickets not available"
    fi

    # MCP fallback
    if ! has_claude; then
        wtx_log WARN "claude CLI not available — cannot use MCP fallback"
        echo "Claude CLI not available — entering manual mode" >&2
        return 0
    fi
    wtx_log INFO "trying MCP fallback (model=$WORKTREE_AI_MODEL timeout=${WORKTREE_JIRA_TIMEOUT:-30}s)"
    local raw_output
    raw_output=$(run_with_timeout "${WORKTREE_JIRA_TIMEOUT:-30}" \
        claude -p "Search Jira for project $jira_project_key. Run TWO searches and combine results:
1. First search: JQL: project = $jira_project_key AND assignee = currentUser() AND status != Done ORDER BY updated DESC (max 10)
2. Second search: JQL: project = $jira_project_key AND labels = frontend AND status != Done AND assignee is EMPTY ORDER BY updated DESC (max 15)
Combine both lists. Mark tickets from search 1 with a star: ★ KEY | Summary | Status. Tickets from search 2 (unassigned) without star: KEY | Summary | Status. Remove duplicates. Return ONLY the plain text list, one per line. No markdown, no headers, no explanation." \
        --model "$WORKTREE_AI_MODEL" \
        --allowedTools "mcp__jira_confluence__jira_search" \
        --output-format json 2>/dev/null)
    local rc=$?
    if [[ $rc -eq 124 ]]; then
        wtx_log WARN "MCP timed out after ${WORKTREE_JIRA_TIMEOUT:-30}s"
        echo "Jira fetch timed out — entering manual mode" >&2
        return 0
    fi
    if [[ $rc -ne 0 ]] || [[ -z "$raw_output" ]]; then
        wtx_log ERROR "MCP claude rc=$rc output_len=${#raw_output}"
        echo "Jira fetch failed — entering manual mode" >&2
        return 0
    fi
    # Parse JSON response
    local parsed
    parsed=$(echo "$raw_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read(), strict=False)
    print(d.get('result', ''))
except (json.JSONDecodeError, KeyError, ValueError):
    sys.exit(1)
" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$parsed" ]]; then
        wtx_log ERROR "MCP response parse failed (raw output_len=${#raw_output})"
        echo "Jira response parse failed — entering manual mode" >&2
        return 0
    fi
    # Filter to only valid ticket lines (with or without ★ prefix)
    local filtered
    filtered=$(echo "$parsed" | grep -E '^(★ )?[A-Z]+-[0-9]+ \|')
    if [[ -z "$filtered" ]]; then
        wtx_log WARN "MCP returned no valid ticket lines (parsed output_len=${#parsed}) content: ${parsed:0:300}"
        echo "No tickets found — entering manual mode" >&2
        return 0
    fi
    wtx_log INFO "MCP ok: $(echo "$filtered" | wc -l | tr -d ' ') tickets"
    echo "$filtered"
}

# Get summary for a specific ticket
# Usage: SUMMARY=$(jira_get_ticket_summary "PROJ-1234")
# Returns: multi-line summary text, empty on failure
jira_get_ticket_summary() {
    local ticket_id="$1"
    if [[ -z "$ticket_id" ]]; then
        return 0
    fi

    # Try curl-first approach
    if type -t api_jira_ticket_details >/dev/null 2>&1; then
        local api_result
        api_result=$(api_jira_ticket_details "$ticket_id" 2>/dev/null)
        if [[ $? -eq 0 ]] && [[ -n "$api_result" ]]; then
            # Parse intermediate _API_* format into plain text (matching current LLM output format)
            local _API_TITLE="" _API_STATUS="" _API_DESCRIPTION="" _API_ISSUE_TYPE="" _API_FIX_VERSIONS="" _API_ACS=""
            if _jira_validate_eval "$api_result"; then
                eval "$api_result"
                printf "TITLE: %s\nSTATUS: %s\nDESCRIPTION: %.200s\n" "$_API_TITLE" "$_API_STATUS" "$_API_DESCRIPTION"
                return 0
            fi
            # Validation failed — fall through to MCP fallback
        fi
    fi

    # MCP fallback
    if ! has_claude; then
        return 0
    fi
    local raw_output
    raw_output=$(run_with_timeout "${WORKTREE_JIRA_TIMEOUT:-20}" \
        claude -p "Get Jira issue $ticket_id. Return ONLY: TITLE: <title>
STATUS: <status>
DESCRIPTION: <first 200 chars of description>. No markdown." \
        --model "$WORKTREE_AI_MODEL" \
        --allowedTools "mcp__jira_confluence__jira_get_issue" \
        --output-format json 2>/dev/null)
    local rc=$?
    if [[ $rc -ne 0 ]] || [[ -z "$raw_output" ]]; then
        return 0
    fi
    local parsed
    parsed=$(echo "$raw_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read(), strict=False)
    print(d.get('result', ''))
except (json.JSONDecodeError, KeyError, ValueError):
    sys.exit(1)
" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        return 0
    fi
    echo "$parsed"
}

# Analyze a Jira ticket — combines branch suggestion + ticket context into a single AI call
# Usage: eval "$(jira_analyze_ticket "PROJ-1234" "my-repo")"
# Sets: SUGGEST_PREFIX, SUGGEST_BASE, SUGGEST_BRANCH_NAME, SUGGEST_SUMMARY,
#        TICKET_TITLE, TICKET_STATUS, TICKET_DESCRIPTION, TICKET_ACS
# Returns exactly ONE line. On failure: all 8 variables set to empty strings.
# Concurrency-safe: no global state, single stdout line.
#
# Performance: curl fetches ticket data (~0.5s), claude -p does reasoning only (~5s).
# If curl fails, falls back to single claude -p + MCP call (~25s).
jira_analyze_ticket() {
    local ticket_id="$1"
    local project_name="$2"
    local empty_defaults="SUGGEST_PREFIX=''; SUGGEST_BASE=''; SUGGEST_BRANCH_NAME=''; SUGGEST_SUMMARY=''; TICKET_TITLE=''; TICKET_STATUS=''; TICKET_DESCRIPTION=''; TICKET_ACS='';"

    if [[ -z "$ticket_id" ]]; then
        echo "$empty_defaults"
        return 0
    fi
    wtx_log INFO "ticket=$ticket_id project=$project_name"

    # Step 1: Try curl for data fetching
    local api_result=""
    if type -t api_jira_ticket_details >/dev/null 2>&1; then
        api_result=$(api_jira_ticket_details "$ticket_id" 2>/dev/null)
        if [[ -n "$api_result" ]]; then
            wtx_log INFO "curl detail ok for $ticket_id (output_len=${#api_result})"
        else
            wtx_log WARN "curl detail failed for $ticket_id — falling through to MCP"
        fi
    else
        wtx_log WARN "api_jira_ticket_details not available"
    fi

    if [[ -n "$api_result" ]]; then
        # Step 2: Curl succeeded — use claude -p for reasoning only (no MCP)
        local _API_TITLE="" _API_STATUS="" _API_DESCRIPTION="" _API_ISSUE_TYPE="" _API_FIX_VERSIONS="" _API_ACS=""
        if ! _jira_validate_eval "$api_result"; then
            echo "$empty_defaults"
            return 0
        fi
        eval "$api_result"

        # Sanitize API data for safe embedding in double-quoted prompt string
        # Strip backticks and $ to prevent any shell expansion (command substitution, variable expansion)
        local _SAFE_TITLE="${_API_TITLE//\`/}"
        _SAFE_TITLE="${_SAFE_TITLE//\$/}"
        local _SAFE_STATUS="${_API_STATUS//\`/}"
        _SAFE_STATUS="${_SAFE_STATUS//\$/}"
        local _SAFE_ISSUE_TYPE="${_API_ISSUE_TYPE//\`/}"
        _SAFE_ISSUE_TYPE="${_SAFE_ISSUE_TYPE//\$/}"
        local _SAFE_FIX_VERSIONS="${_API_FIX_VERSIONS//\`/}"
        _SAFE_FIX_VERSIONS="${_SAFE_FIX_VERSIONS//\$/}"
        local _SAFE_DESCRIPTION="${_API_DESCRIPTION//\`/}"
        _SAFE_DESCRIPTION="${_SAFE_DESCRIPTION//\$/}"

        local ai_output=""
        if has_claude; then
            ai_output=$(run_with_timeout "${WORKTREE_JIRA_TIMEOUT:-30}" \
                env $CLAUDE_FAST_ENV \
                claude -p "Given this Jira ticket context:
TITLE: $_SAFE_TITLE
STATUS: $_SAFE_STATUS
ISSUE TYPE: $_SAFE_ISSUE_TYPE
FIX VERSIONS: $_SAFE_FIX_VERSIONS
DESCRIPTION: $_SAFE_DESCRIPTION

Analyze and return EXACTLY this format (no other text, one field per line):
PREFIX: <one of: feature, fix, refactor, hotfix, spike, test, chore — based on issue type: Bug→fix, Story/Task→feature, Spike→spike, Sub-task→feature, Technical Debt→refactor>
BASE: <suggest base branch: if fixVersion contains a version like 7.13.0 check if release/7.13.0 exists as a common pattern, otherwise develop. Just output the branch name.>
SLUG: <ticket summary converted to lowercase kebab-case slug, max 5 words, e.g. user-login-screen>
SUMMARY: <ticket title, first 80 chars>" \
                --model "$WORKTREE_AI_MODEL" \
                --no-session-persistence --max-turns 1 \
                --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
                --output-format json 2>/dev/null)
        fi

        # Step 3: Assemble final output from curl data + AI reasoning
        local parsed
        parsed=$(python3 -c "
import sys, json, re

api_title = sys.argv[1]
api_status = sys.argv[2]
api_description = sys.argv[3]
api_acs_raw = sys.argv[4]
ai_raw = sys.argv[5] if len(sys.argv) > 5 else ''

# Parse AI output for SUGGEST_* fields only
prefix = ''; base = ''; slug = ''; summary = ''
ai_text = ''
if ai_raw:
    try:
        d = json.loads(ai_raw, strict=False)
        ai_text = d.get('result', '')
    except (json.JSONDecodeError, ValueError):
        pass

for line in ai_text.strip().split('\n'):
    line = line.strip()
    if line.startswith('PREFIX:'):
        prefix = line.split(':', 1)[1].strip().lower().rstrip('/')
    elif line.startswith('BASE:'):
        base = line.split(':', 1)[1].strip()
    elif line.startswith('SLUG:'):
        slug = re.sub(r'[^a-z0-9-]', '', line.split(':', 1)[1].strip().lower().replace(' ', '-'))
    elif line.startswith('SUMMARY:'):
        summary = line.split(':', 1)[1].strip()[:80]

# Validate prefix
valid_prefixes = {'feature','fix','refactor','hotfix','spike','test','chore','bugfix','migration','release'}
if prefix not in valid_prefixes:
    prefix = ''

# TICKET_* fields come EXCLUSIVELY from curl data (api_* vars)
title = api_title[:200]
status = api_status[:50]
description = api_description[:500]

# Convert ACS from unit-separator-delimited to checklist format
acs = ''
if api_acs_raw:
    items = [a.strip() for a in api_acs_raw.split(chr(0x1f)) if a.strip()]
    if items:
        acs = '\\\\n'.join('- [ ] ' + a for a in items)

def safe(s):
    return s.replace(chr(39), chr(0x2019)).replace(chr(36), '').replace(chr(96), '').replace('\n', '\\\\n').replace('\r', '')

out = (
    f\"SUGGEST_PREFIX='{safe(prefix)}'; \"
    f\"SUGGEST_BASE='{safe(base)}'; \"
    f\"SUGGEST_BRANCH_NAME='{safe(slug)}'; \"
    f\"SUGGEST_SUMMARY='{safe(summary)}'; \"
    f\"TICKET_TITLE='{safe(title)}'; \"
    f\"TICKET_STATUS='{safe(status)}'; \"
    f\"TICKET_DESCRIPTION='{safe(description)}'; \"
    f\"TICKET_ACS='{safe(acs)}';\"
)

# Whitelist validation — defense-in-depth
safe_pattern = r\"^([A-Z_]+='[^']*';\s*)+$\"
if not re.match(safe_pattern, out.strip() + ' '):
    print(sys.argv[6])
    sys.exit(0)

print(out)
" "$_API_TITLE" "$_API_STATUS" "$_API_DESCRIPTION" "$_API_ACS" "$ai_output" "$empty_defaults" 2>/dev/null)

        if [[ -n "$parsed" ]]; then
            echo "$parsed"
        else
            echo "$empty_defaults"
        fi
        return 0
    fi

    # Full MCP fallback — curl failed or api function not available
    if ! has_claude; then
        wtx_log WARN "claude CLI not available — jira_analyze_ticket returning empty defaults"
        echo "$empty_defaults"
        return 0
    fi
    wtx_log INFO "using MCP fallback for $ticket_id (model=$WORKTREE_AI_MODEL timeout=${WORKTREE_JIRA_TIMEOUT:-45}s)"
    local raw_output
    raw_output=$(run_with_timeout "${WORKTREE_JIRA_TIMEOUT:-45}" \
        claude -p "Get Jira issue $ticket_id. Analyze it and return EXACTLY this format (no other text, one field per line):
PREFIX: <one of: feature, fix, refactor, hotfix, spike, test, chore — based on issue type: Bug→fix, Story/Task→feature, Spike→spike, Sub-task→feature, Technical Debt→refactor>
BASE: <suggest base branch: if fixVersion contains a version like 7.13.0 check if release/7.13.0 exists as a common pattern, otherwise develop. Just output the branch name.>
SLUG: <ticket summary converted to lowercase kebab-case slug, max 5 words, e.g. user-login-screen>
SUMMARY: <ticket title, first 80 chars>
TITLE: <exact issue title>
STATUS: <issue status, e.g. To Do, In Progress, Done>
DESCRIPTION: <first 500 characters of description, no markdown formatting>
ACS: <acceptance criteria as checklist lines separated by | character, e.g. 'AC1|AC2|AC3'. If no ACs found, return NONE>" \
        --model "$WORKTREE_AI_MODEL" \
        --allowedTools "mcp__jira_confluence__jira_get_issue" \
        --output-format json 2>/dev/null)
    local rc=$?
    if [[ $rc -ne 0 ]] || [[ -z "$raw_output" ]]; then
        wtx_log ERROR "MCP analyze rc=$rc output_len=${#raw_output} ticket=$ticket_id"
        echo "$empty_defaults"
        return 0
    fi
    # Parse JSON and extract all 8 structured fields into a single eval-safe line
    local parsed
    parsed=$(echo "$raw_output" | python3 -c "
import sys, json, re

EMPTY = \"SUGGEST_PREFIX=''; SUGGEST_BASE=''; SUGGEST_BRANCH_NAME=''; SUGGEST_SUMMARY=''; TICKET_TITLE=''; TICKET_STATUS=''; TICKET_DESCRIPTION=''; TICKET_ACS=''\"

try:
    raw = sys.stdin.read()
    d = json.loads(raw, strict=False)
    text = d.get('result', '')
    prefix = ''; base = ''; slug = ''; summary = ''
    title = ''; status = ''; description = ''; acs_raw = ''
    for line in text.strip().split('\n'):
        line = line.strip()
        if line.startswith('PREFIX:'):
            prefix = line.split(':', 1)[1].strip().lower().rstrip('/')
        elif line.startswith('BASE:'):
            base = line.split(':', 1)[1].strip()
        elif line.startswith('SLUG:'):
            slug = re.sub(r'[^a-z0-9-]', '', line.split(':', 1)[1].strip().lower().replace(' ', '-'))
        elif line.startswith('SUMMARY:'):
            summary = line.split(':', 1)[1].strip()[:80]
        elif line.startswith('TITLE:'):
            title = line.split(':', 1)[1].strip()[:200]
        elif line.startswith('STATUS:'):
            status = line.split(':', 1)[1].strip()[:50]
        elif line.startswith('DESCRIPTION:'):
            description = line.split(':', 1)[1].strip()[:500]
        elif line.startswith('ACS:'):
            acs_raw = line.split(':', 1)[1].strip()
    # Validate prefix
    valid_prefixes = {'feature','fix','refactor','hotfix','spike','test','chore','bugfix','migration','release'}
    if prefix not in valid_prefixes:
        prefix = ''
    # Format ACs as checklist with literal \\n separators
    acs = ''
    if acs_raw and acs_raw.upper() != 'NONE':
        items = [a.strip() for a in acs_raw.split('|') if a.strip()]
        acs = '\\\\n'.join('- [ ] ' + a for a in items)
    # Sanitize all values: replace single quotes with right single quotation mark (U+2019)
    # and encode newlines as literal \\n to keep output on one line
    def safe(s):
        return s.replace(chr(39), chr(0x2019)).replace(chr(36), '').replace(chr(96), '').replace('\\n', '\\\\n').replace('\\r', '')
    # Assemble output
    out = (
        f\"SUGGEST_PREFIX='{safe(prefix)}'; \"
        f\"SUGGEST_BASE='{safe(base)}'; \"
        f\"SUGGEST_BRANCH_NAME='{safe(slug)}'; \"
        f\"SUGGEST_SUMMARY='{safe(summary)}'; \"
        f\"TICKET_TITLE='{safe(title)}'; \"
        f\"TICKET_STATUS='{safe(status)}'; \"
        f\"TICKET_DESCRIPTION='{safe(description)}'; \"
        f\"TICKET_ACS='{safe(acs)}';\"
    )
    # Whitelist validation — defense-in-depth
    safe_pattern = r\"^([A-Z_]+='[^']*';\\s*)+$\"
    if not re.match(safe_pattern, out.strip() + ' '):
        print(EMPTY)
        sys.exit(0)
    print(out)
except Exception:
    print(EMPTY)
" 2>/dev/null)
    if [[ -n "$parsed" ]]; then
        echo "$parsed"
    else
        echo "$empty_defaults"
    fi
}

# DEPRECATED: Use jira_analyze_ticket() instead.
# Wrapper maintained for backward compatibility.
# Usage: eval "$(jira_suggest_branch "PROJ-1234" "my-repo")"
# Sets: SUGGEST_PREFIX, SUGGEST_BASE, SUGGEST_BRANCH_NAME, SUGGEST_SUMMARY
jira_suggest_branch() {
    local ticket_id="$1"
    local project_name="$2"
    # Call jira_analyze_ticket and filter to only SUGGEST_* vars
    local full_result
    full_result=$(jira_analyze_ticket "$ticket_id" "$project_name")
    if [[ -z "$full_result" ]]; then
        echo "SUGGEST_PREFIX=''; SUGGEST_BASE=''; SUGGEST_BRANCH_NAME=''; SUGGEST_SUMMARY=''"
        return 0
    fi
    # Strip TICKET_* vars, keep only SUGGEST_* vars (regex-aware, handles ; inside values)
    echo "$full_result" | python3 -c "
import sys, re
line = sys.stdin.read().strip()
# Match each VAR='value'; assignment individually
matches = re.findall(r\"(SUGGEST_[A-Z_]+='[^']*';)\", line)
print(' '.join(matches) if matches else \"SUGGEST_PREFIX=''; SUGGEST_BASE=''; SUGGEST_BRANCH_NAME=''; SUGGEST_SUMMARY=''\")
" 2>/dev/null || echo "SUGGEST_PREFIX=''; SUGGEST_BASE=''; SUGGEST_BRANCH_NAME=''; SUGGEST_SUMMARY=''"
}

# Map repo name to Jira project key
# Usage: JIRA_KEY=$(jira_project_for_repo "my-repo")
# Returns: project key (e.g., "PROJ") or empty string
# F5: Uses WORKSPACE_ROOT (set by caller), no $0-relative path
jira_project_for_repo() {
    local repo_name="$1"
    [[ -n "$repo_name" ]] || { echo ""; return 0; }
    if command -v wtx_config_get >/dev/null 2>&1; then
        wtx_config_get "jira.projects.$repo_name"
    else
        echo ""
    fi
}

# DEPRECATED: Use jira_analyze_ticket() instead.
# Wrapper maintained for backward compatibility.
# Usage: CONTEXT=$(jira_fetch_ticket_context "PROJ-1234")
# Returns: pre-formatted markdown ready to append, or empty on failure
jira_fetch_ticket_context() {
    local ticket_id="$1"
    if [[ -z "$ticket_id" ]]; then
        return 0
    fi
    # Call jira_analyze_ticket with placeholder project name (SUGGEST_* fields are ignored)
    local full_result
    full_result=$(jira_analyze_ticket "$ticket_id" "_compat")
    if [[ -z "$full_result" ]]; then
        return 0
    fi
    # Validate using shared whitelist function
    if ! _jira_validate_eval "$full_result"; then
        return 0
    fi
    local SUGGEST_PREFIX="" SUGGEST_BASE="" SUGGEST_BRANCH_NAME="" SUGGEST_SUMMARY=""
    local TICKET_TITLE="" TICKET_STATUS="" TICKET_DESCRIPTION="" TICKET_ACS=""
    eval "$full_result"
    if [[ -z "$TICKET_TITLE" ]]; then
        return 0
    fi
    # Format as markdown (matches original output format)
    echo "## Ticket Details"
    echo "**Title:** $TICKET_TITLE"
    echo "**Status:** $TICKET_STATUS"
    echo "**Description:** $TICKET_DESCRIPTION"
    if [[ -n "$TICKET_ACS" ]]; then
        echo ""
        echo "## Acceptance Criteria"
        # Use echo not printf %b to avoid interpreting escape sequences
        echo "$TICKET_ACS"
    fi
}

# Check for existing worktrees and open PRs for a ticket
# Usage: DUPES=$(check_duplicate_work "PROJ-1234" "/path/to/project")
# Returns: multi-line "WORKTREE: <path>" and/or "PR: <title> (<url>)" lines, or empty
check_duplicate_work() {
    local ticket_id="$1"
    local project_dir="$2"
    if [[ -z "$ticket_id" ]] || [[ -z "$project_dir" ]]; then
        return 0
    fi
    local output=""
    # Check 1 — local worktrees (pure git, no AI)
    local wt_matches
    wt_matches=$(git -C "$project_dir" worktree list 2>/dev/null | grep -F -- "$ticket_id")
    if [[ -n "$wt_matches" ]]; then
        while IFS= read -r line; do
            local wt_path
            wt_path=$(echo "$line" | awk '{print $1}')
            output="${output}WORKTREE: ${wt_path}"$'\n'
        done <<< "$wt_matches"
    fi

    # Check 2 — open PRs: try curl first, then MCP fallback
    local repo_name
    repo_name="$(basename "$project_dir")"
    local pr_lines=""

    if type -t api_bb_check_open_prs >/dev/null 2>&1; then
        pr_lines=$(api_bb_check_open_prs "$repo_name" "$ticket_id" 2>/dev/null)
        # If curl succeeded (rc=0), use result even if empty (no PRs found)
        if [[ $? -eq 0 ]]; then
            if [[ -n "$pr_lines" ]]; then
                output="${output}${pr_lines}"$'\n'
            fi
            # Trim trailing newline
            output=$(echo "$output" | sed '/^$/d')
            echo "$output"
            return 0
        fi
    fi

    # MCP fallback for PR check
    if has_claude; then
        local raw_output
        raw_output=$(run_with_timeout "${WORKTREE_JIRA_TIMEOUT:-15}" \
            claude -p "Search Bitbucket for open pull requests in repository $BITBUCKET_ORG/$repo_name where the source branch contains '$ticket_id'.
Use: mcp__bitbucket__bb_get with path '/repositories/$BITBUCKET_ORG/$repo_name/pullrequests', queryParams {'state': 'OPEN', 'q': 'source.branch.name ~ \"$ticket_id\"'}, jq 'values[*].{title: title, url: links.html.href, branch: source.branch.name}'.
Return ONLY lines in format: PR: <title> (<url>). No markdown, no headers." \
            --model "$WORKTREE_AI_MODEL" \
            --allowedTools "mcp__bitbucket__bb_get" \
            --output-format json 2>/dev/null)
        local rc=$?
        if [[ $rc -eq 0 ]] && [[ -n "$raw_output" ]]; then
            local parsed
            parsed=$(echo "$raw_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read(), strict=False)
    print(d.get('result', ''))
except (json.JSONDecodeError, KeyError, ValueError):
    sys.exit(1)
" 2>/dev/null)
            if [[ -n "$parsed" ]]; then
                local mcp_pr_lines
                mcp_pr_lines=$(echo "$parsed" | grep '^PR: ')
                if [[ -n "$mcp_pr_lines" ]]; then
                    output="${output}${mcp_pr_lines}"$'\n'
                fi
            fi
        fi
    fi
    # Trim trailing newline
    output=$(echo "$output" | sed '/^$/d')
    echo "$output"
}

# Check if a PR already exists for a specific branch
# Usage: PR_INFO=$(check_existing_pr "feature/PROJ-1234" "my-repo")
# Returns: "PR_TITLE: <title>\tPR_URL: <url>\tPR_STATE: <state>" or empty
check_existing_pr() {
    local branch="$1"
    local repo_name="$2"
    if [[ -z "$branch" ]] || [[ -z "$repo_name" ]]; then
        return 0
    fi

    # Try curl-first approach
    if type -t api_bb_find_pr >/dev/null 2>&1; then
        local api_result
        api_result=$(api_bb_find_pr "$repo_name" "$branch" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            # api_bb_find_pr returns empty on no match (rc=0), or tab-delimited PR info
            if [[ -n "$api_result" ]]; then
                echo "$api_result"
            fi
            return 0
        fi
    fi

    # MCP fallback
    if ! has_claude; then
        return 0
    fi
    local raw_output
    raw_output=$(run_with_timeout "${WORKTREE_JIRA_TIMEOUT:-15}" \
        claude -p "Search Bitbucket for pull requests in repository $BITBUCKET_ORG/$repo_name where the source branch is exactly '$branch' and state is OPEN or MERGED.
Use: mcp__bitbucket__bb_get with path '/repositories/$BITBUCKET_ORG/$repo_name/pullrequests', queryParams {'q': 'source.branch.name = \"$branch\"'}, jq 'values[0].{title: title, url: links.html.href, state: state}'.
If found, return EXACTLY (fields separated by TAB character): PR_TITLE: <title>\tPR_URL: <url>\tPR_STATE: <state>
If not found, return EXACTLY: NONE" \
        --model "$WORKTREE_AI_MODEL" \
        --allowedTools "mcp__bitbucket__bb_get" \
        --output-format json 2>/dev/null)
    local rc=$?
    if [[ $rc -ne 0 ]] || [[ -z "$raw_output" ]]; then
        return 0
    fi
    local parsed
    parsed=$(echo "$raw_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read(), strict=False)
    print(d.get('result', ''))
except (json.JSONDecodeError, KeyError, ValueError):
    sys.exit(1)
" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$parsed" ]]; then
        return 0
    fi
    if [[ "$parsed" == "NONE" ]] || [[ -z "$parsed" ]]; then
        return 0
    fi
    echo "$parsed"
}

# Advisory AC completion check — analyzes diff stats against acceptance criteria
# Usage: RESULT=$(check_ac_completion "/path/to/worktree" "develop" "feature/PROJ-1234")
# Returns: unaddressed ACs (prefixed "- [ ]"), "NONE" if all addressed, or empty on failure
# NOTE: This function is pure reasoning — already optimal, not migrated to curl.
check_ac_completion() {
    local worktree_path="$1"
    local base_branch="$2"
    local branch="$3"
    if [[ -z "$worktree_path" ]] || [[ -z "$base_branch" ]] || [[ -z "$branch" ]]; then
        return 0
    fi
    local context_file="$worktree_path/WORKTREE_CONTEXT.md"
    if [[ ! -f "$context_file" ]]; then
        return 0
    fi
    local acs
    # Only extract lines matching AC format to prevent injection via crafted context files
    acs=$(grep '^- \[ \]' "$context_file" 2>/dev/null | head -30)
    if [[ -z "$acs" ]]; then
        return 0
    fi
    local diff_stat
    diff_stat=$(git -C "$worktree_path" diff --stat "$base_branch..$branch" 2>/dev/null | head -50)
    if [[ -z "$diff_stat" ]]; then
        return 0
    fi
    if ! has_claude; then
        return 0
    fi
    # Use --strict-mcp-config --mcp-config '{"mcpServers":{}}' to skip loading all MCP servers.
    # This is a pure reasoning task — no MCP tools needed. Saves ~15-20s startup.
    local raw_output
    raw_output=$(run_with_timeout "${WORKTREE_JIRA_TIMEOUT:-20}" \
        env $CLAUDE_FAST_ENV \
        claude -p "Given these acceptance criteria:
$acs

And these code changes (diff stat):
$diff_stat

Analyze which acceptance criteria appear to NOT be addressed by the code changes.
Consider file names, change patterns, and scope of modifications.
Return ONLY the potentially unaddressed ACs, one per line prefixed with '- [ ]'.
If ALL acceptance criteria appear to be addressed, return the single word NONE.
Be conservative — when in doubt, mark as potentially unaddressed." \
        --model "$WORKTREE_AI_MODEL" \
        --no-session-persistence --max-turns 1 \
        --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
        --output-format json 2>/dev/null)
    local rc=$?
    if [[ $rc -ne 0 ]] || [[ -z "$raw_output" ]]; then
        return 0
    fi
    local parsed
    parsed=$(echo "$raw_output" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read(), strict=False)
    print(d.get('result', ''))
except (json.JSONDecodeError, KeyError, ValueError):
    sys.exit(1)
" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$parsed" ]]; then
        return 0
    fi
    echo "$parsed"
}
