#!/usr/bin/env bash
# ==============================================================================
# setup_board.sh — Creates GitHub Projects V2 board with custom fields
# Part of gh-repo-bootstrap | Version: 1.0.0
# Uses $PROJ_ID (NOT $PID — reserved variable). All GQL via string concat.
# ==============================================================================
set -euo pipefail

for dep in curl jq; do
  command -v "$dep" &>/dev/null || { echo "❌ '$dep' not found." >&2; exit 1; }
done

print_header() {
  echo ""; echo "═══════════════════════════════════════"
  echo "  04 — Project Board"; echo "═══════════════════════════════════════"
}

gql() {
  local query="$1"
  local payload
  payload=$(jq -n --arg q "$query" '{query: $q}')
  curl -sf -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://api.github.com/graphql"
}

print_header
[[ -z "${GITHUB_TOKEN:-}" ]] && read -rsp "GitHub PAT (project scope): " GITHUB_TOKEN && echo
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp  "GitHub owner: " GITHUB_OWNER
[[ -z "${REPO_NAME:-}"    ]] && read -rp  "Repository name: " REPO_NAME
BOARD_NAME="${BOARD_NAME:-Engineering Backlog}"

CREATED=0; SKIPPED=0; ERRORS=0; TAGGED=0

# Resolve owner ID (user or org)
echo "  → Resolving owner node ID..."
OWNER_ID=$(gql "query { user(login: \"${GITHUB_OWNER}\") { id } }" | jq -r '.data.user.id // empty')
if [[ -z "$OWNER_ID" ]]; then
  OWNER_ID=$(gql "query { organization(login: \"${GITHUB_OWNER}\") { id } }" | jq -r '.data.organization.id')
fi
echo "  → Owner ID: ${OWNER_ID}"

# Find or create project
echo "  → Checking for existing project '${BOARD_NAME}'..."
PROJ_ID=$(gql "query { user(login: \"${GITHUB_OWNER}\") { projectsV2(first: 20) { nodes { id title } } } }" \
  | jq -r --arg t "$BOARD_NAME" '.data.user.projectsV2.nodes[] | select(.title==$t) | .id' 2>/dev/null || echo "")

if [[ -n "$PROJ_ID" ]]; then
  echo "  ⏭️  Project '${BOARD_NAME}' already exists: ${PROJ_ID}"
  SKIPPED=$((SKIPPED+1))
else
  echo "  → Creating project '${BOARD_NAME}'..."
  PROJ_ID=$(gql "mutation { createProjectV2(input: { ownerId: \"${OWNER_ID}\", title: \"${BOARD_NAME}\" }) { projectV2 { id } } }" \
    | jq -r '.data.createProjectV2.projectV2.id')
  echo "  ✅ Project created: ${PROJ_ID}"
  CREATED=$((CREATED+1))
fi

# Create custom fields
create_field() {
  local name="$1" options_json="$2"
  local existing
  existing=$(gql "query { node(id: \"${PROJ_ID}\") { ... on ProjectV2 { fields(first:20) { nodes { ... on ProjectV2SingleSelectField { id name } } } } } }" \
    | jq -r --arg n "$name" '.data.node.fields.nodes[] | select(.name==$n) | .id' 2>/dev/null || echo "")
  if [[ -n "$existing" ]]; then
    echo "    ⏭️  Field '${name}' already exists."; SKIPPED=$((SKIPPED+1))
  else
    gql "mutation { addProjectV2Field(input: { projectId: \"${PROJ_ID}\", dataType: SINGLE_SELECT, name: \"${name}\", singleSelectOptions: ${options_json} }) { projectV2Field { ... on ProjectV2SingleSelectField { id name } } } }" > /dev/null
    echo "    ✅ Field '${name}' created."; CREATED=$((CREATED+1))
  fi
}

echo "  → Configuring custom fields..."
create_field "Priority" '[{"name":"P0: Critical","color":"RED","description":""},{"name":"P1: High","color":"YELLOW","description":""},{"name":"P2: Medium","color":"BLUE","description":""},{"name":"P3: Low","color":"GRAY","description":""}]'
create_field "Epic" '[{"name":"Compliance","color":"PURPLE","description":""},{"name":"Security","color":"RED","description":""},{"name":"Infrastructure","color":"GRAY","description":""},{"name":"UI/UX","color":"PINK","description":""},{"name":"AI/ML","color":"BLUE","description":""},{"name":"Integrations","color":"GREEN","description":""}]'
create_field "Size" '[{"name":"S","color":"GREEN","description":""},{"name":"M","color":"BLUE","description":""},{"name":"L","color":"YELLOW","description":""},{"name":"XL","color":"RED","description":""}]'

echo ""
echo "  ℹ️  NOTE: Workflow automations must be enabled via GitHub UI → Project → Settings → Workflows."
echo "       This is a documented GitHub API limitation."

echo ""; echo "─── Summary ─────────────────────────────"
echo "  ✅ Created : ${CREATED}"
echo "  ⏭️  Skipped : ${SKIPPED}"
echo "  🏷️  Tagged  : ${TAGGED}"
echo "  ❌ Errors  : ${ERRORS}"; echo ""
[[ "$ERRORS" -gt 0 ]] && exit 1 || exit 0
