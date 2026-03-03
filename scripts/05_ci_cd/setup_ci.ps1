#Requires -Version 7
<#
.SYNOPSIS
    Copies enterprise CI/CD workflow templates into a target repository.

.DESCRIPTION
    Copies all files from templates/ci/ into .github/workflows/ of the target
    repository via the GitHub Contents API. Handles binary-safe base64 encoding.
    Existing files are updated (not duplicated), preserving idempotency.

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN  - PAT with 'repo' scope
    GITHUB_OWNER  - GitHub username or organization
    REPO_NAME     - Target repository name

.NOTES
    CI templates include: ci.yml, deploy-production.yml, preview-deploy.yml, lighthouse.yml
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

function Push-FileToRepo {
    param([string]$Owner, [string]$Repo, [string]$RemotePath, [string]$LocalPath, [string]$Token)

    $content = Get-Content -Path $LocalPath -Raw -Encoding UTF8
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    $apiPath = ".github/workflows/$RemotePath"
    $uri = "https://api.github.com/repos/$Owner/$Repo/contents/$apiPath"

    $headers = @{
        'Authorization'        = "Bearer $Token"
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    # Check if file exists to get SHA (required for updates)
    $existingSha = $null
    try {
        $existing = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
        $existingSha = $existing.sha
    }
    catch {}

    $message = if ($existingSha) { "ci: update $RemotePath via gh-repo-bootstrap" } else { "ci: add $RemotePath via gh-repo-bootstrap" }
    
    $body = @{
        message = $message
        content = $encoded
        branch  = 'main'
    }
    if ($existingSha) { $body['sha'] = $existingSha }

    Invoke-RestMethod -Uri $uri -Method PUT -Headers $headers `
        -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json' | Out-Null

    if ($existingSha) { return 'updated' } else { return 'created' }
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Header "05 — CI/CD Workflows"

$TOKEN = Get-Credential-Env -EnvName 'GITHUB_TOKEN' -Prompt 'GitHub PAT' -Secret
$OWNER = Get-Credential-Env -EnvName 'GITHUB_OWNER' -Prompt 'GitHub owner'
$REPO_NAME = Get-Credential-Env -EnvName 'REPO_NAME'    -Prompt 'Repository name'

$stats = @{ created = 0; skipped = 0; errors = 0 }

$templatesDir = Join-Path $PSScriptRoot '..\..\templates\ci'
if (-not (Test-Path $templatesDir)) {
    Write-Host "  ❌ templates/ci/ directory not found at: $templatesDir" -ForegroundColor Red
    exit 1
}

$templates = Get-ChildItem -Path $templatesDir -Filter '*.yml' -File
Write-Host "  → Found $($templates.Count) CI template(s) to deploy..." -ForegroundColor Gray

foreach ($tmpl in $templates) {
    Write-Host "  → Pushing: $($tmpl.Name)..." -ForegroundColor Gray
    try {
        $result = Push-FileToRepo -Owner $OWNER -Repo $REPO_NAME `
            -RemotePath $tmpl.Name -LocalPath $tmpl.FullName -Token $TOKEN
        if ($result -eq 'created') {
            Write-Host "  ✅ Created: .github/workflows/$($tmpl.Name)" -ForegroundColor Green
            $stats.created++
        }
        else {
            Write-Host "  ⏭️  Updated: .github/workflows/$($tmpl.Name)" -ForegroundColor Yellow
            $stats.skipped++
        }
    }
    catch {
        Write-Host "  ❌ Failed: $($tmpl.Name) — $_" -ForegroundColor Red
        $stats.errors++
    }
}

Write-Host ""; Write-Host "─── Summary ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ✅ Created : $($stats.created)" -ForegroundColor Green
Write-Host "  ⏭️  Updated : $($stats.skipped)" -ForegroundColor Yellow
Write-Host "  ❌ Errors  : $($stats.errors)" -ForegroundColor Red; Write-Host ""
if ($stats.errors -gt 0) { exit 1 }
