# gh-repo-bootstrap: Operations & Troubleshooting Manual

Welcome to the **Operations Manual** for `gh-repo-bootstrap`. This document provides exhaustive instructions on how to operate the toolkit, customize its behavior, run it in automated CIs, and troubleshoot common errors.

---

## 📑 Table of Contents

1. [Core Concepts](#1-core-concepts)
2. [Credential Management](#2-credential-management)
3. [Execution Modes](#3-execution-modes)
4. [Customizing the Toolkit](#4-customizing-the-toolkit)
5. [Troubleshooting Guide](#5-troubleshooting-guide)
6. [Architecture & Script Design](#6-architecture--script-design)

---

## 1. Core Concepts

### 1.1 Orchestrator vs. Sub-Scripts

The toolkit is designed with a **Master Orchestrator** pattern.

- **`00_run_all.ps1` (or `.sh`)**: This is the master entry point. It provides an interactive CLI, prompts for missing variables once, and executes the ordered sub-scripts.
- **Sub-Scripts (`01_create_repo`, etc.)**: Each is a standalone, idempotent script. You can run them individually if a specific step failed or if you only need exactly one function (e.g., just updating the project board).

### 1.2 Idempotency

Every script follows a strict "Check, then Create" loop:

1. Validates if the resource (repository, label, branch rule) exists.
2. If it exists, it **skips** creation and outputs a `⏭️ Skipped` message.
3. If it does not exist, it creates it.

*Safe to run multiple times:* You can safely run the entire toolkit against an existing repository without fear of duplicate data or failing builds.

---

## 2. Credential Management

To execute the scripts, you must authenticate to the GitHub API.

### 2.1 Personal Access Token (PAT) Scopes

You need a **Classic PAT** (Fine-Grained PATs do not currently support all necessary GraphQL GraphQL API scopes for Project Boards).

**Required Scopes:**

- `repo` (Full control of private repositories)
- `admin:repo_hook` (For branch protection and checks)
- `project` (Full control of projects)

*(Warning: If interacting with an Organization repository that uses SAML SSO, you must explicitly click "Authorize SSO" next to the PAT in your GitHub settings).*

### 2.2 Providing Credentials

**Option A: Interactive (Recommended for locals)**
Run `pwsh scripts/00_run_all.ps1`. The script explicitly uses `Read-Host -AsSecureString` to prompt for your PAT. The string is stored securely in your PowerShell session environment and is not leaked to your powershell history logs.

**Option B: Environment Variables (Required for Unattended execution)**
Set the variables before running the scripts:

**PowerShell (`.ps1`):**

```powershell
$env:GITHUB_TOKEN = "ghp_xxxxxxxxxxxx"
$env:GITHUB_OWNER = "your-org"
$env:REPO_NAME = "new-awesome-project"
```

**Bash (`.sh`):**

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
export GITHUB_OWNER="your-org"
export REPO_NAME="new-awesome-project"
```

---

## 3. Execution Modes

### 3.1 Interactive CLI Execution

Run the orchestrator:

```powershell
pwsh scripts/00_run_all.ps1
```

The CLI provides a menu `[1] - [9]`. You may type `A` to execute all steps sequentially.

### 3.2 Unattended / CI Mode

If you wish to integrate `gh-repo-bootstrap` into an internal developer portal (like Backstage) or another CI pipeline:

```bash
# Export the required variables
export GITHUB_TOKEN="ghp_xxx"
export GITHUB_OWNER="MyOrg"
export REPO_NAME="new-repo"

# Bypass interactive menus by calling the sub-scripts directly
bash scripts/01_create_repo/create_repo.sh
bash scripts/02_branch_protection/setup_branches.sh
# ... continue through the sequence
```

### 3.3 Partial Executions

If script `04_project_board` fails due to an API timeout, you do not need to start over!

1. Relaunch the orchestrator.
2. Select `4` from the interactive menu.
3. The script will securely load your memory-cached tokens and execute *only* the project board step.

---

## 4. Customizing the Toolkit

### Add or Remove Labels

Edit `scripts/03_labels/setup_labels.ps1` (or `.sh`). Locate the `$LABELS` (or `LABELS` array in bash). You may freely add, remove, or change colors. The script checks for exact name matches.

### Customizing CI/CD behavior

All template files are physically located in the `templates/` directory.

- If you use **AWS** instead of **Vercel**, simply replace `templates/ci/preview-deploy.yml` with your custom workflow.
- When `05_ci_cd` runs, it recursively copies everything in `templates/ci/` to `.github/workflows/`.

### Branch Protection Overrides

If you need to support `develop` branches instead of only `main` and `master`, edit `scripts/02_branch_protection/setup_branches.ps1`. Find the `$BRANCHES = @('main', 'master')` array and append `'develop'`.

---

## 5. Troubleshooting Guide

### Issue: "401 Unauthorized" or "403 Forbidden"

- **Diagnosis**: Your PAT is invalid, expired, or missing the correct scopes.
- **Fix**: Re-generate a Classic PAT. Ensure `repo`, `admin:repo_hook`, and `project` boxes are checked. Make sure to click "Enable SSO" if working on corporate orgs.

### Issue: "GraphQL Parsing Error" on Project Boards

- **Diagnosis**: An unexpected special character (like a rogue double quote `"` or backtick `` ` ``) was used in your title or repository name, causing the raw GraphQL JSON mutation to break.
- **Fix**: Ensure your repository names only contain alphanumeric characters and hyphens.

### Issue: Scripts instantly close/fail on Windows

- **Diagnosis**: PowerShell Execution Policies are blocking local script execution.
- **Fix**: Open PowerShell as Administrator and run: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

### Issue: Bash scripts complain about `\r\n` (Command not found)

- **Diagnosis**: The bash scripts were saved with Windows CRLF line endings instead of Unix LF.
- **Fix**: Open the `.sh` file in your editor (VS Code) and change the line ending (bottom right corner) from `CRLF` to `LF`. Or run `dos2unix scripts/**/*.sh`.

---

## 6. Architecture & Script Design

If you intend to contribute or heavily modify the codebase:

1. **No Third-Party Depdenencies:**
   We strictly rely on `Invoke-RestMethod` (PowerShell) and `curl + jq` (Bash). We do not require the `gh` CLI. This prevents cross-platform dependency hell.
2. **REST vs GraphQL:**
   Most operations use the GitHub REST API (`v3`). However, GitHub Projects V2 does not have a comprehensive REST API. The `04_project_board` script leverages the GraphQL (`v4`) API exclusively.
3. **Idempotent Error Actions:**
   PowerShell utilizes `$ErrorActionPreference = 'Stop'` inside sub-scripts to fail fast, but the master orchestrator (`00_run_all.ps1`) uses `Continue` so sequential steps don't crash the entire menu if one non-critical step fails.
