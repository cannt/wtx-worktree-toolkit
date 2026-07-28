#!/bin/bash
# Worktree API Library
# Direct curl + python3 API calls for Jira and Bitbucket, replacing claude -p for data fetching.
#
# Usage: source "$SCRIPT_DIR/lib/worktree-api.sh"
#
# Prerequisites: WORKSPACE_ROOT must be set by the caller.
# Credentials are read from $WORKSPACE_ROOT/.mcp.json (same file MCP servers use).
# All api_* functions return 1 on failure, enabling MCP fallback in worktree-jira.sh.

# Load wtx config loader (same directory); safe if missing.
_wtx_api_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_wtx_api_self_dir/wtx-config.sh" 2>/dev/null || true

# Logging stub — real implementation provided when worktree-tui.sh is sourced first.
type -t wtx_log >/dev/null 2>&1 || wtx_log() { :; }

# Bitbucket organization slug — from config or env override, empty if unset.
if command -v wtx_config_get >/dev/null 2>&1; then
    BITBUCKET_ORG="${BITBUCKET_ORG:-$(wtx_config_get "forge.org")}"
else
    BITBUCKET_ORG="${BITBUCKET_ORG:-}"
fi

# Credential cache
_API_CREDS_LOADED=""
JIRA_API_URL=""
JIRA_API_USER=""
JIRA_API_TOKEN=""
BB_API_USER=""
BB_API_TOKEN=""

# Load API credentials (lazy, cached).
# Sources, highest precedence first: process environment, $WTX_ENV_FILE or
# $WORKSPACE_ROOT/.env, then any server's `env` block in $WORKSPACE_ROOT/.mcp.json.
# The .mcp.json scan is server-name agnostic on purpose: MCP servers get renamed
# and swapped for OAuth ones, and hardcoding a server key silently kills the
# curl path when that happens.
# Jira and Bitbucket are independent — missing Bitbucket creds must not disable Jira.
# Returns 0 when Jira creds are complete, 1 otherwise.
_load_api_credentials() {
    if [[ "$_API_CREDS_LOADED" == "1" ]]; then
        return 0
    fi

    local mcp_file="${WORKSPACE_ROOT:-.}/.mcp.json"
    local env_file="${WTX_ENV_FILE:-${WORKSPACE_ROOT:-.}/.env}"
    local config_url=""
    if command -v wtx_config_get >/dev/null 2>&1; then
        config_url="$(wtx_config_get "jira.url")"
    fi

    local creds
    creds=$(python3 - "$mcp_file" "$env_file" "$config_url" 2>/dev/null << 'PYEOF'
import json, sys, re, os

mcp_file, env_file, config_url = (sys.argv + ['', '', ''])[1:4]

# Layer the sources into one dict: .mcp.json (lowest) < .env < process env.
values = {}

def load_dotenv(path):
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                k, _, v = line.partition('=')
                k = k.strip()
                if k.startswith('export '):
                    k = k[len('export '):].strip()
                values[k] = v.strip().strip("'\"")
    except OSError:
        pass

def load_mcp(path):
    try:
        with open(path) as f:
            d = json.load(f)
    except (OSError, json.JSONDecodeError, ValueError):
        return
    # Scan every server's env block, not one hardcoded server name.
    for cfg in d.get('mcpServers', {}).values():
        if not isinstance(cfg, dict):
            continue
        for k, v in (cfg.get('env') or {}).items():
            if isinstance(v, str) and k not in values:
                values[k] = v

load_mcp(mcp_file)
load_dotenv(env_file)
values.update(os.environ)

def expand(val):
    # Expand ${VAR:-default}, ${VAR} and $VAR references stored literally in JSON.
    if not val:
        return ''
    val = re.sub(r'\$\{([^}:]+):-([^}]*)\}',
                 lambda m: values.get(m.group(1)) or m.group(2) or '', val)
    val = re.sub(r'\$\{([^}]+)\}', lambda m: values.get(m.group(1), ''), val)
    val = re.sub(r'\$([A-Za-z_][A-Za-z0-9_]*)', lambda m: values.get(m.group(1), ''), val)
    return val.strip()

def pick(*names):
    for n in names:
        v = expand(values.get(n, ''))
        if v:
            return v
    return ''

url      = pick('JIRA_URL', 'ATLASSIAN_URL', 'ATLASSIAN_SITE_URL', 'CONFLUENCE_URL') or config_url
user     = pick('JIRA_USERNAME', 'JIRA_EMAIL', 'ATLASSIAN_USER_EMAIL')
token    = pick('JIRA_API_TOKEN', 'ATLASSIAN_API_TOKEN')
bb_user  = pick('BITBUCKET_USERNAME', 'ATLASSIAN_USER_EMAIL', 'JIRA_USERNAME')
bb_token = pick('BITBUCKET_API_TOKEN', 'ATLASSIAN_API_TOKEN', 'JIRA_API_TOKEN')

# Jira is the gate; Bitbucket values are optional and may print empty.
if not (url and user and token):
    missing = [n for n, v in (('url', url), ('user', user), ('token', token)) if not v]
    sys.stderr.write('missing:' + ','.join(missing) + '\n')
    sys.exit(1)

print(url.rstrip('/')); print(user); print(token); print(bb_user); print(bb_token)
PYEOF
    )

    if [[ $? -ne 0 ]] || [[ -z "$creds" ]]; then
        wtx_log ERROR "no Jira credentials found — looked in env, $env_file, $mcp_file (need JIRA_URL + JIRA_USERNAME + JIRA_API_TOKEN)"
        return 1
    fi

    # Read 5 lines into variables (last two may be empty — Bitbucket is optional)
    {
        IFS= read -r JIRA_API_URL
        IFS= read -r JIRA_API_USER
        IFS= read -r JIRA_API_TOKEN
        IFS= read -r BB_API_USER
        IFS= read -r BB_API_TOKEN
    } <<< "$creds"

    _API_CREDS_LOADED="1"
    wtx_log INFO "credentials loaded (JIRA_URL=$JIRA_API_URL user=$JIRA_API_USER bitbucket=$([[ -n "$BB_API_TOKEN" ]] && echo yes || echo no))"
    return 0
}

