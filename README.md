# gh-repo-bootstrap

<div align="center">

[![CI](https://github.com/RamonRiosJr/gh-repo-bootstrap/actions/workflows/validate.yml/badge.svg)](https://github.com/RamonRiosJr/gh-repo-bootstrap/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-blue?logo=powershell)](https://github.com/PowerShell/PowerShell)
[![GitHub GraphQL API](https://img.shields.io/badge/GitHub-GraphQL%20API-e10098?logo=graphql)](https://docs.github.com/en/graphql)
[![Bash](https://img.shields.io/badge/Shell-Bash%205%2B-4EAA25?logo=gnubash)](https://www.gnu.org/software/bash/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

**A complete, production-ready GitHub Repository Automation Toolkit.**  
Clone once. Run once. Get an enterprise-grade repository in minutes.

[Quick Start](#-quick-start) · [Script Reference](#-script-reference) · [Operations Manual](OPERATIONS_MANUAL.md) · [Design Decisions](#-design-decisions) · [Contributing](CONTRIBUTING.md)

</div>

---

## 🚀 What This Toolkit Does

`gh-repo-bootstrap` is the *Infrastructure-as-Code equivalent for GitHub repository management*. It automates every manual step a Platform Engineering team takes when creating a new repository — from branch protection rules and label taxonomies to CI/CD pipelines, GitHub Projects V2 boards, Dependabot config, and community health files.

| # | Script | What It Creates |
|---|--------|-----------------|
| 01 | `01_create_repo` | New GitHub repo via REST API with best-practice defaults (private, auto-init, license, .gitignore) |
| 02 | `02_branch_protection` | Branch protection on `main`/`master`: required reviews, stale-review dismissal, required status checks, no force-push |
| 03 | `03_labels` | Deletes default labels; creates 27-label professional taxonomy (Type, Priority, Epic, Status, Size) |
| 04 | `04_project_board` | GitHub Projects V2 board with Priority/Epic/Size fields; auto-classifies all existing items via keyword matching |
| 05 | `05_ci_cd` | Copies enterprise CI/CD workflow files (lint, type-check, test, build, coverage, Vercel preview, Lighthouse) |
| 06 | `06_secrets` | Interactively sets GitHub Actions secrets with libsodium encryption (Vercel, Supabase, etc.) |
| 07 | `07_templates` | Copies PR template, 3 issue templates, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY.md |
| 08 | `08_dependabot` | Writes `.github/dependabot.yml` for npm + GitHub Actions + Docker with weekly schedule |
| 09 | `09_description_topics` | Sets repo description, homepage URL, and topic tags via API |

---

## 📋 Prerequisites

### GitHub Personal Access Token (PAT)

Create a **Classic PAT** at `Settings → Developer settings → Personal access tokens` with the following scopes:

| Scope | Required By |
|-------|-------------|
| `repo` | All scripts (create, read, write repo data) |
| `admin:repo_hook` | Branch protection, webhook config |
| `project` | Project board automation (script 04) |
| `delete_repo` | Only if you need to clean up test repos |

> **Tip:** For organization repos, you may also need the `admin:org` scope and SSO authorization for the token.

### PowerShell Path

| Tool | Minimum Version | Install |
|------|----------------|---------|
| PowerShell | 7.0+ | [github.com/PowerShell/PowerShell](https://github.com/PowerShell/PowerShell/releases) |
| (Optional) `curl` | Any | Pre-installed on most systems |
| (Bash path) `curl` | Any | `apt install curl` / `brew install curl` |
| (Bash path) `jq` | 1.6+ | `apt install jq` / `brew install jq` |

---

## ⚡ Quick Start

### 1. Clone the toolkit

```bash
git clone https://github.com/YOUR_ORG/gh-repo-bootstrap.git
cd gh-repo-bootstrap
```

### 2. Set credentials

**PowerShell:**

```powershell
$env:GITHUB_TOKEN = "ghp_your_token_here"
$env:GITHUB_OWNER = "your-username-or-org"
```

**Bash:**

```bash
export GITHUB_TOKEN="ghp_your_token_here"
export GITHUB_OWNER="your-username-or-org"
```

> If you don't set these, each script will prompt you interactively via `Read-Host -AsSecureString`.

### 3. Run the master orchestrator

**PowerShell (Windows / macOS / Linux):**

```powershell
pwsh scripts/00_run_all.ps1
```

**Bash (macOS / Linux):**

```bash
bash scripts/00_run_all.sh
```

You'll see an interactive menu:

```
═══════════════════════════════════════
 🚀 gh-repo-bootstrap — Master Setup
═══════════════════════════════════════
 [1] Create Repository
 [2] Branch Protection
 [3] Labels
 [4] Project Board
 [5] CI/CD Workflows
 [6] Secrets
 [7] PR & Issue Templates
 [8] Dependabot
 [9] Description & Topics
 [A] Run ALL (1-9 in sequence)
 [Q] Quit
```

---

## 📖 Script Reference

### `01_create_repo` — Repository Creation

**API:** `POST /user/repos` or `POST /orgs/{org}/repos`

**Behavior:**

- Creates repo as **private** by default (configurable via `$env:REPO_VISIBILITY`)
- Auto-initializes with a README, MIT license, and language-specific `.gitignore`
- Configures `has_issues: true`, `has_projects: true`, `has_wiki: false`
- Sets description and homepage if provided
- Idempotent: if repo already exists, skips creation and proceeds

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `GITHUB_TOKEN` | *(prompted)* | PAT with `repo` scope |
| `GITHUB_OWNER` | *(prompted)* | Username or org name |
| `REPO_NAME` | *(prompted)* | New repository name |
| `REPO_VISIBILITY` | `private` | `private` or `public` |
| `REPO_DESCRIPTION` | `""` | Short description |
| `REPO_GITIGNORE` | `Node` | GitHub .gitignore template name |

---

### `02_branch_protection` — Branch Protection Rules

**API:** `PUT /repos/{owner}/{repo}/branches/{branch}/protection`

**Enforces on both `main` and `master`:**

- ✅ 1 required PR review
- ✅ Stale review dismissal on new commits
- ✅ Required status check: `Enterprise CI Pipeline / Quality Gate`
- ✅ Branch must be up-to-date before merge
- ✅ Rules enforced on administrators
- 🚫 Force pushes blocked
- 🚫 Branch deletion blocked

---

### `03_labels` — Professional Label Taxonomy

Deletes all 9 default GitHub labels and replaces them with a 27-label enterprise taxonomy:

**Type** (`type:`) → Bug, Feature, Chore, Compliance, Security, Docs  
**Priority** (`P0`–`P3`) → Critical, High, Medium, Low  
**Epic** (`epic:`) → Compliance, Security, Infrastructure, UI/UX, AI/ML, Integrations  
**Status** (`status:`) → In Progress, Blocked, Needs Review, Ready  
**Size** (`size:`) → S, M, L, XL  

---

### `04_project_board` — GitHub Projects V2 Board

**API:** GitHub GraphQL API v4

**Creates:**

- Board columns: 🧊 Backlog · 🎯 Sprint Ready · 🚧 In Progress · 👀 In Review · ✅ Deployed
- Custom Single Select fields: **Priority**, **Epic**, **Size**
- Auto-classifies all existing items (Issues, PRs, Draft Issues) using regex keyword matching

> **Note:** Workflow automations (auto-move cards on PR merge, etc.) must be enabled via the GitHub UI — this is an API limitation as of 2024.

---

### `05_ci_cd` — CI/CD Workflow Files

Copies the following from `templates/ci/` into `.github/workflows/` of the target repo:

| File | Purpose |
|------|---------|
| `ci.yml` | TypeScript type-check, ESLint, Prettier, unit tests + coverage, `npm audit`, production build |
| `deploy-production.yml` | Production deployment pipeline |
| `preview-deploy.yml` | Vercel preview deployments (`continue-on-error: true`) |
| `lighthouse.yml` | Lighthouse performance audit (relaxed assertions, non-blocking) |

---

### `06_secrets` — GitHub Actions Secrets

**API:** `PUT /repos/{owner}/{repo}/actions/secrets/{name}` with libsodium encryption

**Prompts for:**

- `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`

Secrets left blank are skipped. A checklist is printed at the end.

---

### `07_templates` — Community Health Files

Copies into the target repo:

- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/ISSUE_TEMPLATE/bug_report.yml`
- `.github/ISSUE_TEMPLATE/feature_request.yml`
- `.github/ISSUE_TEMPLATE/compliance_task.yml`
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md` (root)

---

### `08_dependabot` — Automated Dependency Updates

Writes `.github/dependabot.yml` with:

- `npm` packages — weekly, target `master`, minor/patch grouped
- `github-actions` — weekly
- `docker` — weekly

---

### `09_description_topics` — Repository Metadata

**API:** `PATCH /repos/{owner}/{repo}` and `PUT /repos/{owner}/{repo}/topics`

Sets description, homepage URL, and topic tags for discoverability.

---

## 🏗 Design Decisions

### Why string concatenation instead of backtick interpolation in GraphQL mutations?

PowerShell backtick interpolation inside multi-line heredoc strings containing `"` characters is notoriously fragile — especially with GraphQL mutations that use double-quoted field names and string arguments. A single misplaced backtick or interpolated `"` breaks the entire mutation silently or throws a cryptic parse error.

**We use explicit string concatenation** (`'mutation { ... "' + $variable + '" ... }'`) throughout all GraphQL calls. This is verbose, but it is 100% predictable, easy to diff, and safe for all variable types including those that contain special characters.

### Why no `gh` CLI dependency?

`gh` is an excellent tool for interactive use, but introducing it as a hard dependency creates friction in CI environments, Docker containers, and machines where it is not installed. By using only `Invoke-RestMethod` (PowerShell) and `curl` + `jq` (Bash), these scripts work in any environment with zero extra installation steps.

### Why idempotent design?

Platform Engineering scripts get run multiple times — during development, in CI dry-runs, when onboarding new teammates, or when a partial run fails midway. Every script in this toolkit checks whether the resource it is about to create already exists, and skips it rather than failing. The final summary always distinguishes between ✅ Created, ⏭️ Skipped, and ❌ Error.

### Why `$PROJ_ID` and not `$PID`?

`$PID` is a **reserved automatic variable** in PowerShell that holds the current process ID. Using it as a custom variable silently overwrites a value the runtime depends on — causing subtle, hard-to-debug failures. All project board scripts use `$PROJ_ID` to avoid this trap.

### Why no `actions/attest-build-provenance`?

This action requires **GitHub Advanced Security**, which is only available on public repos or GitHub Enterprise. Including it in the CI template would cause immediate failures on all private repositories. It is intentionally excluded from the default templates.

---

## 🤝 Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to submit pull requests, report bugs, and propose new features.

Before contributing, please review our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 🔒 Security

Please do **not** open a public GitHub Issue to report security vulnerabilities. See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<div align="center">
Built with ❤️ by Platform Engineers who got tired of clicking buttons.<br><br>

**GitHub:** [github.com/RamonRiosJr](https://github.com/RamonRiosJr) &nbsp;|&nbsp;
**LinkedIn:** [linkedin.com/in/ramon-rios-a8ba3035](https://www.linkedin.com/in/ramon-rios-a8ba3035) &nbsp;|&nbsp;
**Blog:** [ramonrios.net](https://ramonrios.net) &nbsp;|&nbsp;
**Coqui Cloud Dev Co.:** [coqui.cloud](https://coqui.cloud)
</div>
