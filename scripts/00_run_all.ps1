#Requires -Version 7
<#
.SYNOPSIS
    Master orchestrator for gh-repo-bootstrap.

.DESCRIPTION
    Provides an interactive menu to run any combination of the 9 automation
    scripts in sequence. Collects credentials once at startup and passes them
    to all sub-scripts via environment variables. Prints a final pass/fail
    summary table at the end.

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN  - PAT (prompted once if not set)
    GITHUB_OWNER  - GitHub owner (prompted once if not set)
    REPO_NAME     - Repository name (prompted once if not set)

.NOTES
    Author: gh-repo-bootstrap
    Version: 1.0.0
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # Don't abort orchestrator on sub-script errors

# ─── Constants ────────────────────────────────────────────────────────────────

$SCRIPT_DIR = $PSScriptRoot
$VERSION = '1.0.0'

$STEPS = [ordered]@{
    '1' = @{ label = 'Create Repository'; script = '01_create_repo\create_repo.ps1' }
    '2' = @{ label = 'Branch Protection'; script = '02_branch_protection\setup_branches.ps1' }
    '3' = @{ label = 'Labels'; script = '03_labels\setup_labels.ps1' }
    '4' = @{ label = 'Project Board'; script = '04_project_board\setup_board.ps1' }
    '5' = @{ label = 'CI/CD Workflows'; script = '05_ci_cd\setup_ci.ps1' }
    '6' = @{ label = 'Secrets'; script = '06_secrets\setup_secrets.ps1' }
    '7' = @{ label = 'PR & Issue Templates'; script = '07_templates\setup_templates.ps1' }
    '8' = @{ label = 'Dependabot'; script = '08_dependabot\setup_dependabot.ps1' }
    '9' = @{ label = 'Description & Topics'; script = '09_description_topics\setup_meta.ps1' }
}

# ─── Helpers ─────────────────────────────────────────────────────────────────

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                              ║" -ForegroundColor Cyan
    Write-Host "  ║   🚀  gh-repo-bootstrap  v$VERSION            ║" -ForegroundColor Cyan
    Write-Host "  ║   GitHub Repository Automation Toolkit      ║" -ForegroundColor Cyan
    Write-Host "  ║                                              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Owner : $env:GITHUB_OWNER" -ForegroundColor DarkGray
    Write-Host "  Repo  : $env:REPO_NAME" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Menu {
    Write-Host "  ═══════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "   Select a step to run:" -ForegroundColor White
    Write-Host "  ═══════════════════════════════════════" -ForegroundColor DarkCyan
    foreach ($key in $STEPS.Keys) {
        Write-Host "   [$key] $($STEPS[$key].label)" -ForegroundColor White
    }
    Write-Host "   [A] Run ALL (1-9 in sequence)" -ForegroundColor Green
    Write-Host "   [Q] Quit" -ForegroundColor DarkGray
    Write-Host "  ═══════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""
}

function Invoke-Step {
    param([string]$StepKey, [hashtable]$Results)

    $step = $STEPS[$StepKey]
    $scriptPath = Join-Path $SCRIPT_DIR $step.script

    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "  │  Running: [$StepKey] $($step.label)" -ForegroundColor Cyan
    Write-Host "  └─────────────────────────────────────────" -ForegroundColor Cyan

    if (-not (Test-Path $scriptPath)) {
        Write-Host "  ❌ Script not found: $scriptPath" -ForegroundColor Red
        $Results[$StepKey] = 'ERROR'
        return
    }

    $startTime = Get-Date
    try {
        & pwsh -NoProfile -NonInteractive -File $scriptPath
        $exitCode = $LASTEXITCODE
    }
    catch {
        $exitCode = 1
    }
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

    if ($exitCode -eq 0) {
        Write-Host "  ✅ [$StepKey] $($step.label) — completed in ${elapsed}s" -ForegroundColor Green
        $Results[$StepKey] = 'PASS'
    }
    else {
        Write-Host "  ❌ [$StepKey] $($step.label) — FAILED (exit $exitCode) in ${elapsed}s" -ForegroundColor Red
        $Results[$StepKey] = 'FAIL'
    }
}

