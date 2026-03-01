#Requires -Version 7
<#
.SYNOPSIS
    Creates a new GitHub repository with best-practice defaults.

.DESCRIPTION
    Uses the GitHub REST API to create a new repository under a user account
    or organization. Applies sensible enterprise defaults: private, auto-initialized
    with README and MIT license, issues enabled, wiki disabled.

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN       - PAT with 'repo' scope
    GITHUB_OWNER       - GitHub username or organization name
    REPO_NAME          - Repository name to create
    REPO_VISIBILITY    - 'private' (default) or 'public'
    REPO_DESCRIPTION   - Short description of the repository
    REPO_HOMEPAGE      - Homepage URL (optional)
    REPO_GITIGNORE     - .gitignore template name (default: Node)

.NOTES
    Idempotent: if the repository already exists, script skips creation.
    Author: gh-repo-bootstrap
    Version: 1.0.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
}

function Get-Credential-Env {
    param([string]$EnvName, [string]$Prompt, [switch]$Secret)
    $val = [System.Environment]::GetEnvironmentVariable($EnvName)
    if (-not $val) {
        if ($Secret) {
            $secure = Read-Host -Prompt $Prompt -AsSecureString
            $val = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            )
        } else {
            $val = Read-Host -Prompt $Prompt
        }
    }
    return $val
}

function Invoke-GitHubAPI {
    param(
        [string]$Uri,
        [string]$Method = 'GET',
        [hashtable]$Body = $null,
        [string]$Token
    )
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Accept'        = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $params = @{
        Uri     = $Uri
        Method  = $Method
        Headers = $headers
    }
    if ($Body) {
        $params['Body']        = ($Body | ConvertTo-Json -Depth 10)
        $params['ContentType'] = 'application/json'
    }
    return Invoke-RestMethod @params
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Header "01 — Create Repository"

# Collect credentials
$TOKEN       = Get-Credential-Env -EnvName 'GITHUB_TOKEN' -Prompt 'GitHub PAT (repo scope)' -Secret
$OWNER       = Get-Credential-Env -EnvName 'GITHUB_OWNER' -Prompt 'GitHub owner (user or org)'
$REPO_NAME   = Get-Credential-Env -EnvName 'REPO_NAME'    -Prompt 'Repository name'

$VISIBILITY    = if ($env:REPO_VISIBILITY)  { $env:REPO_VISIBILITY }  else { 'private' }
$DESCRIPTION   = if ($env:REPO_DESCRIPTION) { $env:REPO_DESCRIPTION } else { '' }
$HOMEPAGE      = if ($env:REPO_HOMEPAGE)    { $env:REPO_HOMEPAGE }    else { '' }
$GITIGNORE     = if ($env:REPO_GITIGNORE)   { $env:REPO_GITIGNORE }   else { 'Node' }

$stats = @{ created = 0; skipped = 0; errors = 0 }

# Check if repo already exists
Write-Host "  → Checking if '$OWNER/$REPO_NAME' already exists..." -ForegroundColor Gray
$existingRepo = $null
try {
    $existingRepo = Invoke-GitHubAPI -Uri "https://api.github.com/repos/$OWNER/$REPO_NAME" -Token $TOKEN
} catch {
    # 404 means it doesn't exist — that's expected
    if ($_.Exception.Response.StatusCode -ne 404 -and $_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotFound) {
        Write-Host "  ❌ Unexpected error checking repo existence: $_" -ForegroundColor Red
        $stats.errors++
    }
}

if ($existingRepo) {
    Write-Host "  ⏭️  Repository '$OWNER/$REPO_NAME' already exists. Skipping creation." -ForegroundColor Yellow
    $stats.skipped++
} else {
    Write-Host "  → Creating repository '$OWNER/$REPO_NAME' ($VISIBILITY)..." -ForegroundColor Gray

    # Determine if owner is an org or user
    $isOrg = $false
    try {
        $orgCheck = Invoke-GitHubAPI -Uri "https://api.github.com/orgs/$OWNER" -Token $TOKEN
        $isOrg = $true
    } catch { }

    $repoBody = @{
        name                 = $REPO_NAME
        description          = $DESCRIPTION
        homepage             = $HOMEPAGE
        private              = ($VISIBILITY -eq 'private')
        auto_init            = $true
        gitignore_template   = $GITIGNORE
        license_template     = 'mit'
        has_issues           = $true
        has_projects         = $true
        has_wiki             = $false
        allow_squash_merge   = $true
        allow_merge_commit   = $false
        allow_rebase_merge   = $true
        delete_branch_on_merge = $true
    }

    $createUri = if ($isOrg) {
        "https://api.github.com/orgs/$OWNER/repos"
    } else {
        "https://api.github.com/user/repos"
    }

    try {
        $newRepo = Invoke-GitHubAPI -Uri $createUri -Method 'POST' -Body $repoBody -Token $TOKEN
        Write-Host "  ✅ Repository created: $($newRepo.html_url)" -ForegroundColor Green
        $stats.created++
    } catch {
        Write-Host "  ❌ Failed to create repository: $_" -ForegroundColor Red
        $stats.errors++
        exit 1
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─── Summary ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ✅ Created : $($stats.created)" -ForegroundColor Green
Write-Host "  ⏭️  Skipped : $($stats.skipped)" -ForegroundColor Yellow
Write-Host "  ❌ Errors  : $($stats.errors)" -ForegroundColor Red
Write-Host ""

if ($stats.errors -gt 0) { exit 1 }
