#!/usr/bin/env bash
# ==============================================================================
# setup_secrets.sh — Sets GitHub Actions secrets
# Part of gh-repo-bootstrap | Version: 1.0.0
# Uses gh CLI for encryption (handles libsodium natively)
#
# SYNOPSIS
#   Interactively configures encrypted GitHub Actions secrets.
#
# DESCRIPTION
#   Prompts the user for sensitive deployment secrets (e.g. VERCEL_TOKEN,
#   SUPABASE_URL) and securely encrypts them using the 'gh' CLI before
#   uploading them to the repository's action secrets.
#
# ENVIRONMENT VARIABLES
#   GITHUB_TOKEN  - PAT with 'repo' scope
#   GITHUB_OWNER  - GitHub username or organization name
#   REPO_NAME     - Target repository name
#
# NOTES
#   Leaves secrets unchanged if skipped (by pressing Enter).
#   See OPERATIONS_MANUAL.md for vast instructions on operation.
# ==============================================================================
set -euo pipefail

for dep in curl jq; do
  command -v "$dep" &>/dev/null || { echo "❌ '$dep' not found." >&2; exit 1; }
done

# Check for gh CLI (used for secret encryption)
if ! command -v gh &>/dev/null; then
  echo "  ⚠️  'gh' CLI not found. Secrets cannot be encrypted without it." >&2
  echo "     Install: https://cli.github.com/" >&2
  exit 1
fi

print_header() {
  echo ""; echo "═══════════════════════════════════════"
  echo "  06 — GitHub Actions Secrets"; echo "═══════════════════════════════════════"
}

print_header
[[ -z "${GITHUB_TOKEN:-}" ]] && read -rsp "GitHub PAT: " GITHUB_TOKEN && echo
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp  "GitHub owner: " GITHUB_OWNER
[[ -z "${REPO_NAME:-}"    ]] && read -rp  "Repository name: " REPO_NAME

export GH_TOKEN="$GITHUB_TOKEN"

CREATED=0; SKIPPED=0; ERRORS=0

echo ""
echo "  Enter secret values. Press Enter to skip any secret."
echo "  ⚠️  Values are masked — they will not appear on screen."
echo ""

declare -A SECRET_DEFS=(
  [VERCEL_TOKEN]="Vercel deployment token"
  [VERCEL_ORG_ID]="Vercel organization ID"
  [VERCEL_PROJECT_ID]="Vercel project ID"
  [SUPABASE_URL]="Supabase project URL"
  [SUPABASE_ANON_KEY]="Supabase anon/public key"
)
SECRET_ORDER=(VERCEL_TOKEN VERCEL_ORG_ID VERCEL_PROJECT_ID SUPABASE_URL SUPABASE_ANON_KEY)

declare -A RESULTS
for name in "${SECRET_ORDER[@]}"; do
  desc="${SECRET_DEFS[$name]}"
  read -rsp "  ${name} (${desc}): " value; echo
  if [[ -z "$value" ]]; then
    echo "    ⏭️  Skipped: ${name}"; RESULTS[$name]="SKIPPED"; SKIPPED=$((SKIPPED+1))
    continue
  fi
  if echo -n "$value" | gh secret set "$name" --repo "${GITHUB_OWNER}/${REPO_NAME}" 2>/dev/null; then
    echo "    ✅ Set: ${name}"; RESULTS[$name]="SET"; CREATED=$((CREATED+1))
  else
    echo "    ❌ Failed: ${name}"; RESULTS[$name]="FAILED"; ERRORS=$((ERRORS+1))
  fi
done

echo ""; echo "─── Secrets Checklist ────────────────────"
for name in "${SECRET_ORDER[@]}"; do
  status="${RESULTS[$name]:-UNKNOWN}"
  [[ "$status" == "SET"     ]] && echo "  ✅ ${name} [SET]"
  [[ "$status" == "SKIPPED" ]] && echo "  ⏭️  ${name} [SKIPPED]"
  [[ "$status" == "FAILED"  ]] && echo "  ❌ ${name} [FAILED]"
done

echo ""; echo "─── Summary ─────────────────────────────"
echo "  ✅ Set     : ${CREATED}"
echo "  ⏭️  Skipped : ${SKIPPED}"
echo "  ❌ Errors  : ${ERRORS}"; echo ""
if [[ "$ERRORS" -gt 0 ]]; then exit 1; else exit 0; fi
