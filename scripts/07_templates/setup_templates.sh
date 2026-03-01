#!/usr/bin/env bash
# setup_templates.sh — Deploys community health files
# Part of gh-repo-bootstrap | Version: 1.0.0
set -euo pipefail

for dep in curl jq base64; do
  command -v "$dep" &>/dev/null || { echo "❌ '$dep' not found." >&2; exit 1; }
done

print_header() {
  echo ""; echo "═══════════════════════════════════════"
  echo "  07 — PR & Issue Templates"; echo "═══════════════════════════════════════"
}

print_header
[[ -z "${GITHUB_TOKEN:-}" ]] && read -rsp "GitHub PAT: " GITHUB_TOKEN && echo
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp  "GitHub owner: " GITHUB_OWNER
[[ -z "${REPO_NAME:-}"    ]] && read -rp  "Repository name: " REPO_NAME

CREATED=0; SKIPPED=0; ERRORS=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPL_DIR="${SCRIPT_DIR}/../../templates/github"

push_file() {
  local local_path="$1" repo_path="$2"
  [[ ! -f "$local_path" ]] && { echo "  ⚠️  Not found: ${local_path}"; SKIPPED=$((SKIPPED+1)); return; }

  local uri="https://api.github.com/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/${repo_path}"
  local encoded; encoded=$(base64 < "$local_path" | tr -d '\n')
  local sha; sha=$(curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" "$uri" 2>/dev/null | jq -r '.sha // empty' || echo "")

  local msg="chore: add ${repo_path} via gh-repo-bootstrap"
  local body
  if [[ -n "$sha" ]]; then
    body=$(jq -n --arg m "$msg" --arg c "$encoded" --arg s "$sha" \
      '{message:$m, content:$c, branch:"main", sha:$s}')
  else
    body=$(jq -n --arg m "$msg" --arg c "$encoded" \
      '{message:$m, content:$c, branch:"main"}')
  fi

  if curl -sf -X PUT -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
    -d "$body" "$uri" > /dev/null; then
    [[ -n "$sha" ]] && { echo "  ⏭️  Updated: ${repo_path}"; SKIPPED=$((SKIPPED+1)); } \
                    || { echo "  ✅ Created: ${repo_path}"; CREATED=$((CREATED+1)); }
  else
    echo "  ❌ Failed: ${repo_path}"; ERRORS=$((ERRORS+1))
  fi
}

push_file "${TMPL_DIR}/PULL_REQUEST_TEMPLATE.md"      ".github/PULL_REQUEST_TEMPLATE.md"
push_file "${TMPL_DIR}/ISSUE_TEMPLATE/bug_report.yml" ".github/ISSUE_TEMPLATE/bug_report.yml"
push_file "${TMPL_DIR}/ISSUE_TEMPLATE/feature_request.yml" ".github/ISSUE_TEMPLATE/feature_request.yml"
push_file "${TMPL_DIR}/ISSUE_TEMPLATE/compliance_task.yml" ".github/ISSUE_TEMPLATE/compliance_task.yml"
push_file "${TMPL_DIR}/CONTRIBUTING.md"    "CONTRIBUTING.md"
push_file "${TMPL_DIR}/CODE_OF_CONDUCT.md" "CODE_OF_CONDUCT.md"
push_file "${TMPL_DIR}/SECURITY.md"        "SECURITY.md"

echo ""; echo "─── Summary ─────────────────────────────"
echo "  ✅ Created : ${CREATED}"
echo "  ⏭️  Updated : ${SKIPPED}"
echo "  ❌ Errors  : ${ERRORS}"; echo ""
[[ "$ERRORS" -gt 0 ]] && exit 1 || exit 0
