# Build backend jar (no run)
. "$PSScriptRoot\dev-env.ps1"

if (-not (Test-DevTools)) { exit 1 }

& "$script:MavenHome\bin\mvn.cmd" `
    "-Dmaven.repo.local=$script:M2Repo" `
    "-s" (Join-Path $script:ProjectRoot 'backend\settings.xml') `
    "-f" (Join-Path $script:ProjectRoot 'backend\pom.xml') `
    "-DskipTests" clean package

if ($LASTEXITCODE -eq 0) {
    Write-Host 'Build OK: backend\target\followup.jar' -ForegroundColor Green
} else {
    Write-Host 'Build FAILED' -ForegroundColor Red
}

