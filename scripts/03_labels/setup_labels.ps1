#Requires -Version 7
<#
.SYNOPSIS
    Replaces default GitHub labels with a professional enterprise taxonomy.

.DESCRIPTION
    Deletes all default GitHub labels and creates a 27-label taxonomy covering:
    Type, Priority, Epic, Status, and Size dimensions.

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN  - PAT with 'repo' scope
    GITHUB_OWNER  - GitHub username or organization
    REPO_NAME     - Target repository name

.NOTES
    Idempotent: existing labels with matching names are updated, not duplicated.
    Author: gh-repo-bootstrap
    Version: 1.0.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Helpers ─────────────────────────────────────────────────────────────────

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

# ─── Label Taxonomy ──────────────────────────────────────────────────────────

$LABELS = @(
    # Type
    @{ name = 'type: bug'; color = 'b60205'; description = 'Something is not working correctly' }
    @{ name = 'type: feature'; color = '0075ca'; description = 'New functionality or enhancement' }
    @{ name = 'type: chore'; color = 'cfd3d7'; description = 'Maintenance, cleanup, refactoring' }
    @{ name = 'type: compliance'; color = '6f42c1'; description = 'Regulatory requirements, audits' }
    @{ name = 'type: security'; color = '8b0000'; description = 'Security vulnerabilities or hardening' }
    @{ name = 'type: docs'; color = '0e8a16'; description = 'Documentation updates' }

    # Priority
    @{ name = 'P0: critical'; color = 'b60205'; description = 'Outage / blocker — DROP EVERYTHING' }
    @{ name = 'P1: high'; color = 'e4e669'; description = 'Must ship this sprint' }
    @{ name = 'P2: medium'; color = '0075ca'; description = 'Target next sprint' }
    @{ name = 'P3: low'; color = 'cfd3d7'; description = 'Nice to have / future consideration' }

    # Epic
    @{ name = 'epic: compliance'; color = '6f42c1'; description = 'Compliance and regulatory track' }
    @{ name = 'epic: security'; color = '8b0000'; description = 'Security hardening track' }
    @{ name = 'epic: infrastructure'; color = '495057'; description = 'DevOps, CI/CD, platform track' }
    @{ name = 'epic: ui/ux'; color = 'e83e8c'; description = 'Frontend, design system track' }
    @{ name = 'epic: ai/ml'; color = '17a2b8'; description = 'AI/ML integration track' }
    @{ name = 'epic: integrations'; color = '28a745'; description = 'Third-party integration track' }

    # Status
    @{ name = 'status: in-progress'; color = '0052cc'; description = 'Actively being worked on' }
    @{ name = 'status: blocked'; color = 'ee0701'; description = 'Cannot proceed — blocked' }
    @{ name = 'status: needs-review'; color = 'fbca04'; description = 'Awaiting review or approval' }
    @{ name = 'status: ready'; color = '0e8a16'; description = 'Groomed and ready to pick up' }

    # Size
    @{ name = 'size: S'; color = '0e8a16'; description = '≤ 4 hours — trivial change' }
    @{ name = 'size: M'; color = '0075ca'; description = '≤ 1 day — standard ticket' }
    @{ name = 'size: L'; color = 'fbca04'; description = '≤ 3 days — complex ticket' }
    @{ name = 'size: XL'; color = 'b60205'; description = '> 3 days — consider breaking down' }
)

$DEFAULT_LABELS = @('bug', 'documentation', 'duplicate', 'enhancement', 'good first issue', 'help wanted', 'invalid', 'question', 'wontfix')

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Header "03 — Labels"

$TOKEN = Get-Credential-Env -EnvName 'GITHUB_TOKEN' -Prompt 'GitHub PAT' -Secret
$OWNER = Get-Credential-Env -EnvName 'GITHUB_OWNER' -Prompt 'GitHub owner'
$REPO_NAME = Get-Credential-Env -EnvName 'REPO_NAME'    -Prompt 'Repository name'

$stats = @{ created = 0; skipped = 0; errors = 0 }

# Delete default labels
Write-Host "  → Removing default GitHub labels..." -ForegroundColor Gray
foreach ($label in $DEFAULT_LABELS) {
    $encodedLabel = [System.Uri]::EscapeDataString($label)
    try {
        Invoke-GitHubAPI -Uri "https://api.github.com/repos/$OWNER/$REPO_NAME/labels/$encodedLabel" -Method 'DELETE' -Token $TOKEN | Out-Null
        Write-Host "    🗑️  Deleted: $label" -ForegroundColor DarkGray
    }
    catch {
        # 404 = already gone, that's fine
    }
}

# Fetch existing labels for idempotency
Write-Host "  → Fetching existing labels..." -ForegroundColor Gray
$existingLabels = @{}
$page = 1
do {
    $pageResult = Invoke-GitHubAPI -Uri "https://api.github.com/repos/$OWNER/$REPO_NAME/labels?per_page=100&page=$page" -Token $TOKEN
    foreach ($l in $pageResult) { $existingLabels[$l.name] = $l }
    $page++
} while ($pageResult.Count -eq 100)

Write-Host "  → Creating / updating professional label taxonomy..." -ForegroundColor Gray
foreach ($label in $LABELS) {
    $body = @{ name = $label.name; color = $label.color; description = $label.description }
    if ($existingLabels.ContainsKey($label.name)) {
        # Update existing
        $encodedName = [System.Uri]::EscapeDataString($label.name)
        try {
            Invoke-GitHubAPI -Uri "https://api.github.com/repos/$OWNER/$REPO_NAME/labels/$encodedName" -Method 'PATCH' -Body $body -Token $TOKEN | Out-Null
            Write-Host "    ⏭️  Updated: $($label.name)" -ForegroundColor Yellow
            $stats.skipped++
        }
        catch {
            Write-Host "    ❌ Failed to update: $($label.name) — $_" -ForegroundColor Red
            $stats.errors++
        }
    }
    else {
        try {
            Invoke-GitHubAPI -Uri "https://api.github.com/repos/$OWNER/$REPO_NAME/labels" -Method 'POST' -Body $body -Token $TOKEN | Out-Null
            Write-Host "    ✅ Created: $($label.name)" -ForegroundColor Green
            $stats.created++
        }
        catch {
            Write-Host "    ❌ Failed to create: $($label.name) — $_" -ForegroundColor Red
            $stats.errors++
        }
    }
}

Write-Host ""; Write-Host "─── Summary ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ✅ Created : $($stats.created)" -ForegroundColor Green
Write-Host "  ⏭️  Skipped : $($stats.skipped)" -ForegroundColor Yellow
Write-Host "  ❌ Errors  : $($stats.errors)" -ForegroundColor Red; Write-Host ""
if ($stats.errors -gt 0) { exit 1 }
