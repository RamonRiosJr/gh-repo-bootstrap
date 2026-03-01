#Requires -Version 7
<#
.SYNOPSIS
    Creates and populates a GitHub Projects V2 board with custom fields.

.DESCRIPTION
    Uses the GitHub GraphQL API to:
    - Create a linked project for the repository
    - Add custom Single Select fields: Priority, Epic, Size
    - Fetch all board items (Issues, PRs, Draft Issues) with pagination
    - Classify each item using regex keyword matching against board_schema.json rules
    - Tag all items with appropriate Priority, Epic, and Size values

    Uses $PROJ_ID (NOT $PID — which is a reserved PowerShell variable).
    All GraphQL mutations use string concatenation to avoid interpolation issues.

.ENVIRONMENT VARIABLES
    GITHUB_TOKEN  - PAT with 'repo' and 'project' scopes
    GITHUB_OWNER  - GitHub username or organization
    REPO_NAME     - Target repository name

.NOTES
    Workflow automations (auto-move cards) must be enabled via GitHub UI.
    This is a documented API limitation as of 2024.
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

function Invoke-GraphQL {
    param([string]$Query, [string]$Token)
    $body = @{ query = $Query } | ConvertTo-Json -Depth 10
    $result = Invoke-RestMethod -Uri 'https://api.github.com/graphql' -Method POST `
        -Headers @{ 'Authorization' = "Bearer $Token"; 'Content-Type' = 'application/json' } `
        -Body $body
    if ($result.errors) {
        $errMsg = ($result.errors | ForEach-Object { $_.message }) -join '; '
        throw "GraphQL Error: $errMsg"
    }
    return $result.data
}

function Get-RepoId {
    param([string]$Owner, [string]$Repo, [string]$Token)
    $q = 'query { repository(owner: "' + $Owner + '", name: "' + $Repo + '") { id } }'
    $data = Invoke-GraphQL -Query $q -Token $Token
    return $data.repository.id
}

function Get-OwnerId {
    param([string]$Owner, [string]$Token)
    $q = 'query { user(login: "' + $Owner + '") { id } }'
    try {
        $data = Invoke-GraphQL -Query $q -Token $Token
        if ($data.user) { return $data.user.id }
    }
    catch {}
    $q2 = 'query { organization(login: "' + $Owner + '") { id } }'
    $data2 = Invoke-GraphQL -Query $q2 -Token $Token
    return $data2.organization.id
}

function Find-ExistingProject {
    param([string]$Owner, [string]$Title, [string]$Token)
    $q = 'query { user(login: "' + $Owner + '") { projectsV2(first: 20) { nodes { id title } } } }'
    try {
        $data = Invoke-GraphQL -Query $q -Token $Token
        $proj = $data.user.projectsV2.nodes | Where-Object { $_.title -eq $Title }
        if ($proj) { return $proj.id }
    }
    catch {}
    $q2 = 'query { organization(login: "' + $Owner + '") { projectsV2(first: 20) { nodes { id title } } } }'
    try {
        $data2 = Invoke-GraphQL -Query $q2 -Token $Token
        $proj2 = $data2.organization.projectsV2.nodes | Where-Object { $_.title -eq $Title }
        if ($proj2) { return $proj2.id }
    }
    catch {}
    return $null
}

function Create-Project {
    param([string]$OwnerId, [string]$Title, [string]$Token)
    $mut = 'mutation { createProjectV2(input: { ownerId: "' + $OwnerId + '", title: "' + $Title + '" }) { projectV2 { id } } }'
    $data = Invoke-GraphQL -Query $mut -Token $Token
    return $data.createProjectV2.projectV2.id
}

function Get-ProjectFields {
    param([string]$ProjId, [string]$Token)
    $q = 'query { node(id: "' + $ProjId + '") { ... on ProjectV2 { fields(first: 30) { nodes { ... on ProjectV2SingleSelectField { id name options { id name } } ... on ProjectV2Field { id name } } } } } }'
    $data = Invoke-GraphQL -Query $q -Token $Token
    return $data.node.fields.nodes
}

function Create-SingleSelectField {
    param([string]$ProjId, [string]$FieldName, [array]$Options, [string]$Token)
    # Build options JSON array string
    $optParts = $Options | ForEach-Object { '{ name: "' + $_ + '", color: GRAY, description: "" }' }
    $optStr = $optParts -join ', '
    $mut = 'mutation { addProjectV2Field(input: { projectId: "' + $ProjId + '", dataType: SINGLE_SELECT, name: "' + $FieldName + '", singleSelectOptions: [' + $optStr + '] }) { projectV2Field { ... on ProjectV2SingleSelectField { id name options { id name } } } } }'
    $data = Invoke-GraphQL -Query $mut -Token $Token
    return $data.addProjectV2Field.projectV2Field
}

