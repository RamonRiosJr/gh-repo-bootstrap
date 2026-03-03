#Requires -Version 7
<#
.SYNOPSIS
    Sets up branch protection rules on main and master branches.

.DESCRIPTION
    Calls PUT /repos/{owner}/{repo}/branches/{branch}/protection to enforce:
    - Required PR reviews (min 1, stale review dismissal)
    - Required status checks (Enterprise CI Pipeline / Quality Gate)
    - Branch must be up to date before merging
    - Rules enforced on administrators
    - Force pushes and deletions blocked

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN  - PAT with 'repo' and 'admin:repo_hook' scopes
    GITHUB_OWNER  - GitHub username or organization
    REPO_NAME     - Target repository name

.NOTES
    Idempotent: safe to run multiple times.
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
        }
        else {
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
        'Authorization'        = "Bearer $Token"
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $params = @{ Uri = $Uri; Method = $Method; Headers = $headers }
    if ($Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
        $params['ContentType'] = 'application/json'
    }
    return Invoke-RestMethod @params
}

function Set-BranchProtection {
    param([string]$Branch, [string]$Token, [string]$Owner, [string]$Repo)

    $uri = "https://api.github.com/repos/$Owner/$Repo/branches/$Branch/protection"

    # Check branch exists
    try {
        Invoke-GitHubAPI -Uri "https://api.github.com/repos/$Owner/$Repo/branches/$Branch" -Token $Token | Out-Null
    }
    catch {
        Write-Host "  ⏭️  Branch '$Branch' does not exist in '$Owner/$Repo'. Skipping." -ForegroundColor Yellow
        return 'skipped'
    }

    $protectionBody = @{
        required_status_checks           = @{
            strict   = $true
            contexts = @('Enterprise CI Pipeline / Quality Gate')
        }
        enforce_admins                   = $true
        required_pull_request_reviews    = @{
            dismissal_restrictions          = @{ users = @(); teams = @() }
            dismiss_stale_reviews           = $true
            require_code_owner_reviews      = $false
            required_approving_review_count = 1
            require_last_push_approval      = $false
        }
        restrictions                     = @{ users = @(); teams = @(); apps = @() }
        allow_force_pushes               = $false
        allow_deletions                  = $false
        block_creations                  = $false
        required_conversation_resolution = $true
    }

    try {
        Invoke-GitHubAPI -Uri $uri -Method 'PUT' -Body $protectionBody -Token $Token | Out-Null
        Write-Host "  ✅ Branch protection set on '$Branch'" -ForegroundColor Green
        return 'created'
    }
    catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -match "Only organization repositories can have") {
            try {
                $protectionBody.Remove('restrictions')
                Invoke-GitHubAPI -Uri $uri -Method 'PUT' -Body $protectionBody -Token $Token | Out-Null
                Write-Host "  ✅ Branch protection set on '$Branch' (Personal Repo Mode)" -ForegroundColor Green
                return 'created'
            }
            catch {
                Write-Host "  ❌ Failed to set protection on '$Branch' (Personal Repo Mode): $_" -ForegroundColor Red
                return 'error'
            }
        }
        
        # 404 is already handled by the first GET check, but if we somehow hit it here or hit another 422:
        if ($errMsg -match '404') {
            Write-Host "  ⏭️  Branch '$Branch' not found or not accessible." -ForegroundColor Yellow
            return 'skipped'
        }

        Write-Host "  ❌ Failed to set protection on '$Branch': $_" -ForegroundColor Red
        return 'error'
    }
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Header "02 — Branch Protection"

$TOKEN = Get-Credential-Env -EnvName 'GITHUB_TOKEN' -Prompt 'GitHub PAT' -Secret
$OWNER = Get-Credential-Env -EnvName 'GITHUB_OWNER' -Prompt 'GitHub owner'
$REPO_NAME = Get-Credential-Env -EnvName 'REPO_NAME'    -Prompt 'Repository name'

$stats = @{ created = 0; skipped = 0; errors = 0 }

foreach ($branch in @('main', 'master')) {
    $result = Set-BranchProtection -Branch $branch -Token $TOKEN -Owner $OWNER -Repo $REPO_NAME
    switch ($result) {
        'created' { $stats.created++ }
        'skipped' { $stats.skipped++ }
        'error' { $stats.errors++ }
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
