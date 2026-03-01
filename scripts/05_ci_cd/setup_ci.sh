#!/usr/bin/env bash
# setup_ci.sh — Deploys CI/CD templates into target repo
# Part of gh-repo-bootstrap | Version: 1.0.0
set -euo pipefail

for dep in curl jq base64; do
  command -v "$dep" &>/dev/null || { echo "❌ '$dep' not found." >&2; exit 1; }
done

print_header() {
  echo ""; echo "═══════════════════════════════════════"
  echo "  05 — CI/CD Workflows"; echo "═══════════════════════════════════════"
}

print_header
[[ -z "${GITHUB_TOKEN:-}" ]] && read -rsp "GitHub PAT: " GITHUB_TOKEN && echo
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp  "GitHub owner: " GITHUB_OWNER
[[ -z "${REPO_NAME:-}"    ]] && read -rp  "Repository name: " REPO_NAME

CREATED=0; SKIPPED=0; ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/../../templates/ci"

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "  ❌ templates/ci/ not found at: ${TEMPLATES_DIR}" >&2; exit 1
fi

push_file() {
  local local_path="$1" remote_name="$2"
  local api_path=".github/workflows/${remote_name}"
  local uri="https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/${api_path}"
  local encoded; encoded=$(base64 < "$local_path" | tr -d '\n')

  # Get existing SHA
  local sha
  sha=$(curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" "$uri" 2>/dev/null | jq -r '.sha // empty' || echo "")

  local message
  [[ -n "$sha" ]] && message="ci: update ${remote_name} via gh-repo-bootstrap" || message="ci: add ${remote_name} via gh-repo-bootstrap"

  local body
  if [[ -n "$sha" ]]; then
    body=$(jq -n --arg m "$message" --arg c "$encoded" --arg s "$sha" \
      '{message:$m, content:$c, branch:"main", sha:$s}')
  else
    body=$(jq -n --arg m "$message" --arg c "$encoded" \
      '{message:$m, content:$c, branch:"main"}')
  fi

  if curl -sf -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    -d "$body" "$uri" > /dev/null; then
    [[ -n "$sha" ]] && { echo "  ⏭️  Updated: .github/workflows/${remote_name}"; SKIPPED=$((SKIPPED+1)); } \
                    || { echo "  ✅ Created: .github/workflows/${remote_name}"; CREATED=$((CREATED+1)); }
  else
    echo "  ❌ Failed: ${remote_name}"; ERRORS=$((ERRORS+1))
  fi
}

echo "  → Deploying CI templates..."
for f in "$TEMPLATES_DIR"/*.yml; do
  [[ -f "$f" ]] && push_file "$f" "$(basename "$f")"
done

echo ""; echo "─── Summary ─────────────────────────────"
echo "  ✅ Created : ${CREATED}"
echo "  ⏭️  Updated : ${SKIPPED}"
echo "  ❌ Errors  : ${ERRORS}"; echo ""
[[ "$ERRORS" -gt 0 ]] && exit 1 || exit 0
