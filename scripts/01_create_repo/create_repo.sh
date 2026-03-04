#!/usr/bin/env bash
# ==============================================================================
# create_repo.sh — Creates a new GitHub repository with enterprise defaults
# Part of gh-repo-bootstrap | Version: 1.0.0
#
# SYNOPSIS
#   Creates a new GitHub repository with best-practice defaults.
#
# DESCRIPTION
#   Uses the GitHub REST API to create a new repository under a user account
#   or organization. Applies sensible enterprise defaults: private, auto-initialized
#   with README and MIT license, issues enabled, wiki disabled.
#
# ENVIRONMENT VARIABLES
#   GITHUB_TOKEN       - PAT with 'repo' scope
#   GITHUB_OWNER       - GitHub username or organization name
#   REPO_NAME          - Repository name to create
#   REPO_VISIBILITY    - 'private' (default) or 'public'
#   REPO_DESCRIPTION   - Short description of the repository
#   REPO_HOMEPAGE      - Homepage URL (optional)
#   REPO_GITIGNORE     - .gitignore template name (default: Node)
#
# NOTES
#   Idempotent: if the repository already exists, script skips creation.
#   For exhaustive instructions, see OPERATIONS_MANUAL.md
# ==============================================================================
set -euo pipefail

# ─── Dependency Check ─────────────────────────────────────────────────────────
for dep in curl jq; do
  if ! command -v "$dep" &>/dev/null; then
    echo "❌ Required dependency '$dep' is not installed. Please install it and retry." >&2
    exit 1
  fi
done

# ─── Helpers ──────────────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo "═══════════════════════════════════════"
  echo "  01 — Create Repository"
  echo "═══════════════════════════════════════"
}

gh_api() {
  local method="$1"
  local uri="$2"
  local body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sf -X "$method" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "https://api.github.com${uri}"
  else
    curl -sf -X "$method" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com${uri}"
  fi
}

# ─── Credentials ──────────────────────────────────────────────────────────────
print_header

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  read -rsp "GitHub PAT (repo scope): " GITHUB_TOKEN; echo
fi
if [[ -z "${GITHUB_OWNER:-}" ]]; then
  read -rp "GitHub owner (user or org): " GITHUB_OWNER
fi
if [[ -z "${REPO_NAME:-}" ]]; then
  read -rp "Repository name: " REPO_NAME
fi

VISIBILITY="${REPO_VISIBILITY:-private}"
DESCRIPTION="${REPO_DESCRIPTION:-}"
HOMEPAGE="${REPO_HOMEPAGE:-}"
GITIGNORE="${REPO_GITIGNORE:-Node}"

CREATED=0; SKIPPED=0; ERRORS=0

# ─── Check Existence ──────────────────────────────────────────────────────────
echo "  → Checking if '${GITHUB_OWNER}/${REPO_NAME}' already exists..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}")

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "  ⏭️  Repository '${GITHUB_OWNER}/${REPO_NAME}' already exists. Skipping."
  SKIPPED=$((SKIPPED + 1))
else
  echo "  → Creating repository '${GITHUB_OWNER}/${REPO_NAME}' (${VISIBILITY})..."

  # Check if owner is org
  IS_ORG=false
  ORG_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    "https://api.github.com/orgs/${GITHUB_OWNER}")
  [[ "$ORG_CODE" == "200" ]] && IS_ORG=true

  IS_PRIVATE="true"
  [[ "$VISIBILITY" == "public" ]] && IS_PRIVATE="false"

  BODY=$(jq -n \
    --arg name "$REPO_NAME" \
    --arg desc "$DESCRIPTION" \
    --arg homepage "$HOMEPAGE" \
    --arg gitignore "$GITIGNORE" \
    --argjson private "$IS_PRIVATE" \
    '{
      name: $name,
      description: $desc,
      homepage: $homepage,
      private: $private,
      auto_init: true,
      gitignore_template: $gitignore,
      license_template: "mit",
      has_issues: true,
      has_projects: true,
      has_wiki: false,
      allow_squash_merge: true,
      allow_merge_commit: false,
      allow_rebase_merge: true,
      delete_branch_on_merge: true
    }')

  if [[ "$IS_ORG" == "true" ]]; then
    CREATE_URI="/orgs/${GITHUB_OWNER}/repos"
  else
    CREATE_URI="/user/repos"
  fi

  RESPONSE=$(gh_api POST "$CREATE_URI" "$BODY")
  REPO_URL=$(echo "$RESPONSE" | jq -r '.html_url')
  echo "  ✅ Repository created: ${REPO_URL}"
  CREATED=$((CREATED + 1))
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "─── Summary ─────────────────────────────"
echo "  ✅ Created : ${CREATED}"
echo "  ⏭️  Skipped : ${SKIPPED}"
echo "  ❌ Errors  : ${ERRORS}"
echo ""

if [[ "$ERRORS" -gt 0 ]]; then exit 1; else exit 0; fi
