#Requires -Version 7
<#
.SYNOPSIS
    Updates repository description, homepage, and topic tags.

.DESCRIPTION
    Calls PATCH /repos/{owner}/{repo} to set description and homepage URL.
    Calls PUT /repos/{owner}/{repo}/topics to set topic tags.
    Tags are accepted as a comma-separated list via REPO_TOPICS env var or prompt.

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN     - PAT with 'repo' scope
    GITHUB_OWNER     - GitHub username or organization
    REPO_NAME        - Target repository name
    REPO_DESCRIPTION - Short description
    REPO_HOMEPAGE    - Homepage URL
    REPO_TOPICS      - Comma-separated list of topics/tags

.NOTES
    Idempotent: can be run multiple times safely.
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

function Invoke-GitHubAPI {
    param([string]$Uri, [string]$Method = 'GET', [hashtable]$Body = $null, [string]$Token)
    $headers = @{
        'Authorization'        = "Bearer $Token"
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $params = @{ Uri = $Uri; Method = $Method; Headers = $headers }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 5); $params['ContentType'] = 'application/json' }
    return Invoke-RestMethod @params
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Header "09 — Description & Topics"

$TOKEN = Get-Credential-Env -EnvName 'GITHUB_TOKEN'     -Prompt 'GitHub PAT' -Secret
$OWNER = Get-Credential-Env -EnvName 'GITHUB_OWNER'     -Prompt 'GitHub owner'
$REPO_NAME = Get-Credential-Env -EnvName 'REPO_NAME'        -Prompt 'Repository name'
$DESCRIPTION = Get-Credential-Env -EnvName 'REPO_DESCRIPTION' -Prompt 'Repository description'
$HOMEPAGE = if ($env:REPO_HOMEPAGE) { $env:REPO_HOMEPAGE } else {
    Read-Host -Prompt 'Homepage URL (optional, press Enter to skip)' 
}
$TOPICS_RAW = if ($env:REPO_TOPICS) { $env:REPO_TOPICS } else {
    Read-Host -Prompt 'Topics (comma-separated, e.g. devops,automation,github)' 
}

$stats = @{ created = 0; skipped = 0; errors = 0 }

# Parse topics
$topics = @()
if ($TOPICS_RAW) {
    $topics = ($TOPICS_RAW -split ',') | ForEach-Object { $_.Trim().ToLower() -replace '[^a-z0-9-]', '-' } | Where-Object { $_ }
}

# PATCH repo metadata
Write-Host "  → Updating repository metadata..." -ForegroundColor Gray
$patchBody = @{ description = $DESCRIPTION }
if ($HOMEPAGE) { $patchBody['homepage'] = $HOMEPAGE }

try {
    Invoke-GitHubAPI -Uri "https://api.github.com/repos/$OWNER/$REPO_NAME" -Method 'PATCH' -Body $patchBody -Token $TOKEN | Out-Null
    Write-Host "  ✅ Description: $DESCRIPTION" -ForegroundColor Green
    if ($HOMEPAGE) { Write-Host "  ✅ Homepage: $HOMEPAGE" -ForegroundColor Green }
    $stats.created++
}
catch {
    Write-Host "  ❌ Failed to update metadata: $_" -ForegroundColor Red; $stats.errors++
}

# PUT topics
if ($topics.Count -gt 0) {
    Write-Host "  → Setting $($topics.Count) topic(s): $($topics -join ', ')..." -ForegroundColor Gray
    try {
        $topicBody = @{ names = $topics }
        Invoke-GitHubAPI -Uri "https://api.github.com/repos/$OWNER/$REPO_NAME/topics" -Method 'PUT' -Body $topicBody -Token $TOKEN | Out-Null
        Write-Host "  ✅ Topics set: $($topics -join ', ')" -ForegroundColor Green
        $stats.created++
    }
    catch {
        Write-Host "  ❌ Failed to set topics: $_" -ForegroundColor Red; $stats.errors++
    }
}
else {
    Write-Host "  ⏭️  No topics provided. Skipping." -ForegroundColor Yellow; $stats.skipped++
}

Write-Host ""; Write-Host "─── Summary ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ✅ Created : $($stats.created)" -ForegroundColor Green
Write-Host "  ⏭️  Skipped : $($stats.skipped)" -ForegroundColor Yellow
Write-Host "  ❌ Errors  : $($stats.errors)" -ForegroundColor Red; Write-Host ""
if ($stats.errors -gt 0) { exit 1 }