function Get-ProjectItems {
    param([string]$ProjId, [string]$Token)
    $items = @()
    $cursor = $null
    do {
        $afterClause = if ($cursor) { ', after: "' + $cursor + '"' } else { '' }
        $q = 'query { node(id: "' + $ProjId + '") { ... on ProjectV2 { items(first: 100' + $afterClause + ') { pageInfo { hasNextPage endCursor } nodes { id content { ... on Issue { title } ... on PullRequest { title } ... on DraftIssue { title } } } } } } }'
        $data = Invoke-GraphQL -Query $q -Token $Token
        $page = $data.node.items
        $items += $page.nodes | Where-Object { $_.content -and $_.content.title }
        if ($page.pageInfo.hasNextPage) { $cursor = $page.pageInfo.endCursor } else { $cursor = $null }
    } while ($cursor)
    return $items
}

function Classify-Item {
    param([string]$Title, [object]$Rules)
    $titleLower = $Title.ToLower()

    # Priority
    $priority = $Rules.defaults.priority
    foreach ($rule in $Rules.priority) {
        foreach ($kw in $rule.keywords) {
            if ($titleLower -match [regex]::Escape($kw)) { $priority = $rule.value; break }
        }
        if ($priority -ne $Rules.defaults.priority) { break }
    }

    # Epic
    $epic = $Rules.defaults.epic
    foreach ($rule in $Rules.epic) {
        foreach ($kw in $rule.keywords) {
            if ($titleLower -match [regex]::Escape($kw)) { $epic = $rule.value; break }
        }
        if ($epic -ne $Rules.defaults.epic) { break }
    }

    # Size
    $size = $Rules.defaults.size
    foreach ($rule in $Rules.size) {
        foreach ($kw in $rule.keywords) {
            if ($kw -and $titleLower -match [regex]::Escape($kw)) { $size = $rule.name; break }
        }
        if ($size -ne $Rules.defaults.size) { break }
    }

    return @{ priority = $priority; epic = $epic; size = $size }
}

function Set-ItemField {
    param([string]$ProjId, [string]$ItemId, [string]$FieldId, [string]$OptionId, [string]$Token)
    $mut = 'mutation { updateProjectV2ItemFieldValue(input: { projectId: "' + $ProjId + '", itemId: "' + $ItemId + '", fieldId: "' + $FieldId + '", value: { singleSelectOptionId: "' + $OptionId + '" } }) { projectV2Item { id } } }'
    Invoke-GraphQL -Query $mut -Token $Token | Out-Null
}

# ─── Main ─────────────────────────────────────────────────────────────────────

Write-Header "04 — Project Board"

$TOKEN = Get-Credential-Env -EnvName 'GITHUB_TOKEN' -Prompt 'GitHub PAT (project scope)' -Secret
$OWNER = Get-Credential-Env -EnvName 'GITHUB_OWNER' -Prompt 'GitHub owner'
$REPO_NAME = Get-Credential-Env -EnvName 'REPO_NAME'    -Prompt 'Repository name'

$BOARD_NAME = if ($env:BOARD_NAME) { $env:BOARD_NAME } else { 'Engineering Backlog' }

$stats = @{ created = 0; skipped = 0; errors = 0; tagged = 0 }

# Load schema for classification rules
$schemaPath = Join-Path $PSScriptRoot '..\..\config\board_schema.json'
if (Test-Path $schemaPath) {
    $schema = Get-Content $schemaPath | ConvertFrom-Json
    $classRules = $schema.classification_rules
}
else {
    Write-Host "  ⚠️  board_schema.json not found. Using inline defaults." -ForegroundColor Yellow
    $classRules = $null
}

# Get owner node ID
Write-Host "  → Resolving owner node ID..." -ForegroundColor Gray
$OWNER_ID = Get-OwnerId -Owner $OWNER -Token $TOKEN

# Find or create project
Write-Host "  → Checking for existing project '$BOARD_NAME'..." -ForegroundColor Gray
$PROJ_ID = Find-ExistingProject -Owner $OWNER -Title $BOARD_NAME -Token $TOKEN
if ($PROJ_ID) {
    Write-Host "  ⏭️  Project '$BOARD_NAME' already exists (ID: $PROJ_ID)." -ForegroundColor Yellow
    $stats.skipped++
}
else {
    Write-Host "  → Creating project '$BOARD_NAME'..." -ForegroundColor Gray
    $PROJ_ID = Create-Project -OwnerId $OWNER_ID -Title $BOARD_NAME -Token $TOKEN
    Write-Host "  ✅ Project created (ID: $PROJ_ID)" -ForegroundColor Green
    $stats.created++
}