function Show-Summary {
    param([hashtable]$Results)
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════╗" -ForegroundColor White
    Write-Host "  ║               Execution Summary              ║" -ForegroundColor White
    Write-Host "  ╠══════╦════════════════════════════╦══════════╣" -ForegroundColor White
    Write-Host "  ║  Key ║  Step                      ║  Status  ║" -ForegroundColor White
    Write-Host "  ╠══════╬════════════════════════════╬══════════╣" -ForegroundColor White

    foreach ($key in $STEPS.Keys) {
        if ($Results.ContainsKey($key)) {
            $status = $Results[$key]
            $icon = switch ($status) { 'PASS' { '✅ PASS' } 'FAIL' { '❌ FAIL' } default { '⏭️  SKIP' } }
            $color = switch ($status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
            $label = $STEPS[$key].label.PadRight(26)
            Write-Host "  ║  [$key]  ║  $label  ║  $($icon.PadRight(6))  ║" -ForegroundColor $color
        }
    }

    $passCount = ($Results.Values | Where-Object { $_ -eq 'PASS' }).Count
    $failCount = ($Results.Values | Where-Object { $_ -eq 'FAIL' }).Count
    Write-Host "  ╚══════╩════════════════════════════╩══════════╝" -ForegroundColor White
    Write-Host ""
    Write-Host "  Total: $($Results.Count) run  |  ✅ $passCount passed  |  ❌ $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
    Write-Host ""
}

# ─── Credential Collection ───────────────────────────────────────────────────

function Request-Credentials {
    Write-Host "  ─── Credentials ──────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  (Set GITHUB_TOKEN, GITHUB_OWNER, REPO_NAME env vars to skip these prompts)" -ForegroundColor DarkGray
    Write-Host ""

    if (-not $env:GITHUB_TOKEN) {
        $secure = Read-Host -Prompt '  GitHub PAT (will be stored in session env)' -AsSecureString
        $env:GITHUB_TOKEN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    }
    else {
        Write-Host "  ✅ GITHUB_TOKEN loaded from environment" -ForegroundColor DarkGray
    }

    if (-not $env:GITHUB_OWNER) {
        $env:GITHUB_OWNER = Read-Host -Prompt '  GitHub owner (username or org)'
    }
    else {
        Write-Host "  ✅ GITHUB_OWNER: $env:GITHUB_OWNER" -ForegroundColor DarkGray
    }

    if (-not $env:REPO_NAME) {
        $env:REPO_NAME = Read-Host -Prompt '  Repository name'
    }
    else {
        Write-Host "  ✅ REPO_NAME: $env:REPO_NAME" -ForegroundColor DarkGray
    }
}

# ─── Main Loop ────────────────────────────────────────────────────────────────

Request-Credentials

$sessionResults = @{}

do {
    Show-Banner
    Show-Menu

    $choice = Read-Host -Prompt '  Enter choice'
    $choice = $choice.Trim().ToUpper()

    switch ($choice) {
        'Q' {
            Write-Host ""; Write-Host "  👋 Goodbye!" -ForegroundColor Cyan; Write-Host ""
            if ($sessionResults.Count -gt 0) { Show-Summary -Results $sessionResults }
            exit 0
        }
        'A' {
            Write-Host "  🚀 Running ALL steps (1-9)..." -ForegroundColor Green
            foreach ($key in $STEPS.Keys) {
                Invoke-Step -StepKey $key -Results $sessionResults
            }
            Show-Summary -Results $sessionResults
            Write-Host "  Press any key to return to menu..." -ForegroundColor DarkGray
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        default {
            if ($STEPS.ContainsKey($choice)) {
                Invoke-Step -StepKey $choice -Results $sessionResults
                Write-Host "  Press any key to return to menu..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            }
            else {
                Write-Host "  ⚠️  Invalid choice: '$choice'. Please enter 1-9, A, or Q." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }
} while ($true)
