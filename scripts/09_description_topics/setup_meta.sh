#!/usr/bin/env bash
# ==============================================================================
# setup_meta.sh — Updates repo description, homepage, and topics
# Part of gh-repo-bootstrap | Version: 1.0.0
#
# SYNOPSIS
#   Configures repository metadata for better discoverability.
#
# DESCRIPTION
#   Updates the GitHub repository's description, homepage URL, and applies
#   topic tags (e.g., 'react, typescript, ui'). Topics are normalized to
#   kebab-case arrays before submission.
#
# ENVIRONMENT VARIABLES
#   GITHUB_TOKEN      - PAT with 'repo' scope
#   GITHUB_OWNER      - GitHub username or organization name
#   REPO_NAME         - Target repository name
#   REPO_DESCRIPTION  - Summary of the project
#   REPO_HOMEPAGE     - Production/docs URL (optional)
#   REPO_TOPICS       - Comma-separated list of tags (optional)
#
# NOTES
#   See OPERATIONS_MANUAL.md for instructions and troubleshooting.
# ==============================================================================
set -euo pipefail

for dep in curl jq; do
  command -v "$dep" &>/dev/null || { echo "❌ '$dep' not found." >&2; exit 1; }
done

print_header() {
  echo ""; echo "═══════════════════════════════════════"
  echo "  09 — Description & Topics"; echo "═══════════════════════════════════════"
}

print_header
[[ -z "${GITHUB_TOKEN:-}"     ]] && read -rsp "GitHub PAT: " GITHUB_TOKEN && echo
[[ -z "${GITHUB_OWNER:-}"     ]] && read -rp  "GitHub owner: " GITHUB_OWNER
[[ -z "${REPO_NAME:-}"        ]] && read -rp  "Repository name: " REPO_NAME
[[ -z "${REPO_DESCRIPTION:-}" ]] && read -rp  "Repository description: " REPO_DESCRIPTION
[[ -z "${REPO_HOMEPAGE:-}"    ]] && read -rp  "Homepage URL (Enter to skip): " REPO_HOMEPAGE || true
[[ -z "${REPO_TOPICS:-}"      ]] && read -rp  "Topics (comma-separated): " REPO_TOPICS || true

CREATED=0; SKIPPED=0; ERRORS=0

echo "  → Updating repository metadata..."
PATCH_BODY=$(jq -n \
  --arg d "$REPO_DESCRIPTION" \
  --arg h "${REPO_HOMEPAGE:-}" \
  'if $h != "" then {description:$d, homepage:$h} else {description:$d} end')

if curl -sf -X PATCH \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d "$PATCH_BODY" \
  "https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}" > /dev/null; then
  echo "  ✅ Description updated"
  CREATED=$((CREATED+1))
else
  echo "  ❌ Failed to update description"; ERRORS=$((ERRORS+1))
fi

if [[ -n "${REPO_TOPICS:-}" ]]; then
  # Normalize topics to lowercase kebab-case array
  TOPICS_JSON=$(echo "$REPO_TOPICS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | jq -Rsc 'split("\n") | map(select(. != ""))')
  TOPICS_BODY=$(jq -n --argjson names "$TOPICS_JSON" '{names: $names}')
  echo "  → Setting topics: ${REPO_TOPICS}..."
  if curl -sf -X PUT \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -d "$TOPICS_BODY" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}/topics" > /dev/null; then
    echo "  ✅ Topics set"; CREATED=$((CREATED+1))
  else
    echo "  ❌ Failed to set topics"; ERRORS=$((ERRORS+1))
  fi
else
  echo "  ⏭️  No topics provided. Skipping."; SKIPPED=$((SKIPPED+1))
fi

echo ""; echo "─── Summary ─────────────────────────────"
echo "  ✅ Created : ${CREATED}"
echo "  ⏭️  Skipped : ${SKIPPED}"
echo "  ❌ Errors  : ${ERRORS}"; echo ""
if [[ "$ERRORS" -gt 0 ]]; then exit 1; else exit 0; fi
