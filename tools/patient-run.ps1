# Run the patient-facing H5 app (port 5174, proxies /api to backend 8080)
#
# Impatient note: this app shares frontend/node_modules with the staff app,
# so no extra npm install is needed.
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

Write-Host 'Starting patient H5 on http://127.0.0.1:5174 ...' -ForegroundColor Cyan
Write-Host 'Make sure the backend is running (tools/backend-run.ps1)'
Write-Host ''

Push-Location $fe
try {
    npm run dev:patient
} finally {
    Pop-Location
}
