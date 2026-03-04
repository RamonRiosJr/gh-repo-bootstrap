#!/usr/bin/env bash
# ==============================================================================
# setup_labels.sh — Creates enterprise label taxonomy
# Part of gh-repo-bootstrap | Version: 1.0.0
#
# SYNOPSIS
#   Configures professional issue and PR labels.
#
# DESCRIPTION
#   Deletes the 9 default GitHub labels (bug, enhancement, etc) and creates a
#   comprehensive 27-label taxonomy organized by Type, Priority, Epic, Status,
#   and Size with standardized hex colors.
#
# ENVIRONMENT VARIABLES
#   GITHUB_TOKEN  - PAT with 'repo' scope
#   GITHUB_OWNER  - GitHub username or organization name
#   REPO_NAME     - Target repository name
#
# NOTES
#   Idempotent: safely updates existing labels if names conflict.
#   See OPERATIONS_MANUAL.md for exhaustive operation instructions.
# ==============================================================================
set -euo pipefail

for dep in curl jq; do
  command -v "$dep" &>/dev/null || { echo "❌ '$dep' not found." >&2; exit 1; }
done

print_header() {
  echo ""; echo "═══════════════════════════════════════"
  echo "  03 — Labels"; echo "═══════════════════════════════════════"
}

gh_api() {
  local method="$1" uri="$2" body="${3:-}"
  local args=(-sf -X "$method"
    -H "Authorization: Bearer $GITHUB_TOKEN"
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28")
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" -d "$body")
  curl "${args[@]}" "https://api.github.com${uri}"
}

print_header
[[ -z "${GITHUB_TOKEN:-}" ]] && read -rsp "GitHub PAT: " GITHUB_TOKEN && echo
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp  "GitHub owner: " GITHUB_OWNER
[[ -z "${REPO_NAME:-}"    ]] && read -rp  "Repository name: " REPO_NAME

CREATED=0; SKIPPED=0; ERRORS=0

# Default labels to delete
DEFAULT_LABELS=("bug" "documentation" "duplicate" "enhancement" "good first issue" "help wanted" "invalid" "question" "wontfix")
echo "  → Removing default labels..."
for label in "${DEFAULT_LABELS[@]}"; do
  encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${label}', safe=''))" 2>/dev/null || printf '%s' "$label" | sed 's/ /%20/g; s/:/%3A/g')
  curl -s -o /dev/null -X DELETE \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}/labels/${encoded}" || true
done

# Professional label taxonomy: "name|color|description"
LABELS=(
  "type: bug|b60205|Something is not working correctly"
  "type: feature|0075ca|New functionality or enhancement"
  "type: chore|cfd3d7|Maintenance, cleanup, refactoring"
  "type: compliance|6f42c1|Regulatory requirements, audits"
  "type: security|8b0000|Security vulnerabilities or hardening"
  "type: docs|0e8a16|Documentation updates"
  "P0: critical|b60205|Outage / blocker — DROP EVERYTHING"
  "P1: high|e4e669|Must ship this sprint"
  "P2: medium|0075ca|Target next sprint"
  "P3: low|cfd3d7|Nice to have / future consideration"
  "epic: compliance|6f42c1|Compliance and regulatory track"
  "epic: security|8b0000|Security hardening track"
  "epic: infrastructure|495057|DevOps, CI/CD, platform track"
  "epic: ui/ux|e83e8c|Frontend, design system track"
  "epic: ai/ml|17a2b8|AI/ML integration track"
  "epic: integrations|28a745|Third-party integration track"
  "status: in-progress|0052cc|Actively being worked on"
  "status: blocked|ee0701|Cannot proceed — blocked"
  "status: needs-review|fbca04|Awaiting review or approval"
  "status: ready|0e8a16|Groomed and ready to pick up"
  "size: S|0e8a16|≤ 4 hours — trivial change"
  "size: M|0075ca|≤ 1 day — standard ticket"
  "size: L|fbca04|≤ 3 days — complex ticket"
  "size: XL|b60205|> 3 days — consider breaking down"
)

echo "  → Creating label taxonomy..."
# Fetch existing label names
EXISTING=$(gh_api GET "/repos/${GITHUB_OWNER}/${REPO_NAME}/labels?per_page=100" "" | jq -r '.[].name')

for entry in "${LABELS[@]}"; do
  IFS='|' read -r name color desc <<< "$entry"
  BODY=$(jq -n --arg n "$name" --arg c "$color" --arg d "$desc" \
    '{name:$n, color:$c, description:$d}')

  if echo "$EXISTING" | grep -qF "$name"; then
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${name}', safe=''))" 2>/dev/null || printf '%s' "$name" | sed 's/ /%20/g; s/:/%3A/g; s|/|%2F|g')
    gh_api PATCH "/repos/${GITHUB_OWNER}/${REPO_NAME}/labels/${encoded}" "$BODY" > /dev/null
    echo "    ⏭️  Updated: ${name}"; SKIPPED=$((SKIPPED+1))
  else
    gh_api POST "/repos/${GITHUB_OWNER}/${REPO_NAME}/labels" "$BODY" > /dev/null
    echo "    ✅ Created: ${name}"; CREATED=$((CREATED+1))
  fi
done

echo ""; echo "─── Summary ─────────────────────────────"
echo "  ✅ Created : ${CREATED}"
echo "  ⏭️  Skipped : ${SKIPPED}"
echo "  ❌ Errors  : ${ERRORS}"; echo ""
if [[ "$ERRORS" -gt 0 ]]; then exit 1; else exit 0; fi
