# =============================================================================
#  Reset dev demo data (dev profile only).
#
#  Clears business rows and lets DevDataSeeder rebuild them, so repeated
#  integration / performance runs never drain the demo task list.
#  Staff, accounts, department, dictionary and templates are kept, which means
#  passwords stay valid and no re-login is needed afterwards.
#
#  IMPORTANT: keep this file ASCII-only (PowerShell 5.1 + GBK decoding).
#
#  Requires the backend to be running with profile=dev.
# =============================================================================

param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [string]$ManagerNo = 'N0001',
    [string]$Password = 'Followup@2026'
)

$ErrorActionPreference = 'Stop'

Write-Host 'Resetting demo data ...' -ForegroundColor Cyan

$loginBody = @{ staffNo = $ManagerNo; password = $Password } | ConvertTo-Json -Compress
$login = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method Post `
    -ContentType 'application/json; charset=utf-8' -Body $loginBody -TimeoutSec 20

if ($login.code -ne 0) {
    Write-Host "Login failed: $($login.message)" -ForegroundColor Red
    exit 1
}

$headers = @{ Authorization = "Bearer $($login.data.token)" }
$resp = Invoke-RestMethod -Uri "$BaseUrl/api/dev/demo-data/reset" -Method Post `
    -Headers $headers -TimeoutSec 120

if ($resp.code -ne 0) {
    Write-Host "Reset failed: $($resp.message)" -ForegroundColor Red
    exit 1
}

Write-Host 'Demo data rebuilt:' -ForegroundColor Green
$resp.data.PSObject.Properties | ForEach-Object {
    Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Value)
}
