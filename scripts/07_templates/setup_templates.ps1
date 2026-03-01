#Requires -Version 7
<#
.SYNOPSIS
    Copies community health and governance templates into a target repository.

.DESCRIPTION
    Copies from templates/github/ into the target repo via the GitHub Contents API:
    - .github/PULL_REQUEST_TEMPLATE.md
    - .github/ISSUE_TEMPLATE/bug_report.yml
    - .github/ISSUE_TEMPLATE/feature_request.yml
    - .github/ISSUE_TEMPLATE/compliance_task.yml
    - CONTRIBUTING.md (root)
    - CODE_OF_CONDUCT.md (root)
    - SECURITY.md (root)

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN  - PAT with 'repo' scope
    GITHUB_OWNER  - GitHub username or organization
    REPO_NAME     - Target repository name

.NOTES
    Idempotent: existing files are updated (SHA-matched), not duplicated.
    Author: gh-repo-bootstrap
    Version: 1.0.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Header {
    param([string]$Title)
    Write-Host ""; Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan; Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
}

function Get-Credential-Env {
    param([string]$EnvName, [string]$Prompt, [switch]$Secret)
    $val = [System.Environment]::GetEnvironmentVariable($EnvName)
    if (-not $val) {
        if ($Secret) {
            $secure = Read-Host -Prompt $Prompt -AsSecureString
            $val = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        }
        else { $val = Read-Host -Prompt $Prompt }
    }
    return $val
}

function Push-RepoFile {
    param([string]$Owner, [string]$Repo, [string]$RepoPath, [string]$LocalPath, [string]$CommitMsg, [string]$Token)

    $content = Get-Content -Path $LocalPath -Raw -Encoding UTF8
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    $uri = "https://api.github.com/repos/$Owner/$Repo/contents/$RepoPath"

    $headers = @{
        'Authorization'        = "Bearer $Token"
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $existingSha = $null
    try {
        $existing = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
        $existingSha = $existing.sha
    }
    catch {}

    $body = @{ message = $CommitMsg; content = $encoded; branch = 'main' }
    if ($existingSha) { $body['sha'] = $existingSha }

    Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers `
        -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json' | Out-Null

    return if ($existingSha) { 'updated' } else { 'created' }
}

# ─── File Manifest ────────────────────────────────────────────────────────────

# Each entry: [localRelativePath, repoDestinationPath]
$MANIFEST = @(
    @('PULL_REQUEST_TEMPLATE.md', '.github/PULL_REQUEST_TEMPLATE.md')
    @('ISSUE_TEMPLATE/bug_report.yml', '.github/ISSUE_TEMPLATE/bug_report.yml')
    @('ISSUE_TEMPLATE/feature_request.yml', '.github/ISSUE_TEMPLATE/feature_request.yml')
    @('ISSUE_TEMPLATE/compliance_task.yml', '.github/ISSUE_TEMPLATE/compliance_task.yml')
    @('CONTRIBUTING.md', 'CONTRIBUTING.md')
    @('CODE_OF_CONDUCT.md', 'CODE_OF_CONDUCT.md')
    @('SECURITY.md', 'SECURITY.md')
)

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Header "07 — PR & Issue Templates"

$TOKEN = Get-Credential-Env -EnvName 'GITHUB_TOKEN' -Prompt 'GitHub PAT' -Secret
$OWNER = Get-Credential-Env -EnvName 'GITHUB_OWNER' -Prompt 'GitHub owner'
$REPO_NAME = Get-Credential-Env -EnvName 'REPO_NAME'    -Prompt 'Repository name'

$stats = @{ created = 0; skipped = 0; errors = 0 }
$templatesDir = Join-Path $PSScriptRoot '..\..\templates\github'

foreach ($entry in $MANIFEST) {
    $localPath = Join-Path $templatesDir $entry[0]
    $repoPath = $entry[1]

    if (-not (Test-Path $localPath)) {
        Write-Host "  ⚠️  Template not found: $localPath — skipping." -ForegroundColor Yellow
        $stats.skipped++
        continue
    }

    Write-Host "  → Pushing: $repoPath..." -ForegroundColor Gray
    try {
        $commitMsg = "chore: add $repoPath via gh-repo-bootstrap"
        $result = Push-RepoFile -Owner $OWNER -Repo $REPO_NAME -RepoPath $repoPath `
            -LocalPath $localPath -CommitMsg $commitMsg -Token $TOKEN
        if ($result -eq 'created') {
            Write-Host "  ✅ Created: $repoPath" -ForegroundColor Green; $stats.created++
        }
        else {
            Write-Host "  ⏭️  Updated: $repoPath" -ForegroundColor Yellow; $stats.skipped++
        }
    }
    catch {
        Write-Host "  ❌ Failed: $repoPath — $_" -ForegroundColor Red; $stats.errors++
    }
}

Write-Host ""; Write-Host "─── Summary ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ✅ Created : $($stats.created)" -ForegroundColor Green
Write-Host "  ⏭️  Updated : $($stats.skipped)" -ForegroundColor Yellow
Write-Host "  ❌ Errors  : $($stats.errors)" -ForegroundColor Red; Write-Host ""
if ($stats.errors -gt 0) { exit 1 }
