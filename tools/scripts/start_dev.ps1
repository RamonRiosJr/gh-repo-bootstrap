Clear-Host
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "      _                 _    ___  ___   ____                 " -ForegroundColor Cyan
Write-Host "     / \  _   _ _ __ __| |  / _ \/ __| |  _ \  ___   ___ ___ " -ForegroundColor Cyan
Write-Host "    / _ \| | | | '__/ _`` | | | | \__ \ | | | |/ _ \ / __/ __|" -ForegroundColor Cyan
Write-Host "   / ___ \ |_| | | | (_| | | |_| |___/ | |_| | (_) | (__\__ \" -ForegroundColor Cyan
Write-Host "  /_/   \_\__,_|_|  \__,_|  \___/|___/ |____/ \___/ \___|___/" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "               AURA hOS DOCS PORTAL" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting development server on port 7100..." -ForegroundColor Yellow

Set-Location -Path "$PSScriptRoot\..\.."

# Install dependencies if node_modules doesn't exist
if (-not (Test-Path -Path "node_modules")) {
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    npm install
}

npm run dev -- --port 7100
