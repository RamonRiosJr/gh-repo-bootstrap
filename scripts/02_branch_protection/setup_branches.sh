#!/usr/bin/env bash
# ==============================================================================
# setup_branches.sh — Sets up branch protection rules on main and master
# Part of gh-repo-bootstrap | Version: 1.0.0
#
# SYNOPSIS
#   Secures the default branches with pull request requirements and status checks.
#
# DESCRIPTION
#   Applies branch protection rules to 'main' and 'master'. Requires exactly
#   1 approving review, dismisses stale reviews on push, blocks force pushes,
#   requires conversation resolution, and mandates status checks from CI.
#
# ENVIRONMENT VARIABLES
#   GITHUB_TOKEN  - PAT with 'repo' and 'admin:repo_hook' scope
#   GITHUB_OWNER  - GitHub username or organization name
#   REPO_NAME     - Target repository name
#
# NOTES
#   Idempotent: updates existing rules or creates new ones. Skips if branch
#   does not exist. See OPERATIONS_MANUAL.md for vast instructions.
# ==============================================================================
set -euo pipefail

for dep in curl jq; do
  if ! command -v "$dep" &>/dev/null; then
    echo "❌ Required dependency '$dep' not found." >&2; exit 1
  fi
done

print_header() {
  echo ""; echo "═══════════════════════════════════════"
  echo "  02 — Branch Protection"
  echo "═══════════════════════════════════════"
}

gh_api() {
  local method="$1" uri="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sf -X "$method" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      -d "$body" "https://api.github.com${uri}"
  else
    curl -sf -X "$method" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com${uri}"
  fi
}

print_header

[[ -z "${GITHUB_TOKEN:-}" ]] && read -rsp "GitHub PAT: " GITHUB_TOKEN && echo
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp  "GitHub owner: " GITHUB_OWNER
[[ -z "${REPO_NAME:-}"    ]] && read -rp  "Repository name: " REPO_NAME

CREATED=0; SKIPPED=0; ERRORS=0

set_protection() {
  local branch="$1"
  # Check branch exists
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}/branches/${branch}")
  if [[ "$HTTP" != "200" ]]; then
    echo "  ⏭️  Branch '${branch}' does not exist. Skipping."
    SKIPPED=$((SKIPPED+1)); return
  fi

  BODY=$(jq -n '{
    required_status_checks: {
      strict: true,
      contexts: ["Enterprise CI Pipeline / Quality Gate"]
    },
    enforce_admins: true,
    required_pull_request_reviews: {
      dismiss_stale_reviews: true,
      require_code_owner_reviews: false,
      required_approving_review_count: 1,
      require_last_push_approval: false
    },
    restrictions: null,
    allow_force_pushes: false,
    allow_deletions: false,
    required_conversation_resolution: true
  }')

  if gh_api PUT "/repos/${GITHUB_OWNER}/${REPO_NAME}/branches/${branch}/protection" "$BODY" > /dev/null; then
    echo "  ✅ Branch protection set on '${branch}'"
    CREATED=$((CREATED+1))
  else
    echo "  ❌ Failed to set protection on '${branch}'"
    ERRORS=$((ERRORS+1))
  fi
}

for branch in main master; do
  set_protection "$branch"
done

echo ""; echo "─── Summary ─────────────────────────────"
echo "  ✅ Created : ${CREATED}"
echo "  ⏭️  Skipped : ${SKIPPED}"
echo "  ❌ Errors  : ${ERRORS}"; echo ""
[[ "$ERRORS" -gt 0 ]] && exit 1 || exit 0
