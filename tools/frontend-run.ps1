# Run staff frontend dev server (port 5173, proxies /api to backend 8080)
. "$PSScriptRoot\dev-env.ps1"

$fe = Join-Path $script:ProjectRoot 'frontend'

if (-not (Test-Path (Join-Path $fe 'node_modules'))) {
    Write-Host 'node_modules missing, running npm install first...' -ForegroundColor Yellow
    Push-Location $fe
    npm install --no-audit --no-fund
    Pop-Location
}

Write-Host 'Starting frontend on http://127.0.0.1:5173 ...' -ForegroundColor Cyan
Write-Host 'Make sure the backend is running (tools/backend-run.ps1)'
Write-Host ''

Push-Location $fe
try {
    npm run dev
} finally {
    Pop-Location
}