# Convenience: check if Jira credentials are available
has_api_credentials() {
    _load_api_credentials
}

# Convenience: check if Bitbucket credentials are available
has_bitbucket_credentials() {
    _load_api_credentials || return 1
    [[ -n "$BB_API_USER" ]] && [[ -n "$BB_API_TOKEN" ]]
}

# Jira search via REST API v3
# Usage: RESULT=$(api_jira_search "jql query" max_results "key,summary,status")
# Returns raw JSON body on success, returns 1 on failure
api_jira_search() {
    local jql="$1"
    local max_results="${2:-10}"
    local fields="${3:-key,summary,status}"

    _load_api_credentials || return 1

    # Build JSON body with proper escaping via python3
    local body
    body=$(python3 -c "
import json, sys
jql = sys.argv[1]
max_r = int(sys.argv[2])
fields = sys.argv[3].split(',')
print(json.dumps({'jql': jql, 'maxResults': max_r, 'fields': [f.strip() for f in fields]}))
" "$jql" "$max_results" "$fields" 2>/dev/null) || return 1

    local response
    response=$(curl -s --connect-timeout 5 --max-time 15 \
        -u "$JIRA_API_USER:$JIRA_API_TOKEN" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$body" \
        -w '---HTTP_CODE---%{http_code}' \
        "$JIRA_API_URL/rest/api/3/search/jql" 2>/dev/null) || return 1

    # Split response using unique delimiter (avoids trailing newline issues)
    local http_code
    http_code="${response##*---HTTP_CODE---}"
    local json_body
    json_body="${response%---HTTP_CODE---*}"

    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        wtx_log ERROR "Jira search HTTP $http_code url=$JIRA_API_URL user=$JIRA_API_USER — JQL: ${jql:0:120}"
        return 1
    fi

    echo "$json_body"
}

# Fetch a single Jira issue
# Usage: RESULT=$(api_jira_get_issue "PROJ-1234" "summary,status,description")
# Returns raw JSON body on success, returns 1 on failure
api_jira_get_issue() {
    local ticket_id="$1"
    local fields="${2:-summary,status}"

    # Validate ticket_id format to prevent path traversal
    if [[ -z "$ticket_id" ]] || [[ ! "$ticket_id" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
        return 1
    fi
    # Validate fields to prevent URL parameter injection
    if [[ ! "$fields" =~ ^[a-zA-Z,]+$ ]]; then
        return 1
    fi

    _load_api_credentials || return 1

    local response
    response=$(curl -s --connect-timeout 5 --max-time 15 \
        -u "$JIRA_API_USER:$JIRA_API_TOKEN" \
        -H "Content-Type: application/json" \
        -w '---HTTP_CODE---%{http_code}' \
        "$JIRA_API_URL/rest/api/3/issue/${ticket_id}?fields=${fields}" 2>/dev/null) || return 1

    local http_code
    http_code="${response##*---HTTP_CODE---}"
    local json_body
    json_body="${response%---HTTP_CODE---*}"

    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        wtx_log ERROR "Jira get-issue HTTP $http_code — ticket=$ticket_id"
        return 1
    fi

    echo "$json_body"
}

# Fetch current user's tickets formatted for display
# Usage: TICKETS=$(api_jira_my_tickets "PROJ")
# Returns: newline-separated "★ KEY | Title | Status" (assigned) / "KEY | Title | Status" (unassigned)
api_jira_my_tickets() {
    local project_key="$1"
    if [[ -z "$project_key" ]]; then
        return 1
    fi
    # Validate project key
    if [[ ! "$project_key" =~ ^[A-Z][A-Z0-9_]+$ ]]; then
        return 1
    fi

    _load_api_credentials || return 1

    # Search 1: assigned to current user
    local assigned_json
    assigned_json=$(api_jira_search \
        "project = $project_key AND assignee = currentUser() AND status != Done ORDER BY updated DESC" \
        "10" \
        "key,summary,status") || assigned_json=""

    # Search 2: unassigned frontend tickets
    local unassigned_json
    unassigned_json=$(api_jira_search \
        "project = $project_key AND labels = frontend AND status != Done AND assignee is EMPTY ORDER BY updated DESC" \
        "15" \
        "key,summary,status") || unassigned_json=""

    if [[ -z "$assigned_json" ]] && [[ -z "$unassigned_json" ]]; then
        return 1
    fi

    # Parse and format both results
    local result
    result=$(python3 -c "
import json, sys

assigned_raw = sys.argv[1] if len(sys.argv) > 1 else ''
unassigned_raw = sys.argv[2] if len(sys.argv) > 2 else ''

seen = set()
lines = []

def parse_issues(raw, starred):
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return []
    result = []
    for issue in data.get('issues', []):
        key = issue.get('key', '')
        if not key or key in seen:
            continue
        seen.add(key)
        fields = issue.get('fields', {})
        summary = fields.get('summary', '')
        status_obj = fields.get('status', {})
        status = status_obj.get('name', '') if isinstance(status_obj, dict) else ''
        prefix = '★ ' if starred else ''
        result.append(f'{prefix}{key} | {summary} | {status}')
    return result

lines.extend(parse_issues(assigned_raw, True))
lines.extend(parse_issues(unassigned_raw, False))

if lines:
    print('\n'.join(lines))
else:
    sys.exit(1)
" "$assigned_json" "$unassigned_json" 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$result" ]]; then
        return 1
    fi

    echo "$result"
}

# Fetch ticket details with ADF parsing
# Usage: RESULT=$(api_jira_ticket_details "PROJ-1234")
# Returns eval-safe line with _API_* prefix variables (intermediate format)
# Callers MUST declare local vars before eval: local _API_TITLE="" _API_STATUS="" ...
api_jira_ticket_details() {
    local ticket_id="$1"
    if [[ -z "$ticket_id" ]]; then
        return 1
    fi

    _load_api_credentials || return 1

    local raw_json
    raw_json=$(api_jira_get_issue "$ticket_id" "summary,status,description,issuetype,fixVersions,assignee,labels") || return 1

    local result
    result=$(python3 -c "
import json, sys, re

raw = sys.argv[1]

def extract_adf_text(node):
    if not node or not isinstance(node, dict):
        return ''
    texts = []
    if node.get('type') == 'text':
        texts.append(node.get('text', ''))
    for child in node.get('content', []):
        texts.append(extract_adf_text(child))
    return ' '.join(t for t in texts if t)

def flatten_content(doc):
    nodes = []
    for node in doc.get('content', []):
        if node.get('type') in ('panel', 'expand', 'layoutSection', 'layoutColumn'):
            nodes.extend(flatten_content(node))
        else:
            nodes.append(node)
    return nodes

def extract_acs(doc):
    acs = []
    collecting = False
    for node in flatten_content(doc):
        if node.get('type') == 'heading':
            heading_text = extract_adf_text(node).lower()
            if 'acceptance criteria' in heading_text or 'criterios de aceptación' in heading_text or 'criterios de aceptacion' in heading_text:
                collecting = True
                continue
            elif collecting:
                break
        if collecting and node.get('type') in ('bulletList', 'orderedList'):
            for item in node.get('content', []):
                if item.get('type') == 'listItem':
                    acs.append(extract_adf_text(item).strip())
    return acs

def safe(s):
    return s.replace(chr(39), chr(0x2019)).replace(chr(36), '').replace(chr(96), '').replace('\n', '\\\\n').replace('\r', '')

try:
    data = json.loads(raw)
    fields = data.get('fields', {})

    title = fields.get('summary', '')[:200]
    status_obj = fields.get('status', {})
    status = status_obj.get('name', '') if isinstance(status_obj, dict) else ''
    status = status[:50]

    desc_doc = fields.get('description')
    description = ''
    if desc_doc and isinstance(desc_doc, dict):
        description = extract_adf_text(desc_doc)[:500]

    issue_type_obj = fields.get('issuetype', {})
    issue_type = issue_type_obj.get('name', '') if isinstance(issue_type_obj, dict) else ''

    fix_versions_list = fields.get('fixVersions', [])
    fix_versions = ', '.join(v.get('name', '') for v in fix_versions_list if isinstance(v, dict))

    acs = []
    if desc_doc and isinstance(desc_doc, dict):
        acs = extract_acs(desc_doc)

    # Use ASCII unit separator (0x1F) as AC delimiter
    acs_str = chr(0x1f).join(acs) if acs else ''

    out = (
        f\"_API_TITLE='{safe(title)}'; \"
        f\"_API_STATUS='{safe(status)}'; \"
        f\"_API_DESCRIPTION='{safe(description)}'; \"
        f\"_API_ISSUE_TYPE='{safe(issue_type)}'; \"
        f\"_API_FIX_VERSIONS='{safe(fix_versions)}'; \"
        f\"_API_ACS='{safe(acs_str)}';\"
    )

    # Whitelist validation
    safe_pattern = r\"^([A-Z_]+='[^']*';\s*)+$\"
    if not re.match(safe_pattern, out.strip() + ' '):
        sys.exit(1)

    print(out)
except Exception:
    sys.exit(1)
" "$raw_json" 2>/dev/null)

    if [[ $? -ne 0 ]] || [[ -z "$result" ]]; then
        return 1
    fi

    echo "$result"
}

# Search Bitbucket for PRs matching a branch or ticket
# Usage: RESULT=$(api_bb_find_pr "my-repo" "feature/PROJ-1234")
# Returns: "PR_TITLE: ...\tPR_URL: ...\tPR_STATE: ..." or empty if no match
# Checks both OPEN and MERGED states
api_bb_find_pr() {
    local repo_name="$1"
    local branch_or_ticket="$2"
    if [[ -z "$repo_name" ]] || [[ -z "$branch_or_ticket" ]]; then
        return 1
    fi
    # Validate repo_name to prevent URL path corruption
    if [[ ! "$repo_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        return 1
    fi

    has_bitbucket_credentials || return 1

    local query="source.branch.name ~ \"${branch_or_ticket}\""

    # Check OPEN first, then MERGED
    local state
    for state in OPEN MERGED; do
        local encoded_q
        encoded_q=$(python3 -c "
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
" "$query" 2>/dev/null) || continue

        local response
        response=$(curl -s --connect-timeout 5 --max-time 15 \
            -u "$BB_API_USER:$BB_API_TOKEN" \
            -w '---HTTP_CODE---%{http_code}' \
            "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_ORG/${repo_name}/pullrequests?q=${encoded_q}&state=${state}" 2>/dev/null) || continue

        local http_code
        http_code="${response##*---HTTP_CODE---}"
        local json_body
        json_body="${response%---HTTP_CODE---*}"

        if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            continue
        fi

        local pr_info
        pr_info=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    values = data.get('values', [])
    if not values:
        sys.exit(0)
    pr = values[0]
    title = pr.get('title', '')
    url = pr.get('links', {}).get('html', {}).get('href', '')
    state = pr.get('state', '')
    if title and url:
        print(f'PR_TITLE: {title}\tPR_URL: {url}\tPR_STATE: {state}')
except Exception:
    sys.exit(1)
" "$json_body" 2>/dev/null)

        if [[ -n "$pr_info" ]]; then
            echo "$pr_info"
            return 0
        fi
    done

    # No PR found — return empty (success, not failure)
    return 0
}

# Check for open PRs for duplicate detection
# Usage: RESULT=$(api_bb_check_open_prs "my-repo" "PROJ-1234")
# Returns: lines of "PR: <title> (<url>)" or empty
api_bb_check_open_prs() {
    local repo_name="$1"
    local ticket_id="$2"
    if [[ -z "$repo_name" ]] || [[ -z "$ticket_id" ]]; then
        return 1
    fi
    # Validate repo_name to prevent URL path corruption
    if [[ ! "$repo_name" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        return 1
    fi

    has_bitbucket_credentials || return 1

    local query="source.branch.name ~ \"${ticket_id}\""
    local encoded_q
    encoded_q=$(python3 -c "
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1]))
" "$query" 2>/dev/null) || return 1

    local response
    response=$(curl -s --connect-timeout 5 --max-time 15 \
        -u "$BB_API_USER:$BB_API_TOKEN" \
        -w '---HTTP_CODE---%{http_code}' \
        "https://api.bitbucket.org/2.0/repositories/$BITBUCKET_ORG/${repo_name}/pullrequests?q=${encoded_q}&state=OPEN" 2>/dev/null) || return 1

    local http_code
    http_code="${response##*---HTTP_CODE---}"
    local json_body
    json_body="${response%---HTTP_CODE---*}"

    if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        return 1
    fi

    local pr_lines
    pr_lines=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    values = data.get('values', [])
    for pr in values:
        title = pr.get('title', '')
        url = pr.get('links', {}).get('html', {}).get('href', '')
        if title and url:
            print(f'PR: {title} ({url})')
except Exception:
    sys.exit(1)
" "$json_body" 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        return 1
    fi

    echo "$pr_lines"
    return 0
}
