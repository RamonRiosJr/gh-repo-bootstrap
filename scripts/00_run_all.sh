#!/usr/bin/env bash
# ==============================================================================
# 00_run_all.sh — Master orchestrator for gh-repo-bootstrap
# Part of gh-repo-bootstrap | Version: 1.0.0
#
# SYNOPSIS
#   Master orchestrator for executing all repository setup scripts.
#
# DESCRIPTION
#   Provides an interactive menu to run any combination of the 9 automation
#   scripts in sequence. Collects credentials once at startup and passes them
#   to all sub-scripts via environment variables. Prints a final pass/fail
#   summary table at the end.
#
# ENVIRONMENT VARIABLES
#   GITHUB_TOKEN  - GitHub PAT (prompted once if not set)
#   GITHUB_OWNER  - GitHub username or organization name
#   REPO_NAME     - Target repository name
#
# NOTES
#   For exhaustive instructions and troubleshooting, see OPERATIONS_MANUAL.md
# ==============================================================================
set -euo pipefail

for dep in curl jq; do
  command -v "$dep" &>/dev/null || { echo "❌ '$dep' not found." >&2; exit 1; }
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -A STEP_LABELS=(
  [1]="Create Repository"
  [2]="Branch Protection"
  [3]="Labels"
  [4]="Project Board"
  [5]="CI/CD Workflows"
  [6]="Secrets"
  [7]="PR & Issue Templates"
  [8]="Dependabot"
  [9]="Description & Topics"
)
declare -A STEP_SCRIPTS=(
  [1]="01_create_repo/create_repo.sh"
  [2]="02_branch_protection/setup_branches.sh"
  [3]="03_labels/setup_labels.sh"
  [4]="04_project_board/setup_board.sh"
  [5]="05_ci_cd/setup_ci.sh"
  [6]="06_secrets/setup_secrets.sh"
  [7]="07_templates/setup_templates.sh"
  [8]="08_dependabot/setup_dependabot.sh"
  [9]="09_description_topics/setup_meta.sh"
)
declare -A RESULTS

show_banner() {
  clear
  echo ""
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║                                              ║"
  echo "  ║   🚀  gh-repo-bootstrap  v1.0.0              ║"
  echo "  ║   GitHub Repository Automation Toolkit      ║"
  echo "  ║                                              ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo ""
  echo "  Owner : ${GITHUB_OWNER}"
  echo "  Repo  : ${REPO_NAME}"
  echo ""
}

show_menu() {
  echo "  ═══════════════════════════════════════"
  echo "   Select a step to run:"
  echo "  ═══════════════════════════════════════"
  for k in 1 2 3 4 5 6 7 8 9; do
    echo "   [$k] ${STEP_LABELS[$k]}"
  done
  echo "   [A] Run ALL (1-9 in sequence)"
  echo "   [Q] Quit"
  echo "  ═══════════════════════════════════════"
  echo ""
}

run_step() {
  local key="$1"
  local script="${SCRIPT_DIR}/${STEP_SCRIPTS[$key]}"
  echo ""
  echo "  ┌──────────────────────────────────────────"
  echo "  │  Running: [$key] ${STEP_LABELS[$key]}"
  echo "  └──────────────────────────────────────────"

  if [[ ! -f "$script" ]]; then
    echo "  ❌ Script not found: ${script}"; RESULTS[$key]="FAIL"; return
  fi

  local start; start=$(date +%s)
  if bash "$script"; then
    local elapsed=$(( $(date +%s) - start ))
    echo "  ✅ [$key] ${STEP_LABELS[$key]} — completed in ${elapsed}s"
    RESULTS[$key]="PASS"
  else
    local elapsed=$(( $(date +%s) - start ))
    echo "  ❌ [$key] ${STEP_LABELS[$key]} — FAILED in ${elapsed}s"
    RESULTS[$key]="FAIL"
  fi
}

show_summary() {
  echo ""
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║               Execution Summary              ║"
  echo "  ╚══════════════════════════════════════════════╝"
  local pass=0 fail=0
  for k in 1 2 3 4 5 6 7 8 9; do
    if [[ -n "${RESULTS[$k]+x}" ]]; then
      status="${RESULTS[$k]}"
      if [[ "$status" == "PASS" ]]; then
        echo "  ✅ [$k] ${STEP_LABELS[$k]}"; pass=$((pass+1))
      else
        echo "  ❌ [$k] ${STEP_LABELS[$k]}"; fail=$((fail+1))
      fi
    fi
  done
  echo ""
  echo "  Total run: $((pass+fail))  |  ✅ ${pass} passed  |  ❌ ${fail} failed"
  echo ""
}

# ─── Collect credentials ──────────────────────────────────────────────────────
echo "  ─── Credentials ─────────────────────────────────"
echo "  (Set GITHUB_TOKEN, GITHUB_OWNER, REPO_NAME to skip prompts)"
echo ""

[[ -z "${GITHUB_TOKEN:-}" ]] && { read -rsp "  GitHub PAT: " GITHUB_TOKEN; echo; } && export GITHUB_TOKEN
[[ -z "${GITHUB_OWNER:-}" ]] && read -rp  "  GitHub owner: " GITHUB_OWNER && export GITHUB_OWNER
[[ -z "${REPO_NAME:-}"    ]] && read -rp  "  Repository name: " REPO_NAME && export REPO_NAME

# ─── Main Loop ────────────────────────────────────────────────────────────────
while true; do
  show_banner
  show_menu
  read -rp "  Enter choice: " choice
  choice="${choice^^}"

  case "$choice" in
    Q)
      echo ""; echo "  👋 Goodbye!"; echo ""
      [[ "${#RESULTS[@]}" -gt 0 ]] && show_summary
      exit 0
      ;;
    A)
      echo "  🚀 Running ALL steps (1-9)..."
      for k in 1 2 3 4 5 6 7 8 9; do run_step "$k"; done
      show_summary
      read -rp "  Press Enter to return to menu..." _
      ;;
    [1-9])
      run_step "$choice"
      read -rp "  Press Enter to return to menu..." _
      ;;
    *)
      echo "  ⚠️  Invalid choice: '${choice}'. Please enter 1-9, A, or Q."
      sleep 2
      ;;
  esac
done