# Set up custom fields
Write-Host "  → Configuring custom fields..." -ForegroundColor Gray
$fields = Get-ProjectFields -ProjId $PROJ_ID -Token $TOKEN
$fieldMap = @{}
foreach ($f in $fields) { if ($f.name) { $fieldMap[$f.name] = $f } }

$fieldDefs = @(
    @{ name = 'Priority'; options = @('P0: Critical', 'P1: High', 'P2: Medium', 'P3: Low') }
    @{ name = 'Epic'; options = @('Compliance', 'Security', 'Infrastructure', 'UI/UX', 'AI/ML', 'Integrations') }
    @{ name = 'Size'; options = @('S', 'M', 'L', 'XL') }
)

foreach ($fd in $fieldDefs) {
    if ($fieldMap.ContainsKey($fd.name)) {
        Write-Host "    ⏭️  Field '$($fd.name)' already exists." -ForegroundColor Yellow
        $stats.skipped++
    }
    else {
        Write-Host "    → Creating field '$($fd.name)'..." -ForegroundColor Gray
        try {
            $newField = Create-SingleSelectField -ProjId $PROJ_ID -FieldName $fd.name -Options $fd.options -Token $TOKEN
            $fieldMap[$fd.name] = $newField
            Write-Host "    ✅ Field '$($fd.name)' created." -ForegroundColor Green
            $stats.created++
        }
        catch {
            Write-Host "    ❌ Failed to create field '$($fd.name)': $_" -ForegroundColor Red
            $stats.errors++
        }
    }
}

# Refresh fields after creation
$fields = Get-ProjectFields -ProjId $PROJ_ID -Token $TOKEN
$fieldMap = @{}
foreach ($f in $fields) { if ($f.name) { $fieldMap[$f.name] = $f } }

# Tag all items
if ($classRules) {
    Write-Host "  → Fetching board items for classification..." -ForegroundColor Gray
    $items = Get-ProjectItems -ProjId $PROJ_ID -Token $TOKEN
    Write-Host "  → Classifying and tagging $($items.Count) item(s)..." -ForegroundColor Gray

    foreach ($item in $items) {
        $title = $item.content.title
        $classification = Classify-Item -Title $title -Rules $classRules

        try {
            # Priority
            if ($fieldMap.ContainsKey('Priority')) {
                $pField = $fieldMap['Priority']
                $pOpt = $pField.options | Where-Object { $_.name -eq $classification.priority }
                if ($pOpt) { Set-ItemField -ProjId $PROJ_ID -ItemId $item.id -FieldId $pField.id -OptionId $pOpt.id -Token $TOKEN }
            }
            # Epic
            if ($fieldMap.ContainsKey('Epic')) {
                $eField = $fieldMap['Epic']
                $eOpt = $eField.options | Where-Object { $_.name -eq $classification.epic }
                if ($eOpt) { Set-ItemField -ProjId $PROJ_ID -ItemId $item.id -FieldId $eField.id -OptionId $eOpt.id -Token $TOKEN }
            }
            # Size
            if ($fieldMap.ContainsKey('Size')) {
                $sField = $fieldMap['Size']
                $sOpt = $sField.options | Where-Object { $_.name -eq $classification.size }
                if ($sOpt) { Set-ItemField -ProjId $PROJ_ID -ItemId $item.id -FieldId $sField.id -OptionId $sOpt.id -Token $TOKEN }
            }
            Write-Host "    🏷️  Tagged: [$($classification.priority)] [$($classification.epic)] [$($classification.size)] — $title" -ForegroundColor Cyan
            $stats.tagged++
        }
        catch {
            Write-Host "    ❌ Failed to tag '$title': $_" -ForegroundColor Red
            $stats.errors++
        }
    }
}

Write-Host ""
Write-Host "  ℹ️  NOTE: Workflow automations (auto-move cards on PR merge, issue close, etc.)" -ForegroundColor DarkYellow
Write-Host "       must be enabled via GitHub UI → Project → Settings → Workflows." -ForegroundColor DarkYellow
Write-Host "       This is a documented GitHub API limitation." -ForegroundColor DarkYellow

Write-Host ""; Write-Host "─── Summary ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "  ✅ Created : $($stats.created)" -ForegroundColor Green
Write-Host "  ⏭️  Skipped : $($stats.skipped)" -ForegroundColor Yellow
Write-Host "  🏷️  Tagged  : $($stats.tagged)" -ForegroundColor Cyan
Write-Host "  ❌ Errors  : $($stats.errors)" -ForegroundColor Red; Write-Host ""
if ($stats.errors -gt 0) { exit 1 }
