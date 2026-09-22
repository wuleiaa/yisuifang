# Run the admin console (port 5175, proxies /api to backend 8080)
#
# IMPORTANT: keep this file ASCII-only.

. "$PSScriptRoot\dev-env.ps1"

$fe = Join-Path $script:ProjectRoot 'frontend'

if (-not (Test-Path (Join-Path $fe 'node_modules'))) {
    Write-Host 'node_modules missing, running npm install first...' -ForegroundColor Yellow
    Push-Location $fe
    npm install --no-audit --no-fund
    Pop-Location
}

Write-Host 'Starting admin console on http://127.0.0.1:5175 ...' -ForegroundColor Cyan
Write-Host 'Login with an admin account (dev: A0001 / Followup@2026)'
Write-Host ''

Push-Location $fe
try {
    npm run dev:admin
} finally {
    Pop-Location
}
